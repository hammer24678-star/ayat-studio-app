#!/usr/bin/env python3
"""
patch_s73b_fix_duplicate_paint_rain.py

FIXES the build break from S73 (patch_s73_simple_glitch_rain.py):

    lib/services/stage_effects.dart:45:20: Error: Can't find '}' to match '{'.
    class StageEffects {
    ...(cascades into ~40 more errors)

ROOT CAUSE: S73's rain-block replacement used
    old_rain_start = "  // PATCH_S71_REALISTIC_RAIN: 3 depth bands (far/mid/near) instead of one continuous"
as its start anchor, intending that to be the doc-comment sitting ABOVE
the old `static void _paintRain(` signature. In the actual file, that
comment was actually positioned INSIDE the old function, right after its
signature line -- so the replace left the old
    static void _paintRain(
        Canvas canvas, Size size, double t, double intensity) {
orphaned in place, immediately followed by S73's full new function
(which has its own correct signature + comment + body + closing brace).
Two signatures, one dangling unclosed brace -- everything after gets
parsed as if it's nested inside the first (never-closed) _paintRain,
which is what produces the "static modifier not allowed here" / "method
not found" cascade all the way down the file.

THE FIX: delete the orphaned leading duplicate signature line pair, so
only S73's correct, complete _paintRain (comment + signature + body +
closing brace) remains.

WHAT THIS PATCH DOES:
  lib/services/stage_effects.dart
    - removes the dangling
        static void _paintRain(
            Canvas canvas, Size size, double t, double intensity) {
      that precedes S73's own comment+signature for the same function

Usage:
  python3 patch_s73b_fix_duplicate_paint_rain.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S73B_FIX_DUPLICATE_PAINT_RAIN"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S73b was written, "
            "or this was already fixed some other way.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_stage_effects(project_dir):
    target = project_dir / "lib" / "services" / "stage_effects.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    old = (
        "  static void _paintRain(\n"
        "      Canvas canvas, Size size, double t, double intensity) {\n"
        "    // PATCH_S73_SIMPLE_GLITCH_RAIN: replaced the 3-band depth-simulated rain\n"
    )
    new = (
        f"  // {MARKER}: S73 left a duplicate/orphaned signature here (see\n"
        "  // this patch's docstring) that broke the whole file's parse -- removed,\n"
        "  // only the correct signature below (as part of S73's own block) remains.\n"
        "  // PATCH_S73_SIMPLE_GLITCH_RAIN: replaced the 3-band depth-simulated rain\n"
    )
    text = replace_once(text, old, new, "stage_effects.dart orphaned _paintRain signature")

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    changed = patch_stage_effects(project_dir)
    print(f"{'OK: patched' if changed else 'SKIP: already applied'} lib/services/stage_effects.dart")

    print()
    print("Next steps:")
    print("  git add lib/services/stage_effects.dart")
    print("  git commit -m 'S73b: fix duplicate/orphaned _paintRain signature from S73'")
    print("  git push")
    print()
    print("HOW TO VERIFY: the CI build should get past the")
    print("'compileFlutterBuildRelease' step this time -- no more 'Can't find ")
    print("}} to match {{' or the cascade of static-modifier/method-not-found")
    print("errors in stage_effects.dart / stage_preview.dart / export_service.dart.")


if __name__ == "__main__":
    main()
