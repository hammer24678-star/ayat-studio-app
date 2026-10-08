// PATCH_S181_CLIPTOUCH (replaces the S174 version; same public API)
// Audio peaks for the timeline's waveform lanes (the Premiere / Resolve /
// CapCut look). One ffmpeg pass decodes the file to 2 kHz mono PCM, then a
// background isolate reads it in small chunks and collapses every 20 samples
// to one peak = 100 peaks per second. Nothing here runs on the UI isolate and
// the raw file is never loaded whole, so a very long recording no longer
// freezes the editor. Cached per path; null = could not decode and the lane
// just draws a flat bar.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'heavy_gate.dart';

class WaveformService {
  WaveformService._();

  /// Peaks per second of audio.
  static const int peaksPerSec = 100;

  /// Decode rate for the peak pass. Display only, so 2 kHz is plenty.
  static const int _rate = 2000;

  static final Map<String, List<double>> _cache = {};
  static final Map<String, Future<List<double>?>> _pending = {};

  static List<double>? cached(String path) => _cache[path];

  static Future<List<double>?> peaks(String path) {
    final hit = _cache[path];
    if (hit != null) return Future<List<double>?>.value(hit);
    final running = _pending[path];
    if (running != null) return running;
    final job = HeavyGate.run<List<double>?>(() => _compute(path));
    _pending[path] = job;
    job.whenComplete(() {
      _pending.remove(path);
    });
    return job;
  }

  static Future<List<double>?> _compute(String path) async {
    try {
      final dir = await getTemporaryDirectory();
      final rawPath = '${dir.path}/wf_${path.hashCode.abs()}.raw';
      final rawFile = File(rawPath);
      if (rawFile.existsSync()) rawFile.deleteSync();
      final session = await FFmpegKit.execute(
          '-y -threads 2 -i "$path" -vn -ac 1 -ar $_rate -f s16le "$rawPath"');
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc) || !rawFile.existsSync()) return null;
      const per = _rate ~/ peaksPerSec;
      final res = await Isolate.run<List<double>>(() => _reduce(rawPath, per));
      try {
        rawFile.deleteSync();
      } catch (_) {}
      if (res.isEmpty) return null;
      _cache[path] = res;
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Runs inside the background isolate: s16le mono file -> normalised peaks.
  static List<double> _reduce(String rawPath, int per) {
    final raf = File(rawPath).openSync();
    try {
      final n = raf.lengthSync() ~/ 2;
      if (n == 0) return <double>[];
      final count = (n / per).ceil();
      final res = List<double>.filled(count, 0);
      final chunk = Uint8List(per * 2 * 4000); // whole peaks per read
      var idx = 0;
      var maxPeak = 0.0;
      while (idx < count) {
        final got = raf.readIntoSync(chunk);
        if (got <= 0) break;
        final bd = ByteData.sublistView(chunk, 0, got);
        final samples = got ~/ 2;
        for (var s = 0; s < samples && idx < count; s += per) {
          final e = math.min(samples, s + per);
          var peak = 0;
          for (var j = s; j < e; j++) {
            final v = bd.getInt16(j * 2, Endian.little).abs();
            if (v > peak) peak = v;
          }
          final d = peak / 32768.0;
          res[idx++] = d;
          if (d > maxPeak) maxPeak = d;
        }
      }
      final used = res.sublist(0, idx);
      // Display-normalise so quiet recitations still read as a waveform.
      if (maxPeak > 0.02) {
        final k = 1.0 / maxPeak;
        for (var i = 0; i < used.length; i++) {
          used[i] = (used[i] * k).clamp(0.0, 1.0);
        }
      }
      return used;
    } finally {
      raf.closeSync();
    }
  }
}
