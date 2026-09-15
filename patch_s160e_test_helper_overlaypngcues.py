#!/usr/bin/env python3
"""
patch_s160e_test_helper_overlaypngcues.py
=============================================

S160d made `overlayPngCues` a real `required` parameter on
`ExportService.buildMainCommand` -- correctly. The one thing it didn't
touch is `test/export_graph_test.dart`, which calls that same static
method directly (it's `@visibleForTesting`) through its own small
`build(...)` wrapper. That wrapper never knew about the new param, so
the compiler now reports the missing required argument there instead
of the old undefined-name error in the app code.

FIX: give the test wrapper the same optional param, defaulting to
null (i.e. "no timed cues" -- the behaviour every existing test in
this file already assumes), and pass it straight through.

Safe to re-run.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

TEST_FILE = "test/export_graph_test.dart"


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


SIG_OLD = """String build(StudioState state, {
  String? overlayPng,
  String? overlaySeq,"""

SIG_NEW = """String build(StudioState state, {
  String? overlayPng,
  List<({String path, double start, double end})>? overlayPngCues, // PATCH_S160E
  String? overlaySeq,"""

CALL_OLD = """      overlaySeqPattern: overlaySeq,
      overlayPng: overlayPng,
      effectSeqPattern: effectSeq,"""

CALL_NEW = """      overlaySeqPattern: overlaySeq,
      overlayPng: overlayPng,
      overlayPngCues: overlayPngCues, // PATCH_S160E
      effectSeqPattern: effectSeq,"""


def main():
    print("=" * 70)
    print("S160e — pass overlayPngCues through the export_graph_test helper")
    print("=" * 70)
    print()

    p = ROOT / TEST_FILE
    if not p.exists():
        print(f"NOT FOUND: {TEST_FILE}")
        print("Run this from the repo root.")
        return

    text = p.read_text(encoding="utf-8")
    changed = False

    if "overlayPngCues" in text:
        _log("thread through test helper", "SKIPPED-ALREADY-APPLIED")
    elif text.count(SIG_OLD) == 1 and text.count(CALL_OLD) == 1:
        text = text.replace(SIG_OLD, SIG_NEW, 1)
        text = text.replace(CALL_OLD, CALL_NEW, 1)
        changed = True
        _log("thread through test helper", "OK")
    else:
        _log("thread through test helper", "SKIPPED-ANCHOR-NOT-FOUND")

    if changed:
        p.write_text(text, encoding="utf-8")

    print()
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok}/1 step(s) applied this run.")
    print("=" * 70)

    if ok == 0 and not any(s == "SKIPPED-ALREADY-APPLIED" for _, s in LEDGER):
        print("""
Anchor not found -- the build() helper in test/export_graph_test.dart
must have changed shape. Open it and add, by hand:
  1. a new optional param on build(): 
       List<({String path, double start, double end})>? overlayPngCues,
  2. pass it through: overlayPngCues: overlayPngCues,
  right next to the existing overlayPng param/argument.
""")
    else:
        print("""
Next:
  1. flutter analyze
  2. flutter test
  3. git add -A && git commit -m "S160e: pass overlayPngCues through export_graph_test helper"
  4. git push
""")


if __name__ == "__main__":
    main()
