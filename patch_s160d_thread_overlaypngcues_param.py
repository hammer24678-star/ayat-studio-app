#!/usr/bin/env python3
"""
patch_s160d_thread_overlaypngcues_param.py
=============================================

REAL ROOT CAUSE (S160/S160b/S160c all missed it): `overlayPngCues` is
read inside `buildMainCommand`, which is a `static` method with its own
explicit parameter list. A static method cannot see local variables from
the function that calls it -- full stop -- no matter which block, or how
close, the declaration sits in the *caller*. This was never a "wrong
lexical block in the same file" problem; it's "this value was never
passed in." Every prior patch moved the declaration around in the
calling function and could never have worked.

FIX (three edits, all anchor-unique, all idempotent):
  1. Caller: collapse the duplicated `overlayPngCues` declaration left
     behind by S160c back down to a single clean decl.
  2. `buildMainCommand`'s signature: add
         required List<({String path, double start, double end})>? overlayPngCues,
     right next to the existing `required String? overlayPng,` param.
  3. The single call site that builds `cmd = buildMainCommand(...)`:
     pass `overlayPngCues: overlayPngCues,` right next to the existing
     `overlayPng: overlayPng,` argument.

Safe to re-run: each step checks whether it's already applied and
skips itself if so.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

EXPORT_SERVICE = "lib/services/export_service.dart"
FIELD_TYPE = "List<({String path, double start, double end})>? overlayPngCues"


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


def _read(path):
    p = ROOT / path
    if not p.exists():
        return None, p
    return p.read_text(encoding="utf-8"), p


# ---------------------------------------------------------------------
# Step 1: collapse the duplicate declaration S160c left in the caller
# ---------------------------------------------------------------------
DUP_OLD = """      String? overlaySeqPattern;
      String? overlayPng;
      // PATCH_S160_MULTI_TEXT_TIME_CUES (scope fix): declared here, next to the overlayPng
      // this function already had, because the version added by
      // patch_s160 landed in a different same-shaped block elsewhere
      // in this file -- out of scope for the overlayPngCues usage
      // right below in *this* function.
      List<({String path, double start, double end})>? overlayPngCues;
      // PATCH_S160_MULTI_TEXT_TIME_CUES: one rendered PNG + its own [start, end) window per
      // committed text cue, so several different texts can each show up
      // only during their own slice of the export instead of one baked
      // PNG (and one shared window) for the whole clip.
      List<({String path, double start, double end})>? overlayPngCues;"""

DUP_NEW = """      String? overlaySeqPattern;
      String? overlayPng;
      // PATCH_S160_MULTI_TEXT_TIME_CUES: one rendered PNG + its own [start, end) window per
      // committed text cue, so several different texts can each show up
      // only during their own slice of the export instead of one baked
      // PNG (and one shared window) for the whole clip. Threaded into
      // buildMainCommand as a real parameter (PATCH_S160D) -- it's a
      // static method and can't see this local otherwise.
      List<({String path, double start, double end})>? overlayPngCues;"""


def fix_duplicate_decl(text):
    if DUP_OLD in text:
        if text.count(DUP_OLD) > 1:
            _log("1. collapse duplicate decl", "WARN-MULTIPLE-SKIPPED")
            return text, False
        _log("1. collapse duplicate decl", "OK")
        return text.replace(DUP_OLD, DUP_NEW, 1), True

    if text.count(f"{FIELD_TYPE};") <= 1:
        _log("1. collapse duplicate decl", "SKIPPED-ALREADY-SINGLE")
        return text, False

    _log("1. collapse duplicate decl", "SKIPPED-ANCHOR-NOT-FOUND")
    return text, False


# ---------------------------------------------------------------------
# Step 2: add overlayPngCues to buildMainCommand's parameter list
# ---------------------------------------------------------------------
SIG_OLD = """    required String? overlayPng,
    required String? effectSeqPattern, // PATCH_S34_STAGE_EFFECTS"""

SIG_NEW = """    required String? overlayPng,
    required List<({String path, double start, double end})>? overlayPngCues, // PATCH_S160D
    required String? effectSeqPattern, // PATCH_S34_STAGE_EFFECTS"""


def fix_signature(text):
    if "required " + FIELD_TYPE + "," in text:
        _log("2. add param to buildMainCommand", "SKIPPED-ALREADY-APPLIED")
        return text, False

    if text.count(SIG_OLD) == 1:
        _log("2. add param to buildMainCommand", "OK")
        return text.replace(SIG_OLD, SIG_NEW, 1), True

    if text.count(SIG_OLD) == 0:
        _log("2. add param to buildMainCommand", "SKIPPED-ANCHOR-NOT-FOUND")
    else:
        _log("2. add param to buildMainCommand", "WARN-MULTIPLE-SKIPPED")
    return text, False


# ---------------------------------------------------------------------
# Step 3: pass overlayPngCues at the buildMainCommand(...) call site
# ---------------------------------------------------------------------
CALL_OLD = """        overlayPng: overlayPng,
        effectSeqPattern: effectSeqPattern, // PATCH_S34_STAGE_EFFECTS"""

CALL_NEW = """        overlayPng: overlayPng,
        overlayPngCues: overlayPngCues, // PATCH_S160D
        effectSeqPattern: effectSeqPattern, // PATCH_S34_STAGE_EFFECTS"""


def fix_call_site(text):
    if "overlayPngCues: overlayPngCues," in text:
        _log("3. pass at call site", "SKIPPED-ALREADY-APPLIED")
        return text, False

    if text.count(CALL_OLD) == 1:
        _log("3. pass at call site", "OK")
        return text.replace(CALL_OLD, CALL_NEW, 1), True

    if text.count(CALL_OLD) == 0:
        _log("3. pass at call site", "SKIPPED-ANCHOR-NOT-FOUND")
    else:
        _log("3. pass at call site", "WARN-MULTIPLE-SKIPPED")
    return text, False


def main():
    print("=" * 70)
    print("S160d — thread overlayPngCues into buildMainCommand as a real param")
    print("=" * 70)
    print()

    text, p = _read(EXPORT_SERVICE)
    if text is None:
        print(f"NOT FOUND: {EXPORT_SERVICE}")
        print("Run this from the repo root.")
        return

    changed = False
    text, c1 = fix_duplicate_decl(text)
    changed |= c1
    text, c2 = fix_signature(text)
    changed |= c2
    text, c3 = fix_call_site(text)
    changed |= c3

    if changed:
        p.write_text(text, encoding="utf-8")

    print()
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok}/3 step(s) applied this run.")
    print("=" * 70)

    if any(s.startswith("WARN") or s.startswith("SKIPPED-ANCHOR") for _, s in LEDGER):
        print("""
Something didn't match. Most likely a prior patch already reshaped one
of these three spots differently than expected. Open export_service.dart
and check by hand:
  1. the local `overlayPngCues` decl right before
     `if (state.hasVideo && state.timelineActive ...)`
  2. buildMainCommand's parameter list (search "required String? overlayPng,")
  3. the call `buildMainCommand(...)` (search "overlayPng: overlayPng,")
""")
    else:
        print("""
Next:
  1. flutter analyze   (confirm both errors are gone)
  2. flutter test
  3. git add -A && git commit -m "S160d: thread overlayPngCues into buildMainCommand as a real param"
  4. git push
""")


if __name__ == "__main__":
    main()
