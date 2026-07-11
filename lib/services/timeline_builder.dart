// LIVE AYAH TIMELINE — the native port of the HTML prototype's
// buildAyahTimeline(): detects *which ayah is being recited and when* across
// the whole clip, so playback and export can type each ayah out exactly as
// it's spoken ("اكتب كل آية أثناء التلاوة").
//
// Same real engine as the browser version, no fakery:
//   1. ffmpeg extracts the clip's audio as 16kHz mono PCM WAV once.
//   2. The PCM is scanned in overlapping 6-second windows (5s step). Each
//      window is RMS-gated (cheap voice-activity check — Whisper hallucinates
//      fluent Arabic when fed silence/room tone, so silent windows are
//      skipped entirely) and then transcribed on-device by whisper.cpp.
//   3. Each window transcript runs through the same AyahMatcher used by the
//      one-shot detection paths. Borderline matches only commit once two
//      consecutive windows agree; consecutive windows on the same ayah merge
//      into one {start, end, ayah} segment.
//   4. PATCH_S35_SMARTER_DETECTION: recitation follows mushaf order, so when
//      the corpus-wide search fails or is weak, the ayat we EXPECT next
//      (the current ayah continuing, or the following one/two) are re-scored
//      directly with a relaxed threshold — a window straddling two ayat or
//      garbled by reverb often still clearly matches its expected successor.
//   5. PATCH_S35_SMARTER_DETECTION: the raw segments are quantized to the
//      6s-window/5s-step grid, so afterwards overlaps/small gaps between
//      consecutive segments are normalized away and each shared boundary is
//      snapped to the quietest instant nearby — the reciter's breath pause
//      between ayat — which makes the karaoke word timing noticeably tighter.
//   6. PATCH_S42_AUTOSYNC_MAX: three robustness passes on top:
//      • the silence gate adapts to the clip's own noise floor instead of a
//        fixed -42 dBFS, so noisy room tone no longer reaches Whisper (which
//        hallucinates on it) and unusually clean/quiet recordings keep the
//        proven fixed gate;
//      • a short weak mis-detection sandwiched between two halves of the
//        SAME ayah is recognized as noise and merged away;
//      • when detection jumps ayah N → N+2 (or +3) within one surah and the
//        gap between them holds enough recitation time, the skipped ayat are
//        inferred into the gap (flagged `inferred` so the UI can show them
//        for review) — one garbled window no longer silently drops an ayah.
//   7. PATCH_S43_GAP_RESCUE: a second, finer Whisper pass over every gap the
//      main scan left unmatched (including before the first and after the
//      last detection): 4s windows on a 2s stride, scored ONLY against the
//      ayat mushaf order allows at that spot. Real acoustic evidence beats
//      the pure inference of pass 6, so this runs first and pass 6 only
//      fills what the rescue couldn't hear. Afterwards the very first
//      segment's start and the very last segment's end are snapped from the
//      window grid to the actual speech onset/offset, so leading/trailing
//      room tone is no longer captioned.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/studio_state.dart';
import 'ayah_matcher.dart';
import 'media_service.dart';
import 'whisper_service.dart';

class TimelineBuilder {
  static const double chunkSec = 6; // analysis window length
  static const double stepSec = 5; // window stride
  static const double minConfidence = 0.32;
  static const double highConfidence = 0.55; // commit off a single window
  static const double vadSilenceRms = 0.008; // ~-42 dBFS
  static const int sampleRate = 16000;
  // PATCH_S35_SMARTER_DETECTION: thresholds for the expected-next re-score.
  // The mushaf-order prior lets us accept weaker acoustic evidence, and the
  // bonus lets an expected ayah win a near-tie against an unrelated one.
  static const double contextMinConfidence = 0.22;
  static const double contextPriorBonus = 0.08;

  // PATCH_S37_CANCEL_LONG_JOBS: lets the UI abort a long scan; checked once
  // per window so cancellation lands within ~1 window's processing time.
  static bool _cancelRequested = false;
  static void requestCancel() => _cancelRequested = true;

  /// Scans [mediaPath] (video or audio) and returns the detected ayah
  /// timeline. [onStatus] receives human-readable Arabic progress text,
  /// [onProgress] a 0..1 fraction.
  static Future<List<TimelineSegment>> build({
    required String mediaPath,
    required AyahMatcher matcher,
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    _cancelRequested = false; // PATCH_S37_CANCEL_LONG_JOBS
    await WhisperService.ensureReady(onStatus: onStatus);

    onStatus?.call('جارٍ استخراج الصوت الكامل…');
    final wavPath = await MediaService.extractWav16kMono(mediaPath);
    final pcm = _readWavMono16(wavPath);

    final totalSec = pcm.length / sampleRate;
    final totalChunks = max(1, (totalSec / stepSec).ceil());

    // PATCH_S42_AUTOSYNC_MAX: one cheap pre-pass over the whole clip to
    // learn its noise floor, so the silence gate below fits THIS recording.
    final windowRms = <double>[];
    for (double t = 0; t < totalSec; t += stepSec) {
      final s = (t * sampleRate).floor();
      final e = min(pcm.length, ((t + chunkSec) * sampleRate).floor());
      windowRms
          .add(e > s ? _rmsEnergy(Int16List.sublistView(pcm, s, e)) : 0.0);
    }
    final silenceGate = adaptiveSilenceThreshold(windowRms);

    final tempDir = Directory.systemTemp.createTempSync('ayat_timeline');
    final timeline = <TimelineSegment>[];
    // A borderline match (below highConfidence) only commits once the *next*
    // window agrees on the same ayah too — one noisy window can clear
    // minConfidence by chance, two in a row on the same ayah almost never do.
    TimelineSegment? pending;
    var chunkIndex = 0;

    try {
      for (double t = 0; t < totalSec; t += stepSec) {
        if (_cancelRequested) {
          throw Exception('تم إلغاء المزامنة'); // PATCH_S37_CANCEL_LONG_JOBS
        }
        chunkIndex++;
        onStatus?.call('جارٍ رصد الآيات: مقطع $chunkIndex من $totalChunks…');
        // PATCH_S43_GAP_RESCUE: the head 90% — the gap-rescue pass owns the
        // rest. (The remaining-time readout lives in the UI now, derived
        // from this fraction's pace.)
        onProgress?.call(0.9 * chunkIndex / totalChunks);

        final startSample = (t * sampleRate).floor();
        final endSample =
            min(pcm.length, ((t + chunkSec) * sampleRate).floor());
        if (endSample - startSample < sampleRate * 1.2) continue; // tiny tail

        final slice = Int16List.sublistView(pcm, startSample, endSample);
        if ((chunkIndex - 1 < windowRms.length
                ? windowRms[chunkIndex - 1]
                : _rmsEnergy(slice)) <
            silenceGate) {
          pending = null; // near-silent window — nothing to transcribe
          continue;
        }

        String text;
        try {
          final chunkPath = '${tempDir.path}/chunk_$chunkIndex.wav';
          _writeWavMono16(chunkPath, slice);
          text = await WhisperService.transcribeWav(chunkPath);
          File(chunkPath).delete().ignore();
        } catch (_) {
          continue; // one failed window shouldn't kill the whole scan
        }

        var match = matcher.match(text, minConfidence: minConfidence);

        // PATCH_S35_SMARTER_DETECTION: when the corpus-wide search failed or
        // stayed below the single-window commit bar, re-score just the ayat
        // the mushaf order predicts here (current ayah continuing, next,
        // next-after) with a relaxed threshold and a small prior bonus.
        // PATCH_S42_AUTOSYNC_MAX: an uncommitted pending match anchors too —
        // the very first ayah of a clip used to get no context help at all.
        final anchor =
            timeline.isEmpty ? pending?.ayah : timeline.last.ayah;
        if (anchor != null &&
            (match == null || match.confidence < highConfidence)) {
          final expected = _expectedNext(matcher.ayaat, anchor);
          final ctx = matcher.matchAmong(text, expected,
              minConfidence: contextMinConfidence);
          if (ctx != null &&
              (match == null ||
                  identical(ctx.ayah, match.ayah) ||
                  ctx.confidence + contextPriorBonus >= match.confidence)) {
            match = ctx.confidence >= (match?.confidence ?? 0)
                ? ctx
                : AyahMatch(ctx.ayah, match!.confidence);
          }
        }

        if (match == null) {
          pending = null;
          continue;
        }

        final last = timeline.isEmpty ? null : timeline.last;
        if (last != null && identical(last.ayah, match.ayah)) {
          // same ayah still being recited — extend the segment
          last.end = t + chunkSec;
          last.confidence = max(last.confidence, match.confidence);
          pending = null;
          continue;
        }

        if (match.confidence >= highConfidence) {
          timeline.add(TimelineSegment(
              start: t,
              end: t + chunkSec,
              ayah: match.ayah,
              confidence: match.confidence));
          pending = null;
        } else if (pending != null && identical(pending.ayah, match.ayah)) {
          // second window in a row agrees — commit, backdated to where the
          // ayah first appeared
          timeline.add(TimelineSegment(
              start: pending.start,
              end: t + chunkSec,
              ayah: match.ayah,
              confidence: max(pending.confidence, match.confidence)));
          pending = null;
        } else {
          pending = TimelineSegment(
              start: t,
              end: t + chunkSec,
              ayah: match.ayah,
              confidence: match.confidence);
        }
      }
      // PATCH_S42_AUTOSYNC_MAX: structural repairs first (they need the raw
      // gaps normalization would bridge away), then the S35 grid cleanup and
      // breath-pause boundary snapping.
      repairTimeline(timeline);
      // PATCH_S43_GAP_RESCUE: try to actually HEAR what the main scan missed
      // in the gaps before pass 6 resorts to inferring it, then re-merge any
      // rescued pieces into their neighbouring segments.
      await _rescanGaps(
        timeline: timeline,
        pcm: pcm,
        matcher: matcher,
        tempDir: tempDir,
        silenceGate: silenceGate,
        totalSec: totalSec,
        onStatus: onStatus,
        onProgress: onProgress,
      );
      repairTimeline(timeline);
      inferSkippedAyat(timeline, matcher.ayaat);
      // PATCH_S35_SMARTER_DETECTION: clean the step-grid quantization up and
      // snap ayah boundaries to the reciter's breath pauses.
      normalizeTimeline(timeline, totalSec);
      _refineBoundaries(timeline, pcm);
      snapEdgesToSpeech(timeline, pcm, silenceGate); // PATCH_S43_GAP_RESCUE
      onProgress?.call(1);
    } finally {
      tempDir.delete(recursive: true).ignore();
      File(wavPath).delete().ignore();
    }
    return timeline;
  }

  // PATCH_S35_SMARTER_DETECTION: the ayat mushaf order predicts after
  // [anchor]: the anchor itself (still being recited) and the next two.
  // PATCH_S42_AUTOSYNC_MAX: plus the ayah BEFORE the anchor — repeating the
  // previous ayah is common in memorization/practice recordings.
  static List<Ayah> _expectedNext(List<Ayah> ayaat, Ayah anchor) {
    final i = ayaat.indexOf(anchor); // identity ==, Ayah defines no operator==
    if (i < 0) return [anchor];
    return [
      if (i > 0) ayaat[i - 1],
      ...ayaat.sublist(i, min(ayaat.length, i + 3)),
    ];
  }

  // PATCH_S42_AUTOSYNC_MAX --------------------------------------------------

  /// Picks the silence gate for THIS clip from the RMS of all its analysis
  /// windows. The clip's quietest windows are its room tone; anything within
  /// ~2.2× of that is still "silence". The result never drops below the
  /// proven fixed gate ([vadSilenceRms]) and is capped both absolutely and
  /// relative to the clip's loud (speech) windows, so a clip that is
  /// wall-to-wall recitation can never gate real speech away. Pure and
  /// public for unit tests.
  static double adaptiveSilenceThreshold(List<double> windowRms) {
    if (windowRms.length < 4) return vadSilenceRms;
    final sorted = [...windowRms]..sort();
    double at(double q) =>
        sorted[(sorted.length * q).floor().clamp(0, sorted.length - 1)];
    final noiseFloor = at(0.1);
    final speechLevel = at(0.85);
    final cap = min(0.02, max(vadSilenceRms, speechLevel * 0.35));
    return (noiseFloor * 2.2).clamp(vadSilenceRms, cap);
  }

  /// Structural cleanup of the raw scan output. Two repairs, both pure and
  /// public for unit tests:
  ///   • adjacent segments of the same ayah merge (belt-and-braces — the
  ///     scan loop extends in place, but editing/inference can reintroduce
  ///     them);
  ///   • an A-B-A "sandwich": a single short window that matched some other
  ///     ayah B in the middle of ayah A's span, weaker than both A halves —
  ///     that's a garbled window, not a real jump away and back, so B is
  ///     dropped and the halves merge.
  static void repairTimeline(List<TimelineSegment> timeline) {
    for (var i = 0; i + 1 < timeline.length;) {
      final a = timeline[i], b = timeline[i + 1];
      if (identical(a.ayah, b.ayah) && b.start - a.end <= stepSec + 0.01) {
        a.end = max(a.end, b.end);
        a.confidence = max(a.confidence, b.confidence);
        timeline.removeAt(i + 1);
      } else {
        i++;
      }
    }
    for (var i = 0; i + 2 < timeline.length;) {
      final a = timeline[i], mid = timeline[i + 1], b = timeline[i + 2];
      if (identical(a.ayah, b.ayah) &&
          !identical(mid.ayah, a.ayah) &&
          mid.end - mid.start <= chunkSec + 0.01 &&
          mid.confidence < min(a.confidence, b.confidence)) {
        a.end = b.end;
        a.confidence = max(a.confidence, b.confidence);
        timeline.removeAt(i + 2);
        timeline.removeAt(i + 1);
        // stay at i — the merged segment has new neighbours to re-check
      } else {
        i++;
      }
    }
  }

  // An ayah can't realistically be recited in less than this many seconds —
  // gates how many missing ayat a gap is allowed to absorb.
  static const double _minSecPerInferredAyah = 1.5;

  /// When detection jumps from ayah N to ayah N+2/N+3 of the same surah and
  /// the gap between the two segments holds enough recitation time, the
  /// skipped ayat almost certainly WERE recited — their windows just came
  /// back garbled (reverb, overlapping madd, a sneeze…). Insert them across
  /// the gap, splitting it proportionally to each ayah's word count, flagged
  /// [TimelineSegment.inferred] for the UI. Runs BEFORE normalizeTimeline,
  /// which would otherwise bridge exactly the gaps this pass reads. Pure and
  /// public for unit tests.
  static void inferSkippedAyat(
      List<TimelineSegment> timeline, List<Ayah> ayaat) {
    for (var i = 0; i + 1 < timeline.length; i++) {
      final a = timeline[i], b = timeline[i + 1];
      if (a.ayah.surahNum != b.ayah.surahNum) continue;
      final missingCount = b.ayah.num - a.ayah.num - 1;
      if (missingCount < 1 || missingCount > 3) continue;
      final gap = b.start - a.end;
      if (gap < _minSecPerInferredAyah * missingCount) continue;
      final ai = ayaat.indexOf(a.ayah); // identity ==
      if (ai < 0 || ai + missingCount + 1 >= ayaat.length) continue;
      // the corpus must really place b right after the presumed-missing run
      if (!identical(ayaat[ai + missingCount + 1], b.ayah)) continue;
      final missing = ayaat.sublist(ai + 1, ai + 1 + missingCount);
      final weights = [
        for (final m in missing)
          m.ar.trim().split(RegExp(r'\s+')).length.toDouble()
      ];
      final totalWeight = weights.fold(0.0, (s, w) => s + w);
      var t = a.end;
      for (var j = 0; j < missing.length; j++) {
        final end =
            j == missing.length - 1 ? b.start : t + gap * weights[j] / totalWeight;
        timeline.insert(
            i + 1 + j,
            TimelineSegment(
              start: t,
              end: end,
              ayah: missing[j],
              confidence: 0.3,
              inferred: true,
            ));
        t = end;
      }
      i += missing.length; // continue after the inserted run
    }
  }

  // PATCH_S43_GAP_RESCUE ----------------------------------------------------

  // Finer grid for the second pass: gaps are short, so a 4s window on a 2s
  // stride resolves what the main 6s/5s grid smeared.
  static const double gapChunkSec = 4;
  static const double gapStepSec = 2;
  // Gaps shorter than this can't hold a recitation worth rescuing.
  static const double minGapToRescan = 2.5;
  // Give up on a gap whose mushaf-order candidate set would be this large —
  // the constrained-candidate prior that justifies the relaxed threshold is
  // gone at that point.
  static const int maxGapCandidates = 6;

  /// The ayat mushaf order allows inside a gap: everything from [before] to
  /// [after] inclusive (the anchors themselves can spill into the gap), the
  /// two ayat preceding the first detection for the head gap, or the two
  /// following the last one for the tail gap. Returns empty when the span is
  /// too wide to constrain anything. Pure and public for unit tests.
  static List<Ayah> expectedInGap(Ayah? before, Ayah? after, List<Ayah> ayaat) {
    if (before == null && after == null) return const [];
    if (before == null) {
      final i = ayaat.indexOf(after!); // identity ==
      if (i < 0) return [after];
      return ayaat.sublist(max(0, i - 2), i + 1);
    }
    if (after == null) {
      final i = ayaat.indexOf(before);
      if (i < 0) return [before];
      return ayaat.sublist(i, min(ayaat.length, i + 3));
    }
    final i = ayaat.indexOf(before);
    final j = ayaat.indexOf(after);
    if (i < 0 || j < 0 || j <= i) return [before, after];
    if (j - i + 1 > maxGapCandidates) return const [];
    return ayaat.sublist(i, j + 1);
  }

  /// Second detection pass over every span the main scan left empty. Each
  /// gap is rescanned on the finer [gapChunkSec]/[gapStepSec] grid and
  /// scored ONLY against [expectedInGap]'s candidates via matchAmong — the
  /// strong positional prior is what makes the relaxed threshold safe.
  /// Rescued spans are inserted in place (sorted afterwards); merging into
  /// neighbours is left to the repairTimeline call that follows.
  static Future<void> _rescanGaps({
    required List<TimelineSegment> timeline,
    required Int16List pcm,
    required AyahMatcher matcher,
    required Directory tempDir,
    required double silenceGate,
    required double totalSec,
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    if (timeline.isEmpty) return;
    // (start, end, candidates) per gap, edges included
    final gaps = <(double, double, List<Ayah>)>[];
    void addGap(double from, double to, Ayah? before, Ayah? after) {
      if (to - from < minGapToRescan) return;
      final cands = expectedInGap(before, after, matcher.ayaat);
      if (cands.isEmpty) return;
      gaps.add((from, to, cands));
    }

    addGap(0, timeline.first.start, null, timeline.first.ayah);
    for (var i = 0; i + 1 < timeline.length; i++) {
      addGap(timeline[i].end, timeline[i + 1].start, timeline[i].ayah,
          timeline[i + 1].ayah);
    }
    addGap(timeline.last.end, totalSec, timeline.last.ayah, null);
    if (gaps.isEmpty) return;

    final totalWindows = gaps.fold<int>(
        0, (n, g) => n + max(1, ((g.$2 - g.$1) / gapStepSec).ceil()));
    var done = 0;
    final rescued = <TimelineSegment>[];
    for (final (gapStart, gapEnd, candidates) in gaps) {
      TimelineSegment? current;
      for (double t = gapStart; t < gapEnd; t += gapStepSec) {
        if (_cancelRequested) {
          throw Exception('تم إلغاء المزامنة'); // PATCH_S37_CANCEL_LONG_JOBS
        }
        done++;
        onStatus?.call('جارٍ فحص الفجوات بدقة أعلى: $done من $totalWindows…');
        onProgress?.call(0.9 + 0.1 * done / totalWindows);

        final startSample = (t * sampleRate).floor();
        final endSample = min(
            pcm.length, (min(t + gapChunkSec, gapEnd) * sampleRate).floor());
        if (endSample - startSample < sampleRate * 1.2) continue;
        final slice = Int16List.sublistView(pcm, startSample, endSample);
        if (_rmsEnergy(slice) < silenceGate) {
          current = null;
          continue;
        }

        AyahMatch? match;
        try {
          final chunkPath = '${tempDir.path}/gap_$done.wav';
          _writeWavMono16(chunkPath, slice);
          final text = await WhisperService.transcribeWav(chunkPath);
          File(chunkPath).delete().ignore();
          match = matcher.matchAmong(text, candidates,
              minConfidence: contextMinConfidence);
        } catch (_) {
          continue; // one failed window shouldn't kill the rescue
        }
        if (match == null) {
          current = null;
          continue;
        }
        final end = min(t + gapChunkSec, gapEnd);
        if (current != null && identical(current.ayah, match.ayah)) {
          current.end = end;
          current.confidence = max(current.confidence, match.confidence);
        } else {
          current = TimelineSegment(
              start: t, end: end, ayah: match.ayah, confidence: match.confidence);
          rescued.add(current);
        }
      }
    }
    if (rescued.isEmpty) return;
    timeline.addAll(rescued);
    timeline.sort((a, b) => a.start.compareTo(b.start));
  }

  /// The main scan quantizes the first segment's start and the last one's
  /// end to the window grid, which can caption up to a whole step of leading
  /// or trailing room tone. Walk 120ms windows inward until the audio
  /// actually clears [gate] and snap the edge there (with a small pre/post
  /// roll so the first/last syllable's attack isn't clipped). Pure over the
  /// PCM and public for unit tests.
  static void snapEdgesToSpeech(
      List<TimelineSegment> timeline, Int16List pcm, double gate) {
    if (timeline.isEmpty) return;
    const winSec = 0.12, hopSec = 0.05, rollSec = 0.15;
    double rmsAt(double t) {
      final s = max(0, (t * sampleRate).floor());
      final e = min(pcm.length, ((t + winSec) * sampleRate).floor());
      if (e <= s) return 0;
      return _rmsEnergy(Int16List.sublistView(pcm, s, e));
    }

    final first = timeline.first;
    var t = first.start;
    final startLimit = first.end - 0.5;
    while (t < startLimit && rmsAt(t) < gate) {
      t += hopSec;
    }
    if (t < startLimit) first.start = max(first.start, t - rollSec);

    final last = timeline.last;
    var e = last.end - winSec;
    final endLimit = last.start + 0.5;
    while (e > endLimit && rmsAt(e) < gate) {
      e -= hopSec;
    }
    if (e > endLimit) last.end = min(last.end, e + winSec + rollSec);
  }

  /// PATCH_S35_SMARTER_DETECTION: resolves the 6s-window/5s-step grid
  /// artifacts. Consecutive segments that overlap (the previous window
  /// reached past where the next ayah was first heard) get split at the
  /// midpoint of the overlap; small gaps (≤ one step — recitation is
  /// continuous, the gap is just a window that matched nothing) are bridged
  /// the same way. Public and pure so it's unit-testable.
  static void normalizeTimeline(
      List<TimelineSegment> timeline, double totalSec) {
    if (timeline.isEmpty) return;
    for (var i = 0; i + 1 < timeline.length; i++) {
      final a = timeline[i], b = timeline[i + 1];
      if (a.end > b.start || b.start - a.end <= stepSec + 0.01) {
        final mid = (a.end + b.start) / 2;
        a.end = mid;
        b.start = mid;
      }
    }
    timeline.first.start = max(0, timeline.first.start);
    timeline.last.end = min(totalSec, max(timeline.last.end, timeline.last.start + 0.5));
  }

  // PATCH_S35_SMARTER_DETECTION: reciters pause for breath between ayat —
  // scan ±1.5s around each shared segment boundary in 80ms hops and move
  // the boundary to the center of the quietest 240ms window.
  static void _refineBoundaries(
      List<TimelineSegment> timeline, Int16List pcm) {
    const searchSec = 1.5, winSec = 0.24, hopSec = 0.08;
    for (var i = 0; i + 1 < timeline.length; i++) {
      final a = timeline[i], b = timeline[i + 1];
      if ((b.start - a.end).abs() > 0.01) continue; // only shared boundaries
      final lo = max(a.start + 0.5, a.end - searchSec);
      final hi = min(b.end - 0.5, b.start + searchSec);
      if (hi - lo < winSec + 0.05) continue;
      var bestT = a.end;
      var bestRms = double.infinity;
      for (var t = lo; t + winSec <= hi; t += hopSec) {
        final s = (t * sampleRate).floor();
        final e = min(pcm.length, ((t + winSec) * sampleRate).floor());
        if (e <= s) break;
        final rms = _rmsEnergy(Int16List.sublistView(pcm, s, e));
        if (rms < bestRms) {
          bestRms = rms;
          bestT = t + winSec / 2;
        }
      }
      a.end = bestT;
      b.start = bestT;
    }
  }

  static double _rmsEnergy(Int16List samples) {
    if (samples.isEmpty) return 0;
    double sum = 0;
    for (final s in samples) {
      final f = s / 32768.0;
      sum += f * f;
    }
    return sqrt(sum / samples.length);
  }

  /// Reads the 16-bit mono PCM samples out of a WAV file, walking the RIFF
  /// chunks properly instead of assuming a fixed 44-byte header (ffmpeg can
  /// emit LIST/INFO chunks before `data`).
  static Int16List _readWavMono16(String path) {
    final bytes = File(path).readAsBytesSync();
    final bd = ByteData.sublistView(bytes);
    if (bytes.length < 12 ||
        String.fromCharCodes(bytes.sublist(0, 4)) != 'RIFF' ||
        String.fromCharCodes(bytes.sublist(8, 12)) != 'WAVE') {
      throw Exception('ملف الصوت المستخرج ليس WAV صالحًا');
    }
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = String.fromCharCodes(bytes.sublist(offset, offset + 4));
      final size = bd.getUint32(offset + 4, Endian.little);
      if (id == 'data') {
        final end = min(bytes.length, offset + 8 + size);
        final data = bytes.sublist(offset + 8, end);
        return Int16List.sublistView(
            Uint8List.fromList(data), 0, data.length ~/ 2);
      }
      offset += 8 + size + (size.isOdd ? 1 : 0);
    }
    throw Exception('لم يُعثر على بيانات الصوت داخل ملف WAV');
  }

  static void _writeWavMono16(String path, Int16List samples) {
    final dataLen = samples.length * 2;
    final header = ByteData(44);
    void putAscii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        header.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    putAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataLen, Endian.little);
    putAscii(8, 'WAVE');
    putAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, 1, Endian.little); // mono
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    header.setUint16(32, 2, Endian.little); // block align
    header.setUint16(34, 16, Endian.little); // bits per sample
    putAscii(36, 'data');
    header.setUint32(40, dataLen, Endian.little);

    final out = BytesBuilder();
    out.add(header.buffer.asUint8List());
    out.add(samples.buffer
        .asUint8List(samples.offsetInBytes, dataLen));
    File(path).writeAsBytesSync(out.takeBytes());
  }
}
