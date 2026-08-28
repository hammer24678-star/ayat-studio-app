# patch_s135_fix_autoseg_num_shadow.py
# Fixes the CI break introduced by S134's new file
# lib/widgets/autoseg_wizard.dart.
#
# Root cause: _importJson() declares `var num = 0;` inside the parsing
# loop. In Dart, a local variable shadows a type name for its ENTIRE
# enclosing scope, not just from its declaration point onward. Because
# `num` is also the built-in numeric type used earlier in the same loop
# (`st0 is! num`, `r['surah'] is num`, `as num`), the compiler treats
# every one of those earlier/other uses as a reference to the not-yet-
# initialized local variable instead of the type -- hence:
#   - "Local variable 'num' can't be referenced before it's declared"
#   - "Can't assign to a type literal"
#   - "Member not found: 'num.toDouble'"
#
# Fix: rename the local variable num -> ayahNum. All `is num` / `as num`
# type references are left untouched (they're the real numeric type and
# were never the problem). This file already exists in the repo (S134
# created it), so this patch edits it in place via apply_literal rather
# than re-creating it.
#
# Run from the project root.

from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []
TARGET = "lib/widgets/autoseg_wizard.dart"


def _log(label, status):
    LEDGER.append((label, status))


def apply_literal(rel_path, old, new, label, skip_if=None):
    p = ROOT / rel_path
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel_path} not found under {ROOT}")
    text = p.read_text(encoding="utf-8")
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


def main():
    # 1) The declaration itself.
    apply_literal(
        TARGET,
        "      var num = 0;\n",
        "      var ayahNum = 0;\n",
        "autoseg_wizard.dart: rename shadowing local `num` -> `ayahNum` (decl)",
        skip_if="var ayahNum = 0;",
    )

    # 2) Assignment from the regex-parsed reference string.
    apply_literal(
        TARGET,
        "          num = int.parse(m.group(2)!);\n",
        "          ayahNum = int.parse(m.group(2)!);\n",
        "autoseg_wizard.dart: rename `num` -> `ayahNum` (regex assign)",
        skip_if="ayahNum = int.parse(m.group(2)!);",
    )

    # 3) Fallback-from-map line: variable uses renamed, `is num` / `as num`
    #    type references left alone.
    apply_literal(
        TARGET,
        "      if (num == 0 && r['ayah'] is num) num = (r['ayah'] as num).toInt();\n",
        "      if (ayahNum == 0 && r['ayah'] is num) ayahNum = (r['ayah'] as num).toInt();\n",
        "autoseg_wizard.dart: rename `num` -> `ayahNum` (map fallback)",
        skip_if="if (ayahNum == 0 && r['ayah'] is num)",
    )

    # 4) Guard clause.
    apply_literal(
        TARGET,
        "      if (surah == 0 || num == 0 || en <= st) continue;\n",
        "      if (surah == 0 || ayahNum == 0 || en <= st) continue;\n",
        "autoseg_wizard.dart: rename `num` -> `ayahNum` (guard clause)",
        skip_if="surah == 0 || ayahNum == 0",
    )

    # 5) Merge-adjacent-segment comparison.
    apply_literal(
        TARGET,
        "        if (prev[2] == surah && prev[3] == num && st - prev[1] <= minSil) {\n",
        "        if (prev[2] == surah && prev[3] == ayahNum && st - prev[1] <= minSil) {\n",
        "autoseg_wizard.dart: rename `num` -> `ayahNum` (merge compare)",
        skip_if="prev[3] == ayahNum",
    )

    # 6) Final tuple push -- this is the line that produced
    #    "Member not found: 'num.toDouble'".
    apply_literal(
        TARGET,
        "      parsed.add([st, en, surah.toDouble(), num.toDouble()]);\n",
        "      parsed.add([st, en, surah.toDouble(), ayahNum.toDouble()]);\n",
        "autoseg_wizard.dart: rename `num` -> `ayahNum` (parsed.add)",
        skip_if="ayahNum.toDouble()]);",
    )

    print("\n=== S135 gauntlet loop ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================\n")


if __name__ == "__main__":
    main()
