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
  // Slightly below the browser version's 0.008: real phone recordings of a
  // distant/quiet sheikh were getting whole windows skipped as "silence",
  // which is one way an entire recitation collapses to a single detected
  // ayah. Whisper-hallucination guards downstream still protect true noise.
  static const double vadSilenceRms = 0.006;
  static const int sampleRate = 16000;

  /// Scans [mediaPath] (video or audio) and returns the detected ayah
  /// timeline. [onStatus] receives human-readable Arabic progress text,
  /// [onProgress] a 0..1 fraction.
  static Future<List<TimelineSegment>> build({
    required String mediaPath,
    required AyahMatcher matcher,
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    await WhisperService.ensureReady(onStatus: onStatus);

    onStatus?.call('جارٍ استخراج الصوت الكامل…');
    final wavPath = await MediaService.extractWav16kMono(mediaPath);
    final pcm = _readWavMono16(wavPath);

    final totalSec = pcm.length / sampleRate;
    final totalChunks = max(1, (totalSec / stepSec).ceil());

    final tempDir = Directory.systemTemp.createTempSync('ayat_timeline');
    final timeline = <TimelineSegment>[];
    // A borderline match (below highConfidence) only commits once the *next*
    // window agrees on the same ayah too — one noisy window can clear
    // minConfidence by chance, two in a row on the same ayah almost never do.
    // EXCEPTION: the mushaf-order sequential prior. Once an ayah is on the
    // timeline, the very next ayah commits off a single window — recitation
    // is sequential, so "previous ayah then this one" IS the corroborating
    // evidence. Without this, any ayah recited faster than ~2 windows (most
    // short/medium ayat) could never be committed, which is exactly the
    // "only one ayah detected in the whole video" failure seen in testing.
    TimelineSegment? pending;
    int? pendingIndex;
    int? lastIndex; // corpus index of the ayah most recently on the timeline
    var chunkIndex = 0;

    try {
      for (double t = 0; t < totalSec; t += stepSec) {
        chunkIndex++;
        onStatus?.call('جارٍ رصد الآيات: مقطع $chunkIndex من $totalChunks…');
        onProgress?.call(chunkIndex / totalChunks);

        final startSample = (t * sampleRate).floor();
        final endSample =
            min(pcm.length, ((t + chunkSec) * sampleRate).floor());
        if (endSample - startSample < sampleRate * 1.2) continue; // tiny tail

        final slice = Int16List.sublistView(pcm, startSample, endSample);
        if (_rmsEnergy(slice) < vadSilenceRms) {
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

        final match =
            matcher.match(text, minConfidence: minConfidence, priorIndex: lastIndex);
        if (match == null) {
          pending = null;
          pendingIndex = null;
          continue;
        }

        final last = timeline.isEmpty ? null : timeline.last;
        if (last != null && identical(last.ayah, match.ayah)) {
          // same ayah still being recited — extend the segment
          last.end = t + chunkSec;
          last.confidence = max(last.confidence, match.confidence);
          pending = null;
          pendingIndex = null;
          continue;
        }

        final isExpectedNext = lastIndex != null &&
            (match.index == lastIndex + 1 || match.index == lastIndex + 2);
        if (match.confidence >= highConfidence || isExpectedNext) {
          timeline.add(TimelineSegment(
              start: t,
              end: t + chunkSec,
              ayah: match.ayah,
              confidence: match.confidence));
          lastIndex = match.index;
          pending = null;
          pendingIndex = null;
        } else if (pending != null && pendingIndex == match.index) {
          // second window in a row agrees — commit, backdated to where the
          // ayah first appeared
          timeline.add(TimelineSegment(
              start: pending.start,
              end: t + chunkSec,
              ayah: match.ayah,
              confidence: max(pending.confidence, match.confidence)));
          lastIndex = match.index;
          pending = null;
          pendingIndex = null;
        } else {
          pending = TimelineSegment(
              start: t,
              end: t + chunkSec,
              ayah: match.ayah,
              confidence: match.confidence);
          pendingIndex = match.index;
        }
      }
    } finally {
      tempDir.delete(recursive: true).ignore();
      File(wavPath).delete().ignore();
    }
    _stitch(timeline);
    return timeline;
  }

  /// Post-pass cleanup: clamp overlapping neighbors, and when two committed
  /// segments are consecutive ayat in the mushaf with a small analysis gap
  /// between them, extend the earlier one to meet the later — the gap is a
  /// window-quantization artifact, not a real pause in the recitation, and
  /// closing it keeps the typed ayah on screen until the next one starts.
  static void _stitch(List<TimelineSegment> timeline) {
    for (var i = 1; i < timeline.length; i++) {
      final prev = timeline[i - 1], cur = timeline[i];
      if (cur.start < prev.end) prev.end = cur.start;
      final consecutive = cur.ayah.surahNum == prev.ayah.surahNum &&
          cur.ayah.num == prev.ayah.num + 1;
      if (consecutive &&
          cur.start > prev.end &&
          cur.start - prev.end <= stepSec * 2) {
        prev.end = cur.start;
      }
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
