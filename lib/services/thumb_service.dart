// PATCH_S179_AAA
// Video thumbnails for the timeline's video lane (the filmstrip every pro
// editor shows). One ffmpeg pass writes at most ~40 small JPEG frames, one
// every `step` seconds; cached per path for the session. null = could not
// decode, and the lane just keeps its plain bar.
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class ThumbStrip {
  /// Seconds between two thumbnails.
  final double step;
  final List<String> files;
  const ThumbStrip(this.step, this.files);
}

class ThumbService {
  ThumbService._();

  static final Map<String, ThumbStrip> _cache = {};
  static final Map<String, Future<ThumbStrip?>> _pending = {};

  static ThumbStrip? cached(String path) => _cache[path];

  static Future<ThumbStrip?> strip(String path, double durSec) {
    final hit = _cache[path];
    if (hit != null) return Future<ThumbStrip?>.value(hit);
    final running = _pending[path];
    if (running != null) return running;
    final job = _compute(path, durSec);
    _pending[path] = job;
    job.whenComplete(() {
      _pending.remove(path);
    });
    return job;
  }

  static Future<ThumbStrip?> _compute(String path, double durSec) async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/thumbs_${path.hashCode.abs()}');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final stepI = math.max(1, (durSec / 40).ceil());
      final session = await FFmpegKit.execute(
          '-y -i "$path" -an -vf "fps=1/$stepI,scale=-2:72" -q:v 7 '
          '-frames:v 60 "${dir.path}/t_%03d.jpg"');
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) return null;
      final files = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.jpg'))
          .toList()
        ..sort();
      if (files.isEmpty) return null;
      final res = ThumbStrip(stepI.toDouble(), files);
      _cache[path] = res;
      return res;
    } catch (_) {
      return null;
    }
  }
}
