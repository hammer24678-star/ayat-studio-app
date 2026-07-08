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

    void flushPending() {
      final p = pending;
      if (p != null) {
        timeline.add(p);
        pending = null;
      }
    }

    try {
      for (double t = 0; t < totalSec; t += stepSec) {
        if (_cancelRequested) {
          throw Exception('تم إلغاء المزامنة'); // PATCH_S37_CANCEL_LONG_JOBS
        }
        chunkIndex++;
        onStatus?.call('جارٍ رصد الآيات: مقطع $chunkIndex من $totalChunks…');
        onProgress?.call(chunkIndex / totalChunks);

        final startSample = (t * sampleRate).floor();
        final endSample =
            min(pcm.length, ((t + chunkSec) * sampleRate).floor());
        if (endSample - startSample < sampleRate * 1.2) continue; // tiny tail

        final slice = Int16List.sublistView(pcm, startSample, endSample);
        if (_rmsEnergy(slice) < vadSilenceRms) {
          flushPending(); // real gap in speech — whatever was pending is done
          continue;
        }

        // PATCH_S31_ACCURATE_SYNC: ask Whisper for its own phrase-level
        // timestamps within this window instead of treating the window as
        // one opaque blob — this is what makes the on-screen timing track
        // the real audio instead of drifting ahead of الشيخ.
        final windowDurationSec = (endSample - startSample) / sampleRate;
        WhisperTranscript transcript;
        try {
          final chunkPath = '${tempDir.path}/chunk_$chunkIndex.wav';
          _writeWavMono16(chunkPath, slice);
          transcript = await WhisperService.transcribeWavWithSegments(
            chunkPath,
            audioDurationSec: windowDurationSec,
          );
          File(chunkPath).delete().ignore();
        } catch (_) {
          continue; // one failed window shouldn't kill the whole scan
        }

        // Fall back to the whole window as a single piece if no per-phrase
        // timestamps came back, so sync degrades to the old (still working)
        // window-granularity behaviour instead of detecting nothing.
        final pieces = transcript.segments.isNotEmpty
            ? transcript.segments
            : [TranscriptSegment(0, windowDurationSec, transcript.text)];

        for (final piece in pieces) {
          final text = piece.text.trim();
          if (text.isEmpty) continue;
          final absStart = t + piece.startSec;
          final absEnd = max(absStart + 0.2, t + piece.endSec);

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
            continue;
          }

          if (match.confidence >= highConfidence) {
            flushPending();
            timeline.add(TimelineSegment(
                start: absStart,
                end: absEnd,
                ayah: match.ayah,
                confidence: match.confidence));
          } else {
            // previous pending (if any) never got reconfirmed — commit it
            // as-is rather than silently dropping it, then open the new one
            flushPending();
            pending = TimelineSegment(
                start: absStart,
                end: absEnd,
                ayah: match.ayah,
                confidence: match.confidence);
          }
        }
      }
      // PATCH_S31_ACCURATE_SYNC: a partial ayah still pending at the very
      // end of the scan is real — commit it instead of dropping it.
      flushPending();
      // PATCH_S35_SMARTER_DETECTION: resolve overlaps/small gaps and snap
      // ayah boundaries to the reciter's breath pauses.
      normalizeTimeline(timeline, totalSec);
      _refineBoundaries(timeline, pcm);
      // PATCH_S44_CONFIDENCE_RETRANSCRIBE: give low-confidence segments one more focused look now
      // that their real boundaries are known.
      await _reTranscribeWeakSegments(timeline, pcm, matcher, tempDir,
          onStatus: onStatus);
    } finally {
      tempDir.delete(recursive: true).ignore();
      File(wavPath).delete().ignore();
    }
    return timeline;
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
        );
      }
    }
  }

  // PATCH_S35_SMARTER_DETECTION: the ayat mushaf order predicts after
  // [anchor]: the anchor itself (still being recited) and the next two.
  static List<Ayah> _expectedNext(List<Ayah> ayaat, Ayah anchor) {
    final i = ayaat.indexOf(anchor); // identity ==, Ayah defines no operator==
    if (i < 0) return [anchor];
    return ayaat.sublist(i, min(ayaat.length, i + 3));
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
