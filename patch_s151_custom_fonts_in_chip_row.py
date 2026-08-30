#!/usr/bin/env python3
"""
PATCH_S151_CUSTOM_FONTS_IN_CHIP_ROW
=====================================

THE PROBLEM (found while checking whether font upload works):
    Uploading a custom TTF/OTF (PATCH_S39_PERSISTENT_FONTS, lib/services/
    font_service.dart) works correctly end to end -- it registers, applies,
    persists to disk, and re-registers on every launch before settings
    restore. But the only live font picker on screen (TextEditorPro's chip
    row, in the النص tab's التنسيق panel) only ever looped the hardcoded
    `_fonts` list of built-in fonts -- it never included
    state.customFonts. So a freshly uploaded font applied immediately, but
    once you switched to a different font, there was no chip anywhere to
    tap back to it -- your only option was re-uploading the same file.
    (A dropdown that DOES list state.customFonts correctly already exists
    in home_screen.dart's _textPanel(), but that method is dead code, never
    mounted since PATCH_S128 replaced it with TextEditorPro -- so it wasn't
    actually reachable.)

    (v2 of this patch -- the first version anchored on the 'خط قرآني'/
    amiri_quran chip, which PATCH_S149 had already removed by the time this
    ran, so it found 0 matches and made no changes. This version anchors on
    the _fonts loop itself, which is still there post-S149.)

THE FIX:
    One more `for` loop in the same Wrap, right after the built-in chips
    and before the "+ إضافة خط" button, over state.customFonts -- using the
    exact same _chip() helper everything else in that row already uses, so
    an uploaded font previews in its own typeface and shows selected the
    same way a built-in one does.

WHAT THIS PATCH TOUCHES:
    lib/widgets/text_editor_pro.dart (one insertion, inside _text())

Run from the project root:
    python3 patch_s151_custom_fonts_in_chip_row.py [project_root]
(defaults to the directory this script lives in)

Idempotent: safe to run multiple times.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
LEDGER: list[tuple[str, str]] = []


def _log(label: str, status: str) -> None:
    LEDGER.append((label, status))


def apply_literal(rel_path: str, old: str, new: str, label: str,
                   skip_if: str | None = None) -> None:
    p = ROOT / rel_path
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel_path} not found under {ROOT}")
    text = p.read_text(encoding="utf-8")
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


TEXT_EDITOR_PRO = "lib/widgets/text_editor_pro.dart"


def patch_add_custom_fonts_to_chip_row() -> None:
    old = """      for (final f in _fonts) _chip(f.$2, f.$1, s.fontKey == f.$1,
          () => s.update(() => s.fontKey = f.$1)),
      // PATCH_S129_WIRE_AND_SIMPLIFY_UI: was hardcoded to onPressed: null
      ActionChip(avatar: const Icon(Icons.add, size: 14),
"""
    new = """      for (final f in _fonts) _chip(f.$2, f.$1, s.fontKey == f.$1,
          () => s.update(() => s.fontKey = f.$1)),
      // PATCH_S151_CUSTOM_FONTS_IN_CHIP_ROW: uploaded fonts applied
      // correctly the moment you picked them but had no chip here
      // afterward -- this loop was missing entirely. Same _chip() as
      // everything else, so an uploaded font previews in its own
      // typeface and shows selected exactly like a built-in one.
      for (final f in s.customFonts)
        _chip(f.label, f.key, s.fontKey == f.key,
            () => s.update(() => s.fontKey = f.key)),
      // PATCH_S129_WIRE_AND_SIMPLIFY_UI: was hardcoded to onPressed: null
      ActionChip(avatar: const Icon(Icons.add, size: 14),
"""
    apply_literal(TEXT_EDITOR_PRO, old, new,
                  "text_editor_pro.dart: show uploaded custom fonts as chips",
                  skip_if="PATCH_S151_CUSTOM_FONTS_IN_CHIP_ROW")


def main() -> None:
    patch_add_custom_fonts_to_chip_row()

    print("\n=== S151 custom-fonts-chip-row patch ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("=============================================\n")


if __name__ == "__main__":
    main()
