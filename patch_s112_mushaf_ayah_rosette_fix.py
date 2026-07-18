#!/usr/bin/env python3
"""
PATCH_S112_MUSHAF_AYAH_ROSETTE_FIX
=======================================================

S111's rosette (8 separate overlapping gold-filled petal circles) rendered
as a muddy blob and swallowed the digit. This replaces it with what a real
printed mushaf ayah-stop actually is: a single thin-outlined scalloped
flower/gear ring, UNFILLED in the middle, drawn as one continuous Path
(quadratic-bezier bumps around a circle) -- not a cluster of separate
circles. The digit sits directly on the page background inside that ring,
in a bright colour, so it is never competing with a solid fill behind it.

Requires PATCH_S111_MUSHAF_AYAH_ROSETTE to already be applied.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s112_mushaf_ayah_rosette_fix.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S112_MUSHAF_AYAH_ROSETTE_FIX"


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")

    if new.strip() in text:
        print(f"  SKIP  ({label}): already applied")
        return False

    count = text.count(old)
    if count == 0:
        raise SystemExit(
            f"ERROR ({label}): expected old text not found in {path}. "
            f"Make sure PATCH_S111_MUSHAF_AYAH_ROSETTE was applied first, "
            f"and that the file hasn't drifted since -- aborting instead "
            f"of guessing."
        )
    if count > 1:
        raise SystemExit(
            f"ERROR ({label}): old text found {count} times in {path}, "
            f"expected exactly 1 -- refusing to guess which one."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  OK    ({label}): patched")
    return True


_OLD = """// PATCH_S111_MUSHAF_AYAH_ROSETTE: the classic printed-mushaf ayah-stop is an
// 8-petal flower/rosette around the number, not a flat circle. This redraws
// that shape with CustomPainter, using the app's own gold-on-ink palette
// (AyatColors.gold / goldBright / goldDim) instead of the printed page's
// maroon/black, so it reads as "our" ornament rather than a copy.
Widget _ayahRosetteOrnament(int num, {double size = 34}) {
  return SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: const _AyahRosettePainter(),
        ),
        Text(
          _easternArabicNumeral(num),
          style: GoogleFonts.amiriQuran(
            textStyle: const TextStyle(
              color: AyatColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AyahRosettePainter extends CustomPainter {
  const _AyahRosettePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = size.width / 2;
    final petalR = outerR * 0.32;
    final petalDist = outerR - petalR * 0.65;

    // Soft outer glow so the ornament doesn't collide with surrounding
    // letters, matching the glow already used on ayahNumberBadge.
    final glow = Paint()
      ..color = AyatColors.gold.withValues(alpha: 0.35)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(center, outerR, glow);

    final petalFill = Paint()
      ..shader = RadialGradient(
        colors: [AyatColors.goldBright, AyatColors.gold],
      ).createShader(Rect.fromCircle(center: center, radius: outerR));
    final petalRim = Paint()
      ..color = AyatColors.goldDim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Eight petals radiating from the centre -- the classic mushaf
    // ayah-stop rosette shape.
    for (var i = 0; i < 8; i++) {
      final angle = (pi / 4) * i;
      final petalCenter = center + Offset(cos(angle), sin(angle)) * petalDist;
      canvas.drawCircle(petalCenter, petalR, petalFill);
      canvas.drawCircle(petalCenter, petalR, petalRim);
    }

    // Solid centre disc so the digit sits on a clean, high-contrast field.
    final centerR = outerR * 0.58;
    final centerFill = Paint()
      ..shader = RadialGradient(
        colors: [AyatColors.goldBright, AyatColors.gold],
      ).createShader(Rect.fromCircle(center: center, radius: centerR));
    canvas.drawCircle(center, centerR, centerFill);
    canvas.drawCircle(
      center,
      centerR,
      Paint()
        ..color = AyatColors.goldDim
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}"""

_NEW = """// PATCH_S112_MUSHAF_AYAH_ROSETTE_FIX: matches a real printed-mushaf
// ayah-stop -- a single thin scalloped ring (one continuous outline, not
// a cluster of filled circles), left UNFILLED so the digit sits directly
// on the page and stays legible, drawn in the app's gold-on-ink palette.
Widget _ayahRosetteOrnament(int num, {double size = 26}) {
  return SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: const _AyahRosettePainter(),
        ),
        Text(
          _easternArabicNumeral(num),
          style: GoogleFonts.amiriQuran(
            textStyle: const TextStyle(
              color: AyatColors.goldBright,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AyahRosettePainter extends CustomPainter {
  const _AyahRosettePainter();

  static const _teeth = 10;

  Path _scallopedRing(Offset center, double baseR, double bumpR) {
    final path = Path();
    const step = 2 * pi / _teeth;
    for (var i = 0; i <= _teeth; i++) {
      final angle = i * step;
      final midAngle = angle - step / 2;
      final outerPt = center + Offset(cos(angle), sin(angle)) * baseR;
      final bumpPt = center + Offset(cos(midAngle), sin(midAngle)) * bumpR;
      if (i == 0) {
        path.moveTo(outerPt.dx, outerPt.dy);
      } else {
        path.quadraticBezierTo(bumpPt.dx, bumpPt.dy, outerPt.dx, outerPt.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * 0.30;
    final bumpR = size.width * 0.5;

    final ring = _scallopedRing(center, baseR, bumpR);

    // Left unfilled -- the digit reads straight off the paragraph
    // background inside the ring, exactly like the printed page.
    canvas.drawPath(
      ring,
      Paint()
        ..color = AyatColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );

    // Faint inner circle, echoing the thin double-ring on printed
    // ayah-stop marks, still fully see-through.
    canvas.drawCircle(
      center,
      baseR * 0.82,
      Paint()
        ..color = AyatColors.goldDim.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    target = root / "lib/screens/mushaf_screen.dart"
    if not target.exists():
        raise SystemExit(f"ERROR: expected file not found: {target}")

    print(f"Applying {MARKER}...")
    replace_once(target, _OLD, _NEW, "rosette: scalloped outline ring, legible digit")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
