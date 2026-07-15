#!/usr/bin/env python3
"""
PATCH_S111_MUSHAF_AYAH_ROSETTE
=======================================================

The mushaf reader's ayah-end marker (redone in S108 as a plain two-tone
gradient circle) still reads flat next to a real printed mushaf, where the
ayah-stop is a small 8-petal flower/rosette around the number. This swaps
the flat circle for a hand-drawn rosette (CustomPainter, 8 gold petals
around a solid centre disc) in the app's own gold-on-ink palette, keeping
the Eastern Arabic-Indic digit from S108.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s111_mushaf_ayah_rosette.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S111_MUSHAF_AYAH_ROSETTE"


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")

    if new.strip() in text:
        print(f"  SKIP  ({label}): already applied")
        return False

    count = text.count(old)
    if count == 0:
        raise SystemExit(
            f"ERROR ({label}): expected old text not found in {path}. "
            f"File may have drifted since this patch was written -- "
            f"aborting instead of guessing."
        )
    if count > 1:
        raise SystemExit(
            f"ERROR ({label}): old text found {count} times in {path}, "
            f"expected exactly 1 -- refusing to guess which one."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  OK    ({label}): patched")
    return True


# --- 1. add dart:math import for cos/sin/pi -------------------------------

_IMPORTS_OLD = """import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // PATCH_S108_MUSHAF_AYAH_ORNAMENT_REDESIGN"""

_IMPORTS_NEW = """import 'dart:math'; // PATCH_S111_MUSHAF_AYAH_ROSETTE: cos/sin/pi for petal layout
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // PATCH_S108_MUSHAF_AYAH_ORNAMENT_REDESIGN"""


# --- 2. add the rosette widget + painter, right after the numeral helper --

_HELPER_OLD = """const _kEasternArabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
String _easternArabicNumeral(int n) =>
    n.toString().split('').map((d) => _kEasternArabicDigits[int.parse(d)]).join();

class _MushafScreenState extends State<MushafScreen> {"""

_HELPER_NEW = """const _kEasternArabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
String _easternArabicNumeral(int n) =>
    n.toString().split('').map((d) => _kEasternArabicDigits[int.parse(d)]).join();

// PATCH_S111_MUSHAF_AYAH_ROSETTE: the classic printed-mushaf ayah-stop is an
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
}

class _MushafScreenState extends State<MushafScreen> {"""


# --- 3. swap the flat-circle Container for the new rosette ornament -------

_ORNAMENT_OLD = """                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    // PATCH_S108_MUSHAF_AYAH_ORNAMENT_REDESIGN:
                                    // two-tone radial-gradient medallion with a
                                    // thin rim ring, Eastern Arabic-Indic digit,
                                    // and more breathing margin so it reads as
                                    // a proper ayah-end marker instead of a flat
                                    // dot colliding with the surrounding letters.
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 5),
                                      width: 30,
                                      height: 30,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [
                                            AyatColors.goldBright,
                                            AyatColors.gold,
                                          ],
                                          stops: const [0.0, 1.0],
                                        ),
                                        border: Border.all(
                                          color: AyatColors.goldDim,
                                          width: 1,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: AyatColors.gold.withValues(alpha: 0.5),
                                            blurRadius: 7,
                                            spreadRadius: 0.5,
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        _easternArabicNumeral(a.num),
                                        style: GoogleFonts.amiriQuran(
                                          textStyle: const TextStyle(
                                            color: AyatColors.ink,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            height: 1.0,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),"""

_ORNAMENT_NEW = """                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    // PATCH_S111_MUSHAF_AYAH_ROSETTE: traditional
                                    // 8-petal flower/rosette ayah-end ornament,
                                    // like a real printed mushaf, redrawn in the
                                    // app's own gold-on-ink palette. Replaces the
                                    // S108 flat gradient circle.
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 5),
                                      child: _ayahRosetteOrnament(a.num),
                                    ),
                                  ),"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    target = root / "lib/screens/mushaf_screen.dart"
    if not target.exists():
        raise SystemExit(f"ERROR: expected file not found: {target}")

    print(f"Applying {MARKER}...")
    replace_once(target, _IMPORTS_OLD, _IMPORTS_NEW, "add dart:math import")
    replace_once(target, _HELPER_OLD, _HELPER_NEW, "add rosette widget + painter")
    replace_once(target, _ORNAMENT_OLD, _ORNAMENT_NEW, "swap flat circle for rosette")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
