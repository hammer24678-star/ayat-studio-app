#!/usr/bin/env python3
"""
PATCH_S116_LIVE_CAPTION_PREVIEW
=======================================================

Bug: "نص إضافي" (caption text / reciter name / ayah-range label, added in
S109) is correctly baked into the exported video by
OverlayRenderer.renderTextOverlayPng() -- but the live editing preview
(StagePreview's Stack in stage_preview.dart) never draws state.captionText
anywhere. Typing a caption and picking أعلى/أسفل genuinely updates state,
but nothing on screen ever reflects it, so it looks completely broken
while editing even though it would show up correctly in the export.

Fix: add a caption widget to the StagePreview Stack, styled the same way
(gold text, subtle shadow, near top/bottom edge) as the export overlay,
so what you type shows up immediately.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s116_live_caption_preview.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S116_LIVE_CAPTION_PREVIEW"


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


_OLD = """                    return PositionedDirectional(
                      bottom: 10,
                      end: 10,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AyatColors.ink.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AyatColors.hairline),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                                fontSize: 9.5, color: AyatColors.goldBright),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // PATCH_S34_PLAYER_CONTROLS_TRIM: brief ▶/⏸ feedback after a tap."""

_NEW = """                    return PositionedDirectional(
                      bottom: 10,
                      end: 10,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AyatColors.ink.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AyatColors.hairline),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                                fontSize: 9.5, color: AyatColors.goldBright),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // PATCH_S116_LIVE_CAPTION_PREVIEW: state.captionText (the
                // "نص إضافي" field from S109) was only ever drawn by the
                // export renderer (OverlayRenderer.renderTextOverlayPng) --
                // never shown here, so it looked like the feature did
                // nothing while editing. Mirrors that same styling.
                if (state.captionText.trim().isNotEmpty)
                  PositionedDirectional(
                    top: state.captionPosition == CaptionPosition.top
                        ? 14
                        : null,
                    bottom: state.captionPosition == CaptionPosition.top
                        ? null
                        : 14,
                    start: 12,
                    end: 12,
                    child: IgnorePointer(
                      child: Text(
                        state.captionText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13 * scale.clamp(0.8, 1.6),
                          color: AyatColors.goldBright,
                          shadows: const [
                            Shadow(
                                color: Color(0xB3000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
                  ),
                // PATCH_S34_PLAYER_CONTROLS_TRIM: brief ▶/⏸ feedback after a tap."""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    target = root / "lib/widgets/stage_preview.dart"
    if not target.exists():
        raise SystemExit(f"ERROR: expected file not found: {target}")

    print(f"Applying {MARKER}...")
    replace_once(target, _OLD, _NEW, "draw caption live in the stage preview")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
