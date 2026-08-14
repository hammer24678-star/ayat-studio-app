// PATCH_S123_SPLASH: cold start used to drop straight onto a static welcome
// card. This is the opening the app deserves — the logo spins in out of a
// burst of the theme's own gold particles, an ornamental ring draws itself
// around it, and only then does the wordmark resolve.
//
// The whole thing is ~2.2s and is skipped entirely (straight to the welcome
// screen, no flash) when "حركات الواجهة" is off, so it can never become
// something a user has to sit through.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_settings.dart';
import '../theme/ayat_theme.dart';
import '../widgets/motion.dart';
import 'welcome_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const _total = Duration(milliseconds: 2300);

  late final AnimationController _c =
      AnimationController(vsync: this, duration: _total);

  // The logo lands and settles first…
  late final Animation<double> _logoIn = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
  );
  // …the particle burst rides the same window, slightly longer so the last
  // motes are still drifting when the logo has already stopped…
  late final Animation<double> _burst = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.02, 0.72, curve: Curves.easeOutQuad),
  );
  // …the ring draws itself around the settled logo…
  late final Animation<double> _ring = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.30, 0.78, curve: Curves.easeOutCubic),
  );
  // …and the wordmark resolves last.
  late final Animation<double> _title = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.50, 0.86, curve: Curves.easeOutCubic),
  );
  late final Animation<double> _sub = CurvedAnimation(
    parent: _c,
    curve: const Interval(0.66, 1.0, curve: Curves.easeOutCubic),
  );

  @override
  void initState() {
    super.initState();
    if (!AppMotion.on) {
      // Motion is off: don't show an animation-shaped screen at all.
      WidgetsBinding.instance.addPostFrameCallback((_) => _go());
      return;
    }
    _c.forward().whenComplete(() {
      if (mounted) _go();
    });
  }

  void _go() {
    if (!mounted) return;
    Navigator.of(context)
        .pushReplacement(AppMotion.route(const WelcomeScreen()));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance.strings;
    if (!AppMotion.on) {
      return const Scaffold(backgroundColor: AyatColors.ink, body: SizedBox());
    }
    return Scaffold(
      backgroundColor: AyatColors.ink,
      body: GestureDetector(
        // Tapping skips ahead — never trap someone behind an intro.
        onTap: _go,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A very slow radial wash so the ink background isn't dead flat
            // behind the gold.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [Color(0xFF0C1F1A), AyatColors.ink],
                ),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 220,
                      height: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (_burst.value > 0 && _burst.value < 1)
                            ParticleField(progress: _burst.value, count: 34),
                          CustomPaint(
                            size: const Size(190, 190),
                            painter: _RingPainter(_ring.value, _c.value),
                          ),
                          Transform.rotate(
                            // One and a half turns, decelerating into place.
                            angle: (1 - _logoIn.value) * math.pi * 3,
                            child: Transform.scale(
                              scale: 0.45 + _logoIn.value * 0.55,
                              child: Opacity(
                                opacity: _logoIn.value.clamp(0.0, 1.0),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AyatColors.gold.withValues(
                                            alpha: 0.35 * _logoIn.value),
                                        blurRadius: 34,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(22),
                                    child: Image.asset(
                                      'assets/icon/app_icon.png',
                                      width: 96,
                                      height: 96,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 26),
                    Opacity(
                      opacity: _title.value,
                      child: Transform.translate(
                        offset: Offset(0, 18 * (1 - _title.value)),
                        child: GoldShimmer(
                          child: Text(
                            s.t('app.name'),
                            textAlign: TextAlign.center,
                            style: GoogleFonts.arefRuqaa(
                              color: AyatColors.parchment,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    // A gold rule that grows out from the centre under the
                    // wordmark — the visual "signature" at the end of the
                    // sequence.
                    Container(
                      height: 1,
                      width: 160 * _sub.value,
                      color: AyatColors.gold.withValues(alpha: 0.7),
                    ),
                    const SizedBox(height: 12),
                    Opacity(
                      opacity: _sub.value,
                      child: Text(
                        s.t('app.eyebrow'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.tajawal(
                          color: AyatColors.gold,
                          fontSize: 11.5,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two ornamental rings around the logo: an outer one that sweeps itself
/// into existence, and an inner dotted one that rotates continuously.
class _RingPainter extends CustomPainter {
  /// 0..1 draw progress of the outer arc.
  final double draw;

  /// 0..1 overall timeline, used for the inner ring's slow spin.
  final double spin;
  const _RingPainter(this.draw, this.spin);

  @override
  void paint(Canvas canvas, Size size) {
    if (draw <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 6;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      math.pi * 2 * draw,
      false,
      Paint()
        ..color = AyatColors.gold.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..strokeCap = StrokeCap.round,
    );

    // Inner dotted ring — 24 small marks, rotating a third of a turn over
    // the whole sequence so the ornament reads as alive, not printed.
    const dots = 24;
    final innerR = r - 13;
    for (var i = 0; i < dots; i++) {
      final a = (i / dots) * math.pi * 2 + spin * math.pi * 0.7;
      final progressed = (i / dots) <= draw;
      if (!progressed) continue;
      canvas.drawCircle(
        center + Offset(math.cos(a), math.sin(a)) * innerR,
        1.5,
        Paint()..color = AyatColors.goldBright.withValues(alpha: 0.55 * draw),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.draw != draw || old.spin != spin;
}
