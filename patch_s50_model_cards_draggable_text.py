#!/usr/bin/env python3
"""
patch_s50_model_cards_draggable_text.py

Two UI fixes requested together:

1. STT accuracy picker redesign -- the squeezed four-way ChoiceChip Wrap
   under "دقة التعرّف على الكلام" is replaced with a vertical list of
   full-width cards (one per WhisperModelSize tier). Each card shows the
   size and quality tradeoff as title/subtitle instead of one cramped
   chip label, with a clear gold-border + check selected state instead
   of chip-fill (which read as low-contrast on the dark theme). No
   change to WhisperService / _modelSpecs -- this only reformats the
   existing labelFor() string (split on " -- ") into two lines.

2. Draggable + pinch-resizable ayah text overlay -- the ayah/translation
   text block on the stage preview can now be dragged (pan) to
   reposition and pinched to resize, on top of the existing
   top/center/bottom preset + font-size sliders (which still work as
   the base anchor / fine-tune controls). A double-tap on the text
   resets both. The same offset + scale are threaded through to the
   export renderer (OverlayRenderer/OverlayStyle) so the exported video
   matches what was seen in the live preview -- this was the main risk
   here, since preview and export are two separate rendering paths.

Changes:
  1. lib/models/studio_state.dart -- textOffset, textUserScale fields
  2. lib/services/settings_service.dart -- persist/restore for both
  3. lib/screens/home_screen.dart -- accuracy cards, GestureDetector on
     the stage overlay, reset-position hint button
  4. lib/services/overlay_renderer.dart -- OverlayStyle.offset/userScale
     + applied in renderTextOverlayPng() so export matches preview

Usage:
  python3 patch_s50_model_cards_draggable_text.py /path/to/ayat_studio_app
"""

import sys
import pathlib

MARKER = "PATCH_S50_DRAGGABLE_TEXT"
MARKER_CARDS = "PATCH_S50_MODEL_SIZE_CARDS"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S50 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_file(project_dir, rel_path, edits, marker):
    target = project_dir / rel_path
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if marker in text:
        return False
    for old, new, label in edits:
        text = replace_once(text, old, new, label)
    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    results = {}

    # 1. StudioState -- new fields
    results["lib/models/studio_state.dart"] = patch_file(
        project_dir, "lib/models/studio_state.dart",
        [(
            "  // PATCH_S48_TEXT_SPACING_TOGGLES\n"
            "  double letterSpacing = 0; // -1..3\n"
            "  double lineHeightMultiplier = 1.5; // 1.2..2.2, previous hardcoded value\n",

            "  // PATCH_S48_TEXT_SPACING_TOGGLES\n"
            "  double letterSpacing = 0; // -1..3\n"
            "  double lineHeightMultiplier = 1.5; // 1.2..2.2, previous hardcoded value\n"
            "\n"
            f"  // {MARKER}: user drag/pinch on the stage preview, on top of the\n"
            "  // textPosition preset + ayahFontSize/transFontSize sliders above.\n"
            "  // textOffset is stored in 270-wide reference units (same convention\n"
            "  // as ayahFontSize etc.) so preview and export can both multiply it\n"
            "  // by their own `scale = width / 270.0` and land on the same spot.\n"
            "  Offset textOffset = Offset.zero;\n"
            "  double textUserScale = 1.0; // 0.6..1.8, pinch-to-resize multiplier\n",
            "studio_state fields",
        )],
        MARKER,
    )

    # 2. settings_service.dart -- restore()
    results["lib/services/settings_service.dart (restore)"] = patch_file(
        project_dir, "lib/services/settings_service.dart",
        [(
            "      state.letterSpacing =\n"
            "          (read<double>('letterSpacing') ?? state.letterSpacing).clamp(-1.0, 3.0);\n"
            "      state.lineHeightMultiplier =\n"
            "          (read<double>('lineHeightMultiplier') ?? state.lineHeightMultiplier)\n"
            "              .clamp(1.2, 2.2);\n",

            "      state.letterSpacing =\n"
            "          (read<double>('letterSpacing') ?? state.letterSpacing).clamp(-1.0, 3.0);\n"
            "      state.lineHeightMultiplier =\n"
            "          (read<double>('lineHeightMultiplier') ?? state.lineHeightMultiplier)\n"
            "              .clamp(1.2, 2.2);\n"
            f"      // {MARKER}\n"
            "      state.textOffset = Offset(\n"
            "        read<double>('textOffsetDx') ?? state.textOffset.dx,\n"
            "        read<double>('textOffsetDy') ?? state.textOffset.dy,\n"
            "      );\n"
            "      state.textUserScale =\n"
            "          (read<double>('textUserScale') ?? state.textUserScale).clamp(0.6, 1.8);\n",
            "settings restore",
        )],
        MARKER,
    )

    # 3. settings_service.dart -- persist()
    results["lib/services/settings_service.dart (persist)"] = patch_file(
        project_dir, "lib/services/settings_service.dart",
        [(
            "      p.setDouble('${_prefix}letterSpacing', state.letterSpacing),\n"
            "      p.setDouble('${_prefix}lineHeightMultiplier', state.lineHeightMultiplier),\n",

            "      p.setDouble('${_prefix}letterSpacing', state.letterSpacing),\n"
            "      p.setDouble('${_prefix}lineHeightMultiplier', state.lineHeightMultiplier),\n"
            f"      // {MARKER}\n"
            "      p.setDouble('${_prefix}textOffsetDx', state.textOffset.dx),\n"
            "      p.setDouble('${_prefix}textOffsetDy', state.textOffset.dy),\n"
            "      p.setDouble('${_prefix}textUserScale', state.textUserScale),\n",
            "settings persist",
        )],
        MARKER,
    )

    # 4. home_screen.dart -- STT accuracy card redesign
    results["lib/screens/home_screen.dart (accuracy cards)"] = patch_file(
        project_dir, "lib/screens/home_screen.dart",
        [(
            "        _fieldLabel('دقة التعرّف على الكلام'),\n"
            "        Wrap(\n"
            "          spacing: 6,\n"
            "          runSpacing: 6,\n"
            "          children: [\n"
            "            for (final size in WhisperModelSize.values)\n"
            "              ChoiceChip(\n"
            "                label: Text(WhisperService.labelFor(size)),\n"
            "                selected: state.whisperModelSize == size,\n"
            "                onSelected: _busy\n"
            "                    ? null\n"
            "                    : (_) {\n"
            "                        state.update(() => state.whisperModelSize = size);\n"
            "                        WhisperService.setModelSize(size);\n"
            "                      },\n"
            "              ),\n"
            "          ],\n"
            "        ),\n"
            "        const SizedBox(height: 8),\n",

            f"        // {MARKER_CARDS}: one full-width card per tier instead of four\n"
            "        // squeezed ChoiceChips -- clearer size/quality tradeoff, bigger tap\n"
            "        // targets, unambiguous selected state. Still drives the same\n"
            "        // WhisperService.setModelSize() as before.\n"
            "        _fieldLabel('دقة التعرّف على الكلام'),\n"
            "        for (final size in WhisperModelSize.values)\n"
            "          Builder(builder: (context) {\n"
            "            final selected = state.whisperModelSize == size;\n"
            "            final parts = WhisperService.labelFor(size).split(' — ');\n"
            "            final sizeLabel = parts.first;\n"
            "            final qualityLabel = parts.length > 1 ? parts[1] : '';\n"
            "            return Padding(\n"
            "              padding: const EdgeInsets.only(bottom: 8),\n"
            "              child: Material(\n"
            "                color: selected\n"
            "                    ? AyatColors.gold.withValues(alpha: 0.12)\n"
            "                    : AyatColors.ink.withValues(alpha: 0.4),\n"
            "                borderRadius: BorderRadius.circular(10),\n"
            "                child: InkWell(\n"
            "                  borderRadius: BorderRadius.circular(10),\n"
            "                  onTap: _busy\n"
            "                      ? null\n"
            "                      : () {\n"
            "                          state.update(() => state.whisperModelSize = size);\n"
            "                          WhisperService.setModelSize(size);\n"
            "                        },\n"
            "                  child: Container(\n"
            "                    padding: const EdgeInsets.symmetric(\n"
            "                        horizontal: 14, vertical: 12),\n"
            "                    decoration: BoxDecoration(\n"
            "                      borderRadius: BorderRadius.circular(10),\n"
            "                      border: Border.all(\n"
            "                        color:\n"
            "                            selected ? AyatColors.gold : AyatColors.hairline,\n"
            "                        width: selected ? 1.4 : 1,\n"
            "                      ),\n"
            "                    ),\n"
            "                    child: Row(\n"
            "                      children: [\n"
            "                        Expanded(\n"
            "                          child: Column(\n"
            "                            crossAxisAlignment: CrossAxisAlignment.start,\n"
            "                            children: [\n"
            "                              Text(\n"
            "                                sizeLabel,\n"
            "                                style: TextStyle(\n"
            "                                  fontWeight: selected\n"
            "                                      ? FontWeight.bold\n"
            "                                      : FontWeight.w500,\n"
            "                                  color: selected\n"
            "                                      ? AyatColors.goldBright\n"
            "                                      : Colors.white,\n"
            "                                ),\n"
            "                              ),\n"
            "                              if (qualityLabel.isNotEmpty) ...[\n"
            "                                const SizedBox(height: 2),\n"
            "                                Text(\n"
            "                                  qualityLabel,\n"
            "                                  style: TextStyle(\n"
            "                                    fontSize: 12,\n"
            "                                    color: Colors.white.withValues(alpha: 0.6),\n"
            "                                  ),\n"
            "                                ),\n"
            "                              ],\n"
            "                            ],\n"
            "                          ),\n"
            "                        ),\n"
            "                        if (selected)\n"
            "                          const Icon(Icons.check_circle,\n"
            "                              color: AyatColors.goldBright, size: 20)\n"
            "                        else\n"
            "                          Icon(Icons.circle_outlined,\n"
            "                              color: Colors.white.withValues(alpha: 0.3),\n"
            "                              size: 20),\n"
            "                      ],\n"
            "                    ),\n"
            "                  ),\n"
            "                ),\n"
            "              ),\n"
            "            );\n"
            "          }),\n"
            "        const SizedBox(height: 8),\n",
            "accuracy picker cards",
        )],
        MARKER_CARDS,
    )

    # 5. home_screen.dart -- reset-position hint button after the font-size sliders
    results["lib/screens/home_screen.dart (reset hint)"] = patch_file(
        project_dir, "lib/screens/home_screen.dart",
        [(
            "        _fieldLabel('حجم خط ترجمة المعاني'),\n"
            "        Slider(\n"
            "          value: state.transFontSize,\n"
            "          min: 9,\n"
            "          max: 18,\n"
            "          onChanged: (v) => state.update(() => state.transFontSize = v),\n"
            "        ),\n",

            "        _fieldLabel('حجم خط ترجمة المعاني'),\n"
            "        Slider(\n"
            "          value: state.transFontSize,\n"
            "          min: 9,\n"
            "          max: 18,\n"
            "          onChanged: (v) => state.update(() => state.transFontSize = v),\n"
            "        ),\n"
            f"        // {MARKER}: sliders above stay as the fine-tune/reset-to-default\n"
            "        // controls; drag the ayah text directly on the preview above to\n"
            "        // reposition, pinch it to resize, or double-tap it to snap back.\n"
            "        if (state.textOffset != Offset.zero || state.textUserScale != 1.0)\n"
            "          Padding(\n"
            "            padding: const EdgeInsets.only(bottom: 8),\n"
            "            child: OutlinedButton.icon(\n"
            "              onPressed: () => state.update(() {\n"
            "                state.textOffset = Offset.zero;\n"
            "                state.textUserScale = 1.0;\n"
            "              }),\n"
            "              icon: const Icon(Icons.restart_alt, size: 16),\n"
            "              label: const Text('إعادة موضع/حجم النص للوضع الافتراضي'),\n"
            "            ),\n"
            "          ),\n",
            "reset position button",
        )],
        MARKER,
    )

    # 6. home_screen.dart -- ayahFontSize now includes textUserScale
    results["lib/screens/home_screen.dart (ayah font scale)"] = patch_file(
        project_dir, "lib/screens/home_screen.dart",
        [(
            "    final ayahFontSize =\n"
            "        state.ayahFontSize * scale * ayahAutoFontScale(text); // PATCH_S24_AUTO_SHRINK_LONG_AYAH\n",

            "    final ayahFontSize = state.ayahFontSize *\n"
            "        scale *\n"
            "        ayahAutoFontScale(text) *\n"
            f"        state.textUserScale; // PATCH_S24_AUTO_SHRINK_LONG_AYAH, {MARKER}\n",
            "live preview ayah font scale",
        )],
        MARKER,
    )

    # 7. home_screen.dart -- wrap the stage overlay in a drag/pinch GestureDetector
    results["lib/screens/home_screen.dart (overlay gesture)"] = patch_file(
        project_dir, "lib/screens/home_screen.dart",
        [(
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

            f"    // {MARKER}: one GestureDetector handles both drag-to-reposition\n"
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
        )],
        MARKER,
    )

    # 8. overlay_renderer.dart -- OverlayStyle gets offset/userScale
    results["lib/services/overlay_renderer.dart (style fields)"] = patch_file(
        project_dir, "lib/services/overlay_renderer.dart",
        [(
            "  final double letterSpacing; // PATCH_S48_TEXT_SPACING_TOGGLES\n"
            "  final double lineHeightMultiplier;\n"
            "  const OverlayStyle({\n"
            "    required this.fontKey,\n"
            "    required this.ayahFontSize,\n"
            "    required this.transFontSize,\n"
            "    required this.color,\n"
            "    required this.position,\n"
            "    required this.extra,\n"
            "    required this.showTranslation,\n"
            "    this.glowEnabled = true,\n"
            "    this.glowIntensity = 1.0,\n"
            "    this.letterSpacing = 0,\n"
            "    this.lineHeightMultiplier = 1.5,\n"
            "  });\n"
            "}\n",

            "  final double letterSpacing; // PATCH_S48_TEXT_SPACING_TOGGLES\n"
            "  final double lineHeightMultiplier;\n"
            f"  final Offset offset; // {MARKER}: matches StudioState.textOffset\n"
            "  final double userScale; // matches StudioState.textUserScale\n"
            "  const OverlayStyle({\n"
            "    required this.fontKey,\n"
            "    required this.ayahFontSize,\n"
            "    required this.transFontSize,\n"
            "    required this.color,\n"
            "    required this.position,\n"
            "    required this.extra,\n"
            "    required this.showTranslation,\n"
            "    this.glowEnabled = true,\n"
            "    this.glowIntensity = 1.0,\n"
            "    this.letterSpacing = 0,\n"
            "    this.lineHeightMultiplier = 1.5,\n"
            "    this.offset = Offset.zero,\n"
            "    this.userScale = 1.0,\n"
            "  });\n"
            "}\n",
            "OverlayStyle fields",
        )],
        MARKER,
    )

    # 9. overlay_renderer.dart -- apply userScale to font sizes
    results["lib/services/overlay_renderer.dart (ayah font scale)"] = patch_file(
        project_dir, "lib/services/overlay_renderer.dart",
        [(
            "      final ayahFontSize =\n"
            "          style.ayahFontSize * scale * ayahAutoFontScale(text); // PATCH_S24_AUTO_SHRINK_LONG_AYAH\n",

            "      final ayahFontSize = style.ayahFontSize *\n"
            "          scale *\n"
            "          ayahAutoFontScale(text) *\n"
            f"          style.userScale; // PATCH_S24_AUTO_SHRINK_LONG_AYAH, {MARKER}\n",
            "export ayah font scale",
        )],
        MARKER,
    )

    results["lib/services/overlay_renderer.dart (trans font scale)"] = patch_file(
        project_dir, "lib/services/overlay_renderer.dart",
        [(
            "          text: TextSpan(\n"
            "            text: translation,\n"
            "            style: translationTextStyle(\n"
            "              fontSize: style.transFontSize * scale,\n",

            "          text: TextSpan(\n"
            "            text: translation,\n"
            "            style: translationTextStyle(\n"
            f"              fontSize: style.transFontSize * scale * style.userScale, // {MARKER}\n",
            "export translation font scale",
        )],
        MARKER,
    )

    # 10. overlay_renderer.dart -- apply offset to centerY/top and paint X
    results["lib/services/overlay_renderer.dart (position offset)"] = patch_file(
        project_dir, "lib/services/overlay_renderer.dart",
        [(
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
            f"          style.offset.dy * scale; // {MARKER}\n"
            "      final top = centerY - totalH / 2;\n"
            f"      final dx = style.offset.dx * scale; // {MARKER}\n"
            "\n"
            "      if (style.extra != FrameExtra.none) {\n"
            "        final padX = 24 * scale, padY = 18 * scale;\n"
            "        final rect = Rect.fromLTWH(\n"
            "            w * 0.07 - padX * 0.2 + dx, top - padY,\n"
            "            w * 0.86 + padX * 0.4, totalH + padY * 2);\n",
            "export decoration rect offset",
        )],
        MARKER,
    )

    results["lib/services/overlay_renderer.dart (paint offset)"] = patch_file(
        project_dir, "lib/services/overlay_renderer.dart",
        [(
            "      ayahPainter.paint(canvas, Offset((w - ayahPainter.width) / 2, top));\n"
            "      transPainter?.paint(\n"
            "          canvas,\n"
            "          Offset((w - transPainter.width) / 2,\n"
            "              top + ayahPainter.height + gap));\n",

            "      ayahPainter.paint(\n"
            f"          canvas, Offset((w - ayahPainter.width) / 2 + dx, top)); // {MARKER}\n"
            "      transPainter?.paint(\n"
            "          canvas,\n"
            "          Offset((w - transPainter.width) / 2 + dx,\n"
            "              top + ayahPainter.height + gap));\n",
            "export paint offset",
        )],
        MARKER,
    )

    # 11. overlay_renderer.dart -- pass the new params at the (only) construction site
    results["lib/services/overlay_renderer.dart (construction site)"] = patch_file(
        project_dir, "lib/screens/home_screen.dart",
        [(
            "        letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES\n"
            "        lineHeightMultiplier: state.lineHeightMultiplier,\n"
            "      );\n",

            "        letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES\n"
            "        lineHeightMultiplier: state.lineHeightMultiplier,\n"
            f"        offset: state.textOffset, // {MARKER}\n"
            "        userScale: state.textUserScale,\n"
            "      );\n",
            "OverlayStyle construction call",
        )],
        MARKER,
    )

    print("S50 patch results:")
    any_applied = False
    for name, applied in results.items():
        status = "applied" if applied else "SKIPPED (marker already present)"
        print(f"  - {name}: {status}")
        any_applied = any_applied or applied

    if not any_applied:
        print("\nNothing changed -- S50 already applied.")
    else:
        print("\nDone. Run `flutter analyze` to confirm, then rebuild.")


if __name__ == "__main__":
    main()
