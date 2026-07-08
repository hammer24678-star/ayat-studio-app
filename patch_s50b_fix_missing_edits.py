#!/usr/bin/env python3
"""
patch_s50b_fix_missing_edits.py

Hotfix for a bug in patch_s50_model_cards_draggable_text.py: that script
checked "has this file already been touched by S50?" using one shared
marker string per file, but several files got *multiple* separate S50
edits. The first edit to land wrote the marker as a comment, and every
subsequent edit to that same file then saw the marker and skipped
itself -- even though it had never actually been applied.

Result after running S50 once: studio_state.dart, the accuracy-card UI,
and the restore() half of settings persistence all landed correctly,
but these did NOT:
  - the GestureDetector/Transform.translate wrapper on the stage overlay
    in home_screen.dart (so nothing is actually draggable yet)
  - textUserScale being multiplied into font sizes, in both the live
    preview (home_screen.dart) and the export renderer
    (overlay_renderer.dart)
  - offset/userScale actually being passed into OverlayStyle at the
    (only) construction call site in home_screen.dart
  - persist() writing textOffset/textUserScale to SharedPreferences
    (restore() was patched, but nothing was ever being saved to restore)

This script applies exactly those 8 missing edits. Each is checked
independently (by whether ITS OWN new text is already present, not a
shared file marker), so it's safe to run regardless of exactly which
subset of S50 already landed, and safe to re-run.

Usage:
  python3 patch_s50b_fix_missing_edits.py /path/to/ayat_studio_app
"""

import sys
import pathlib

TAG = "PATCH_S50_DRAGGABLE_TEXT"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def apply_edit(project_dir, rel_path, old, new, label):
    target = project_dir / rel_path
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()

    if text.count(new) >= 1:
        return "already applied"

    count = text.count(old)
    if count == 0:
        die(
            f"[{label}] anchor not found in {rel_path} and the patched text "
            "isn't there either -- file may have changed since this hotfix "
            "was written. No changes made to this file."
        )
    if count > 1:
        die(
            f"[{label}] anchor in {rel_path} is not unique ({count} matches) "
            "-- refusing to guess, no changes made."
        )

    target.write_text(text.replace(old, new, 1))
    return "applied"


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    results = {}

    # 1. settings_service.dart -- persist() (restore() already landed)
    results["settings_service.dart (persist)"] = apply_edit(
        project_dir, "lib/services/settings_service.dart",
        "      p.setDouble('${_prefix}letterSpacing', state.letterSpacing),\n"
        "      p.setDouble('${_prefix}lineHeightMultiplier', state.lineHeightMultiplier),\n",

        "      p.setDouble('${_prefix}letterSpacing', state.letterSpacing),\n"
        "      p.setDouble('${_prefix}lineHeightMultiplier', state.lineHeightMultiplier),\n"
        f"      // {TAG}\n"
        "      p.setDouble('${_prefix}textOffsetDx', state.textOffset.dx),\n"
        "      p.setDouble('${_prefix}textOffsetDy', state.textOffset.dy),\n"
        "      p.setDouble('${_prefix}textUserScale', state.textUserScale),\n",
        "settings persist",
    )

    # 2. home_screen.dart -- ayahFontSize now includes textUserScale
    results["home_screen.dart (ayah font scale)"] = apply_edit(
        project_dir, "lib/screens/home_screen.dart",
        "    final ayahFontSize =\n"
        "        state.ayahFontSize * scale * ayahAutoFontScale(text); // PATCH_S24_AUTO_SHRINK_LONG_AYAH\n",

        "    final ayahFontSize = state.ayahFontSize *\n"
        "        scale *\n"
        "        ayahAutoFontScale(text) *\n"
        f"        state.textUserScale; // PATCH_S24_AUTO_SHRINK_LONG_AYAH, {TAG}\n",
        "live preview ayah font scale",
    )

    # 3. home_screen.dart -- the actual GestureDetector wrapper
    results["home_screen.dart (overlay gesture)"] = apply_edit(
        project_dir, "lib/screens/home_screen.dart",
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
        "live preview gesture wrapper",
    )

    # 4. home_screen.dart -- pass offset/userScale at the OverlayStyle construction site
    results["home_screen.dart (OverlayStyle construction)"] = apply_edit(
        project_dir, "lib/screens/home_screen.dart",
        "        letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES\n"
        "        lineHeightMultiplier: state.lineHeightMultiplier,\n"
        "      );\n",

        "        letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES\n"
        "        lineHeightMultiplier: state.lineHeightMultiplier,\n"
        f"        offset: state.textOffset, // {TAG}\n"
        "        userScale: state.textUserScale,\n"
        "      );\n",
        "OverlayStyle construction call",
    )

    # 5. overlay_renderer.dart -- ayah font scale
    results["overlay_renderer.dart (ayah font scale)"] = apply_edit(
        project_dir, "lib/services/overlay_renderer.dart",
        "      final ayahFontSize =\n"
        "          style.ayahFontSize * scale * ayahAutoFontScale(text); // PATCH_S24_AUTO_SHRINK_LONG_AYAH\n",

        "      final ayahFontSize = style.ayahFontSize *\n"
        "          scale *\n"
        "          ayahAutoFontScale(text) *\n"
        f"          style.userScale; // PATCH_S24_AUTO_SHRINK_LONG_AYAH, {TAG}\n",
        "export ayah font scale",
    )

    # 6. overlay_renderer.dart -- translation font scale
    results["overlay_renderer.dart (trans font scale)"] = apply_edit(
        project_dir, "lib/services/overlay_renderer.dart",
        "          text: TextSpan(\n"
        "            text: translation,\n"
        "            style: translationTextStyle(\n"
        "              fontSize: style.transFontSize * scale,\n",

        "          text: TextSpan(\n"
        "            text: translation,\n"
        "            style: translationTextStyle(\n"
        f"              fontSize: style.transFontSize * scale * style.userScale, // {TAG}\n",
        "export translation font scale",
    )

    # 7. overlay_renderer.dart -- position offset (centerY/top/dx + decoration rect)
    results["overlay_renderer.dart (position offset)"] = apply_edit(
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
        "export decoration rect offset",
    )

    # 8. overlay_renderer.dart -- paint offset (needs edit 7 applied first, for `dx`)
    results["overlay_renderer.dart (paint offset)"] = apply_edit(
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
        "export paint offset",
    )

    print("S50b hotfix results:")
    for name, status in results.items():
        print(f"  - {name}: {status}")

    if all(v == "already applied" for v in results.values()):
        print("\nNothing to do -- all 8 edits were already present.")
    else:
        print("\nDone. Run `flutter analyze`, then rebuild and test dragging/pinching the ayah text.")


if __name__ == "__main__":
    main()
