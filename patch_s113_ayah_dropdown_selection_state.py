#!/usr/bin/env python3
"""
PATCH_S113_AYAH_DROPDOWN_SELECTION_STATE
=======================================================

Bug: the "الآية" dropdown in _ayahPanel() had `value: null` hardcoded.
There was no field tracking which ayah index was picked, so every
rebuild (and there are many -- setAyah/state.update, partial-word
section, red-word section, etc. all trigger one) the dropdown snapped
back to showing the 'اختر الآية' hint instead of the chosen ayah. The
selection *was* being applied underneath (setAyah/_partialSourceAyah
still ran), but with no visual confirmation it looked like nothing
happened -- which is exactly what was reported ("لا يطبق شيء").

Fix: add a real `_selectedAyahIdx` field, set it in onChanged, wire it
into the dropdown's `value`, and clear it whenever the surah changes
(since the old index would point into a different surah's ayah list).

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s113_ayah_dropdown_selection_state.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S113_AYAH_DROPDOWN_SELECTION_STATE"


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
            f"aborting instead of guessing."
        )
    if count > 1:
        raise SystemExit(
            f"ERROR ({label}): old text found {count} times in {path}, "
            f"expected exactly 1 -- refusing to guess which one."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  OK    ({label}): patched")
    return True


# --- 1. add the tracking field next to _selectedSurah ----------------------

_FIELD_OLD = """  int _selectedTab = 0;
  int _selectedSurah = 1;
  // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: last ayah picked from the dropdown below,
  // so the partial-ayah word-range section knows what to slice from.
  Ayah? _partialSourceAyah;"""

_FIELD_NEW = """  int _selectedTab = 0;
  int _selectedSurah = 1;
  // PATCH_S113_AYAH_DROPDOWN_SELECTION_STATE: the "الآية" dropdown's value
  // was hardcoded to null, so it never reflected the chosen ayah and reset
  // to the hint on every rebuild -- looked like the selection wasn't being
  // applied even though it was. This is the missing tracked selection.
  int? _selectedAyahIdx;
  // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: last ayah picked from the dropdown below,
  // so the partial-ayah word-range section knows what to slice from.
  Ayah? _partialSourceAyah;"""


# --- 2. clear it when the surah changes (old index belongs to old surah) --

_SURAH_ONCHANGED_OLD = """          onChanged: (v) => setState(() => _selectedSurah = v ?? 1),
        ),
        _fieldLabel('الآية'),
        DropdownButton<int>(
          isExpanded: true,
          value: null,
          hint: const Text('اختر الآية'),"""

_SURAH_ONCHANGED_NEW = """          onChanged: (v) => setState(() {
            _selectedSurah = v ?? 1;
            // PATCH_S113_AYAH_DROPDOWN_SELECTION_STATE: old index belonged
            // to the previous surah's ayah list -- drop it instead of
            // pointing at the wrong ayah (or a now out-of-range index).
            _selectedAyahIdx = null;
          }),
        ),
        _fieldLabel('الآية'),
        DropdownButton<int>(
          isExpanded: true,
          value: _selectedAyahIdx,
          hint: const Text('اختر الآية'),"""


# --- 3. actually record the pick in onChanged ------------------------------

_AYAH_ONCHANGED_OLD = """          onChanged: (v) {
            if (v == null) return;
            final a = state.ayaat[v];
            _liveOverlay.value = null;
            state.setAyah(a.ar, a.en,
                'تم الاختيار يدويًا: سورة ${a.surah} — آية ${a.num}',
                surahNum: a.surahNum, ayahNum: a.num); // PATCH_S32_AI_ART_NANO_BANANA
            // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH
            final words = a.ar.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
            setState(() {
              _partialSourceAyah = a;
              _partialFromWord = 0;
              _partialToWord = words.isEmpty ? 0 : words.length - 1;
            });
          },"""

_AYAH_ONCHANGED_NEW = """          onChanged: (v) {
            if (v == null) return;
            final a = state.ayaat[v];
            _liveOverlay.value = null;
            state.setAyah(a.ar, a.en,
                'تم الاختيار يدويًا: سورة ${a.surah} — آية ${a.num}',
                surahNum: a.surahNum, ayahNum: a.num); // PATCH_S32_AI_ART_NANO_BANANA
            // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH
            final words = a.ar.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
            setState(() {
              // PATCH_S113_AYAH_DROPDOWN_SELECTION_STATE: actually remember
              // the picked index so the dropdown shows it instead of
              // snapping back to the 'اختر الآية' hint.
              _selectedAyahIdx = v;
              _partialSourceAyah = a;
              _partialFromWord = 0;
              _partialToWord = words.isEmpty ? 0 : words.length - 1;
            });
          },"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    # Find the file containing _ayahPanel() -- same file as _selectedSurah.
    candidates = [
        root / "lib/screens/editor_screen.dart",
        root / "lib/screens/home_screen.dart",
        root / "lib/main.dart",
    ]
    target = None
    for c in candidates:
        if c.exists() and "_selectedSurah = 1;" in c.read_text(encoding="utf-8"):
            target = c
            break
    if target is None:
        # Fall back to scanning lib/ for the field.
        for p in (root / "lib").rglob("*.dart"):
            if "_selectedSurah = 1;" in p.read_text(encoding="utf-8"):
                target = p
                break
    if target is None:
        raise SystemExit(
            "ERROR: could not locate the file containing '_selectedSurah = 1;' "
            "under lib/ -- pass the right project root."
        )

    print(f"Applying {MARKER} to {target}...")
    replace_once(target, _FIELD_OLD, _FIELD_NEW, "add _selectedAyahIdx field")
    replace_once(target, _SURAH_ONCHANGED_OLD, _SURAH_ONCHANGED_NEW,
                 "wire dropdown value + clear on surah change")
    replace_once(target, _AYAH_ONCHANGED_OLD, _AYAH_ONCHANGED_NEW,
                 "record picked index in onChanged")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
