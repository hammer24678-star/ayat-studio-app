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
// PATCH_S73_SIMPLE_GLITCH_RAIN
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// PATCH_S85_MORE_EFFECTS: fireflies/fog/rays appended at the END — the
// settings persistence stores effect.index, so existing saved choices keep
// pointing at the same effect.
enum StageEffect { none, rain, snow, dust, sparkle, geometricShimmer, confetti, glitch, fireflies, fog, rays } // PATCH_S72_GLITCH_EFFECT

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
        StageEffect.fireflies => 'يراعات مضيئة', // PATCH_S85_MORE_EFFECTS
        StageEffect.fog => 'ضباب هادئ', // PATCH_S85_MORE_EFFECTS
        StageEffect.rays => 'أشعة نور', // PATCH_S85_MORE_EFFECTS
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
        StageEffect.fireflies => Icons.emoji_nature_outlined, // PATCH_S85_MORE_EFFECTS
        StageEffect.fog => Icons.cloud_outlined, // PATCH_S85_MORE_EFFECTS
        StageEffect.rays => Icons.wb_twilight_outlined, // PATCH_S85_MORE_EFFECTS
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
      case StageEffect.fireflies: // PATCH_S85_MORE_EFFECTS
        _paintFireflies(canvas, size, timeSec, intensity);
      case StageEffect.fog: // PATCH_S85_MORE_EFFECTS
        _paintFog(canvas, size, timeSec, intensity);
      case StageEffect.rays: // PATCH_S85_MORE_EFFECTS
        _paintRays(canvas, size, timeSec, intensity);
    }
  }

  // PATCH_S85_MORE_EFFECTS: a handful of large, softly glowing points that
  // wander slowly around their anchor and pulse — unlike the dense drifting
  // `dust`, fireflies are few, bright and individually noticeable. Whole
  // wander/pulse cycles per loop keep the export tile seamless, same
  // convention as every other effect here.
  static void _paintFireflies(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final count = (14 * intensity).round().clamp(3, 20);
    final paint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6.0 * w / 1080);
    for (var i = 0; i < count; i++) {
      final phase = _rand(i, 1) * 2 * pi;
      final wanderCycles = 1 + (i % 2);
      // two independent eased oscillations trace a slow lissajous wander
      final dx = _easedOscillate(
              sin(2 * pi * wanderCycles * t / loopSeconds + phase)) *
          w *
          0.06;
      final dy = _easedOscillate(
              cos(2 * pi * (wanderCycles + 1) * t / loopSeconds + phase * 1.7)) *
          h *
          0.04;
      final x = _rand(i, 2) * w + dx;
      final y = _rand(i, 3) * h + dy;
      // slow pulse, mostly-on with a soft dip — a firefly, not a strobe
      final pulseCycles = 1 + (i % 3);
      final pulse =
          0.35 + 0.65 * (0.5 + 0.5 * sin(2 * pi * pulseCycles * t / loopSeconds + phase * 2));
      final r = (3.0 + 3.0 * _rand(i, 4)) * w / 1080;
      // warm green-gold glow halo + brighter core
      paint.color =
          const Color(0xFFD7EFA0).withValues(alpha: 0.45 * pulse * intensity);
      canvas.drawCircle(Offset(x, y), r * 2.2, paint);
      paint.color =
          const Color(0xFFF4FFCE).withValues(alpha: 0.9 * pulse * intensity);
      canvas.drawCircle(Offset(x, y), r, paint);
    }
  }

  // PATCH_S85_MORE_EFFECTS: two depth layers of very large, heavily blurred
  // ellipses drifting sideways — a quiet fog bank rolling through, not a
  // smoke machine. Each blob makes a whole traversal (or two) per loop so
  // the export tile wraps seamlessly.
  static void _paintFog(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.06 * w);
    const blobs = 10;
    for (var i = 0; i < blobs; i++) {
      final depth = _rand(i, 1); // far blobs: slower, dimmer, higher
      final bw = w * (0.55 + 0.5 * _rand(i, 2));
      final bh = h * (0.10 + 0.08 * _rand(i, 3));
      final range = w + bw;
      final kLoops = 1 + (i % 2); // whole traversals per loop
      final dir = (i % 2 == 0) ? 1.0 : -1.0; // layers cross for parallax
      final v = kLoops * range / loopSeconds;
      final travel = (_rand(i, 4) * range + v * t) % range;
      final x = (dir > 0 ? travel : range - travel) - bw / 2;
      // fog sits low-to-mid; far blobs float a bit higher
      final y = h * (0.35 + 0.55 * _rand(i, 5)) - depth * h * 0.15;
      paint.color = Colors.white
          .withValues(alpha: (0.045 + 0.05 * depth) * intensity);
      canvas.drawOval(
          Rect.fromCenter(center: Offset(x + bw / 2, y), width: bw, height: bh),
          paint);
    }
  }

  // PATCH_S85_MORE_EFFECTS: soft diagonal light beams falling from the top
  // edge — the classic "God rays through the window" recitation-video look.
  // Each beam sways around its base angle by a whole eased cycle per loop
  // and breathes in brightness, so the tile stays seamless.
  static void _paintRays(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    const beams = 6;
    for (var i = 0; i < beams; i++) {
      final phase = _rand(i, 1) * 2 * pi;
      final baseAngle = -0.35 + 0.7 * _rand(i, 2); // radians off vertical
      final sway = _easedOscillate(
              sin(2 * pi * (1 + i % 2) * t / loopSeconds + phase)) *
          0.05;
      final breathe =
          0.55 + 0.45 * sin(2 * pi * (1 + i % 3) * t / loopSeconds + phase * 2);
      final beamW = w * (0.05 + 0.09 * _rand(i, 3));
      final topX = w * (0.15 + 0.7 * _rand(i, 4));
      canvas.save();
      canvas.translate(topX, -h * 0.05);
      canvas.rotate(baseAngle + sway);
      final rect = Rect.fromLTWH(-beamW / 2, 0, beamW, h * 1.5);
      final paint = Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [
            const Color(0xFFFFF3D6)
                .withValues(alpha: 0.22 * breathe * intensity),
            const Color(0xFFFFF3D6).withValues(alpha: 0.0),
          ],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 0.012 * w);
      canvas.drawRect(rect, paint);
      canvas.restore();
    }
  }

  // PATCH_S73B_FIX_DUPLICATE_PAINT_RAIN: S73 left a duplicate/orphaned signature here (see
  // this patch's docstring) that broke the whole file's parse -- removed,
  // only the correct signature below (as part of S73's own block) remains.
  // PATCH_S73_SIMPLE_GLITCH_RAIN: replaced the 3-band depth-simulated rain
  // (far/mid/near blur + wind-gust slant drift + motion-blur trails) with a
  // single uniform layer -- the plain, flat "rain overlay" look used in
  // most recitation-video edits, not a simulated rain shower.
  static void _paintRain(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final count = (90 * intensity).round();
    const slant = 0.08; // fixed gentle slant, no wind-gust drift
    for (var i = 0; i < count; i++) {
      final len = h * 0.05;
      final range = h + len;
      final v = range / loopSeconds; // one traversal per loop
      final y = ((_rand(i, 2) * range + v * t) % range) - len;
      final x = _rand(i, 3) * w;
      final start = Offset(x, y);
      final end = Offset(x + len * slant, y + len);
      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.4 * w / 1080
        ..color = Colors.white.withValues(alpha: 0.22 * intensity);
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


  // PATCH_S73_SIMPLE_GLITCH_RAIN: replaced the multi-layer RGB-ghost +
  // scanline-jitter + static-noise glitch with the plain "block glitch"
  // every basic video editor ships as a glitch preset: a handful of
  // horizontal slices jump-cut sideways by a fixed offset for the burst
  // (no per-frame drift, no eased envelope) plus one flat red/cyan
  // channel split. No static noise, no scanline shimmer.
  static void _paintGlitch(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    const burstCount = 3; // fewer, punchier bursts than before
    for (var b = 0; b < burstCount; b++) {
      final burstCenter = (b + 0.5) / burstCount * loopSeconds;
      final dt =
          ((t - burstCenter + loopSeconds / 2) % loopSeconds) - loopSeconds / 2;
      const burstWidth = 0.08; // short and sharp -- a cut, not a wave
      final burstEnv = (1 - (dt.abs() / burstWidth)).clamp(0.0, 1.0);
      if (burstEnv <= 0) continue;
      final strength = burstEnv * intensity; // linear on/off, no easing curve

      // A few horizontal slices jump-cut sideways by a fixed offset for
      // the whole burst -- the classic "block glitch" look.
      final sliceCount = 3 + (b % 2);
      for (var s = 0; s < sliceCount; s++) {
        final i = b * 10 + s;
        final rowY = _rand(i, 1) * h;
        final rowH = h * (0.03 + 0.05 * _rand(i, 2));
        final dir = (_rand(i, 3) > 0.5) ? 1.0 : -1.0;
        final shift = dir * w * (0.02 + 0.05 * _rand(i, 4)) * strength;
        final rect = Rect.fromLTWH(0, rowY, w, rowH);
        canvas.save();
        canvas.translate(shift, 0);
        canvas.drawRect(
          rect,
          Paint()..color = Colors.black.withValues(alpha: 0.18 * strength),
        );
        canvas.restore();
      }

      // One flat red/cyan channel split across the whole frame -- a clean
      // offset, not a per-strip gradient ghost.
      final splitShift = w * 0.006 * strength;
      canvas.save();
      canvas.translate(-splitShift, 0);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..color = const Color(0xFFFF3B3B).withValues(alpha: 0.18 * strength)
          ..blendMode = BlendMode.plus,
      );
      canvas.restore();
      canvas.save();
      canvas.translate(splitShift, 0);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..color = const Color(0xFF3BE8FF).withValues(alpha: 0.18 * strength)
          ..blendMode = BlendMode.plus,
      );
      canvas.restore();
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
