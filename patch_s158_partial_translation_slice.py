#!/usr/bin/env python3
"""
patch_s158_partial_translation_slice.py
===========================================

BUG: when a timeline segment only carries PART of an ayah's Arabic text
(seg.textOverride set -- from "استخدام جزء من الآية فقط", or from an
ayah getting split into two+ separate timeline segments), the
translation shown for that segment is the FULL ayah's English
translation, every time -- not the portion that actually corresponds
to the Arabic words on screen.

Root cause, in buildKaraokeChunks() (lib/services/karaoke.dart):
`total` is the word count of `words` (which is ALREADY just the
override's partial word list when textOverride is set), and the
English slice was computed as a fraction of `total`/`parts` -- i.e.
"what fraction of THIS SEGMENT'S OWN words" rather than "what fraction
of the WHOLE AYAH's words". A segment holding the first 7 of a
14-word ayah, split into 1 part (7 words is under the 12-word split
threshold), got `enTo = ((0+1) * enWords.length / 1).round()` ==
100% of the translation, regardless of it only showing half the
Arabic.

FIX: locate where the segment's word range actually falls inside the
FULL canonical ayah (matched via normalizeArabic(), the same
normalizer the Quran matcher and search already share, so this
doesn't drift from either), and slice the translation proportionally
to that position in the full ayah -- not to the override's own
(already partial) word count. A full-ayah segment (textOverride ==
null) takes rangeStart=0 and fullTotal==total, which is exactly the
old formula -- so this is a no-op there, not a behavior change for
the common case.

Freely typed text that isn't a literal match against the canonical
ayah (so no word range can be located) falls back to the previous
behavior (whole translation) rather than guessing -- there's no
"correct" partial slice to compute for text that isn't the ayah.

Run from project root. Marker-gated, idempotent, safe to re-run.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []
MARKER = "PATCH_S158_PARTIAL_TRANSLATION_SLICE"

KARAOKE = "lib/services/karaoke.dart"
PUBSPEC = "pubspec.yaml"


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


def edit(rel, old, new, label):
    p = ROOT / rel
    if not p.exists():
        _log(label, "SKIPPED-NOT-FOUND")
        return False
    text = p.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            _log(label, "SKIPPED-ALREADY")
        else:
            _log(label, "SKIPPED-NOT-FOUND")
        return False
    text = text.replace(old, new, 1)
    p.write_text(text, encoding="utf-8")
    _log(label, "OK")
    return True


def main():
    print("=" * 70)
    print("S158 — partial-segment translation slice bug fix")
    print("=" * 70)

    p = ROOT / KARAOKE
    if p.exists() and MARKER in p.read_text(encoding="utf-8"):
        print(f"  {'SKIPPED-ALREADY':20s} karaoke.dart: already patched")
    else:
        # ── 1. import normalizeArabic (already shared by matcher+search) ─
        edit(KARAOKE,
             "import 'dart:math';\n\nimport '../models/studio_state.dart';",
             "import 'dart:math';\n\nimport '../models/studio_state.dart';\n"
             f"import 'ayah_matcher.dart'; // {MARKER}: normalizeArabic()",
             "karaoke: import ayah_matcher.dart for normalizeArabic()")

        # ── 2. word-range-lookup helper ───────────────────────────────
        edit(KARAOKE,
             "double _wordWeight(String word) => word.length + 2.0;",
             f"""// {MARKER}: finds where [part]'s words start inside [full] (both
// already word-split), comparing with normalizeArabic() so tashkeel/
// hamza-shape differences between the stored override and the
// canonical ayah text don't break the match. Returns 0 -- i.e. "treat
// [part] as if it opened the ayah" -- when no clean run is found,
// which is the same fallback as before this patch (whole translation)
// since fullTotal ends up == total in the caller for that case.
int _wordRangeStart(List<String> full, List<String> part) {{
  if (part.isEmpty || part.length > full.length) return 0;
  final normFull = [for (final w in full) normalizeArabic(w)];
  final normPart = [for (final w in part) normalizeArabic(w)];
  for (var i = 0; i <= normFull.length - normPart.length; i++) {{
    var match = true;
    for (var j = 0; j < normPart.length; j++) {{
      if (normFull[i + j] != normPart[j]) {{
        match = false;
        break;
      }}
    }}
    if (match) return i;
  }}
  return 0;
}}

double _wordWeight(String word) => word.length + 2.0;""",
             "karaoke: add _wordRangeStart() helper")

        # ── 3. buildKaraokeChunks: locate the range + fix the enTo math ──
        edit(KARAOKE,
             "  final words = seg.displayText.trim().split(RegExp(r'\\s+')); // PATCH_S157_TYPED_TEXT_DISPLAY\n"
             "  final total = words.length;\n"
             "  final parts = max(1, (total / maxWordsPerChunk).ceil());\n"
             "  final enWords = seg.ayah.en.trim().isEmpty\n"
             "      ? const <String>[]\n"
             "      : seg.ayah.en.trim().split(RegExp(r'\\s+'));\n"
             "  final segDur = max(0.001, seg.end - seg.start);",
             "  final words = seg.displayText.trim().split(RegExp(r'\\s+')); // PATCH_S157_TYPED_TEXT_DISPLAY\n"
             "  final total = words.length;\n"
             "  final parts = max(1, (total / maxWordsPerChunk).ceil());\n"
             "  final enWords = seg.ayah.en.trim().isEmpty\n"
             "      ? const <String>[]\n"
             "      : seg.ayah.en.trim().split(RegExp(r'\\s+'));\n"
             f"  // {MARKER}: a textOverride segment's `words` is already just\n"
             "  // its own slice -- fullArWords/rangeStart locate that slice\n"
             "  // inside the WHOLE ayah so the translation below is cut to the\n"
             "  // same span, not treated as 0%-100% of its own partial text.\n"
             "  final fullArWords = seg.textOverride == null\n"
             "      ? words\n"
             "      : seg.ayah.ar.trim().split(RegExp(r'\\s+'));\n"
             "  final fullTotal = fullArWords.length;\n"
             "  final rangeStart = seg.textOverride == null\n"
             "      ? 0\n"
             "      : _wordRangeStart(fullArWords, words);\n"
             "  final segDur = max(0.001, seg.end - seg.start);",
             "karaoke: compute fullArWords/rangeStart")

        edit(KARAOKE,
             "    final wordTo = ((p + 1) * total / parts).round();\n"
             "    final enTo = ((p + 1) * enWords.length / parts).round();",
             "    final wordTo = ((p + 1) * total / parts).round();\n"
             f"    // {MARKER}: proportional to position in the FULL ayah\n"
             "    // (rangeStart + wordTo) / fullTotal, not to this segment's\n"
             "    // own (possibly partial) word count.\n"
             "    final enTo = fullTotal == 0\n"
             "        ? 0\n"
             "        : (((rangeStart + wordTo) * enWords.length) / fullTotal)\n"
             "            .round()\n"
             "            .clamp(0, enWords.length);",
             "karaoke: enTo proportional to full-ayah position")

    # ── 4. pubspec.yaml: version bump ────────────────────────────────
    edit(PUBSPEC, "version: 1.7.0+7", "version: 1.7.1+8",
         "pubspec: version 1.7.0+7 -> 1.7.1+8")

    print()
    print("=" * 70)
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok} fix(es) applied.")
    print("=" * 70)
    print("""
Next:
  1. flutter clean && flutter pub get
  2. flutter analyze
  3. Reopen the يوسف 86 clip that showed the bug, scrub across both
     parts, confirm the translation now changes with them instead of
     showing the whole sentence throughout.

Note: the "turn off splitting" toggle you asked for already exists --
Text editor -> advanced -> \"تقسيم الآيات الطويلة إلى أجزاء متتالية\"
(off keeps a long ayah as one piece; a \"أقصى كلمات/جزء\" slider shows
under it when on). If you can't find it in the app, say so and I'll
check whether it's actually reachable from the screen you're using.
""")


if __name__ == "__main__":
    main()
