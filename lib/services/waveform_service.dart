// PATCH_S174_PRO_EDITOR
// Audio peaks for the timeline's waveform lanes (the Premiere / Resolve /
// CapCut look). One ffmpeg pass decodes the file to 4 kHz mono PCM, then
// every 40 samples collapse to one peak = 100 peaks per second. Results are
// cached per path for the session; null means "could not decode" and the
// lane simply draws a flat bar instead of failing.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class WaveformService {
  WaveformService._();

  /// Peaks per second of audio.
  static const int peaksPerSec = 100;

  static final Map<String, List<double>> _cache = {};
  static final Map<String, Future<List<double>?>> _pending = {};

  static List<double>? cached(String path) => _cache[path];

  static Future<List<double>?> peaks(String path) {
    final hit = _cache[path];
    if (hit != null) return Future<List<double>?>.value(hit);
    final running = _pending[path];
    if (running != null) return running;
    final job = _compute(path);
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
          '-y -i "$path" -vn -ac 1 -ar 4000 -f s16le "$rawPath"');
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc) || !rawFile.existsSync()) return null;
      final bytes = await rawFile.readAsBytes();
      try {
        rawFile.deleteSync();
      } catch (_) {}
      final n = bytes.length ~/ 2;
      if (n == 0) return null;
      final bd = ByteData.sublistView(bytes);
      const per = 4000 ~/ peaksPerSec; // samples per peak
      final count = (n / per).ceil();
      final res = List<double>.filled(count, 0);
      var maxPeak = 0.0;
      for (var i = 0; i < count; i++) {
        final s = i * per;
        final e = math.min(n, s + per);
        var peak = 0;
        for (var j = s; j < e; j++) {
          final v = bd.getInt16(j * 2, Endian.little).abs();
          if (v > peak) peak = v;
        }
        final d = peak / 32768.0;
        res[i] = d;
        if (d > maxPeak) maxPeak = d;
      }
      // Display-normalise so quiet recitations still read as a waveform.
      if (maxPeak > 0.02) {
        final k = 1.0 / maxPeak;
        for (var i = 0; i < count; i++) {
          res[i] = (res[i] * k).clamp(0.0, 1.0);
        }
      }
      _cache[path] = res;
      return res;
    } catch (_) {
      return null;
    }
  }
}
