# patch_s153_dedupe_guide_keys.py
#
# FIX for PATCH_S152_LANGUAGES_PATCH_A's "bonus fix" section.
#
# S152 assumed 9 keys -- settings.guide / settings.guideOpen /
# settings.guideHint and guide.title / guide.box / guide.drag /
# guide.pinch / guide.wordTap / guide.timeline -- were missing from
# lib/i18n/app_strings.dart entirely, and added them with fresh,
# English-only-fallback text.
#
# They were not missing. An earlier patch had already added all 9 with
# real hand-translated text in all 5 languages. S152's copy landed under
# the exact same keys in the same `const Map`, which Dart rejects at
# compile time -- this is the "settings.guide conflicts with another
# existing key" error from the CI log.
#
# This patch removes ONLY the S152 duplicate block (comment + 9 keys)
# from lib/i18n/app_strings.dart. It does not touch the original,
# correctly-translated entries for these same keys, and it does not
# touch any other key S152 added (common.remove, sequence.*,
# firstRunTour.*, textEditorPro.* are untouched -- those were not
# duplicates).
#
# Idempotent: if the duplicate block has already been removed (e.g. this
# patch already ran), it's skipped rather than erroring.
#
# Run from the project root.

from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []


def _log(label, status):
    LEDGER.append((label, status))


def apply_literal(rel_path, old, new, label, skip_if=None):
    p = ROOT / rel_path
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel_path} not found under {ROOT}")
    text = p.read_text(encoding="utf-8")
    if skip_if is not None and old not in text and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


APP_STRINGS = 'lib/i18n/app_strings.dart'

# This is the exact block PATCH_S152 inserted: its "bonus fix" comment
# plus the 9 duplicate keys, with English-only fallback text (no real
# fr/id/ur translations -- unlike the pre-existing entries for the same
# keys elsewhere in the table, which this patch leaves alone).
DUP_BLOCK_OLD = (
    "\n\n  // ---- PATCH_S145_LANGUAGES_PATCH_A bonus fix: these 9 keys were\n"
    "  // referenced by settings_screen.dart / user_guide_sheet.dart but never\n"
    "  // added to the table at all -- not a translation gap, there was no\n"
    "  // Arabic text anywhere to translate from. Written fresh here; please\n"
    "  // sanity-check the wording since it wasn't yours to begin with.\n"
    "  // French/Indonesian/Urdu fall back to English, same as the rest of\n"
    "  // this patch. ----\n"
    "  'settings.guide': ['دليل التحكم باللمس', 'Touch controls guide', 'Touch controls guide', 'Touch controls guide', 'Touch controls guide'],\n"
    "  'settings.guideOpen': ['فتح الدليل', 'Open the guide', 'Open the guide', 'Open the guide', 'Open the guide'],\n"
    "  'settings.guideHint': ['شرح سريع لكل إيماءات اللمس في الاستوديو.', 'A quick explainer for every touch gesture in the studio.', 'A quick explainer for every touch gesture in the studio.', 'A quick explainer for every touch gesture in the studio.', 'A quick explainer for every touch gesture in the studio.'],\n"
    "  'guide.title': ['دليل التحكم باللمس', 'Touch controls guide', 'Touch controls guide', 'Touch controls guide', 'Touch controls guide'],\n"
    "  'guide.box': ['اسحبي الإطار حول النص لتحريكه، واسحبي أطرافه لتغيير حجمه', 'Drag the box around the text to move it, and drag its corners to resize it', 'Drag the box around the text to move it, and drag its corners to resize it', 'Drag the box around the text to move it, and drag its corners to resize it', 'Drag the box around the text to move it, and drag its corners to resize it'],\n"
    "  'guide.drag': ['اسحبي النص مباشرة لتحريكه في أي اتجاه', 'Drag the text directly to move it in any direction', 'Drag the text directly to move it in any direction', 'Drag the text directly to move it in any direction', 'Drag the text directly to move it in any direction'],\n"
    "  'guide.pinch': ['اقرصي بإصبعين لتكبير النص أو تصغيره', 'Pinch with two fingers to make the text bigger or smaller', 'Pinch with two fingers to make the text bigger or smaller', 'Pinch with two fingers to make the text bigger or smaller', 'Pinch with two fingers to make the text bigger or smaller'],\n"
    "  'guide.wordTap': ['اضغطي على أي كلمة لتلوينها بالأحمر', 'Tap any word to color it red', 'Tap any word to color it red', 'Tap any word to color it red', 'Tap any word to color it red'],\n"
    "  'guide.timeline': ['اسحبي على الخط الزمني لتحديد وقت ظهور كل آية يدويًا', 'Drag along the timeline to manually set when each ayah appears', 'Drag along the timeline to manually set when each ayah appears', 'Drag along the timeline to manually set when each ayah appears', 'Drag along the timeline to manually set when each ayah appears'],"
)

DUP_BLOCK_NEW = ""

# If DUP_BLOCK_OLD is no longer present, we treat this marker string
# (part of it) as evidence the removal already happened -- lets the
# patch be re-run safely.
SKIP_MARKER = "PATCH_S145_LANGUAGES_PATCH_A bonus fix"


def main():
    apply_literal(APP_STRINGS, DUP_BLOCK_OLD, DUP_BLOCK_NEW,
                  'lib/i18n/app_strings.dart: remove S152 duplicate guide keys',
                  skip_if=SKIP_MARKER)

    print("\n=== S153 dedupe-guide-keys ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("========================================\n")


if __name__ == "__main__":
    main()
