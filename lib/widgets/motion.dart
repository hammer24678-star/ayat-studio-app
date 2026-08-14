// PATCH_S123_MOTION: one place for every piece of motion in the app, so the
// "حركات الواجهة" switch in Settings can genuinely turn ALL of it off rather
// than leaving a half-animated UI behind.
//
// Every widget here degrades to its final, static frame when
// AppSettings.instance.animations is false — no controllers are started, no
// tickers run, and the child is laid out exactly where it would have landed.
import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  @override
  void initState() {
    super.initState();
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
    Widget content = AnimatedScale(
      scale: _down && enabled ? widget.pressedScale : 1.0,
      duration: AppMotion.d(AppMotion.fast),
      curve: Curves.easeOut,
      child: widget.child,
    );
    content = Material(
      color: Colors.transparent,
      borderRadius: widget.borderRadius,
      child: InkWell(
        borderRadius: widget.borderRadius,
        splashColor: AyatColors.gold.withValues(alpha: 0.12),
        highlightColor: AyatColors.gold.withValues(alpha: 0.06),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        child: content,
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
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
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
