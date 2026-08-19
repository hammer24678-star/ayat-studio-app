// PATCH_S123_MOTION: one place for every piece of motion in the app, so the
// "حركات الواجهة" switch in Settings can genuinely turn ALL of it off rather
// than leaving a half-animated UI behind.
//
// Every widget here degrades to its final, static frame when
// AppSettings.instance.animations is false — no controllers are started, no
// tickers run, and the child is laid out exactly where it would have landed.
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../data/text_transitions.dart'; // PATCH_S126_TEXT_TRANSITIONS
import '../services/app_settings.dart';
import '../theme/ayat_theme.dart';

/// Shared curves/durations, so the whole app moves with one personality
/// instead of every screen picking its own.
class AppMotion {
  static bool get on => AppSettings.instance.animations;

  /// [d], or zero when motion is off — pass this to any implicit animation
  /// (AnimatedContainer, AnimatedOpacity…) to make it obey the switch.
  static Duration d(Duration duration) => on ? duration : Duration.zero;

  static const fast = Duration(milliseconds: 180);
  static const medium = Duration(milliseconds: 340);
  static const slow = Duration(milliseconds: 620);

  /// Gentle deceleration used for entrances.
  static const enter = Curves.easeOutCubic;

  /// Slight overshoot, for things that should feel physical (button press).
  static const spring = Curves.easeOutBack;

  /// A page route that cross-fades and lifts, honouring the motion switch.
  static Route<T> route<T>(Widget page) {
    if (!on) {
      return PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    }
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 420),
      reverseTransitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.035),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}

/// Fades + lifts [child] into place once, [delay] after it is first built.
/// Used to stagger a column so a screen assembles itself instead of
/// appearing all at once.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;

  /// Where the child starts, in logical pixels, relative to its final spot.
  final Offset from;

  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.medium,
    this.from = const Offset(0, 14),
  });

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  // Created in initState, NOT as a lazy `late final` initializer. A lazy one
  // is only constructed on first use -- and when motion is off nothing uses
  // it until dispose(), at which point createTicker looks up a TickerMode
  // ancestor on an already-deactivated element and throws.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
    if (!AppMotion.on) {
      _c.value = 1;
      return;
    }
    // forward(from:) after a delay rather than a Timer we'd have to cancel:
    // AnimationController is already disposed-safe via [_c].
    Future<void>.delayed(widget.delay, () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.on) return widget.child;
    final curved = CurvedAnimation(parent: _c, curve: AppMotion.enter);
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: widget.from * (1 - curved.value),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Staggers [children] with [step] between each one. Returns them unchanged
/// when motion is off, so callers can use it unconditionally.
List<Widget> staggered(List<Widget> children,
    {Duration step = const Duration(milliseconds: 70),
    Duration start = Duration.zero}) {
  if (!AppMotion.on) return children;
  return [
    for (var i = 0; i < children.length; i++)
      FadeSlideIn(delay: start + step * i, child: children[i]),
  ];
}

/// Wraps any tappable surface with a press-in scale + a soft gold ripple.
/// This is what gives every button in the app the same physical feel.
class PressableScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// How far the widget shrinks while held (1.0 = no shrink).
  final double pressedScale;
  final BorderRadius borderRadius;
  final String? tooltip;

  const PressableScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.965,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
    this.tooltip,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool v) {
    if (!AppMotion.on || _down == v) return;
    setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    // The ink layer sits ON TOP of the child rather than behind it. Most of
    // what this wraps is an opaque decorated Container, and a Material placed
    // underneath one paints its ripple where nobody can see it — the press
    // would scale but never flash.
    Widget content = AnimatedScale(
      scale: _down && enabled ? widget.pressedScale : 1.0,
      duration: AppMotion.d(AppMotion.fast),
      curve: Curves.easeOut,
      child: Stack(
        children: [
          widget.child,
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              borderRadius: widget.borderRadius,
              child: InkWell(
                borderRadius: widget.borderRadius,
                splashColor: AyatColors.gold.withValues(alpha: 0.14),
                highlightColor: AyatColors.gold.withValues(alpha: 0.06),
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                onTapDown: (_) => _set(true),
                onTapUp: (_) => _set(false),
                onTapCancel: () => _set(false),
              ),
            ),
          ),
        ],
      ),
    );
    if (widget.tooltip != null) {
      content = Tooltip(message: widget.tooltip!, child: content);
    }
    return content;
  }
}

/// A slow, continuous gold shimmer sweeping across [child]. Used sparingly —
/// the mushaf entry card and the splash wordmark — to make a surface read as
/// "special" without adding a second colour to the palette.
class GoldShimmer extends StatefulWidget {
  final Widget child;
  final Duration period;
  const GoldShimmer({
    super.key,
    required this.child,
    this.period = const Duration(milliseconds: 3200),
  });

  @override
  State<GoldShimmer> createState() => _GoldShimmerState();
}

class _GoldShimmerState extends State<GoldShimmer>
    with SingleTickerProviderStateMixin {
  // Eager, for the same reason as _FadeSlideInState._c above.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period);
    if (AppMotion.on) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.on) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (rect) {
          // Sweep a narrow highlight from one edge to the other; -0.4..1.4
          // keeps the band fully off-screen at both ends of the cycle so the
          // loop has a rest beat instead of snapping.
          final p = -0.4 + _c.value * 1.8;
          return LinearGradient(
            begin: Alignment.centerRight,
            end: Alignment.centerLeft,
            stops: [
              (p - 0.18).clamp(0.0, 1.0),
              p.clamp(0.0, 1.0),
              (p + 0.18).clamp(0.0, 1.0),
            ],
            colors: [
              Colors.transparent,
              AyatColors.goldBright.withValues(alpha: 0.30),
              Colors.transparent,
            ],
          ).createShader(rect);
        },
        child: child,
      ),
      child: widget.child,
    );
  }
}

/// The gold particle field used behind the splash logo and, faintly, behind
/// the mushaf entry card. Deterministic per [seed] so it never "jumps"
/// between rebuilds.
class ParticleField extends StatelessWidget {
  /// 0..1 progress through the animation — drives outward travel and fade.
  final double progress;
  final int count;
  final int seed;
  final Color color;
  const ParticleField({
    super.key,
    required this.progress,
    this.count = 26,
    this.seed = 7,
    this.color = AyatColors.gold,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _ParticlePainter(progress, count, seed, color),
        size: Size.infinite,
      );
}

class _ParticlePainter extends CustomPainter {
  final double progress;
  final int count;
  final int seed;
  final Color color;
  _ParticlePainter(this.progress, this.count, this.seed, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(seed);
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = math.min(size.width, size.height) / 2;
    for (var i = 0; i < count; i++) {
      final angle = rnd.nextDouble() * math.pi * 2;
      // Each particle has its own launch delay and speed so the field
      // breathes instead of pulsing as one ring.
      final delay = rnd.nextDouble() * 0.35;
      final speed = 0.65 + rnd.nextDouble() * 0.55;
      final local = ((progress - delay) / (1 - delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final travelled = maxR * (0.22 + local * speed * 0.85);
      // Orbit slightly as it travels — a straight radial burst reads
      // mechanical, a slow curl reads like light.
      final drift = angle + local * 0.9 * (i.isEven ? 1 : -1);
      final pos = center + Offset(math.cos(drift), math.sin(drift)) * travelled;
      final fade = local < 0.15
          ? local / 0.15
          : (1 - ((local - 0.15) / 0.85)).clamp(0.0, 1.0);
      final radius = (0.9 + rnd.nextDouble() * 1.9) * (0.5 + fade * 0.9);
      canvas.drawCircle(
        pos,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.75 * fade)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.1),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter old) =>
      old.progress != progress || old.count != count || old.seed != seed;
}

/// PATCH_S126_TEXT_TRANSITIONS: applies a [TextMotion] to a widget, so the
/// live preview animates the ayah text with the very same motion model the
/// exporter bakes into the overlay frames. One model, two renderers — which
/// is the only way "what you see is what you get" can actually hold.
///
/// The clip-based reveals (wipes, iris, curtain) are applied here. The
/// per-unit ones (word- and letter-by-letter) are not: they change which
/// glyphs are painted rather than which pixels survive, so the stage applies
/// them while building the text spans, using the same [revealUnitAlpha] ramp
/// the export renderer uses.
class TextMotionBox extends StatelessWidget {
  final TextMotion motion;
  final Widget child;
  const TextMotionBox({super.key, required this.motion, required this.child});

  @override
  Widget build(BuildContext context) {
    if (motion.isIdentity) return child;
    Widget out = child;

    final reveal = motion.reveal.clamp(0.0, 1.0);
    if (reveal < 1) {
      switch (motion.revealMode) {
        case RevealMode.wipeUp:
          out = ClipRect(
              clipper: _FactorClipper(heightFactor: reveal, alignY: 1),
              child: out);
        case RevealMode.wipeDown:
          out = ClipRect(
              clipper: _FactorClipper(heightFactor: reveal, alignY: -1),
              child: out);
        case RevealMode.wipeStart:
          out = ClipRect(
              clipper: _FactorClipper(widthFactor: reveal, alignX: 1),
              child: out);
        case RevealMode.wipeEnd:
          out = ClipRect(
              clipper: _FactorClipper(widthFactor: reveal, alignX: -1),
              child: out);
        case RevealMode.curtain:
          out = ClipRect(
              clipper: _FactorClipper(heightFactor: reveal), child: out);
        case RevealMode.iris:
          out = ClipOval(clipper: _IrisClipper(reveal), child: out);
        case RevealMode.words:
        case RevealMode.letters:
          // Nothing to clip: these reveals change which glyphs are painted,
          // and the stage builds them into the text spans itself via
          // revealUnitAlpha — the same ramp the exporter uses.
          break;
        case RevealMode.none:
          break;
      }
    }

    if (motion.blur > 0) {
      // motion.blur is a fraction of frame width; the preview stage is 270
      // design units wide, the same reference the text sizes use.
      final sigma = motion.blur * 270;
      out = ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: out,
      );
    }
    if (motion.opacity < 1) {
      out = Opacity(opacity: motion.opacity.clamp(0.0, 1.0), child: out);
    }
    if (motion.scale != 1 || motion.rotation != 0) {
      out = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..rotateZ(motion.rotation)
          ..scaleByDouble(motion.scale, motion.scale, 1, 1),
        child: out,
      );
    }
    if (motion.dx != 0 || motion.dy != 0) {
      out = FractionalTranslation(
          translation: Offset(motion.dx, motion.dy), child: out);
    }
    return out;
  }
}

class _FactorClipper extends CustomClipper<Rect> {
  final double widthFactor;
  final double heightFactor;

  /// -1 anchors to the leading/top edge, 1 to the trailing/bottom, 0 centres.
  final double alignX;
  final double alignY;
  const _FactorClipper({
    this.widthFactor = 1,
    this.heightFactor = 1,
    this.alignX = 0,
    this.alignY = 0,
  });

  @override
  Rect getClip(Size size) {
    final w = size.width * widthFactor;
    final h = size.height * heightFactor;
    final left = (size.width - w) * (alignX + 1) / 2;
    final top = (size.height - h) * (alignY + 1) / 2;
    return Rect.fromLTWH(left, top, w, h);
  }

  @override
  bool shouldReclip(_FactorClipper old) =>
      old.widthFactor != widthFactor ||
      old.heightFactor != heightFactor ||
      old.alignX != alignX ||
      old.alignY != alignY;
}

class _IrisClipper extends CustomClipper<Rect> {
  final double reveal;
  const _IrisClipper(this.reveal);

  @override
  Rect getClip(Size size) {
    final r = size.longestSide * 0.75 * reveal;
    return Rect.fromCircle(
        center: Offset(size.width / 2, size.height / 2), radius: r);
  }

  @override
  bool shouldReclip(_IrisClipper old) => old.reveal != reveal;
}
