#!/usr/bin/env python3
"""
patch_s160b_fix_missing_overlaypngcues_decl.py
=============================================

BUG (CI): build fails with

    lib/services/export_service.dart:1171:16: Error: Undefined name 'overlayPngCues'.

ROOT CAUSE: patch_s160_multi_text_time_cues.py has FOUR replace_once()
calls against export_service.dart. Three of them (render-one-PNG-per-cue,
chain-one-gated-overlay-per-cue) clearly landed -- that's the only way
lines ~1171-1189 could reference `overlayPngCues` at all. But the FIRST
one -- the one that actually declares the field:

    List<({String path, double start, double end})>? overlayPngCues;

-- used a fragile two-line anchor:

    "      String? overlaySeqPattern;\\n      String? overlayPng;"

That anchor apparently didn't match byte-for-byte in the real file
(different indentation / something between the two lines / etc.), so
replace_once() silently no-op'd (SKIPPED-ANCHOR-NOT-FOUND) while the
other three calls against the same file went ahead and started using a
variable that was never declared. Nothing failed loudly because each
replace_once() call is independent -- this is exactly the kind of
partial-apply state the marker-gated design is supposed to make rare,
but a bad anchor on the *declaration* line slipped through.

FIX: add the missing declaration using a single-line anchor
(`String? overlayPng;` alone, which -- given the other three patches
already landed -- we know exists and is unique) instead of the
brittle two-line pair. Marker-gated, idempotent, safe to re-run even
if patch_s160 is re-run first or after.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

EXPORT_SERVICE = "lib/services/export_service.dart"
MARKER = "PATCH_S160_MULTI_TEXT_TIME_CUES"


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


def replace_once(path, old, new, label):
    p = ROOT / path
    if not p.exists():
        _log(label, "SKIPPED-NOT-FOUND")
        return False
    text = p.read_text(encoding="utf-8")
    if "overlayPngCues;" in text:
        _log(label, "SKIPPED-ALREADY")
        return False
    count = text.count(old)
    if count == 0:
        _log(label, "SKIPPED-ANCHOR-NOT-FOUND")
        return False
    if count > 1:
        _log(label, f"SKIPPED-ANCHOR-AMBIGUOUS({count})")
        return False
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "OK")
    return True


# ---------------------------------------------------------------------
# declare overlayPngCues right after overlayPng, using a single-line
# anchor instead of the two-line pair that didn't match last time
# ---------------------------------------------------------------------

_DECL_OLD = "String? overlayPng;"

_DECL_NEW = f"""String? overlayPng;
      // {MARKER}: one rendered PNG + its own [start, end) window per
      // committed text cue, so several different texts can each show up
      // only during their own slice of the export instead of one baked
      // PNG (and one shared window) for the whole clip.
      List<({{String path, double start, double end}})>? overlayPngCues;"""

replace_once(EXPORT_SERVICE, _DECL_OLD, _DECL_NEW,
             "export_service.dart: declare overlayPngCues (retry, single-line anchor)")


def main():
    print("=" * 70)
    print("S160b — fix missing overlayPngCues declaration")
    print("=" * 70)
    print()
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok} fix(es) applied.")
    print("=" * 70)
    if ok == 0:
        print("""
Nothing applied -- check the SKIPPED reason above:
  - ANCHOR-NOT-FOUND: 'String? overlayPng;' isn't in export_service.dart
    verbatim (whitespace differs). Open the file and add the
    overlayPngCues declaration next to overlayPng by hand.
  - ANCHOR-AMBIGUOUS: more than one match -- narrow the anchor with
    surrounding context (e.g. include 'String? overlaySeqPattern;' above
    it) and re-run.
""")
    else:
        print("""
Next:
  1. flutter analyze   (confirm 'Undefined name overlayPngCues' is gone)
  2. flutter test
  3. git add -A && git commit -m "S160b: fix missing overlayPngCues declaration"
  4. git push
""")


if __name__ == "__main__":
    main()
