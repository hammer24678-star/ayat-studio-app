// PATCH_S123_QURAN_ENTRY: the way into the mushaf used to be a bare
// OutlinedButton with a label — the plainest control on a screen full of
// gold. It is the most meaningful destination in the app, so it now looks
// like one: a framed card with hand-drawn corner ornaments, a rosette around
// the icon, a gold shimmer that sweeps across it, and a glow that breathes.
//
// All of the motion sits behind [AppMotion], so with animations off it is
// still the same ornamented card — just still.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/ayat_theme.dart';
import 'motion.dart';

class QuranEntryButton extends StatefulWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Compact drops the subtitle and shrinks the ornament — for use inside a
  /// studio panel, where the card sits among other controls.
  final bool compact;

  const QuranEntryButton({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.compact = false,
  });

  @override
  State<QuranEntryButton> createState() => _QuranEntryButtonState();
}

class _QuranEntryButtonState extends State<QuranEntryButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3600),
  );

  @override
  void initState() {
    super.initState();
    if (AppMotion.on) _breath.repeat(reverse: true);
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = AnimatedBuilder(
      animation: _breath,
      builder: (context, child) {
        final t = AppMotion.on ? _breath.value : 0.5;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: AyatColors.gold.withValues(alpha: 0.10 + 0.12 * t),
                blurRadius: 20 + 10 * t,
                spreadRadius: 0.5,
              ),
            ],
          ),
          child: child,
        );
      },
      child: CustomPaint(
        foregroundPainter: const _CornerOrnamentPainter(),
        child: Container(
          padding: EdgeInsets.symmetric(
              horizontal: 16, vertical: widget.compact ? 13 : 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Color(0xFF17342A),
                AyatColors.surface2,
                Color(0xFF10241D),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AyatColors.gold.withValues(alpha: 0.55)),
          ),
          child: Row(
            children: [
              _RosetteIcon(size: widget.compact ? 36 : 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.arefRuqaa(
                        color: AyatColors.parchment,
                        fontSize: widget.compact ? 15 : 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (!widget.compact) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: GoogleFonts.tajawal(
                          color: AyatColors.parchmentDim,
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_left,
                  color: AyatColors.gold, size: 22),
            ],
          ),
        ),
      ),
    );

    return PressableScale(
      onTap: widget.onTap,
      borderRadius: BorderRadius.circular(18),
      pressedScale: 0.98,
      child: GoldShimmer(period: const Duration(milliseconds: 4200), child: card),
    );
  }
}

/// The open-book glyph sitting inside a gold scalloped rosette — the same
/// ornament language as the mushaf's ayah-stop marks, so the button reads as
/// belonging to the reader it opens.
class _RosetteIcon extends StatelessWidget {
  final double size;
  const _RosetteIcon({required this.size});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: const _RosettePainter(),
            ),
            Icon(Icons.auto_stories_outlined,
                size: size * 0.44, color: AyatColors.goldBright),
          ],
        ),
      );
}

class _RosettePainter extends CustomPainter {
  const _RosettePainter();
  static const _teeth = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * 0.33;
    final bumpR = size.width * 0.48;
    final path = Path();
    const step = 2 * math.pi / _teeth;
    for (var i = 0; i <= _teeth; i++) {
      final angle = i * step;
      final mid = angle - step / 2;
      final outer = center + Offset(math.cos(angle), math.sin(angle)) * baseR;
      final bump = center + Offset(math.cos(mid), math.sin(mid)) * bumpR;
      if (i == 0) {
        path.moveTo(outer.dx, outer.dy);
      } else {
        path.quadraticBezierTo(bump.dx, bump.dy, outer.dx, outer.dy);
      }
    }
    path.close();
    canvas
      ..drawPath(
        path,
        Paint()..color = AyatColors.gold.withValues(alpha: 0.14),
      )
      ..drawPath(
        path,
        Paint()
          ..color = AyatColors.gold
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Thin gold brackets in each corner of the card — the printed-mushaf frame,
/// reduced to four marks so it decorates without boxing the content in.
class _CornerOrnamentPainter extends CustomPainter {
  const _CornerOrnamentPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AyatColors.goldBright.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;
    const inset = 7.0;
    const len = 13.0;
    final w = size.width, h = size.height;
    // top-left
    canvas.drawLine(const Offset(inset, inset + len),
        const Offset(inset, inset), paint);
    canvas.drawLine(const Offset(inset, inset),
        const Offset(inset + len, inset), paint);
    // top-right
    canvas.drawLine(Offset(w - inset - len, inset), Offset(w - inset, inset), paint);
    canvas.drawLine(Offset(w - inset, inset), Offset(w - inset, inset + len), paint);
    // bottom-left
    canvas.drawLine(Offset(inset, h - inset - len), Offset(inset, h - inset), paint);
    canvas.drawLine(Offset(inset, h - inset), Offset(inset + len, h - inset), paint);
    // bottom-right
    canvas.drawLine(
        Offset(w - inset - len, h - inset), Offset(w - inset, h - inset), paint);
    canvas.drawLine(
        Offset(w - inset, h - inset - len), Offset(w - inset, h - inset), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
