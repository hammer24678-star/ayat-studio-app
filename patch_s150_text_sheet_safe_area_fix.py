#!/usr/bin/env python3
"""
PATCH_S150_TEXT_SHEET_SAFE_AREA_FIX
=====================================

Quick fix: the "إضافة نص" bottom sheet (from PATCH_S144) only padded its
bottom by MediaQuery.viewInsets.bottom (the keyboard inset) + 18. That
covers the keyboard, but not the phone's own bottom system nav / gesture
bar (MediaQuery.padding.bottom) -- so with no keyboard open, the sheet's
last button ("حفظ في الخط الزمني") rendered straight underneath the nav
bar and was effectively unreachable/invisible, per the reported
screenshot.

PATCH_S147 already wrapped the sheet body in a SingleChildScrollView, so
scrolling itself works once there's something to scroll to -- the actual
bug is that the visible area never reserved room for the nav bar in the
first place, so there was nothing past it to scroll into.

THE FIX:
    bottom: MediaQuery.of(context).viewInsets.bottom + 18
        becomes
    bottom: MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).padding.bottom + 18

Now the sheet always reserves space for both the keyboard AND the system
nav bar, so every field/button stays fully visible and scrollable into
view instead of hiding behind the nav bar.

WHAT THIS PATCH TOUCHES:
    lib/screens/home_screen.dart (one line, inside _openTextSheet())

Run from the project root:
    python3 patch_s150_text_sheet_safe_area_fix.py [project_root]
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


HOME_SCREEN = "lib/screens/home_screen.dart"


def patch_sheet_bottom_padding() -> None:
    old = """          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
"""
    new = """          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 14,
            // PATCH_S150_TEXT_SHEET_SAFE_AREA_FIX: viewInsets.bottom only
            // covers the keyboard -- it ignored the bottom system nav /
            // gesture bar, so the last button in the sheet rendered
            // straight underneath it. padding.bottom is the system-UI
            // inset; add it on top of the keyboard inset so content
            // always clears both.
            bottom: MediaQuery.of(context).viewInsets.bottom +
                MediaQuery.of(context).padding.bottom +
                18,
          ),
"""
    apply_literal(HOME_SCREEN, old, new,
                  "home_screen.dart: reserve bottom system-nav inset in the text sheet",
                  skip_if="PATCH_S150_TEXT_SHEET_SAFE_AREA_FIX")


def main() -> None:
    patch_sheet_bottom_padding()

    print("\n=== S150 text-sheet safe-area patch ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("=============================================\n")


if __name__ == "__main__":
    main()
