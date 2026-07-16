#!/usr/bin/env python3
"""
PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX
=======================================================

Two real bugs from S118 + existing manual-add flow:

1. "إضافة هذا الجزء إلى الخط الزمني" (S118) was disabled whenever the
   selected word range happened to equal the whole ayah (isFull ==
   true) -- which is the DEFAULT selection, and is also just the normal
   case for short ayat (a 2-word ayah like "الرحمن الرحيم" is *always*
   "full" no matter what you pick). That disabling made sense for
   "استخدام هذا الجزء فقط" (redundant with just picking the ayah
   normally), but adding a whole ayah as a timeline segment is exactly
   what the full-ayah manual-add dialog already does with no such
   restriction -- there was no reason to block it here. This is why it
   looked greyed out / unselectable.

2. "مراجعة الآيات المرصودة" genuinely does appear once a segment is
   added (state.timelineActive flips true) -- but it renders ABOVE the
   ayah panel/tabs, while the buttons that add a segment live deep
   inside that panel, scrolled down. The toast text has said "مرّري
   لأعلى" (scroll up) for a while (S57) because this was already a
   known gap -- nothing actually scrolled the view there. Adding a
   ScrollController and animating to the top after a successful add
   makes the card actually visible instead of relying on the user to
   notice a toast and scroll manually.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s119_timeline_visibility_and_enable_fix.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX"


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
            f"aborting instead of guessing. (Does this project already "
            f"have PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE applied?)"
        )
    if count > 1:
        raise SystemExit(
            f"ERROR ({label}): old text found {count} times in {path}, "
            f"expected exactly 1 -- refusing to guess which one."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  OK    ({label}): patched")
    return True


# --- 1. add the ScrollController field ------------------------------------

_FIELD_OLD = """  final _customArCtrl = TextEditingController();
  final _customEnCtrl = TextEditingController();"""

_FIELD_NEW = """  // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX: "مراجعة الآيات
  // المرصودة" renders above the ayah panel, but every action that adds a
  // segment to it lives scrolled down inside that panel -- so the card
  // appearing was invisible in practice. This lets code scroll back to
  // it instead of just telling the user to do it themselves in a toast.
  final _scrollCtrl = ScrollController();
  final _customArCtrl = TextEditingController();
  final _customEnCtrl = TextEditingController();"""


# --- 2. attach it to the scroll view ---------------------------------------

_SCROLLVIEW_OLD = """          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),"""

_SCROLLVIEW_NEW = """          builder: (context, _) => SingleChildScrollView(
            controller: _scrollCtrl, // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX
            padding: const EdgeInsets.all(16),"""


# --- 3. dispose it ----------------------------------------------------------

_DISPOSE_OLD = """    _video?.dispose();
    _reciterPreview?.dispose();
    _liveOverlay.dispose();"""

_DISPOSE_NEW = """    _video?.dispose();
    _reciterPreview?.dispose();
    _liveOverlay.dispose();
    _scrollCtrl.dispose(); // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX"""


# --- 4. scroll-to-top helper, placed right by _addManualSegmentDialog ----

_HELPER_ANCHOR_OLD = """  Future<void> _addManualSegmentDialog() {"""

_HELPER_ANCHOR_NEW = """  // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX: "مراجعة الآيات
  // المرصودة" sits above the panel/tabs -- animate back up to it after a
  // segment is added so it's actually seen instead of scrolled past.
  void _revealTimelineCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _addManualSegmentDialog() {"""


# --- 5. call it from the full-ayah manual-add dialog -----------------------

_DIALOG_CALL_OLD = """                        final wasEmpty = state.timeline.isEmpty;
                        state.addManualSegment(
                            state.ayaat[dialogAyahIdx!], start, end);
                        Navigator.pop(context);
                        _toast(wasEmpty
                            ? 'أُضيفت الآية الأولى ✓ — مرّري لأعلى لرؤية \\'مراجعة الآيات المرصودة\\' وأكملي إضافة بقية النطاق من هناك'
                            : 'أُضيفت الآية إلى الخط الزمني ✓');"""

_DIALOG_CALL_NEW = """                        final wasEmpty = state.timeline.isEmpty;
                        state.addManualSegment(
                            state.ayaat[dialogAyahIdx!], start, end);
                        Navigator.pop(context);
                        _revealTimelineCard(); // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX
                        _toast(wasEmpty
                            ? 'أُضيفت الآية الأولى ✓ — إلى \\'مراجعة الآيات المرصودة\\' أعلى الشاشة'
                            : 'أُضيفت الآية إلى الخط الزمني ✓');"""


# --- 6. fix the partial-ayah "add to timeline" button (S118) --------------

_PARTIAL_BTN_OLD = """        OutlinedButton.icon(
          onPressed: isFull
              ? null
              : () {
                  final start =
                      state.timeline.isNotEmpty ? state.timeline.last.end : 0.0;
                  final end = start + 4;
                  state.addManualSegment(a, start, end,
                      textOverride: partialText);
                  _toast(
                      'أُضيف هذا الجزء إلى الخط الزمني ✓ — عدّلي توقيته من '
                      '\\'مراجعة الآيات المرصودة\\' أعلى الشاشة');
                },
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('إضافة هذا الجزء إلى الخط الزمني'),
        ),"""

_PARTIAL_BTN_NEW = """        // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX: this was disabled
        // whenever the picked range equalled the full ayah (isFull), but
        // that's the default selection AND the only possible selection
        // for any 2-word ayah -- adding a *whole* ayah to the timeline is
        // completely valid (it's what the full-ayah dialog already does
        // with no such restriction), so this button no longer checks
        // isFull at all.
        OutlinedButton.icon(
          onPressed: () {
            final start =
                state.timeline.isNotEmpty ? state.timeline.last.end : 0.0;
            final end = start + 4;
            state.addManualSegment(a, start, end, textOverride: partialText);
            _revealTimelineCard();
            _toast('أُضيف هذا الجزء إلى الخط الزمني ✓');
          },
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('إضافة هذا الجزء إلى الخط الزمني'),
        ),"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()

    home_file = None
    for p in (root / "lib").rglob("*.dart"):
        content = p.read_text(encoding="utf-8")
        if "Widget _partialAyahSection()" in content and "Future<void> _addManualSegmentDialog()" in content:
            home_file = p
            break
    if home_file is None:
        raise SystemExit(
            "ERROR: could not find the screen containing both "
            "_partialAyahSection() and _addManualSegmentDialog() under lib/."
        )

    print(f"Applying {MARKER} to {home_file}...")
    replace_once(home_file, _FIELD_OLD, _FIELD_NEW, "add _scrollCtrl field")
    replace_once(home_file, _SCROLLVIEW_OLD, _SCROLLVIEW_NEW, "attach controller to scroll view")
    replace_once(home_file, _DISPOSE_OLD, _DISPOSE_NEW, "dispose _scrollCtrl")
    replace_once(home_file, _HELPER_ANCHOR_OLD, _HELPER_ANCHOR_NEW, "add _revealTimelineCard()")
    replace_once(home_file, _DIALOG_CALL_OLD, _DIALOG_CALL_NEW,
                 "scroll to timeline after full-ayah manual add")
    replace_once(home_file, _PARTIAL_BTN_OLD, _PARTIAL_BTN_NEW,
                 "always-enabled partial-ayah add-to-timeline button")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
