#!/usr/bin/env python3
"""
patch_s50c_fix_missing_edits_v2.py

S50b (the first hotfix attempt) died on its very first edit:
"[live preview ayah font scale] anchor not found in home_screen.dart
and the patched text isn't there either." Two compounding problems:

1. S50b's apply_edit() calls sys.exit() on the FIRST anchor mismatch,
   so a single whitespace/wrapping difference kills the whole hotfix
   before it even attempts the other 7 edits -- we have no idea which
   of those would have worked.
2. Several of S50b's anchors (the two `ayahFontSize = ... *
   ayahAutoFontScale(text);` lines, in home_screen.dart and
   overlay_renderer.dart) are matched as an exact literal string
   including exact line-wrapping. If dart format (or any manual edit)
   reflowed those lines even slightly, the literal match fails even
   though the semantic target is sitting right there.

This version:
  - NEVER aborts early. Every one of the 8 edits is attempted
    independently; a failure on one is reported and we move on to the
    rest, so you get a complete picture in one run instead of one
    error at a time.
  - The two `ayahFontSize` scale edits use a REGEX anchored on the
    stable substrings (`ayahFontSize`, `ayahAutoFontScale(text)`,
    `PATCH_S24_AUTO_SHRINK_LONG_AYAH`) rather than exact whitespace,
    so line-wrap differences don't matter.
  - Everything else is unchanged from S50b (same 6 literal edits),
    just no longer able to take down the whole run.
  - Every edit checks for its OWN completed state first (not a shared
    file marker), so this is safe to re-run after a partial success.

Usage:
  python3 patch_s50c_fix_missing_edits_v2.py /path/to/ayat_studio_app
"""

import re
import sys
import pathlib

TAG = "PATCH_S50_DRAGGABLE_TEXT"


def apply_literal(project_dir, rel_path, old, new, label, results):
    target = project_dir / rel_path
    if not target.exists():
        results[label] = f"ERROR: {target} not found"
        return
    text = target.read_text()
    if text.count(new) >= 1:
        results[label] = "already applied"
        return
    count = text.count(old)
    if count == 0:
        results[label] = "MISSING: anchor not found, and patched text isn't there either -- needs a manual look"
        return
    if count > 1:
        results[label] = f"MISSING: anchor not unique ({count} matches) -- refusing to guess"
        return
    target.write_text(text.replace(old, new, 1))
    results[label] = "applied"


def apply_ayah_scale_regex(project_dir, rel_path, var_prefix, label, results):
    """
    var_prefix is 'state' (home_screen.dart) or 'style' (overlay_renderer.dart).
    Matches the ayahFontSize assignment regardless of exact line-wrapping,
    and inserts `* {var_prefix}.{scale_field}` right before the semicolon
    if it isn't already there.
    """
    scale_field = "textUserScale" if var_prefix == "state" else "userScale"
    target = project_dir / rel_path
    if not target.exists():
        results[label] = f"ERROR: {target} not found"
        return
    text = target.read_text()

    pattern = re.compile(
        r"final ayahFontSize\s*=\s*"
        r"(?P<expr>" + re.escape(var_prefix) + r"\.ayahFontSize\s*\*\s*scale\s*\*\s*"
        r"ayahAutoFontScale\(text\)"
        r"(?P<already>\s*\*\s*" + re.escape(var_prefix) + r"\." + re.escape(scale_field) + r")?"
        r")\s*;"
        r"(?P<comment>[^\n]*PATCH_S24_AUTO_SHRINK_LONG_AYAH[^\n]*)?",
    )
    matches = list(pattern.finditer(text))
    if not matches:
        results[label] = "MISSING: regex didn't match this file at all -- needs a manual look"
        return
    if len(matches) > 1:
        results[label] = f"MISSING: regex matched {len(matches)} times -- refusing to guess"
        return

    m = matches[0]
    if m.group("already"):
        results[label] = "already applied"
        return

    comment = m.group("comment") or ""
    # Strip a bare trailing PATCH_S24 comment so we can re-append it with our tag added.
    if "PATCH_S24_AUTO_SHRINK_LONG_AYAH" in comment:
        new_comment = comment.rstrip() + f", {TAG}"
    else:
        new_comment = comment + f"  // {TAG}"

    replacement = (
        f"final ayahFontSize = {var_prefix}.ayahFontSize * scale * "
        f"ayahAutoFontScale(text) * {var_prefix}.{scale_field};{new_comment}"
    )
    new_text = text[: m.start()] + replacement + text[m.end():]
    target.write_text(new_text)
    results[label] = "applied"


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    results = {}

    # 1. settings_service.dart -- persist()
    apply_literal(
        project_dir, "lib/services/settings_service.dart",
        "      p.setDouble('${_prefix}letterSpacing', state.letterSpacing),\n"
        "      p.setDouble('${_prefix}lineHeightMultiplier', state.lineHeightMultiplier),\n",
        "      p.setDouble('${_prefix}letterSpacing', state.letterSpacing),\n"
        "      p.setDouble('${_prefix}lineHeightMultiplier', state.lineHeightMultiplier),\n"
        f"      // {TAG}\n"
        "      p.setDouble('${_prefix}textOffsetDx', state.textOffset.dx),\n"
        "      p.setDouble('${_prefix}textOffsetDy', state.textOffset.dy),\n"
        "      p.setDouble('${_prefix}textUserScale', state.textUserScale),\n",
        "settings_service.dart (persist)", results,
    )

    # 2. stage_preview.dart -- live preview ayah font scale (regex, tolerant of wrapping)
    # NOTE: this logic lives in lib/widgets/stage_preview.dart, not
    # home_screen.dart -- the overlay-building code was extracted into its
    # own widget at some point and S50/S50b were written against the old
    # location, which is the actual root cause of the original failure.
    apply_ayah_scale_regex(
        project_dir, "lib/widgets/stage_preview.dart", "state",
        "stage_preview.dart (ayah font scale)", results,
    )

    # 3. stage_preview.dart -- the GestureDetector/Transform.translate wrapper
    apply_literal(
        project_dir, "lib/widgets/stage_preview.dart",
        "    return Align(\n"
        "      alignment: Alignment(0, alignY),\n"
        "      child: Container(\n"
        "        margin: EdgeInsets.symmetric(horizontal: 0.07 * 270 * scale / 2),\n"
        "        padding: deco != null\n"
        "            ? EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale)\n"
        "            : EdgeInsets.zero,\n"
        "        decoration: deco,\n"
        "        child: Column(\n"
        "          mainAxisSize: MainAxisSize.min,\n"
        "          children: [\n"
        "            ayahWidget,\n"
        "            if (state.showTranslation && trans.isNotEmpty) ...[\n"
        "              SizedBox(height: 4 * scale),\n"
        "              Text(\n"
        "                trans,\n"
        "                textAlign: TextAlign.center,\n"
        "                style: translationTextStyle(\n"
        "                  fontSize: state.transFontSize * scale,\n"
        "                  color: state.textColor.withValues(alpha: 0.88),\n"
        "                  shadows: shadows,\n"
        "                ),\n"
        "              ),\n"
        "            ],\n"
        "          ],\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n"
        "}\n",

        f"    // {TAG}: one GestureDetector handles both drag-to-reposition\n"
        "    // (one finger) and pinch-to-resize (two fingers) -- onScaleUpdate\n"
        "    // fires for single-finger pans too, so a separate onPanUpdate would\n"
        "    // only fight it. gestureStartUserScale is a plain local, not a\n"
        "    // field: ScaleUpdateDetails.scale is cumulative from onScaleStart,\n"
        "    // so each gesture needs its own starting snapshot, and a fresh\n"
        "    // closure over a local is enough since _overlay reruns every build.\n"
        "    double gestureStartUserScale = state.textUserScale;\n"
        "    return GestureDetector(\n"
        "      onScaleStart: (_) => gestureStartUserScale = state.textUserScale,\n"
        "      onScaleUpdate: (details) {\n"
        "        state.update(() {\n"
        "          state.textOffset += details.focalPointDelta / scale;\n"
        "          state.textUserScale =\n"
        "              (gestureStartUserScale * details.scale).clamp(0.6, 1.8);\n"
        "        });\n"
        "      },\n"
        "      onDoubleTap: () => state.update(() {\n"
        "        state.textOffset = Offset.zero;\n"
        "        state.textUserScale = 1.0;\n"
        "      }),\n"
        "      child: Transform.translate(\n"
        "        offset: Offset(\n"
        "            state.textOffset.dx * scale, state.textOffset.dy * scale),\n"
        "        child: Align(\n"
        "          alignment: Alignment(0, alignY),\n"
        "          child: Container(\n"
        "            margin: EdgeInsets.symmetric(horizontal: 0.07 * 270 * scale / 2),\n"
        "            padding: deco != null\n"
        "                ? EdgeInsets.symmetric(\n"
        "                    horizontal: 14 * scale, vertical: 10 * scale)\n"
        "                : EdgeInsets.zero,\n"
        "            decoration: deco,\n"
        "            child: Column(\n"
        "              mainAxisSize: MainAxisSize.min,\n"
        "              children: [\n"
        "                ayahWidget,\n"
        "                if (state.showTranslation && trans.isNotEmpty) ...[\n"
        "                  SizedBox(height: 4 * scale),\n"
        "                  Text(\n"
        "                    trans,\n"
        "                    textAlign: TextAlign.center,\n"
        "                    style: translationTextStyle(\n"
        "                      fontSize:\n"
        "                          state.transFontSize * scale * state.textUserScale,\n"
        "                      color: state.textColor.withValues(alpha: 0.88),\n"
        "                      shadows: shadows,\n"
        "                    ),\n"
        "                  ),\n"
        "                ],\n"
        "              ],\n"
        "            ),\n"
        "          ),\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n"
        "}\n",
        "stage_preview.dart (overlay gesture)", results,
    )

    # 4. export_service.dart -- OverlayStyle construction call site
    # NOTE: this is where OverlayStyle is actually built for the export
    # renderer -- not home_screen.dart.
    apply_literal(
        project_dir, "lib/services/export_service.dart",
        "        letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES\n"
        "        lineHeightMultiplier: state.lineHeightMultiplier,\n"
        "      );\n",
        "        letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES\n"
        "        lineHeightMultiplier: state.lineHeightMultiplier,\n"
        f"        offset: state.textOffset, // {TAG}\n"
        "        userScale: state.textUserScale,\n"
        "      );\n",
        "export_service.dart (OverlayStyle construction)", results,
    )

    # 5. overlay_renderer.dart -- export ayah font scale (regex, tolerant of wrapping)
    apply_ayah_scale_regex(
        project_dir, "lib/services/overlay_renderer.dart", "style",
        "overlay_renderer.dart (ayah font scale)", results,
    )

    # 6. overlay_renderer.dart -- translation font scale
    apply_literal(
        project_dir, "lib/services/overlay_renderer.dart",
        "          text: TextSpan(\n"
        "            text: translation,\n"
        "            style: translationTextStyle(\n"
        "              fontSize: style.transFontSize * scale,\n",
        "          text: TextSpan(\n"
        "            text: translation,\n"
        "            style: translationTextStyle(\n"
        f"              fontSize: style.transFontSize * scale * style.userScale, // {TAG}\n",
        "overlay_renderer.dart (trans font scale)", results,
    )

    # 7. overlay_renderer.dart -- position offset
    apply_literal(
        project_dir, "lib/services/overlay_renderer.dart",
        "      final totalH =\n"
        "          ayahPainter.height + gap + (transPainter?.height ?? 0);\n"
        "      final centerY = switch (style.position) {\n"
        "        AyahTextPosition.top => h * 0.16,\n"
        "        AyahTextPosition.center => h * 0.5,\n"
        "        AyahTextPosition.bottom => h * 0.78,\n"
        "      };\n"
        "      final top = centerY - totalH / 2;\n"
        "\n"
        "      if (style.extra != FrameExtra.none) {\n"
        "        final padX = 24 * scale, padY = 18 * scale;\n"
        "        final rect = Rect.fromLTWH(\n"
        "            w * 0.07 - padX * 0.2, top - padY,\n"
        "            w * 0.86 + padX * 0.4, totalH + padY * 2);\n",
        "      final totalH =\n"
        "          ayahPainter.height + gap + (transPainter?.height ?? 0);\n"
        "      final centerY = switch (style.position) {\n"
        "            AyahTextPosition.top => h * 0.16,\n"
        "            AyahTextPosition.center => h * 0.5,\n"
        "            AyahTextPosition.bottom => h * 0.78,\n"
        "          } +\n"
        f"          style.offset.dy * scale; // {TAG}\n"
        "      final top = centerY - totalH / 2;\n"
        f"      final dx = style.offset.dx * scale; // {TAG}\n"
        "\n"
        "      if (style.extra != FrameExtra.none) {\n"
        "        final padX = 24 * scale, padY = 18 * scale;\n"
        "        final rect = Rect.fromLTWH(\n"
        "            w * 0.07 - padX * 0.2 + dx, top - padY,\n"
        "            w * 0.86 + padX * 0.4, totalH + padY * 2);\n",
        "overlay_renderer.dart (position offset)", results,
    )

    # 8. overlay_renderer.dart -- paint offset (needs edit 7 for `dx`)
    apply_literal(
        project_dir, "lib/services/overlay_renderer.dart",
        "      ayahPainter.paint(canvas, Offset((w - ayahPainter.width) / 2, top));\n"
        "      transPainter?.paint(\n"
        "          canvas,\n"
        "          Offset((w - transPainter.width) / 2,\n"
        "              top + ayahPainter.height + gap));\n",
        "      ayahPainter.paint(\n"
        f"          canvas, Offset((w - ayahPainter.width) / 2 + dx, top)); // {TAG}\n"
        "      transPainter?.paint(\n"
        "          canvas,\n"
        "          Offset((w - transPainter.width) / 2 + dx,\n"
        "              top + ayahPainter.height + gap));\n",
        "overlay_renderer.dart (paint offset)", results,
    )

    print("S50c hotfix results:")
    ok, missing, errors = 0, 0, 0
    for label, status in results.items():
        print(f"  - {label}: {status}")
        if status == "applied" or status == "already applied":
            ok += 1
        elif status.startswith("MISSING"):
            missing += 1
        else:
            errors += 1

    print(f"\nOK/already-applied: {ok}   Needs manual look: {missing}   Errors: {errors}")
    if missing or errors:
        print(
            "\nFor any 'MISSING' line above, paste back the actual current content "
            "around that spot (e.g. `grep -n -B2 -A2 'ayahFontSize' lib/screens/home_screen.dart` "
            "or the equivalent file/area) and I'll write an exact-match patch for it."
        )
    else:
        print("\nAll 8 edits landed. Run `flutter analyze`, then rebuild and test dragging/pinching the ayah text.")


if __name__ == "__main__":
    main()
