#!/usr/bin/env python3
"""
patch_s160c_fix_overlaypngcues_scope.py
=============================================

BUG (still): 'Undefined name overlayPngCues' persists even though
S160's decl step reported OK and S160b's script says SKIPPED-ALREADY.

ROOT CAUSE (corrected): the field genuinely got declared somewhere in
export_service.dart -- that's why S160b saw the text and bailed. But
the file has TWO similarly-shaped blocks each with their own local
    String? overlaySeqPattern;
    String? overlayPng;
(almost certainly two separate export paths, e.g. two functions that
both build a filter graph). S160's decl patch matched ONE of them
(uniquely, so replace_once was happy); the render/gate patches -- which
are what actually reference `overlayPngCues` -- matched anchors that
happen to live in the OTHER one. Two different lexical scopes: declared
in scope A, used in scope B. Dart sees no declaration in scope B ->
undefined name, even though the field text exists in the file.

FIX: don't rely on "does this text exist anywhere in the file" (that's
what made S160b's already-applied check a false positive). Instead,
find the actual usage site (`overlayPngCues != null`), walk BACKWARDS
from there to the nearest preceding `String? overlayPng;`, and -- only
if a declaration isn't already sitting right there -- insert it at
that exact spot. This guarantees same-scope placement regardless of
how many look-alike blocks exist elsewhere in the file.

Marker-gated per-site (checks the 200 chars right after the anchor,
not "anywhere in file"), safe to re-run.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

EXPORT_SERVICE = "lib/services/export_service.dart"
MARKER = "PATCH_S160_MULTI_TEXT_TIME_CUES"

USAGE_NEEDLE = "overlayPngCues != null"
DECL_NEEDLE = "String? overlayPng;"
ALREADY_NEEDLE = "overlayPngCues;"  # only checked in the local window now


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


def fix_scope(path, label):
    p = ROOT / path
    if not p.exists():
        _log(label, "SKIPPED-NOT-FOUND")
        return False

    text = p.read_text(encoding="utf-8")

    usage_positions = []
    start = 0
    while True:
        i = text.find(USAGE_NEEDLE, start)
        if i == -1:
            break
        usage_positions.append(i)
        start = i + 1

    if not usage_positions:
        _log(label, "SKIPPED-NO-USAGE-FOUND")
        return False
    if len(usage_positions) > 1:
        _log(label, f"WARN-MULTIPLE-USAGES({len(usage_positions)})-using-first")

    usage_pos = usage_positions[0]

    # local window: from the usage site back to the nearest declaration
    # candidate, and forward a little to check for an existing decl.
    window_lookback = text.rfind(DECL_NEEDLE, 0, usage_pos)
    if window_lookback == -1:
        _log(label, "SKIPPED-NO-DECL-ANCHOR-BEFORE-USAGE")
        return False

    decl_line_end = window_lookback + len(DECL_NEEDLE)

    # already fixed at THIS site? check the ~300 chars right after the
    # anchor (same scope), not the whole file.
    local_after = text[decl_line_end:decl_line_end + 300]
    if ALREADY_NEEDLE in local_after:
        _log(label, "SKIPPED-ALREADY-AT-THIS-SITE")
        return False

    insertion = f"""
      // {MARKER} (scope fix): declared here, next to the overlayPng
      // this function already had, because the version added by
      // patch_s160 landed in a different same-shaped block elsewhere
      // in this file -- out of scope for the overlayPngCues usage
      // right below in *this* function.
      List<({{String path, double start, double end}})>? overlayPngCues;"""

    new_text = text[:decl_line_end] + insertion + text[decl_line_end:]
    p.write_text(new_text, encoding="utf-8")
    _log(label, "OK")
    return True


fix_scope(EXPORT_SERVICE, "export_service.dart: declare overlayPngCues in the SAME scope as its usage")


def main():
    print("=" * 70)
    print("S160c — fix overlayPngCues scope mismatch")
    print("=" * 70)
    print()
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok} fix(es) applied.")
    print("=" * 70)
    if ok == 0:
        print("""
Nothing applied -- check the SKIPPED/WARN reason above. If it says
NO-DECL-ANCHOR-BEFORE-USAGE, the usage site's enclosing function never
had its own 'String? overlayPng;' line to anchor on -- open
export_service.dart around the 'overlayPngCues != null' branch by hand
and add:
    List<({String path, double start, double end})>? overlayPngCues;
right after that function's other local overlay-path variables.
""")
    else:
        print("""
Next:
  1. flutter analyze   (confirm 'Undefined name overlayPngCues' is gone)
  2. flutter test
  3. git add -A && git commit -m "S160c: fix overlayPngCues scope mismatch"
  4. git push
""")


if __name__ == "__main__":
    main()
