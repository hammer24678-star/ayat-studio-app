#!/usr/bin/env python3
"""
PATCH_S115_HOTFIX_LIVE_LITWORDS_NULL_CHECK
=======================================================

Build break from S114 (red-word overrides in karaoke):

    lib/widgets/stage_preview.dart:613:37: Error: Property 'litWords'
    cannot be accessed on 'StageOverlayText?' because it is potentially
    null. Try accessing using ?. instead.
                      shadows: i < live.litWords ? litShadows : shadows,

The line right above it already does `i < live!.litWords` (asserting
non-null), but the `shadows:` line a few lines down was left as plain
`live.litWords` -- an inconsistency introduced while adding the red-word
override branch in S114. Both reads happen inside the same
`karaokeWords != null && karaokeWords.isNotEmpty` block where `live` is
known non-null (karaokeWords comes from `live?.karaokeWords`), so this
just needs the same `!` the line above already has.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s115_hotfix_live_litwords_null_check.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S115_HOTFIX_LIVE_LITWORDS_NULL_CHECK"


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


_OLD = """                  color: state.redWordIndices.contains(i)
                      ? redColor
                      : (i < live!.litWords ? state.textColor : dimColor),
                  height: state.lineHeightMultiplier,
                  letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
                  shadows: i < live.litWords ? litShadows : shadows,"""

_NEW = """                  color: state.redWordIndices.contains(i)
                      ? redColor
                      : (i < live!.litWords ? state.textColor : dimColor),
                  height: state.lineHeightMultiplier,
                  letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
                  // PATCH_S115_HOTFIX_LIVE_LITWORDS_NULL_CHECK: `live` is
                  // non-null in this branch (karaokeWords came from
                  // live?.karaokeWords and passed the isNotEmpty check
                  // above) but the analyzer can't see that across the
                  // ternary -- same `!` the line above already uses.
                  shadows: i < live!.litWords ? litShadows : shadows,"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    target = root / "lib/widgets/stage_preview.dart"
    if not target.exists():
        raise SystemExit(f"ERROR: expected file not found: {target}")

    print(f"Applying {MARKER}...")
    replace_once(target, _OLD, _NEW, "add missing ! on live.litWords")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
