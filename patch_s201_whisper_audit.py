#!/usr/bin/env python3
"""
patch_s201_whisper_audit.py
===========================
Ayat Studio S201 - run from the repo root (after S200):

    python3 patch_s201_whisper_audit.py

Whisper audit: what was found and what this patch changes
----------------------------------------------------------
1. BUG - auto-sync only ever heard the FIRST HALF of a clip.
   TimelineBuilder._readWavMono16 did
       Int16List.sublistView(Uint8List.fromList(data), 0, data.length ~/ 2)
   but sublistView counts in elements of its SOURCE (bytes), so `length ~/ 2`
   viewed length/2 BYTES = half of the samples - and threw an ArgumentError
   whenever the sample count was odd. (Dart SDK, typed_data.dart.) Fixed with
   asInt16List(), and the decoder is now a pure public function
   (TimelineBuilder.decodeWavMono16) with a regression test.
   NOTE: after this fix a scan covers the whole clip, so it does ~2x the
   windows it used to on a clip that was being cut in half. Item 2 pays part
   of that back.

2. SPEED - every 6 s scan window was padded to Whisper's 30 s window.
   whisper.cpp encodes a fixed 30 s of audio even for a 6 s chunk (~80% of the
   encoder work is spent on silence). whisper_ggml_plus has one switch for this
   (speedUp -> half the encoder context, 15 s). The patch adds it for audio of
   12 s or less only (every scan / gap-rescue / re-transcribe window), so
   nothing can lose its tail - but it costs a little accuracy that I could not
   measure on Quran audio, so it ships OFF. To try it (about 35-40% faster):
       sed -i 's/fastShortWindows = false/fastShortWindows = true/' lib/services/whisper_service.dart
   then compare one clip's sync against the OFF build.

3. CONSISTENCY - the same windows no longer hear different audio per path.
   The package auto-enables a bundled Silero VAD for the non-word-split calls
   but never for the word-split ones, so the S61 fallback and the re-transcribe
   pass could drop soft/held sounds the main scan kept. Those short windows are
   already RMS-gated and known to contain speech, so VAD is now off for them
   (same as the main scan already was).

4. "Detect ayah from video" transcribed the video's ENTIRE soundtrack and then
   matched that whole transcript against single ayat. It now transcribes only
   the first ~25 s of actual speech (leading silence skipped). Any failure in
   the trimming falls back to the old behaviour.

5. MEMORY - the native Whisper context (model weights + buffers, roughly the
   model file's size again; ~1.5 GB for the medium tier) stayed resident after
   an auto-sync while FFmpeg exported video in the same process. It is now
   released when a scan ends (the next scan simply reloads it).

Checked and left alone: model-path routing of the Quran tier (the native
turbo heuristic keys on layer/vocab counts, not the file name), GGML magic
check, resume/retry download, thread picking (4 on the S22), S200 fallback.

Files touched: lib/services/whisper_service.dart, lib/services/timeline_builder.dart,
lib/screens/home_screen.dart (one call), test/wav_decode_test.dart (new).
All edits are applied together or not at all. Idempotent (marker PATCH_S201).
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S201'
WS = os.path.join(ROOT, 'lib/services/whisper_service.dart')
TB = os.path.join(ROOT, 'lib/services/timeline_builder.dart')
HS = os.path.join(ROOT, 'lib/screens/home_screen.dart')
TEST = os.path.join(ROOT, 'test/wav_decode_test.dart')
for p in (WS, TB, HS):
    if not os.path.exists(p):
        sys.exit('%s missing' % os.path.relpath(p, ROOT))

ws = open(WS, encoding='utf-8').read()
tb = open(TB, encoding='utf-8').read()
hs = open(HS, encoding='utf-8').read()

if MARK in ws and MARK in tb and MARK in hs:
    print('  OK      already applied (PATCH_S201)')
    sys.exit(0)
if MARK in ws or MARK in tb or MARK in hs:
    sys.exit('  SKIP    PATCH_S201 is only partly present - restore the files (git checkout) and re-run.')
if 'PATCH_S200_WHISPER_FALLBACK' not in ws:
    sys.exit('  SKIP    whisper_service.dart is not at S200 - apply S200 first.')


def apply_fix(src, label, old, new):
    n = src.count(old)
    if n != 1:
        sys.exit('  SKIP    %s: anchor found %d times (need exactly 1) - nothing written' % (label, n))
    print('  PATCHED %s' % label)
    return src.replace(old, new)


# ===================================================================== whisper_service.dart

W1_OLD = "import 'dart:math' as math;\n"
W1_NEW = "import 'dart:math' as math;\nimport 'dart:typed_data'; // PATCH_S201\n"

# ---- helpers (inserted just above transcribeWav's doc comment)
W2_OLD = "  /// Transcribes a 16kHz mono WAV file (extract audio with ffmpeg first —\n"
W2_NEW = r"""  // ---------------------------------------------------------------------
  // PATCH_S201_WHISPER_AUDIT
  //
  // 1) Short windows. whisper.cpp pads every input to a 30-second window
  //    before the encoder runs, so a 6-second scan window spends ~80% of the
  //    encoder's time on padding. whisper_ggml_plus exposes exactly one knob
  //    for that - speedUp, which halves the encoder context to 15 s - and
  //    audio longer than 15 s would lose its tail under it. So it would be
  //    used ONLY for audio that fits with room to spare (every scan /
  //    gap-rescue / re-transcribe window does). It trades a little accuracy
  //    for ~35-40% less scan time and has not been measured on Quran audio,
  //    so [fastShortWindows] ships OFF - set it to true to try it.
  //    Short windows also skip the bundled Silero VAD: the package turns it
  //    on by default for the non-word-split calls but never for the word-split
  //    ones, so the S61 fallback and the re-transcribe pass heard different
  //    audio than the main scan. These windows are already RMS-gated and known
  //    to hold speech, so all three paths now behave the same.
  // ---------------------------------------------------------------------
  static bool fastShortWindows = false;
  static const double _shortWindowMaxSec = 12.0;

  /// Duration of a 16 kHz mono 16-bit WAV from its size (44-byte header).
  static double _wavSeconds(String path) {
    try {
      final dataBytes = File(path).lengthSync() - 44;
      return dataBytes <= 0 ? 0.0 : dataBytes / 32000.0;
    } catch (_) {
      return double.infinity; // unknown length -> never take the fast path
    }
  }

  static ({bool speedUp, WhisperVadMode vad}) _fastParams(String wavPath) {
    final short = _wavSeconds(wavPath) <= _shortWindowMaxSec;
    return (
      speedUp: short && fastShortWindows,
      vad: short ? WhisperVadMode.disabled : WhisperVadMode.auto,
    );
  }

  /// PATCH_S201: frees the native Whisper context (the model's weights plus
  /// its working buffers - roughly the model file's size again). It otherwise
  /// stays resident for the life of the app, next to FFmpeg exports. Safe to
  /// call any time: the next transcribe simply loads the model again.
  static Future<void> release() async {
    try {
      await _controller.dispose(model: _model);
    } catch (_) {
      // best effort
    }
  }

  // PATCH_S201: "detect ayah from video" only needs to hear where the
  // recitation starts, but it used to transcribe the video's ENTIRE
  // soundtrack (minutes of CPU) and then match that whole transcript against
  // single ayat. This copies about the first [maxSec] seconds of actual speech
  // (leading silence skipped) of a 16 kHz mono 16-bit WAV into a temp file and
  // returns its path. Returns null when the file is already short enough, is
  // not the expected format, holds no speech, or anything goes wrong - the
  // caller then simply uses the original file (the old behaviour).
  static Future<String?> _leadingSpeechWav(String wavPath, double maxSec) async {
    const rate = 16000;
    const frame = 1600; // 100 ms
    RandomAccessFile? raf;
    try {
      raf = await File(wavPath).open();
      final fileLen = await raf.length();
      final head = await raf.read(math.min(fileLen, 4096));
      if (head.length < 44 ||
          String.fromCharCodes(head.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(head.sublist(8, 12)) != 'WAVE') {
        return null;
      }
      final hd = ByteData.sublistView(head);
      var off = 12;
      var dataStart = -1;
      var dataLen = 0;
      var formatOk = false;
      while (off + 8 <= head.length) {
        final id = String.fromCharCodes(head.sublist(off, off + 4));
        final size = hd.getUint32(off + 4, Endian.little);
        if (id == 'fmt ' && off + 24 <= head.length) {
          formatOk = hd.getUint16(off + 8, Endian.little) == 1 && // PCM
              hd.getUint16(off + 10, Endian.little) == 1 && // mono
              hd.getUint32(off + 12, Endian.little) == rate &&
              hd.getUint16(off + 22, Endian.little) == 16; // bits
        } else if (id == 'data') {
          dataStart = off + 8;
          dataLen = size;
          break;
        }
        off += 8 + size + (size.isOdd ? 1 : 0);
      }
      if (!formatOk || dataStart < 0) return null;
      final avail = fileLen - dataStart;
      if (dataLen <= 0 || dataLen > avail) dataLen = avail; // streamed WAVs
      final totalSamples = dataLen ~/ 2;
      if (totalSamples <= ((maxSec + 2) * rate).floor()) return null;

      // look for the first speech in the first two minutes
      final want = math.min(totalSamples, ((120 + maxSec) * rate).floor());
      await raf.setPosition(dataStart);
      final raw = Uint8List.fromList(await raf.read(want * 2));
      final n = raw.length ~/ 2;
      final pcm = raw.buffer.asInt16List(0, n);
      final nFrames = n ~/ frame;
      if (nFrames < 5) return null;
      final rms = List<double>.filled(nFrames, 0);
      for (var f = 0; f < nFrames; f++) {
        var sum = 0.0;
        final base = f * frame;
        for (var i = 0; i < frame; i++) {
          final v = pcm[base + i] / 32768.0;
          sum += v * v;
        }
        rms[f] = math.sqrt(sum / frame);
      }
      // same idea as TimelineBuilder.adaptiveSilenceThreshold: just above the
      // clip's own room tone, never below the proven fixed gate
      final sorted = [...rms]..sort();
      final noiseFloor = sorted[(sorted.length * 0.1).floor()];
      final gate = (noiseFloor * 2.2).clamp(0.008, 0.02).toDouble();
      var onset = -1;
      for (var f = 0; f + 1 < nFrames; f++) {
        if (rms[f] >= gate && rms[f + 1] >= gate) {
          onset = f;
          break;
        }
      }
      if (onset < 0) return null;

      final startSample = math.max(0, onset * frame - rate ~/ 2); // 0.5 s lead-in
      final endSample = math.min(n, startSample + (maxSec * rate).floor());
      if (endSample - startSample < rate) return null;

      final dataBytes = (endSample - startSample) * 2;
      final header = ByteData(44);
      void putAscii(int at, String s) {
        for (var i = 0; i < s.length; i++) {
          header.setUint8(at + i, s.codeUnitAt(i));
        }
      }

      putAscii(0, 'RIFF');
      header.setUint32(4, 36 + dataBytes, Endian.little);
      putAscii(8, 'WAVE');
      putAscii(12, 'fmt ');
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little); // PCM
      header.setUint16(22, 1, Endian.little); // mono
      header.setUint32(24, rate, Endian.little);
      header.setUint32(28, rate * 2, Endian.little); // byte rate
      header.setUint16(32, 2, Endian.little); // block align
      header.setUint16(34, 16, Endian.little); // bits per sample
      putAscii(36, 'data');
      header.setUint32(40, dataBytes, Endian.little);

      final out = BytesBuilder();
      out.add(header.buffer.asUint8List());
      out.add(pcm.buffer.asUint8List(startSample * 2, dataBytes));
      final outPath = '${Directory.systemTemp.path}/'
          'ayat_lead_${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(outPath).writeAsBytes(out.takeBytes(), flush: true);
      return outPath;
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

""" + W2_OLD

# ---- transcribeWav: new optional parameter
W3_OLD = r"""  static Future<String> transcribeWav(
    String wavPath, {
    void Function(String status)? onStatus,
  }) async {
"""
W3_NEW = r"""  static Future<String> transcribeWav(
    String wavPath, {
    void Function(String status)? onStatus,
    // PATCH_S201: when set, only about the first [leadSeconds] seconds of
    // actual speech are transcribed (see _leadingSpeechWav).
    double? leadSeconds,
  }) async {
"""

# ---- transcribeWav: body
W4_OLD = """    // PATCH_S200_WHISPER_FALLBACK: guarded - see _guarded().
    final result = await _guarded(
      () => _controller.transcribe(
        model: _model,
        audioPath: wavPath,
        lang: 'ar',
        threads: _threads, // PATCH_S123_WHISPER_THREADS
        convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass
      ),
      onStatus: onStatus,
    );
    return result?.transcription.text.trim() ?? '';
  }
"""
W4_NEW = """    // PATCH_S201: optionally trim to the first seconds of speech.
    final lead = leadSeconds == null
        ? null
        : await _leadingSpeechWav(wavPath, leadSeconds);
    final path = lead ?? wavPath;
    final fast = _fastParams(path); // PATCH_S201
    try {
      // PATCH_S200_WHISPER_FALLBACK: guarded - see _guarded().
      final result = await _guarded(
        () => _controller.transcribe(
          model: _model,
          audioPath: path,
          lang: 'ar',
          threads: _threads, // PATCH_S123_WHISPER_THREADS
          convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass
          speedUp: fast.speedUp, // PATCH_S201: short windows only
          vadMode: fast.vad, // PATCH_S201
        ),
        onStatus: onStatus,
      );
      return result?.transcription.text.trim() ?? '';
    } finally {
      if (lead != null) File(lead).delete().ignore(); // PATCH_S201
    }
  }
"""

# ---- transcribeWavWithSegments
W5_OLD = """    // PATCH_S200_WHISPER_FALLBACK: guarded. The word-split attempt keeps
    // throwing untouched so TimelineBuilder's S61 retry still happens.
"""
W5_NEW = W5_OLD + "    final fast = _fastParams(wavPath); // PATCH_S201\n"

W6_OLD = """        splitOnWord: splitOnWord,
        threads: _threads, // PATCH_S123_WHISPER_THREADS
"""
W6_NEW = """        splitOnWord: splitOnWord,
        threads: _threads, // PATCH_S123_WHISPER_THREADS
        speedUp: fast.speedUp, // PATCH_S201: short windows only
        vadMode: fast.vad, // PATCH_S201
"""

ws2 = ws
ws2 = apply_fix(ws2, 'whisper_service.dart - dart:typed_data import', W1_OLD, W1_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - short-window params, release(), leading-speech trim', W2_OLD, W2_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - transcribeWav leadSeconds parameter', W3_OLD, W3_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - transcribeWav body', W4_OLD, W4_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - transcribeWavWithSegments params', W5_OLD, W5_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - transcribeWavWithSegments call', W6_OLD, W6_NEW)

# ===================================================================== timeline_builder.dart

T1_OLD = """  static Int16List _readWavMono16(String path) {
    final bytes = File(path).readAsBytesSync();
    final bd = ByteData.sublistView(bytes);
"""
T1_NEW = """  static Int16List _readWavMono16(String path) =>
      decodeWavMono16(File(path).readAsBytesSync()); // PATCH_S201

  /// PATCH_S201: the pure part of [_readWavMono16], public so a test can pin
  /// it down: the PCM samples of a 16-bit WAV, every one of them.
  static Int16List decodeWavMono16(Uint8List bytes) {
    final bd = ByteData.sublistView(bytes);
"""

T2_OLD = """        final data = bytes.sublist(offset + 8, end);
        return Int16List.sublistView(
            Uint8List.fromList(data), 0, data.length ~/ 2);
"""
T2_NEW = """        final data = bytes.sublist(offset + 8, end); // a fresh copy, offset 0
        // PATCH_S201: Int16List.sublistView(src, a, b) counts in elements of
        // its SOURCE - bytes here - so `0, data.length ~/ 2` viewed only HALF
        // of the samples (and threw when that count was odd): auto-sync heard
        // the first half of every clip. asInt16List takes a sample count.
        return data.buffer.asInt16List(data.offsetInBytes, data.length ~/ 2);
"""

T3_OLD = """    } finally {
      tempDir.delete(recursive: true).ignore();
      File(wavPath).delete().ignore();
    }
"""
T3_NEW = """    } finally {
      tempDir.delete(recursive: true).ignore();
      File(wavPath).delete().ignore();
      // PATCH_S201: give the native model's memory back before the export.
      await WhisperService.release();
    }
"""

tb2 = tb
tb2 = apply_fix(tb2, 'timeline_builder.dart - WAV decoder split out', T1_OLD, T1_NEW)
tb2 = apply_fix(tb2, 'timeline_builder.dart - WAV decoder reads ALL samples', T2_OLD, T2_NEW)
tb2 = apply_fix(tb2, 'timeline_builder.dart - release Whisper after a scan', T3_OLD, T3_NEW)

# ===================================================================== home_screen.dart

H1_OLD = """        return await WhisperService.transcribeWav(wav,
            onStatus: (s) => _setBusyStatus(s));
"""
H1_NEW = """        return await WhisperService.transcribeWav(wav,
            leadSeconds: 25, // PATCH_S201: only the start is needed to identify the ayah
            onStatus: (s) => _setBusyStatus(s));
"""
hs2 = apply_fix(hs, 'home_screen.dart - detect-from-video transcribes only the start', H1_OLD, H1_NEW)

# ===================================================================== test

TEST_SRC = r"""// PATCH_S201_WHISPER_AUDIT: regression test for the PCM reader. It used to
// return only the first half of a clip's samples (and throw when the sample
// count was odd), so auto-sync never heard the second half of a recording.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/services/timeline_builder.dart';

/// A 16 kHz mono 16-bit WAV holding [samples]. [listBytes] > 0 puts a LIST
/// chunk of that many payload bytes before `data`, like ffmpeg's encoder tag.
Uint8List makeWav(List<int> samples, {int listBytes = 0}) {
  final pcm = Int16List.fromList(samples);
  final dataLen = pcm.lengthInBytes;
  final listPad = listBytes.isOdd ? 1 : 0;
  final listTotal = listBytes > 0 ? 8 + listBytes + listPad : 0;
  final out = BytesBuilder();
  void ascii(String s) => out.add(s.codeUnits);
  void u32(int v) =>
      out.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      out.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

  ascii('RIFF');
  u32(4 + 24 + listTotal + 8 + dataLen);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(16000);
  u32(32000);
  u16(2);
  u16(16);
  if (listBytes > 0) {
    ascii('LIST');
    u32(listBytes);
    out.add(List<int>.filled(listBytes + listPad, 0));
  }
  ascii('data');
  u32(dataLen);
  out.add(pcm.buffer.asUint8List(pcm.offsetInBytes, dataLen));
  return out.takeBytes();
}

List<int> ramp(int n) => List<int>.generate(n, (i) => (i * 37) % 30000 - 15000);

void main() {
  group('TimelineBuilder.decodeWavMono16', () {
    test('returns every sample of an even-length clip', () {
      final samples = ramp(1000);
      final out = TimelineBuilder.decodeWavMono16(makeWav(samples));
      expect(out.length, 1000);
      expect(out.toList(), orderedEquals(samples));
    });

    test('returns every sample of an odd-length clip (used to throw)', () {
      final samples = ramp(1001);
      final out = TimelineBuilder.decodeWavMono16(makeWav(samples));
      expect(out.length, 1001);
      expect(out.last, samples.last);
    });

    test('skips a LIST chunk (odd size, padded) before the data chunk', () {
      final samples = ramp(777);
      final out =
          TimelineBuilder.decodeWavMono16(makeWav(samples, listBytes: 13));
      expect(out.toList(), orderedEquals(samples));
    });

    test('rejects something that is not a WAV', () {
      expect(() => TimelineBuilder.decodeWavMono16(Uint8List(64)),
          throwsException);
    });
  });
}
"""

# ===================================================================== write + verify

if os.path.exists(TEST):
    sys.exit('  SKIP    test/wav_decode_test.dart already exists - nothing written')

open(WS, 'w', encoding='utf-8').write(ws2)
open(TB, 'w', encoding='utf-8').write(tb2)
open(HS, 'w', encoding='utf-8').write(hs2)
os.makedirs(os.path.dirname(TEST), exist_ok=True)
open(TEST, 'w', encoding='utf-8').write(TEST_SRC)
print('  CREATED test/wav_decode_test.dart')

ok = True
for p in (WS, TB, HS, TEST):
    t = re.sub(r"//[^\n]*", '', open(p, encoding='utf-8').read())
    bal = all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))
    ok = ok and bal
print('  all balanced' if ok else '  !! UNBALANCED - check the files before committing')
print('Next: git add -A && git commit -m "S201: Whisper audit - full-clip PCM decode, short-window speedup, detect-from-start, release after scan" && git push')
