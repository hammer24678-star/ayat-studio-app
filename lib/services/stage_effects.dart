// PATCH_S34_STAGE_EFFECTS
// Decorative particle effects (rain / snow / golden light-dust) drawn over
// the video or background, under the ayah text. One deterministic painter
// serves BOTH the live preview (driven by an AnimationController) and the
// export (rendered as a short transparent PNG loop that ffmpeg tiles over
// the whole clip), so the burned-in effect looks exactly like the preview.
//
// Every particle's motion is periodic with period [loopSeconds]: positions
// wrap by whole multiples of the travel range and sways/twinkles use whole
// sine cycles, so frame t=loopSeconds is pixel-identical to t=0 and the
// exported loop is seamless.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

enum StageEffect { none, rain, snow, dust, sparkle }

extension StageEffectLabel on StageEffect {
  String get label => switch (this) {
        StageEffect.none => 'بدون تأثير',
        StageEffect.rain => 'مطر',
        StageEffect.snow => 'ثلج',
        StageEffect.dust => 'غبار ضوئي',
        StageEffect.sparkle => 'بريق نجمي', // PATCH_S51_MORE_EFFECTS
      };

  IconData get icon => switch (this) {
        StageEffect.none => Icons.block,
        StageEffect.rain => Icons.water_drop_outlined,
        StageEffect.snow => Icons.ac_unit,
        StageEffect.dust => Icons.auto_awesome,
        StageEffect.sparkle => Icons.star_outline, // PATCH_S51_MORE_EFFECTS
      };
}

class StageEffects {
  /// Period of the seamless loop. The export renders exactly
  /// [exportFrameCount] transparent frames covering one period and tiles
  /// them with ffmpeg's -stream_loop.
  static const double loopSeconds = 3.0;
  static const int exportFps = 12;
  static int get exportFrameCount => (loopSeconds * exportFps).round();

  // Deterministic pseudo-random in [0,1) from a particle index + salt —
  // no RNG state, so preview and export always agree.
  static double _rand(int i, int salt) {
    final x = sin(i * 127.1 + salt * 311.7) * 43758.5453;
    return x - x.floorToDouble();
  }

  static void paint(Canvas canvas, Size size, StageEffect effect,
      double timeSec, double intensity) {
    switch (effect) {
      case StageEffect.none:
        return;
      case StageEffect.rain:
        _paintRain(canvas, size, timeSec, intensity);
      case StageEffect.snow:
        _paintSnow(canvas, size, timeSec, intensity);
      case StageEffect.dust:
        _paintDust(canvas, size, timeSec, intensity);
      case StageEffect.sparkle: // PATCH_S51_MORE_EFFECTS
        _paintSparkle(canvas, size, timeSec, intensity);
    }
  }

  static void _paintRain(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final count = (150 * intensity).round();
    final paint = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < count; i++) {
      final depth = _rand(i, 1); // 0 = far/dim/short, 1 = near/bright/long
      final len = h * (0.030 + 0.045 * depth);
      final range = h + len;
      // whole [kLoops] traversals per loop keeps the wrap seamless
      final kLoops = 2 + (i % 2);
      final v = kLoops * range / loopSeconds;
      final y = ((_rand(i, 2) * range + v * t) % range) - len;
      final x = _rand(i, 3) * w;
      paint
        ..color = Colors.white.withValues(alpha: 0.14 + 0.30 * depth)
        ..strokeWidth = (1.0 + 1.6 * depth) * w / 1080;
      // constant slant: the drop is drawn tilted while falling vertically,
      // which reads as wind-blown rain without breaking the loop wrap
      canvas.drawLine(Offset(x, y), Offset(x + len * 0.18, y + len), paint);
    }
  }

  static void _paintSnow(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final count = (110 * intensity).round();
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final depth = _rand(i, 1);
      final r = (1.2 + 3.0 * depth) * w / 1080;
      final range = h + 2 * r;
      final v = range / loopSeconds; // one traversal per loop
      final y = ((_rand(i, 2) * range + v * t) % range) - r;
      // whole sine cycles per loop so the sway is also seamless
      final swayCycles = 1 + (i % 3);
      final phase = _rand(i, 4) * 2 * pi;
      final sway =
          sin(2 * pi * swayCycles * t / loopSeconds + phase) * w * 0.03;
      final x = (_rand(i, 3) * w + sway + w) % w;
      paint.color = Colors.white.withValues(alpha: 0.25 + 0.55 * depth);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  static void _paintDust(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final count = (70 * intensity).round();
    final paint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 * w / 1080);
    for (var i = 0; i < count; i++) {
      final depth = _rand(i, 1);
      final r = (1.0 + 2.4 * depth) * w / 1080;
      // dust hovers in place: whole-cycle sways + twinkle, no net drift,
      // so nothing needs to wrap at all
      final phase = _rand(i, 4) * 2 * pi;
      final swayCycles = 1 + (i % 2);
      final x = _rand(i, 2) * w +
          sin(2 * pi * swayCycles * t / loopSeconds + phase) * w * 0.015;
      final y = _rand(i, 3) * h +
          cos(2 * pi * swayCycles * t / loopSeconds + phase) * h * 0.008;
      final twinkleCycles = 1 + (i % 3);
      final twinkle =
          0.5 + 0.5 * sin(2 * pi * twinkleCycles * t / loopSeconds + phase * 2);
      paint.color = const Color(0xFFECC875)
          .withValues(alpha: (0.10 + 0.55 * twinkle) * (0.4 + 0.6 * depth));
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  // PATCH_S51_MORE_EFFECTS: quick white twinkling glints -- fixed points
  // that flash on and off fast, unlike the slow drifting golden dust.
  // Whole twinkle cycles per loop keep the export tile seamless, same
  // convention as the other effects.
  static void _paintSparkle(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final count = (90 * intensity).round();
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final x = _rand(i, 1) * w;
      final y = _rand(i, 2) * h;
      final twinkleCycles = 3 + (i % 4);
      final phase = _rand(i, 3) * 2 * pi;
      final twinkle =
          0.5 + 0.5 * sin(2 * pi * twinkleCycles * t / loopSeconds + phase);
      // most of the cycle stays dim/off; only a brief peak actually
      // flashes, so sparkles read as scattered quick glints rather than
      // a steady field
      final flash = pow(twinkle, 6).toDouble();
      if (flash < 0.02) continue;
      final r = (0.8 + 1.6 * _rand(i, 4)) * w / 1080;
      paint.color = Colors.white.withValues(alpha: flash * 0.9);
      canvas.drawCircle(Offset(x, y), r, paint);
      // a thin cross flare on the brightest sparkles sells the glint look
      if (flash > 0.6) {
        final flareLen = r * 5;
        paint
          ..color = Colors.white.withValues(alpha: (flash - 0.6) * 2 * 0.7)
          ..strokeWidth = r * 0.5;
        canvas.drawLine(
            Offset(x - flareLen, y), Offset(x + flareLen, y), paint);
        canvas.drawLine(
            Offset(x, y - flareLen), Offset(x, y + flareLen), paint);
      }
    }
  }

  /// One transparent frame of the export loop as PNG bytes.
  static Future<Uint8List> renderEffectFramePng({
    required int w,
    required int h,
    required StageEffect effect,
    required double timeSec,
    required double intensity,
  }) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    paint(canvas, Size(w.toDouble(), h.toDouble()), effect, timeSec, intensity);
    final img = await rec.endRecording().toImage(w, h);
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  }
}

/// Live-preview painter: driven by a repeating 0..1 animation that spans one
/// [StageEffects.loopSeconds] period, drawing the same deterministic
/// particles as the export loop.
class StageEffectPainter extends CustomPainter {
  final StageEffect effect;
  final Animation<double> loop;
  final double intensity;
  StageEffectPainter({
    required this.effect,
    required this.loop,
    required this.intensity,
  }) : super(repaint: loop);

  @override
  void paint(Canvas canvas, Size size) => StageEffects.paint(
      canvas, size, effect, loop.value * StageEffects.loopSeconds, intensity);

  @override
  bool shouldRepaint(StageEffectPainter old) =>
      old.effect != effect || old.intensity != intensity || old.loop != loop;
}
