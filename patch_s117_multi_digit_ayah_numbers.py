#!/usr/bin/env python3
"""
PATCH_S117_MULTI_DIGIT_AYAH_NUMBERS
=======================================================

Bug: ayah numbers of 100+ (three Eastern-Arabic-Indic digits, e.g. ١٠٠)
didn't fit inside the small mushaf ayah-stop rosette at its fixed font
size -- the digit effectively rendered with nothing visible, leaving
just the empty scalloped ring (reported: "when the ayah is above 100
you can't see the number"). ayahNumberBadge (used in the ayah-picker
list) has the same fixed-size assumption and would eventually hit the
same wall.

Fix: wrap the digit in each widget with a size-constrained FittedBox
(BoxFit.scaleDown) so it shrinks to fit 1, 2, or 3+ digits instead of
silently overflowing/disappearing. 1- and 2-digit ayahs render exactly
as before (no shrink needed); only 3-digit ayahs actually scale down.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s117_multi_digit_ayah_numbers.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S117_MULTI_DIGIT_AYAH_NUMBERS"


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


# --- 1. mushaf rosette digit (lib/screens/mushaf_screen.dart) -------------

_ROSETTE_OLD = """        Text(
          _easternArabicNumeral(num),
          textAlign: TextAlign.center,
          strutStyle: const StrutStyle(
            fontSize: 12,
            height: 1.0,
            forceStrutHeight: true,
          ),
          style: GoogleFonts.notoKufiArabic(
            textStyle: const TextStyle(
              color: AyatColors.goldBright,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),"""

_ROSETTE_NEW = """        // PATCH_S117_MULTI_DIGIT_AYAH_NUMBERS: 3-digit ayah numbers (100+)
        // didn't fit at a fixed font size and rendered as nothing at all.
        // FittedBox shrinks the digit to whatever space is actually
        // available instead of silently overflowing/disappearing.
        SizedBox(
          width: size * 0.62,
          height: size * 0.62,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              _easternArabicNumeral(num),
              textAlign: TextAlign.center,
              strutStyle: const StrutStyle(
                fontSize: 12,
                height: 1.0,
                forceStrutHeight: true,
              ),
              style: GoogleFonts.notoKufiArabic(
                textStyle: const TextStyle(
                  color: AyatColors.goldBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),"""


# --- 2. ayahNumberBadge (top-level widget, used in the ayah picker) ------

_BADGE_OLD = """Widget ayahNumberBadge(int num, {double size = 26, double fontSize = 11}) {
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AyatColors.gold,
      boxShadow: [
        BoxShadow(
          color: AyatColors.gold.withValues(alpha: 0.45),
          blurRadius: 6,
          spreadRadius: 0.5,
        ),
      ],
    ),
    child: Text(
      '$num',
      style: TextStyle(
        color: AyatColors.ink,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}"""

_BADGE_NEW = """Widget ayahNumberBadge(int num, {double size = 26, double fontSize = 11}) {
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AyatColors.gold,
      boxShadow: [
        BoxShadow(
          color: AyatColors.gold.withValues(alpha: 0.45),
          blurRadius: 6,
          spreadRadius: 0.5,
        ),
      ],
    ),
    // PATCH_S117_MULTI_DIGIT_AYAH_NUMBERS: same fixed-size assumption as
    // the mushaf rosette -- shrink 3-digit ayah numbers (100+) to fit
    // instead of letting them crowd or clip against the circle's edge.
    child: Padding(
      padding: EdgeInsets.all(size * 0.14),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$num',
          style: TextStyle(
            color: AyatColors.ink,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()

    mushaf = root / "lib/screens/mushaf_screen.dart"
    if not mushaf.exists():
        raise SystemExit(f"ERROR: expected file not found: {mushaf}")

    badge_file = None
    for p in (root / "lib").rglob("*.dart"):
        if "Widget ayahNumberBadge(" in p.read_text(encoding="utf-8"):
            badge_file = p
            break
    if badge_file is None:
        raise SystemExit(
            "ERROR: could not find 'Widget ayahNumberBadge(' anywhere under lib/."
        )

    print(f"Applying {MARKER}...")
    replace_once(mushaf, _ROSETTE_OLD, _ROSETTE_NEW, "shrink-to-fit rosette digit")
    replace_once(badge_file, _BADGE_OLD, _BADGE_NEW, "shrink-to-fit ayahNumberBadge digit")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
