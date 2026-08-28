// PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
import 'package:flutter/material.dart';
import '../theme/ayat_theme.dart';

/// Dashed gold box + corner handles drawn around the ayah text while it
/// is selected on the stage. Pure paint — all gestures stay on the
/// existing GestureDetector so drag/pinch behaviour is unchanged.
class SelectionBoxPainter extends CustomPainter {
  final Rect box; final bool active;
  const SelectionBoxPainter({required this.box, required this.active});
  @override
  void paint(Canvas c, Size size) {
    if (!active) return;
    // PATCH_S133_STAGE_TEXT_SELECT_EDIT: an empty box now means "draw
    // around whatever this CustomPaint was sized to" -- the stage wiring
    // sizes the painter to exactly the selected text's own Container via
    // CustomPaint's foregroundPainter auto-sizing, so it never has to
    // compute the text's on-screen Rect by hand.
    final r = (box.isEmpty ? Offset.zero & size : box).inflate(10);
    final line = Paint()..color = AyatColors.gold..strokeWidth = 1.6
      ..style = PaintingStyle.stroke;
    _dash(c, r, line);
    final fill = Paint()..color = AyatColors.goldBright..style = PaintingStyle.fill;
    final ring = Paint()..color = AyatColors.ink..style = PaintingStyle.stroke..strokeWidth = 1.2;
    for (final p in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight]) {
      c.drawCircle(p, 5, fill); c.drawCircle(p, 5, ring);
    }
  }
  void _dash(Canvas c, Rect r, Paint p) {
    void seg(Offset a, Offset b) {
      final d = b - a; final len = d.distance;
      if (len <= 0) return;
      final dir = d / len;
      for (double t = 0; t < len; t += 10) {
        final e = (t + 6) < len ? (t + 6) : len;
        c.drawLine(a + dir * t, a + dir * e, p);
      }
    }
    seg(r.topLeft, r.topRight); seg(r.topRight, r.bottomRight);
    seg(r.bottomRight, r.bottomLeft); seg(r.bottomLeft, r.topLeft);
  }
  @override
  bool shouldRepaint(covariant SelectionBoxPainter o) => o.box != box || o.active != active;
}

/// Hit-tests a tap against the words of a paragraph laid out exactly the
/// way the stage paints it (same TextStyle, same maxWidth, centered, RTL).
/// [local] must be in the paragraph's own coordinate space, i.e. the tap
/// position minus the same paint offset the stage uses
/// (Offset((w - tp.width)/2 + dx, top)). Returns the word index or null.
class WordHitTester {
  static int? wordAt({required String text, required TextStyle style,
      required double maxWidth, required Offset local}) {
    final words = text.split(RegExp(r'\s+'));
    if (words.isEmpty || text.trim().isEmpty) return null;
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.rtl, textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
    var off = 0;
    for (var i = 0; i < words.length; i++) {
      final start = off, end = off + words[i].length;
      for (final b in tp.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: end))) {
        if (b.toRect().inflate(4).contains(local)) return i;
      }
      off = end + 1; // +1 skips the space; last word simply never reads past end
    }
    return null;
  }
}
