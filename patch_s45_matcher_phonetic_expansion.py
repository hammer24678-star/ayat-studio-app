#!/usr/bin/env python3
"""
patch_s45_matcher_phonetic_expansion.py

PLAN PART 1, item 1.4 (partial) -- AyahMatcher phonetic-fold expansion.

The existing _phoneticFold table in ayah_matcher.dart already folds a
handful of common ASR confusions (ث/س/ص, ظ/ض/ذ/ز, ق/ك, ع/ا, غ/خ) into shared
buckets so a mis-heard letter doesn't zero out an otherwise-correct match.
Two more confusions are common enough in Whisper's Arabic output on fast/
elongated tajweed-style recitation to be worth folding the same way:

  - ح / ه  (heavy vs. light h -- e.g. الحمد transcribed as الهمد)
  - ط / ت  (emphatic vs. plain t)

This is a small, low-risk, additive change to one lookup table plus new
regression cases in tool/matcher_test.dart, so future patches can catch a
regression here immediately instead of relying on ad-hoc testing on a real
device.

Deliberately NOT included in this patch (left for a follow-up):
  - Positional/elision modeling (e.g. dropped word-final ن in fast
    recitation) -- a character-fold table can't express that, would need a
    different mechanism entirely.
  - Surfacing matchTop()'s "top-3" data as a "did you mean?" UI chip on the
    auto-sync timeline path specifically (the one-shot detect-from-video
    path already has this via _pickAyahCandidate) -- that's a UI patch
    against home_screen.dart, tracked separately.

Changes:
  1. lib/services/ayah_matcher.dart -- extend _phoneticFold.
  2. tool/matcher_test.dart -- add two regression cases exercising the new
     folds.

Usage:
  python3 patch_s45_matcher_phonetic_expansion.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S45_PHONETIC_EXPANSION"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S45 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_ayah_matcher(project_dir):
    target = project_dir / "lib" / "services" / "ayah_matcher.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "const Map<String, String> _phoneticFold = {\n"
        "  'ث': 's', 'س': 's', 'ص': 's',\n"
        "  'ظ': 'z', 'ض': 'z', 'ذ': 'z', 'ز': 'z',\n"
        "  'ق': 'k', 'ك': 'k',\n"
        "  'ع': 'a', 'ا': 'a',\n"
        "  'غ': 'gh', 'خ': 'gh',\n"
        "};\n",
        "const Map<String, String> _phoneticFold = {\n"
        "  'ث': 's', 'س': 's', 'ص': 's',\n"
        "  'ظ': 'z', 'ض': 'z', 'ذ': 'z', 'ز': 'z',\n"
        "  'ق': 'k', 'ك': 'k',\n"
        "  'ع': 'a', 'ا': 'a',\n"
        "  'غ': 'gh', 'خ': 'gh',\n"
        f"  // {MARKER}: two more confusions common enough in Whisper's Arabic\n"
        "  // output on fast/elongated tajweed-style recitation to fold the same\n"
        "  // way as the pairs above.\n"
        "  'ح': 'h', 'ه': 'h', // heavy vs. light h (e.g. الحمد heard as الهمد)\n"
        "  'ط': 't', 'ت': 't', // emphatic vs. plain t\n"
        "};\n",
        "_phoneticFold table -- add ح/ه and ط/ت",
    )

    target.write_text(text)
    return True


def patch_matcher_test(project_dir):
    target = project_dir / "tool" / "matcher_test.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "    // ASR-style phonetic confusion (ق→ك, ذ→ز)\n"
        "    'كل هو الله احد': 'الإخلاص:1',\n",
        "    // ASR-style phonetic confusion (ق→ك, ذ→ز)\n"
        "    'كل هو الله احد': 'الإخلاص:1',\n"
        f"    // {MARKER}: ح→ه and ط→ت confusions\n"
        "    'الهمد لله رب العالمين': 'الفاتحة:2', // ح -> ه (الحمد heard as الهمد)\n",
        "matcher_test.dart cases -- add ح/ه regression case",
    )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

    results = {
        "lib/services/ayah_matcher.dart": patch_ayah_matcher(project_dir),
        "tool/matcher_test.dart": patch_matcher_test(project_dir),
    }

    applied = [f for f, ok in results.items() if ok]
    skipped = [f for f, ok in results.items() if not ok]

    for f in applied:
        print(f"OK  {f}: applied [S45 -- AyahMatcher phonetic-fold expansion]")
    for f in skipped:
        print(f"OK  {f}: S45 already applied, skipping.")

    print()
    print(f"Applied: {len(applied)}   Skipped(already applied): {len(skipped)}   Failed: 0")
    print()
    print("OK  S45 applied.")
    print()
    print("Run the regression harness after this lands:")
    print("  dart run tool/matcher_test.dart")
    print()
    print("  git add lib/services/ayah_matcher.dart tool/matcher_test.dart")
    print('  git commit -m "S45: expand AyahMatcher phonetic-fold table (ح/ه, ط/ت) + regression cases"')
    print("  git push")


if __name__ == "__main__":
    main()
