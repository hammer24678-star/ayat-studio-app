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

enum StageEffect { none, rain, snow, dust, sparkle, geometricShimmer, confetti, glitch } // PATCH_S72_GLITCH_EFFECT

extension StageEffectLabel on StageEffect {
  String get label => switch (this) {
        StageEffect.none => 'بدون تأثير',
        StageEffect.rain => 'مطر',
        StageEffect.snow => 'ثلج',
        StageEffect.dust => 'غبار ضوئي',
        StageEffect.sparkle => 'بريق نجمي', // PATCH_S51_MORE_EFFECTS
        StageEffect.geometricShimmer => 'بريق زخرفي إسلامي', // PATCH_S52_MORE_EFFECTS
        StageEffect.confetti => 'قصاصات ذهبية', // PATCH_S52_MORE_EFFECTS
        StageEffect.glitch => 'أعطال بصرية', // PATCH_S72_GLITCH_EFFECT
      };

  IconData get icon => switch (this) {
        StageEffect.none => Icons.block,
        StageEffect.rain => Icons.water_drop_outlined,
        StageEffect.snow => Icons.ac_unit,
        StageEffect.dust => Icons.auto_awesome,
        StageEffect.sparkle => Icons.star_outline, // PATCH_S51_MORE_EFFECTS
        StageEffect.geometricShimmer => Icons.auto_awesome_mosaic, // PATCH_S52_MORE_EFFECTS
        StageEffect.confetti => Icons.celebration_outlined, // PATCH_S52_MORE_EFFECTS
        StageEffect.glitch => Icons.broken_image_outlined, // PATCH_S72_GLITCH_EFFECT
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

  // PATCH_S71_REALISTIC_RAIN: shared easing helper -- turns a raw sin/cos value
  // into a signed eased value (still in [-1, 1], still continuous and
  // periodic) so a sway reads as ease-in-out rather than constant-velocity
  // sinusoidal motion.
  static double _easeInOutSine(double x) => -(cos(pi * x) - 1) / 2;

  static double _easedOscillate(double raw) =>
      raw.sign * _easeInOutSine(raw.abs());

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
      case StageEffect.geometricShimmer: // PATCH_S52_MORE_EFFECTS
        _paintGeometricShimmer(canvas, size, timeSec, intensity);
      case StageEffect.confetti: // PATCH_S52_MORE_EFFECTS
        _paintConfetti(canvas, size, timeSec, intensity);
      case StageEffect.glitch: // PATCH_S72_GLITCH_EFFECT
        _paintGlitch(canvas, size, timeSec, intensity);
    }
  }

  static void _paintRain(
      Canvas canvas, Size size, double t, double intensity) {
    // PATCH_S71_REALISTIC_RAIN: 3 depth bands (far/mid/near) instead of one continuous
    // depth gradient -- distinct opacity/blur/speed/streak-length per band
    // is what makes rain read as real layered rainfall rather than "lines
    // falling in front of the camera."
    const bands = [
      (count: 70, alpha: 0.10, lenFrac: 0.028, blur: 1.6, speedMul: 0.75, widthMul: 0.8),
      (count: 55, alpha: 0.20, lenFrac: 0.045, blur: 0.6, speedMul: 1.05, widthMul: 1.15),
      (count: 35, alpha: 0.34, lenFrac: 0.065, blur: 0.0, speedMul: 1.35, widthMul: 1.5),
    ];
    var seedBase = 0;
    for (final band in bands) {
      _paintRainBand(canvas, size, t, intensity, band, seedBase);
      seedBase += 1000;
    }
  }

  // PATCH_S71_REALISTIC_RAIN: one depth band of the layered rain above.
  static void _paintRainBand(
    Canvas canvas,
    Size size,
    double t,
    double intensity,
    ({
      int count,
      double alpha,
      double lenFrac,
      double blur,
      double speedMul,
      double widthMul
    }) band,
    int seedBase,
  ) {
    final w = size.width, h = size.height;
    final count = (band.count * intensity).round();
    // Gentle whole-cycle wind-gust drift on the slant angle instead of a
    // constant slant -- one full gust cycle per loop keeps the export tile
    // seamless.
    final gustPhase = _rand(seedBase, 99) * 2 * pi;
    final slant = 0.14 + 0.10 * sin(2 * pi * t / loopSeconds + gustPhase);
    for (var i = 0; i < count; i++) {
      final idx = seedBase + i;
      final len = h * band.lenFrac;
      final range = h + len;
      final kLoops = 2 + (i % 2);
      final v = kLoops * range / loopSeconds * band.speedMul;
      final y = ((_rand(idx, 2) * range + v * t) % range) - len;
      final x = _rand(idx, 3) * w;
      final start = Offset(x, y);
      final end = Offset(x + len * slant, y + len);
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth =
            (1.0 + 1.2 * _rand(idx, 5)) * band.widthMul * w / 1080;
      if (band.blur > 0) {
        paint.maskFilter =
            MaskFilter.blur(BlurStyle.normal, band.blur * w / 1080);
      }
      // Motion-blur trail: gradient from transparent to the drop's color
      // along the streak, instead of a hard-edged uniform line.
      paint.shader = ui.Gradient.linear(
        start,
        end,
        [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: band.alpha),
        ],
      );
      canvas.drawLine(start, end, paint);
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
      // PATCH_S71_REALISTIC_RAIN: eased sway instead of a raw sine position --
      // lingers a touch near the sway's extremes and moves faster through
      // the middle, reading less mechanical. Still one whole sine cycle per
      // loop underneath, so the seamless wrap is untouched.
      final swayRaw = sin(2 * pi * swayCycles * t / loopSeconds + phase);
      final sway = _easedOscillate(swayRaw) * w * 0.03;
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
      // PATCH_S71_REALISTIC_RAIN: eased sway (see _paintSnow) instead of a raw
      // sin/cos position -- same whole-cycle-per-loop guarantee.
      final swayRawX = sin(2 * pi * swayCycles * t / loopSeconds + phase);
      final swayRawY = cos(2 * pi * swayCycles * t / loopSeconds + phase);
      final x = _rand(i, 2) * w + _easedOscillate(swayRawX) * w * 0.015;
      final y = _rand(i, 3) * h + _easedOscillate(swayRawY) * h * 0.008;
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

  // PATCH_S52_MORE_EFFECTS: a grid of 8-pointed star motifs (two overlapping squares
  // rotated 45° apart -- the classic Islamic geometric-pattern building
  // block) that gently counter-rotate and catch a soft diagonal shimmer
  // sweep. Whole rotations and whole sweep cycles per loop keep the
  // export tile seamless, same convention as every other effect here.
  static void _paintGeometricShimmer(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final cell = w / 6; // roughly 6 motifs across regardless of canvas size
    final cols = (w / cell).ceil() + 1;
    final rows = (h / cell).ceil() + 1;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, w / 540);
    for (var row = -1; row < rows; row++) {
      for (var col = -1; col < cols; col++) {
        final i = row * 1000 + col; // unique deterministic index per cell
        final cx = (col + 0.5) * cell;
        final cy = (row + 0.5) * cell;
        // a soft band of brightness sweeps diagonally across the grid once
        // per loop -- whole-cycle, so the wrap is seamless.
        final diag = (cx + cy) / (w + h); // 0..1 position along the sweep
        final phase = _rand(i, 5) * 2 * pi;
        final sweep = 0.5 +
            0.5 * sin(2 * pi * (t / loopSeconds - diag) + phase * 0.15);
        final glow = pow(sweep, 4).toDouble();
        if (glow < 0.03) continue;
        // gentle whole-rotation per loop, alternating direction and staggered
        // per cell so the lattice doesn't spin in lockstep.
        final spinDir = (i.abs() % 2 == 0) ? 1 : -1;
        final angle =
            spinDir * 2 * pi * t / loopSeconds + _rand(i, 6) * 2 * pi;
        paint.color = const Color(0xFFECC875)
            .withValues(alpha: glow * 0.55 * intensity);
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(angle);
        _drawEightPointStar(canvas, paint, cell * 0.30);
        canvas.restore();
      }
    }
  }

  // PATCH_S52_MORE_EFFECTS: two squares 45° apart, the simplest way to draw an
  // 8-pointed star outline (rub el hizb style) without needing an asset.
  static void _drawEightPointStar(Canvas canvas, Paint paint, double r) {
    Path square(double rot) {
      final path = Path();
      for (var k = 0; k < 4; k++) {
        final a = rot + k * pi / 2;
        final pt = Offset(cos(a) * r, sin(a) * r);
        if (k == 0) {
          path.moveTo(pt.dx, pt.dy);
        } else {
          path.lineTo(pt.dx, pt.dy);
        }
      }
      path.close();
      return path;
    }

    canvas.drawPath(square(pi / 4), paint);
    canvas.drawPath(square(0), paint);
  }

  // PATCH_S52_MORE_EFFECTS: small rotating gold rectangles falling and tumbling in a
  // light shower -- a festive alternative to the plain `dust` effect.
  // Same seamless-loop conventions as _paintRain/_paintSnow: whole
  // traversals for the fall and whole spin/sway cycles for the tumble.
  static void _paintConfetti(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final count = (60 * intensity).round();
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final depth = _rand(i, 1);
      final pw = (2.5 + 4.5 * depth) * w / 1080;
      final ph = pw * 0.5;
      final range = h + ph * 2;
      final kLoops = 1 + (i % 2); // whole traversals per loop
      final v = kLoops * range / loopSeconds;
      final y = ((_rand(i, 2) * range + v * t) % range) - ph;
      final swayCycles = 1 + (i % 3);
      final phase = _rand(i, 4) * 2 * pi;
      final sway =
          sin(2 * pi * swayCycles * t / loopSeconds + phase) * w * 0.04;
      final x = (_rand(i, 3) * w + sway + w) % w;
      // whole spin cycles per loop keeps the tumble seamless too
      final spinCycles = 2 + (i % 3);
      final angle = 2 * pi * spinCycles * t / loopSeconds + phase;
      final hueMix = _rand(i, 5);
      final color = Color.lerp(
          const Color(0xFFECC875), const Color(0xFFFFF3D6), hueMix)!;
      paint.color = color.withValues(alpha: (0.35 + 0.5 * depth) * intensity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);
      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: pw, height: ph), paint);
      canvas.restore();
    }
  }


  // PATCH_S72_GLITCH_EFFECT: RGB channel-split ghosting, horizontal scanline jitter, and
  // short static-noise bursts. Burst timing/offsets are deterministic and
  // whole-cycle-per-loop like every other effect here, so the exported
  // PNG-tile loop still wraps seamlessly. Most of the loop stays calm --
  // only [burstCount] brief windows per loop actually show anything, which
  // reads as an intermittent glitch rather than constant noise.
  static void _paintGlitch(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    const burstCount = 5;
    for (var b = 0; b < burstCount; b++) {
      final burstCenter = (b + 0.5) / burstCount * loopSeconds;
      final dt =
          ((t - burstCenter + loopSeconds / 2) % loopSeconds) - loopSeconds / 2;
      final burstWidth = 0.12 + 0.10 * _rand(b, 90);
      final burstEnv = (1 - (dt.abs() / burstWidth)).clamp(0.0, 1.0);
      if (burstEnv <= 0) continue;
      final strength = pow(burstEnv, 2).toDouble() * intensity;

      // RGB channel-split ghosting: a few horizontal strips duplicated with
      // a small red/blue horizontal offset, like a chromatic-aberration tear.
      final stripCount = 4 + (b % 3);
      for (var s = 0; s < stripCount; s++) {
        final i = b * 100 + s;
        final rowY = _rand(i, 1) * h;
        final rowH = h * (0.01 + 0.03 * _rand(i, 2));
        final shift = (2 + 10 * _rand(i, 3)) * w / 1080 * strength;
        final rect = Rect.fromLTWH(0, rowY, w, rowH);
        final redPaint = Paint()
          ..color = const Color(0xFFFF3B3B).withValues(alpha: 0.28 * strength)
          ..blendMode = BlendMode.plus;
        final bluePaint = Paint()
          ..color = const Color(0xFF3B9BFF).withValues(alpha: 0.28 * strength)
          ..blendMode = BlendMode.plus;
        canvas.save();
        canvas.translate(-shift, 0);
        canvas.drawRect(rect, redPaint);
        canvas.restore();
        canvas.save();
        canvas.translate(shift, 0);
        canvas.drawRect(rect, bluePaint);
        canvas.restore();
      }

      // Horizontal scanline jitter: a few thin strips shifted sideways.
      final jitterCount = 3 + (b % 2);
      for (var s = 0; s < jitterCount; s++) {
        final i = b * 200 + s;
        final rowY = _rand(i, 4) * h;
        final rowH = h * (0.006 + 0.012 * _rand(i, 5));
        final shift = (w * 0.02 + w * 0.10 * _rand(i, 6)) * strength;
        final dir = (i % 2 == 0) ? 1.0 : -1.0;
        final paint = Paint()..color = Colors.white.withValues(alpha: 0.10 * strength);
        canvas.drawRect(Rect.fromLTWH(dir * shift, rowY, w, rowH), paint);
      }

      // Brief static-noise burst: scattered small white/black flecks.
      final staticCount = (40 * strength).round();
      final staticPaint = Paint();
      for (var s = 0; s < staticCount; s++) {
        final i = b * 300 + s;
        final x = _rand(i, 7) * w;
        final y = _rand(i, 8) * h;
        final dotSize = (1.0 + 2.0 * _rand(i, 9)) * w / 1080;
        final bright = _rand(i, 10) > 0.5;
        staticPaint.color =
            (bright ? Colors.white : Colors.black).withValues(alpha: 0.5 * strength);
        canvas.drawRect(
            Rect.fromCenter(center: Offset(x, y), width: dotSize, height: dotSize),
            staticPaint);
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
