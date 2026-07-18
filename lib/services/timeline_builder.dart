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
//   6. PATCH_S82_AUTOSYNC_MAX: four robustness passes on top:
//      • the silence gate adapts to the clip's own noise floor instead of a
//        fixed -42 dBFS, so noisy room tone no longer reaches Whisper (which
//        hallucinates on it) and unusually clean/quiet recordings keep the
//        proven fixed gate;
//      • a short weak mis-detection sandwiched between two halves of the
//        SAME ayah is recognized as noise and merged away;
//      • a second, finer Whisper pass re-scans every span the main scan left
//        unmatched (including before the first and after the last detection),
//        scored ONLY against the ayat mushaf order allows at that spot;
//      • when a same-surah jump (N → N+2/N+3) still remains and the gap
//        holds enough recitation time, the skipped ayat are inferred into it
//        (flagged `inferred` so the UI can show them for review) — real
//        acoustic evidence from the rescue pass always wins over inference.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../models/studio_state.dart';
import 'ayah_matcher.dart';
import 'media_service.dart';
import 'whisper_service.dart';

// PATCH_S77_ONSET_ENERGY_SNAP
// PATCH_S78_FIX_S77_CLAMP_TYPE_ERROR
class TimelineBuilder {
  static const double chunkSec = 6; // analysis window length
  // PATCH_S84_AUTOSYNC_PRECISION_V2: tighter stride -> more overlap between
  // consecutive scan windows (was 5s stride / 1s overlap; now 2s overlap),
  // so a phrase sitting right on a window edge gets a full, un-truncated
  // hearing in at least one of the two windows that cover it, instead of
  // being cut short on both sides and never transcribing cleanly enough
  // to match anything.
  static const double stepSec = 4; // window stride
  static const double minConfidence = 0.32;
  static const double highConfidence = 0.55; // commit off a single window
  // PATCH_S44_CONFIDENCE_RETRANSCRIBE: segments that committed but stayed below this bar get a
  // focused second look once their real (refined) boundaries are known --
  // a tight, single-ayah-sized window often transcribes more cleanly than
  // the original coarse 6s scan window did.
  static const double reTranscribeBelowConfidence = 0.45;
  static const double vadSilenceRms = 0.008; // ~-42 dBFS
  static const int sampleRate = 16000;
  // PATCH_S35_SMARTER_DETECTION: thresholds for the expected-next re-score.
  // The mushaf-order prior lets us accept weaker acoustic evidence, and the
  // bonus lets an expected ayah win a near-tie against an unrelated one.
  static const double contextMinConfidence = 0.22;
  static const double contextPriorBonus = 0.08;
  // PATCH_S31_ACCURATE_SYNC: max gap (seconds) between two same-ayah pieces
  // for them to be merged into one segment — keeps a repeated ayah heard
  // much later in the clip from stretching a stale segment across the gap.
  static const double mergeGapSec = 2.0;
  // PATCH_S31_ACCURATE_SYNC: with real phrase timestamps the segments are no
  // longer quantized to the 5s scan grid, so only genuinely small gaps
  // (breath pauses / one garbled phrase) get bridged in normalization.
  static const double bridgeGapSec = 3.0;

  // PATCH_S37_CANCEL_LONG_JOBS: lets the UI abort a long scan; checked once
  // per window so cancellation lands within ~1 window's processing time.
  static bool _cancelRequested = false;
  static void requestCancel() => _cancelRequested = true;

  /// Scans [mediaPath] (video or audio) and returns the detected ayah
  /// timeline. [onStatus] receives human-readable Arabic progress text,
  /// [onProgress] a 0..1 fraction.
  /// PATCH_S86_SCAN_RANGE: [scanStart]/[scanEnd] limit the scan to that
  /// span of the clip (used when a manual cut is set — only the part that
  /// will actually be exported gets analyzed, which is proportionally
  /// faster). Segment times stay absolute clip seconds either way.
  // PATCH_S90_HONEST_COVERAGE: returns the real decoded duration
  // alongside the timeline so callers can report coverage against
  // the actual clip length instead of a possibly-unset video duration.
  static Future<({List<TimelineSegment> timeline, double totalSec, String? decodeWarning})> build({
    required String mediaPath,
    required AyahMatcher matcher,
    double? scanStart,
    double? scanEnd,
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    _cancelRequested = false; // PATCH_S37_CANCEL_LONG_JOBS
    await WhisperService.ensureReady(onStatus: onStatus);

    onStatus?.call('جارٍ استخراج الصوت الكامل…');
    final wavPath = await MediaService.extractWav16kMono(mediaPath);
    final pcm = _readWavMono16(wavPath);

    final decodedSec = pcm.length / sampleRate;
    // PATCH_S96_HONEST_SCAN_DURATION: cross-check the decode against the
    // container's own declared duration. ffmpeg decodes real audio frames
    // (immune to a bad/short duration HEADER, per PATCH_S89's export fix)
    // -- but a genuinely truncated/corrupt source can still make the
    // decode itself come up short, and nothing before this caught that
    // case: coverage would silently measure itself against its own short
    // decode and read back near 100% no matter how much was actually
    // missed. Report whichever is longer; the scan loop below still only
    // works with the audio actually decoded, since that's all there is to
    // scan -- this only changes what's REPORTED as the clip's real length.
    final probedSec = await MediaService.probedDurationSec(mediaPath);
    final totalSec =
        (probedSec != null && probedSec > decodedSec) ? probedSec : decodedSec;
    // PATCH_S97_DECODE_MISMATCH_WARNING: a real, meaningful gap between what
    // the container claims and what ffmpeg actually decoded means part of
    // THIS SPECIFIC FILE's audio never made it into the scan at all -- not a
    // detection-quality problem tunable from here, a source-file problem
    // (most likely corrupted, or discontinuous partway through). Surface it
    // plainly and specifically instead of letting it hide behind a coverage
    // percentage the person has to notice and correctly interpret themselves.
    final String? decodeWarning =
        (probedSec != null && probedSec > decodedSec * 1.1)
            ? 'تنبيه: مدة الملف الأصلي ~${probedSec.round()}ث لكن تم فك ترميز '
                '~${decodedSec.round()}ث فقط منه فعليًا — على الأرجح الملف تالف '
                'أو يحتوي جزءًا غير مقروء بعد هذه النقطة (وليس مشكلة في دقة '
                'الرصد نفسها). جرّب تصدير/تسجيل الملف من جديد.'
            : null;
    // PATCH_S86_SCAN_RANGE
    final rangeStart = (scanStart ?? 0).clamp(0.0, decodedSec);
    final rangeEnd = (scanEnd == null || scanEnd <= rangeStart)
        ? decodedSec
        : scanEnd.clamp(rangeStart, decodedSec);
    final totalChunks = max(1, ((rangeEnd - rangeStart) / stepSec).ceil());

    // PATCH_S82_AUTOSYNC_MAX: one cheap pre-pass over the scanned span to
    // learn its noise floor, so the silence gate below fits THIS recording.
    final windowRms = <double>[];
    for (double t = rangeStart; t < rangeEnd; t += stepSec) {
      final s = (t * sampleRate).floor();
      final e = min(pcm.length, ((t + chunkSec) * sampleRate).floor());
      windowRms
          .add(e > s ? _rmsEnergy(Int16List.sublistView(pcm, s, e)) : 0.0);
    }
    final silenceGate = adaptiveSilenceThreshold(windowRms);

    final tempDir = Directory.systemTemp.createTempSync('ayat_timeline');
    final timeline = <TimelineSegment>[];
    // PATCH_S31_ACCURATE_SYNC: a borderline match is held as `pending` and
    // merged into one segment once a close-in-time piece agrees on the same
    // ayah — but `pending` is never just discarded. It's flushed (committed
    // as-is) on a real silence gap, when the recitation clearly moves to
    // something else, and always at the end of the scan, so a partial ayah
    // that never gets a confirming second piece still ends up in the
    // timeline instead of silently vanishing.
    TimelineSegment? pending;
    var chunkIndex = 0;
    // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES: distinguishes "we transcribed the audio but
    // nothing matched confidently" (a normal, expected outcome) from
    // "transcription itself never worked" (an engine/model problem) --
    // the two look identical as an empty timeline unless tracked.
    var windowsAttempted = 0;
    var windowsFailed = 0;
    Object? lastTranscribeError;

    void flushPending() {
      final p = pending;
      if (p != null) {
        timeline.add(p);
        pending = null;
      }
    }

    try {
      for (double t = rangeStart; t < rangeEnd; t += stepSec) { // PATCH_S86_SCAN_RANGE
        if (_cancelRequested) {
          throw Exception('تم إلغاء المزامنة'); // PATCH_S37_CANCEL_LONG_JOBS
        }
        chunkIndex++;
        onStatus?.call('جارٍ رصد الآيات: مقطع $chunkIndex من $totalChunks…');
        // PATCH_S82_AUTOSYNC_MAX: the head 90% — the gap-rescue pass owns
        // the remainder.
        onProgress?.call(0.9 * chunkIndex / totalChunks);
        // PATCH_S95_UI_RESPONSIVE_SCAN: a clean scheduling point between
        // chunks -- an unbroken run of native transcription calls can
        // otherwise leave the UI thread starved long enough for Android to
        // treat the app as unresponsive.
        await Future<void>.delayed(Duration.zero);

        final startSample = (t * sampleRate).floor();
        final endSample =
            min(pcm.length, ((t + chunkSec) * sampleRate).floor());
        if (endSample - startSample < sampleRate * 1.2) continue; // tiny tail

        final slice = Int16List.sublistView(pcm, startSample, endSample);
        if ((chunkIndex - 1 < windowRms.length
                ? windowRms[chunkIndex - 1]
                : _rmsEnergy(slice)) <
            silenceGate) {
          flushPending(); // real gap in speech — whatever was pending is done
          continue;
        }

        // PATCH_S31_ACCURATE_SYNC: ask Whisper for its own phrase-level
        // timestamps within this window instead of treating the window as
        // one opaque blob — this is what makes the on-screen timing track
        // the real audio instead of drifting ahead of الشيخ.
        final windowDurationSec = (endSample - startSample) / sampleRate;
        WhisperTranscript transcript;
        windowsAttempted++; // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES
        final chunkPath = '${tempDir.path}/chunk_$chunkIndex.wav';
        _writeWavMono16(chunkPath, slice);
        try {
          transcript = await WhisperService.transcribeWavWithSegments(
            chunkPath,
            audioDurationSec: windowDurationSec,
            splitOnWord: true, // PATCH_S55_WORD_TIMESTAMPS
          );
        } catch (e) {
          // PATCH_S61_SPLITONWORD_FALLBACK: whisper_ggml_plus's word-split path is narrower
          // than its normal one (it force-disables VAD, per its own docs)
          // and can throw a json.exception.type_error.302 for some inputs.
          // Retry this window without word-splitting before giving up on
          // it -- _groupWords() already falls back to whole-window text
          // when no per-word timestamps come back, so this only costs
          // karaoke-onset precision for the affected window(s), not the
          // whole video's detection.
          try {
            transcript = await WhisperService.transcribeWavWithSegments(
              chunkPath,
              audioDurationSec: windowDurationSec,
              splitOnWord: false,
            );
          } catch (e2) {
            File(chunkPath).delete().ignore();
            windowsFailed++; // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES
            lastTranscribeError = e2; // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES
            continue; // one failed window shouldn't kill the whole scan
          }
        }
        File(chunkPath).delete().ignore();

        // PATCH_S55_WORD_TIMESTAMPS: per-word segments are grouped back into
        // phrases for corpus matching (single words can't match an ayah),
        // while each word's onset is kept to pace the karaoke lighting.
        // Falls back to the whole window when no timestamps came back.
        // PATCH_S84_AUTOSYNC_PRECISION_V2: pass this window's own audio +
        // the clip's adaptive silence gate through, so the no-segments
        // fallback inside _groupWords can trim to where the real speech
        // actually is instead of trusting the raw window bounds.
        final pieces = _groupWords(
            transcript.segments, windowDurationSec, transcript.text,
            pcm: slice, silenceGate: silenceGate);

        for (final (piece, rawOnsets) in pieces) {
          final text = piece.text.trim();
          if (text.isEmpty) continue;
          // PATCH_S86_ASR_JUNK_FILTER: Whisper narrates non-speech audio
          // with stock YouTube-caption phrases ("اشتركوا في القناة",
          // "موسيقى"…). Those windows are noise, not recitation — treat
          // them exactly like silence so they can't extend or seed a
          // segment via the relaxed mushaf-order rescore.
          if (isAsrHallucination(text)) {
            flushPending();
            continue;
          }
          final absStart = t + piece.startSec;
          final absEnd = max(absStart + 0.2, t + piece.endSec);
          final rawAbsOnsets = [for (final s in rawOnsets) t + s];
          // PATCH_S77_ONSET_ENERGY_SNAP: correct against real audio energy
          // instead of trusting Whisper's per-word timestamp as-is.
          final absOnsets =
              _snapOnsetsToEnergyAttacks(pcm, sampleRate, rawAbsOnsets);

          var match = matcher.match(text, minConfidence: minConfidence);

          // PATCH_S35_SMARTER_DETECTION: when the corpus-wide search failed
          // or stayed below the single-piece commit bar, re-score just the
          // ayat the mushaf order predicts here (current ayah continuing,
          // next, next-after) with a relaxed threshold and a prior bonus.
          final anchor =
              pending?.ayah ?? (timeline.isEmpty ? null : timeline.last.ayah);
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
            flushPending();
            continue;
          }

          // Same ayah continuing close in time — extend the open segment.
          // (The time bound keeps a repeated ayah heard much later in the
          // clip from stretching a stale segment across the gap; using max()
          // absorbs re-hearings from the overlapping scan windows.)
          final p = pending;
          if (p != null &&
              identical(p.ayah, match.ayah) &&
              absStart - p.end <= mergeGapSec) {
            p.end = max(p.end, absEnd);
            p.confidence = max(p.confidence, match.confidence);
            _appendOnsets(p.wordStarts, absOnsets); // PATCH_S55_WORD_TIMESTAMPS
            // a close-in-time piece agrees — commit, backdated to where
            // the ayah first appeared
            flushPending();
            continue;
          }
          final last = timeline.isEmpty ? null : timeline.last;
          if (p == null &&
              last != null &&
              identical(last.ayah, match.ayah) &&
              absStart - last.end <= mergeGapSec) {
            last.end = max(last.end, absEnd);
            last.confidence = max(last.confidence, match.confidence);
            _appendOnsets(last.wordStarts, absOnsets); // PATCH_S55_WORD_TIMESTAMPS
            continue;
          }

          if (match.confidence >= highConfidence) {
            flushPending();
            timeline.add(TimelineSegment(
                start: absStart,
                end: absEnd,
                ayah: match.ayah,
                confidence: match.confidence,
                wordStarts: List.of(absOnsets)));
          } else {
            // previous pending (if any) never got reconfirmed — commit it
            // as-is rather than silently dropping it, then open the new one
            flushPending();
            pending = TimelineSegment(
                start: absStart,
                end: absEnd,
                ayah: match.ayah,
                confidence: match.confidence,
                wordStarts: List.of(absOnsets));
          }
        }
      }
      // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES: an empty timeline because nothing matched is a
      // normal outcome the UI already explains well. An empty timeline
      // because transcription itself never once succeeded is a broken
      // engine/model, and silently reporting it the same way just hides
      // the real problem -- surface it instead.
      if (windowsAttempted > 0 && windowsFailed == windowsAttempted) {
        throw Exception(
            'تعذّر التعرّف على الكلام في كل مقاطع هذا الفيديو (${lastTranscribeError ?? "خطأ غير معروف"}) — '
            'جرّب حجم نموذج مختلف من الإعدادات أو أعد تشغيل التطبيق.');
      }
      // PATCH_S31_ACCURATE_SYNC: a partial ayah still pending at the very
      // end of the scan is real — commit it instead of dropping it.
      flushPending();
      // PATCH_S82_AUTOSYNC_MAX: structural repairs and the gap-rescue pass
      // need the raw gaps that normalization would bridge away, so they run
      // first: repair → hear what the gaps actually contain → re-merge any
      // rescued pieces → only then infer what still couldn't be heard.
      repairTimeline(timeline);
      // PATCH_S88_AUTOSYNC_HONEST_FIX: drop out-of-mushaf-order weak
      // detections before anything downstream can build on them.
      _enforceMushafOrderChain(timeline);
      await _rescanGaps(
        timeline: timeline,
        pcm: pcm,
        matcher: matcher,
        tempDir: tempDir,
        silenceGate: silenceGate,
        // PATCH_S86_SCAN_RANGE: head/tail gaps end at the scanned span, not
        // the whole clip — outside it there's nothing we're exporting.
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        onStatus: onStatus,
        onProgress: onProgress,
      );
      repairTimeline(timeline);
      // PATCH_S92_TRAILING_INFERENCE: also needs to know where the real
      // recording actually ends.
      inferSkippedAyat(timeline, matcher.ayaat, rangeEnd);
      // PATCH_S35_SMARTER_DETECTION: resolve overlaps/small gaps and snap
      // ayah boundaries to the reciter's breath pauses.
      normalizeTimeline(timeline, totalSec);
      _refineBoundaries(timeline, pcm);
      // PATCH_S44_CONFIDENCE_RETRANSCRIBE: give low-confidence segments one more focused look now
      // that their real boundaries are known. (PATCH_S82_AUTOSYNC_MAX: this
      // also doubles as free verification of inferred segments — their 0.3
      // confidence puts them under the re-transcribe bar, and if Whisper
      // hears the inferred ayah in that span it's upgraded to a real match.)
      await _reTranscribeWeakSegments(timeline, pcm, matcher, tempDir,
          onStatus: onStatus);
      onProgress?.call(1);
    } finally {
      tempDir.delete(recursive: true).ignore();
      File(wavPath).delete().ignore();
    }
    return (
      timeline: timeline,
      totalSec: totalSec,
      decodeWarning: decodeWarning,
    ); // PATCH_S90_HONEST_COVERAGE / PATCH_S97_DECODE_MISMATCH_WARNING
  }

  // PATCH_S88_AUTOSYNC_HONEST_FIX: a detection strong enough to stand on
  // its own outside the chain -- a clearly-heard deliberate repeat, or a
  // genuinely correct out-of-order match -- without needing chain support.
  static const double chainKeepConfidence = 0.5;

  /// PATCH_S88_AUTOSYNC_HONEST_FIX: the deepest structural flaw in the old
  /// pipeline was that ANY single scan window scoring above [minConfidence]
  /// got committed to the timeline as-is, so one garbled window = one wrong
  /// ayah in the results. Recitation follows mushaf order, so this finds
  /// the maximum-weight (duration × confidence) subsequence of [timeline]
  /// whose ayat are in strictly increasing mushaf order (surah, then ayah
  /// number) and drops everything outside that chain UNLESS it's
  /// individually strong enough ([chainKeepConfidence]+) to survive on its
  /// own -- a clearly-heard deliberate repeat necessarily breaks strict
  /// order, so it has to earn its place by confidence rather than by chain
  /// membership. Runs before the gap-rescue/inference passes so a wrong
  /// ayah here can't go on to anchor wrong inferences or wrong rescue
  /// matches around it.
  static void _enforceMushafOrderChain(List<TimelineSegment> timeline) {
    final n = timeline.length;
    if (n < 2) return;

    int key(TimelineSegment s) => s.ayah.surahNum * 10000 + s.ayah.num;
    final weight = [
      for (final s in timeline) (s.end - s.start) * s.confidence
    ];

    // dp[i] = best total weight of an in-order chain ending at segment i.
    final dp = List<double>.filled(n, 0);
    final prev = List<int>.filled(n, -1);
    for (var i = 0; i < n; i++) {
      dp[i] = weight[i];
      for (var j = 0; j < i; j++) {
        if (key(timeline[j]) < key(timeline[i]) &&
            dp[j] + weight[i] > dp[i]) {
          dp[i] = dp[j] + weight[i];
          prev[i] = j;
        }
      }
    }

    var bestEnd = 0;
    for (var i = 1; i < n; i++) {
      if (dp[i] > dp[bestEnd]) bestEnd = i;
    }

    final inChain = List<bool>.filled(n, false);
    for (var cur = bestEnd; cur != -1; cur = prev[cur]) {
      inChain[cur] = true;
    }

    final kept = <TimelineSegment>[
      for (var i = 0; i < n; i++)
        if (inChain[i] || timeline[i].confidence >= chainKeepConfidence)
          timeline[i],
    ];
    if (kept.length == timeline.length) return; // nothing to drop
    timeline
      ..clear()
      ..addAll(kept);
  }

  // PATCH_S44_CONFIDENCE_RETRANSCRIBE: re-transcribes each committed segment that stayed below
  // [reTranscribeBelowConfidence], using its own refined (tight,
  // single-ayah-sized) boundaries instead of the original coarse scan
  // window. Replaces the segment in place only if the new pass scores
  // strictly higher -- never makes a confident match worse, and any
  // failure on an individual segment (transcription error, empty text,
  // no better candidate) just leaves that segment exactly as it was.
  static Future<void> _reTranscribeWeakSegments(
    List<TimelineSegment> timeline,
    Int16List pcm,
    AyahMatcher matcher,
    Directory tempDir, {
    void Function(String status)? onStatus,
  }) async {
    for (var i = 0; i < timeline.length; i++) {
      if (_cancelRequested) return;
      final seg = timeline[i];
      if (seg.confidence >= reTranscribeBelowConfidence) continue;
      final durSec = seg.end - seg.start;
      if (durSec < 0.6) continue; // too short to bother re-transcribing

      final startSample =
          (seg.start * sampleRate).floor().clamp(0, pcm.length);
      final endSample =
          (seg.end * sampleRate).floor().clamp(startSample, pcm.length);
      if (endSample - startSample < (sampleRate * 0.5).round()) continue;

      onStatus?.call(
          'تحسين دقة آية ذات ثقة منخفضة (${i + 1}/${timeline.length})…');
      // PATCH_S95_UI_RESPONSIVE_SCAN: same responsiveness yield as the
      // main scan loop.
      await Future<void>.delayed(Duration.zero);
      final slice = Int16List.sublistView(pcm, startSample, endSample);
      final chunkPath = '${tempDir.path}/retrans_$i.wav';
      String text;
      try {
        _writeWavMono16(chunkPath, slice);
        text = await WhisperService.transcribeWav(chunkPath);
      } catch (_) {
        continue; // a failed re-pass just keeps the original segment
      } finally {
        File(chunkPath).delete().ignore();
      }
      if (text.trim().isEmpty) continue;

      // Prefer testing against the mushaf-order neighbourhood first (same
      // prior used during the main scan) -- a weak match is often just a
      // slightly-off boundary on the SAME or an ADJACENT ayah, not a wild
      // miss -- falling back to a corpus-wide search so a genuinely
      // different ayah can still win if the neighbourhood check fails.
      final neighbours = _expectedNext(matcher.ayaat, seg.ayah);
      var candidate = matcher.matchAmong(text, neighbours,
          minConfidence: contextMinConfidence);
      candidate ??= matcher.match(text, minConfidence: minConfidence);
      if (candidate != null && candidate.confidence > seg.confidence) {
        timeline[i] = TimelineSegment(
          start: seg.start,
          end: seg.end,
          ayah: candidate.ayah,
          confidence: candidate.confidence,
          // PATCH_S82_AUTOSYNC_MAX: keep the acoustic word onsets (they
          // belong to the audio span, not the ayah label) and clear the
          // inferred flag — this span has now actually been heard.
          wordStarts: seg.wordStarts,
        );
      }
    }
  }

  // PATCH_S55_WORD_TIMESTAMPS: groups Whisper's per-word segments back into
  // matchable phrases (split on >1s pauses or every 14 words), keeping each
  // word's onset. If splitOnWord ever returns phrase-level segments (older
  // native builds), the same grouping still works — onsets just get coarser
  // and karaoke pacing degrades gracefully toward the linear fallback.
  static List<(TranscriptSegment, List<double>)> _groupWords(
      List<TranscriptSegment> words,
      double windowDurationSec,
      String fullText, {
      Int16List? pcm,
      double silenceGate = vadSilenceRms,
      }) {
    if (words.isEmpty) {
      // PATCH_S84_AUTOSYNC_PRECISION_V2: Whisper sometimes returns text but
      // no segments at all for a window. The old fallback blindly used the
      // whole 6s scan window as the ayah's span -- if the real speech only
      // filled part of it, the segment's start/end could be wrong by
      // however much silence or other-ayah audio shared the window (up to
      // the full window length, i.e. several seconds). Trim to where this
      // window's own audio actually crosses the silence gate instead.
      final (trimStart, trimEnd) = pcm != null
          ? _trimWindowToSpeech(pcm, windowDurationSec, silenceGate)
          : (0.0, windowDurationSec);
      return [(TranscriptSegment(trimStart, trimEnd, fullText), const [])];
    }
    final out = <(TranscriptSegment, List<double>)>[];
    final buf = StringBuffer();
    var starts = <double>[];
    var pStart = 0.0, pEnd = 0.0;
    void flush() {
      if (starts.isNotEmpty) {
        out.add(
            (TranscriptSegment(pStart, pEnd, buf.toString().trim()), starts));
        buf.clear();
        starts = <double>[];
      }
    }

    for (final w in words) {
      if (w.text.trim().isEmpty) continue;
      if (starts.isNotEmpty &&
          (w.startSec - pEnd > 1.0 || starts.length >= 14)) {
        flush();
      }
      if (starts.isEmpty) pStart = w.startSec;
      starts.add(w.startSec);
      buf.write('${w.text.trim()} ');
      pEnd = max(w.endSec, w.startSec + 0.1);
    }
    flush();
    return out;
  }

  // PATCH_S84_AUTOSYNC_PRECISION_V2: used only by _groupWords' no-segments
  // fallback above. Scans this window's own PCM in 100ms frames and returns
  // (firstAboveGate, lastAboveGate) -- the real speech extent inside the
  // window -- instead of the caller having to trust the window's outer
  // bounds. Falls back to the full window when nothing clears the gate
  // (silence-only window that still produced text is rare, but keeping the
  // full span rather than guessing is the safer failure mode).
  static const double _trimFrameSec = 0.1;
  static (double, double) _trimWindowToSpeech(
      Int16List pcm, double windowDurationSec, double silenceGate) {
    final frameLen = (_trimFrameSec * sampleRate).round();
    if (frameLen <= 0 || pcm.length < frameLen) {
      return (0.0, windowDurationSec);
    }
    double? onset;
    for (var s = 0; s + frameLen <= pcm.length; s += frameLen) {
      final rms = _rmsEnergy(Int16List.sublistView(pcm, s, s + frameLen));
      if (rms >= silenceGate) {
        onset = s / sampleRate;
        break;
      }
    }
    double? offset;
    for (var s = pcm.length - frameLen; s >= 0; s -= frameLen) {
      final rms = _rmsEnergy(Int16List.sublistView(pcm, s, s + frameLen));
      if (rms >= silenceGate) {
        offset = (s + frameLen) / sampleRate;
        break;
      }
    }
    if (onset == null || offset == null || offset <= onset) {
      return (0.0, windowDurationSec);
    }
    return (onset, min(windowDurationSec, offset));
  }

  // PATCH_S55_WORD_TIMESTAMPS: sorted-append with dedupe — overlapping scan
  // windows re-hear the same words, so onsets within 50ms of an existing
  // one are dropped.
  static void _appendOnsets(List<double> into, List<double> add) {
    for (final s in add) {
      if (into.isEmpty || s > into.last + 0.05) into.add(s);
    }
  }

  // PATCH_S35_SMARTER_DETECTION: the ayat mushaf order predicts after
  // [anchor]: the anchor itself (still being recited) and the next two.
  // PATCH_S82_AUTOSYNC_MAX: plus the ayah BEFORE the anchor — repeating the
  // previous ayah is common in memorization/practice recordings.
  static List<Ayah> _expectedNext(List<Ayah> ayaat, Ayah anchor) {
    final i = ayaat.indexOf(anchor); // identity ==, Ayah defines no operator==
    if (i < 0) return [anchor];
    return [
      if (i > 0) ayaat[i - 1],
      ...ayaat.sublist(i, min(ayaat.length, i + 3)),
    ];
  }

  // PATCH_S86_ASR_JUNK_FILTER ------------------------------------------------

  // Stock phrases Whisper "hears" in music, applause and room noise —
  // artifacts of its YouTube-subtitle training data, not speech. Stored
  // pre-normalized (no tashkeel, ى→ي, ة→ه, alef forms→ا) to match
  // [_lightNormalize]'s output.
  static const List<String> _asrJunkPhrases = [
    'اشتركوا في القناه',
    'اشترك في القناه',
    'لا تنسي الاشتراك',
    'لا تنسوا الاشتراك',
    'فعلوا زر الجرس',
    'فعل زر الجرس',
    'جرس التنبيهات',
    'لايك واشتراك',
    'شكرا للمشاهده',
    'شكرا علي المشاهده',
    'ترجمه نانسي قنقر',
    'نانسي قنقر',
    'موسيقي',
    'تصفيق',
  ];

  static String _lightNormalize(String text) => text
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED\u0640]'), '') // tashkeel+tatweel, same ranges as AyahMatcher.normalize
      .replaceAll(RegExp(r'[إأآٱ]'), 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// True when [text] is one of Whisper's stock non-speech hallucination
  /// phrases (music/applause/subtitle credits). Pure and public for unit
  /// tests.
  static bool isAsrHallucination(String text) {
    final norm = _lightNormalize(text);
    if (norm.isEmpty) return false;
    for (final junk in _asrJunkPhrases) {
      if (norm.contains(junk)) return true;
    }
    return false;
  }

  // PATCH_S82_AUTOSYNC_MAX --------------------------------------------------

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
  ///   • adjacent segments of the same ayah merge (the scan already merges
  ///     close-in-time re-hearings, but rescue/editing can reintroduce
  ///     them);
  ///   • an A-B-A "sandwich": a single short span that matched some other
  ///     ayah B in the middle of ayah A's span, weaker than both A halves —
  ///     that's a garbled window, not a real jump away and back, so B is
  ///     dropped and the halves merge.
  static void repairTimeline(List<TimelineSegment> timeline) {
    for (var i = 0; i + 1 < timeline.length;) {
      final a = timeline[i], b = timeline[i + 1];
      if (identical(a.ayah, b.ayah) && b.start - a.end <= bridgeGapSec + 0.01) {
        a.end = max(a.end, b.end);
        a.confidence = max(a.confidence, b.confidence);
        _appendOnsets(a.wordStarts, b.wordStarts);
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
        _appendOnsets(a.wordStarts, b.wordStarts);
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
  /// back garbled even for the rescue pass. Insert them across the gap,
  /// splitting it proportionally to each ayah's word count, flagged
  /// [TimelineSegment.inferred] for the UI. Runs BEFORE normalizeTimeline,
  /// which would otherwise bridge exactly the gaps this pass reads. Pure and
  /// public for unit tests.
  static void inferSkippedAyat(
      List<TimelineSegment> timeline, List<Ayah> ayaat,
      // PATCH_S92_TRAILING_INFERENCE: needed to know how much real
      // recording time is left after the last detected segment.
      double clipEnd) {
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
        final end = j == missing.length - 1
            ? b.start
            : t + gap * weights[j] / totalWeight;
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
    // PATCH_S92_TRAILING_INFERENCE: the loop above only ever looks BETWEEN
    // two already-detected segments -- a gap after the very LAST segment
    // (the reciter kept going, but nothing after it was ever confidently
    // heard, not even by the gap-rescue pass) had no inference path at
    // all, so real recited ayat at the tail of a clip silently vanished
    // from the timeline instead of at least showing up flagged for
    // review like every other missed-but-inferable ayah does.
    if (timeline.isEmpty) return;
    final last = timeline.last;
    final remaining = clipEnd - last.end;
    if (remaining < _minSecPerInferredAyah) return;
    final li = ayaat.indexOf(last.ayah); // identity ==
    if (li < 0) return;
    final maxByTime = (remaining / _minSecPerInferredAyah).floor();
    final missing = <Ayah>[];
    for (var k = 1; k <= min(3, maxByTime); k++) {
      final idx = li + k;
      if (idx >= ayaat.length) break;
      final cand = ayaat[idx];
      if (cand.surahNum != last.ayah.surahNum) break; // don't guess across surahs
      missing.add(cand);
    }
    if (missing.isEmpty) return;
    final tailWeights = [
      for (final m in missing) m.ar.trim().split(RegExp(r'\s+')).length.toDouble()
    ];
    final tailTotalWeight = tailWeights.fold(0.0, (s, w) => s + w);
    var tt = last.end;
    for (var j = 0; j < missing.length; j++) {
      final end = j == missing.length - 1
          ? clipEnd
          : tt + remaining * tailWeights[j] / tailTotalWeight;
      timeline.add(TimelineSegment(
        start: tt,
        end: end,
        ayah: missing[j],
        confidence: 0.3,
        inferred: true,
      ));
      tt = end;
    }
  }

  // Finer grid for the rescue pass: gaps are short, so a 4s window on a 2s
  // stride resolves what the main 6s/5s grid smeared.
  static const double gapChunkSec = 4;
  static const double gapStepSec = 2;
  // Gaps shorter than this can't hold a recitation worth rescuing.
  // PATCH_S84_AUTOSYNC_PRECISION_V2: lowered from 2.5s -- a short
  // mis-heard fragment of an ayah (part of it, not the whole thing) was
  // falling under the old bar and never getting a rescue attempt at all.
  static const double minGapToRescan = 1.2;
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
  /// Rescued spans keep their word onsets (same word-split transcription as
  /// the main scan) and are inserted in place; merging into neighbours is
  /// left to the repairTimeline call that follows.
  static Future<void> _rescanGaps({
    required List<TimelineSegment> timeline,
    required Int16List pcm,
    required AyahMatcher matcher,
    required Directory tempDir,
    required double silenceGate,
    required double rangeStart, // PATCH_S86_SCAN_RANGE
    required double rangeEnd,
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    if (timeline.isEmpty) return;
    // (start, end, candidates) per gap, head/tail included
    final gaps = <(double, double, List<Ayah>)>[];
    void addGap(double from, double to, Ayah? before, Ayah? after) {
      if (to - from < minGapToRescan) return;
      final cands = expectedInGap(before, after, matcher.ayaat);
      if (cands.isEmpty) return;
      gaps.add((from, to, cands));
    }

    addGap(rangeStart, timeline.first.start, null, timeline.first.ayah);
    for (var i = 0; i + 1 < timeline.length; i++) {
      addGap(timeline[i].end, timeline[i + 1].start, timeline[i].ayah,
          timeline[i + 1].ayah);
    }
    addGap(timeline.last.end, rangeEnd, timeline.last.ayah, null);
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
        onProgress?.call(0.9 + 0.1 * min(1, done / totalWindows));
        // PATCH_S95_UI_RESPONSIVE_SCAN: same responsiveness yield as the
        // main scan loop.
        await Future<void>.delayed(Duration.zero);

        final startSample = (t * sampleRate).floor();
        final endSample = min(
            pcm.length, (min(t + gapChunkSec, gapEnd) * sampleRate).floor());
        if (endSample - startSample < sampleRate * 1.2) continue;
        final slice = Int16List.sublistView(pcm, startSample, endSample);
        if (_rmsEnergy(slice) < silenceGate) {
          current = null;
          continue;
        }

        final sliceDurSec = (endSample - startSample) / sampleRate;
        final chunkPath = '${tempDir.path}/gap_$done.wav';
        WhisperTranscript transcript;
        try {
          _writeWavMono16(chunkPath, slice);
          try {
            transcript = await WhisperService.transcribeWavWithSegments(
              chunkPath,
              audioDurationSec: sliceDurSec,
              splitOnWord: true,
            );
          } catch (_) {
            // same S61 fallback as the main scan: costs onset precision
            // for this window only, not the rescue itself
            transcript = await WhisperService.transcribeWavWithSegments(
              chunkPath,
              audioDurationSec: sliceDurSec,
              splitOnWord: false,
            );
          }
        } catch (_) {
          continue; // one failed window shouldn't kill the rescue
        } finally {
          File(chunkPath).delete().ignore();
        }

        final text = transcript.text.trim();
        if (text.isEmpty) continue;
        // PATCH_S86_ASR_JUNK_FILTER: same guard as the main scan — the
        // rescue's relaxed threshold makes it MORE vulnerable to stock
        // hallucination phrases, not less.
        if (isAsrHallucination(text)) {
          current = null;
          continue;
        }
        final match = matcher.matchAmong(text, candidates,
            minConfidence: contextMinConfidence);
        if (match == null) {
          current = null;
          continue;
        }
        // real phrase bounds when available, the window bounds otherwise
        final segs = transcript.segments;
        final absStart =
            segs.isEmpty ? t : min(gapEnd, t + segs.first.startSec);
        final absEnd = segs.isEmpty
            ? min(t + gapChunkSec, gapEnd)
            : min(gapEnd, max(absStart + 0.2, t + segs.last.endSec));
        final onsets = _snapOnsetsToEnergyAttacks(pcm, sampleRate,
            [for (final s in segs) t + s.startSec]);
        if (current != null &&
            identical(current.ayah, match.ayah) &&
            absStart - current.end <= mergeGapSec) {
          current.end = max(current.end, absEnd);
          current.confidence = max(current.confidence, match.confidence);
          _appendOnsets(current.wordStarts, onsets);
        } else {
          current = TimelineSegment(
              start: absStart,
              end: absEnd,
              ayah: match.ayah,
              confidence: match.confidence,
              wordStarts: List.of(onsets));
          rescued.add(current);
        }
      }
    }
    if (rescued.isEmpty) return;
    timeline.addAll(rescued);
    timeline.sort((a, b) => a.start.compareTo(b.start));
  }

  /// PATCH_S35_SMARTER_DETECTION: consecutive segments that overlap (the
  /// same audio re-heard by two overlapping scan windows) get split at the
  /// midpoint of the overlap; small gaps (≤ [bridgeGapSec] — a breath pause
  /// or one garbled phrase in a continuous recitation) are bridged the same
  /// way. Public and pure so it's unit-testable.
  static void normalizeTimeline(
      List<TimelineSegment> timeline, double totalSec) {
    if (timeline.isEmpty) return;
    for (var i = 0; i + 1 < timeline.length; i++) {
      final a = timeline[i], b = timeline[i + 1];
      if (a.end > b.start || b.start - a.end <= bridgeGapSec + 0.01) {
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
  // PATCH_S81_REFINE_BOUNDARY_SANITY: on professionally mastered/reverberant
  // recitation audio (loudness-normalized, reverb tail, never truly silent
  // between phrases -- verified against 3 real recitation files, median RMS
  // 0.29-0.36, essentially never dipping near real silence), EVERY search
  // window has *some* locally-quietest point even with no real pause
  // present. Blindly trusting that point relocated boundaries by up to the
  // full 1.5s search radius on such audio, in ~half to ~3/4 of cases tested,
  // silently shrinking (or growing) a segment's real recited duration by up
  // to ~3s combined across its start+end -- this is what caused the ayah
  // text to fall out of sync with the actual recitation length. A genuine
  // breath pause shows a strong dip *relative to* the window's own average
  // energy; noise-floor jitter within continuous speech doesn't. Requiring
  // that relative dip before trusting the relocation was re-tested against
  // the same 3 files and correctly left every boundary untouched instead of
  // moving it on noise.
  static const double _boundaryDipFactor = 0.45;

  // PATCH_S84_AUTOSYNC_PRECISION_V2: extracted from the old shared-boundary
  // loop below so the same "find the quietest point in [lo, hi], but only
  // trust it if it's a real relative dip" logic can snap ANY edge -- not
  // just ones that happen to sit exactly between two touching segments.
  // Returns null (leave the edge alone) when no qualifying dip is found.
  static double? _findQuietDip(Int16List pcm, double lo, double hi) {
    const winSec = 0.24, hopSec = 0.08;
    if (hi - lo < winSec + 0.05) return null;
    var bestT = lo;
    var bestRms = double.infinity;
    var sumRms = 0.0;
    var countRms = 0;
    for (var t = lo; t + winSec <= hi; t += hopSec) {
      final s = (t * sampleRate).floor();
      final e = min(pcm.length, ((t + winSec) * sampleRate).floor());
      if (e <= s || s < 0) continue;
      final rms = _rmsEnergy(Int16List.sublistView(pcm, s, e));
      sumRms += rms;
      countRms++;
      if (rms < bestRms) {
        bestRms = rms;
        bestT = t + winSec / 2;
      }
    }
    // PATCH_S81_REFINE_BOUNDARY_SANITY: only accept the relocation if the
    // quietest point found is meaningfully below this window's own
    // average -- otherwise there's no real pause here, so leave the
    // original (Whisper/VAD-committed) boundary alone.
    if (countRms == 0) return null;
    final avgRms = sumRms / countRms;
    if (bestRms > avgRms * _boundaryDipFactor) return null;
    return bestT;
  }

  static void _refineBoundaries(
      List<TimelineSegment> timeline, Int16List pcm) {
    const searchSec = 1.5;
    for (var i = 0; i + 1 < timeline.length; i++) {
      final a = timeline[i], b = timeline[i + 1];
      final gap = b.start - a.end;
      if (gap.abs() <= 0.01) {
        // Touching -- one shared point serves both edges (S81 behaviour,
        // unchanged).
        final lo = max(a.start + 0.5, a.end - searchSec);
        final hi = min(b.end - 0.5, b.start + searchSec);
        final t = _findQuietDip(pcm, lo, hi);
        if (t != null) {
          a.end = t;
          b.start = t;
        }
      } else if (gap > 0.01) {
        // PATCH_S84_AUTOSYNC_PRECISION_V2: a real gap remains here --
        // normalizeTimeline() only bridges gaps up to bridgeGapSec, so
        // anything bigger (very often exactly where a whole-window
        // fallback segment or a rescue-pass segment sits) never reached
        // the shared-boundary branch above and was left on whatever
        // coarse bound it started with. Snap each edge independently,
        // each searching within its own slack, toward real silence.
        final aLo = max(a.start + 0.5, a.end - searchSec);
        final aHi = min(b.start - 0.05, a.end + min(searchSec, gap));
        final aT = _findQuietDip(pcm, aLo, aHi);
        if (aT != null) a.end = aT;
        final bLo = max(a.end + 0.05, b.start - min(searchSec, gap));
        final bHi = min(b.end - 0.5, b.start + searchSec);
        final bT = _findQuietDip(pcm, bLo, bHi);
        if (bT != null) b.start = bT;
      }
    }
    // PATCH_S84_AUTOSYNC_PRECISION_V2: the very first segment's start and
    // the very last segment's end never had a neighbour to pair with in
    // the loop above, so they never got refined at all -- but a coarse
    // whole-window-fallback bound is exactly as likely to be wrong there
    // as anywhere else.
    if (timeline.isNotEmpty) {
      final first = timeline.first;
      final t0 = _findQuietDip(
          pcm, max(0, first.start - searchSec), first.start + searchSec);
      if (t0 != null) first.start = max(0, t0);
      final last = timeline.last;
      final t1 =
          _findQuietDip(pcm, last.end - searchSec, last.end + searchSec);
      if (t1 != null) last.end = t1;
    }
  }

  // PATCH_S77_ONSET_ENERGY_SNAP: corrects Whisper's per-word onset timestamps
  // against the real audio energy -- see the doc-comment at the top of this
  // patch for the full reasoning. Forward-only: a word's lit moment can be
  // pushed later (to catch a held مدّ/غنة Whisper cut short) but never
  // earlier than what Whisper actually heard.
  static const double _onsetSearchCapSec = 0.6;
  static const double _onsetHopSec = 0.02;
  static const double _onsetFrameSec = 0.05;

  static List<double> _snapOnsetsToEnergyAttacks(
      Int16List pcm, int sampleRate, List<double> rawOnsets) {
    if (rawOnsets.isEmpty) return rawOnsets;
    final frameLen = (_onsetFrameSec * sampleRate).round();
    final hopLen = (_onsetHopSec * sampleRate).round();
    final refined = <double>[];
    for (var i = 0; i < rawOnsets.length; i++) {
      final onset = rawOnsets[i];
      // Never search past the next declared onset -- keeps this word's
      // correction from wandering into the next word's audio.
      final hardLimit =
          i + 1 < rawOnsets.length ? rawOnsets[i + 1] - 0.05 : onset + _onsetSearchCapSec;
      final searchEnd = min(onset + _onsetSearchCapSec, hardLimit);
      if (searchEnd <= onset) {
        refined.add(onset);
        continue;
      }
      double frameRmsAt(double atSec) {
        // PATCH_S78_FIX_S77_CLAMP_TYPE_ERROR: int.clamp() returns num, not int.
        final start = (atSec * sampleRate).round().clamp(0, max(0, pcm.length - 1)).toInt();
        final end = min(pcm.length, start + frameLen);
        if (end <= start) return 0;
        return _rmsEnergy(Int16List.sublistView(pcm, start, end));
      }

      final baseEnergy = frameRmsAt(onset);
      var sawDip = false;
      var snapped = onset;
      var t = onset;
      while (t < searchEnd) {
        final e = frameRmsAt(t);
        if (e < baseEnergy * 0.55) {
          sawDip = true; // a real gap/consonant closure near here
        } else if (sawDip && e > baseEnergy * 0.85) {
          snapped = t; // energy climbed back after a real dip -- the true next attack
          break;
        }
        t += hopLen / sampleRate;
      }
      // No real dip found before the cap -- the audio stayed energetic the
      // whole window, i.e. a held مدّ/غنة Whisper's timestamp cut short.
      // Push the onset out to the search cap rather than trusting the
      // early guess.
      refined.add(sawDip ? snapped : min(searchEnd, onset + _onsetSearchCapSec));
    }
    return refined;
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
