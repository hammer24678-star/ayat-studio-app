#!/usr/bin/env python3
"""
patch_s58_live_effects_preview.py

The complaint: "تأثيرات التصدير doesn't seem to do anything." It does --
_postFilterChain wires color grade / vignette / grain into the ffmpeg
filter graph correctly (verified: [outv]$post[outv2], applied to both the
main clip and the bismillah/outro title segments), and Ken Burns/quality/
resolution are all correctly threaded through too. The actual gap is that
none of it is visible on the StagePreview stage while editing -- the panel
even says so outright ("لا يبطئ المعاينة المباشرة"). Only the export
render shows the result, so from the editor it looks inert.

Fix: give color grade, vignette, grain, and Ken Burns (photo-background
case) a live approximation on the stage widget itself.

  lib/widgets/stage_preview.dart
    - color grade: ColorFiltered wraps the whole Stack with a 4x5
      ColorMatrix per grade. Sepia is an exact match to
      ExportService._colorGradeFilter's colorchannelmixer coefficients;
      warmGold/nightTeal/softMono are tuned approximations of the
      eq/colorbalance chains, not pixel-identical -- the exported MP4
      stays the authoritative render.
    - vignette: a RadialGradient overlay on top of the stack (including
      the ayah text), matching the export's post-filter ordering where
      vignette/grain apply to the already-composited, text-burned-in
      frame.
    - grain: a CustomPainter redrawing a seeded random dot field on a
      plain ~90ms Timer (not a 60fps AnimationController -- grain reads
      as flicker, not smooth motion, and this is far cheaper on-device).
    - Ken Burns: only previewed for the custom/AI-art photo background
      case (Image.file), via a breathing Transform.scale on _kenBurnsAnim.
      The flat preset-gradient background isn't rendered as a discrete
      image widget in the preview tree, so it's out of scope here --
      Ken Burns still applies correctly to it at export time.

  lib/screens/home_screen.dart
    - updates the "تأثيرات التصدير" panel intro line, since it's no
      longer strictly true that nothing here touches the live preview.

Usage:
  python3 patch_s58_live_effects_preview.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S58_LIVE_EFFECTS_PREVIEW"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S58 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_stage_preview(project_dir):
    target = project_dir / "lib" / "widgets" / "stage_preview.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    # 1. dart:math for Random (grain dot field).
    text = replace_once(
        text,
        "import 'dart:async';\n"
        "import 'dart:io';\n"
        "\n"
        "import 'package:flutter/material.dart';\n",
        "import 'dart:async';\n"
        "import 'dart:io';\n"
        f"import 'dart:math'; // {MARKER}\n"
        "\n"
        "import 'package:flutter/material.dart';\n",
        "add dart:math import",
    )

    # 2. new controllers/timer alongside the existing particle-loop controller.
    text = replace_once(
        text,
        "  // PATCH_S34_STAGE_EFFECTS: drives one seamless particle loop; only runs\n"
        "  // while an effect is actually selected.\n"
        "  late final AnimationController _fxAnim = AnimationController(\n"
        "    vsync: this,\n"
        "    duration: Duration(\n"
        "        milliseconds: (StageEffects.loopSeconds * 1000).round()),\n"
        "  );\n"
        "\n"
        "  // PATCH_S34_PLAYER_CONTROLS_TRIM: transient ▶/⏸ flash after tapping the video.\n"
        "  IconData? _tapFlashIcon;\n"
        "  Timer? _tapFlashTimer;\n"
        "\n"
        "  @override\n"
        "  void dispose() {\n"
        "    _bgAnim.dispose();\n"
        "    _fxAnim.dispose();\n"
        "    _tapFlashTimer?.cancel();\n"
        "    super.dispose();\n"
        "  }\n",
        "  // PATCH_S34_STAGE_EFFECTS: drives one seamless particle loop; only runs\n"
        "  // while an effect is actually selected.\n"
        "  late final AnimationController _fxAnim = AnimationController(\n"
        "    vsync: this,\n"
        "    duration: Duration(\n"
        "        milliseconds: (StageEffects.loopSeconds * 1000).round()),\n"
        "  );\n"
        "\n"
        f"  // {MARKER}: slow breathing zoom approximating the export's zoompan\n"
        "  // Ken Burns move -- a real ffmpeg zoompan only ever zooms forward for\n"
        "  // the length of the clip, but the preview loops indefinitely with no\n"
        "  // export duration to pace against, so it breathes in/out instead.\n"
        "  late final AnimationController _kenBurnsAnim = AnimationController(\n"
        "    vsync: this,\n"
        "    duration: const Duration(seconds: 9),\n"
        "  );\n"
        "\n"
        f"  // {MARKER}: the grain dot field is regenerated on a plain ~90ms Timer,\n"
        "  // not a 60fps AnimationController -- real grain reads as flicker, not\n"
        "  // smooth motion, and a coarse refresh is far cheaper on-device (this\n"
        "  // is a Termux/S22 build) than repainting a dense random field every\n"
        "  // frame.\n"
        "  final ValueNotifier<int> _grainSeed = ValueNotifier(0);\n"
        "  Timer? _grainTimer;\n"
        "\n"
        "  // PATCH_S34_PLAYER_CONTROLS_TRIM: transient ▶/⏸ flash after tapping the video.\n"
        "  IconData? _tapFlashIcon;\n"
        "  Timer? _tapFlashTimer;\n"
        "\n"
        "  @override\n"
        "  void dispose() {\n"
        "    _bgAnim.dispose();\n"
        "    _fxAnim.dispose();\n"
        f"    _kenBurnsAnim.dispose(); // {MARKER}\n"
        f"    _grainTimer?.cancel(); // {MARKER}\n"
        f"    _grainSeed.dispose(); // {MARKER}\n"
        "    _tapFlashTimer?.cancel();\n"
        "    super.dispose();\n"
        "  }\n",
        "new Ken Burns controller + grain timer + dispose",
    )

    # 3. start/stop them in build(), same on-only-when-needed pattern as _fxAnim.
    text = replace_once(
        text,
        "        // PATCH_S34_STAGE_EFFECTS: run the particle loop only when needed.\n"
        "        if (state.effect != StageEffect.none) {\n"
        "          if (!_fxAnim.isAnimating) _fxAnim.repeat();\n"
        "        } else if (_fxAnim.isAnimating) {\n"
        "          _fxAnim.stop();\n"
        "        }\n"
        "        return ClipRRect(\n",
        "        // PATCH_S34_STAGE_EFFECTS: run the particle loop only when needed.\n"
        "        if (state.effect != StageEffect.none) {\n"
        "          if (!_fxAnim.isAnimating) _fxAnim.repeat();\n"
        "        } else if (_fxAnim.isAnimating) {\n"
        "          _fxAnim.stop();\n"
        "        }\n"
        f"        // {MARKER}: same on-only-when-needed pattern as the particle\n"
        "        // loop above, for Ken Burns and grain.\n"
        "        if (state.kenBurnsEnabled) {\n"
        "          if (!_kenBurnsAnim.isAnimating) _kenBurnsAnim.repeat(reverse: true);\n"
        "        } else if (_kenBurnsAnim.isAnimating) {\n"
        "          _kenBurnsAnim.stop();\n"
        "          _kenBurnsAnim.value = 0;\n"
        "        }\n"
        "        if (state.grainEnabled) {\n"
        "          _grainTimer ??= Timer.periodic(const Duration(milliseconds: 90),\n"
        "              (_) => _grainSeed.value++);\n"
        "        } else {\n"
        "          _grainTimer?.cancel();\n"
        "          _grainTimer = null;\n"
        "        }\n"
        "        return ClipRRect(\n",
        "start/stop Ken Burns anim + grain timer in build()",
    )

    # 4. wrap the Stack in ColorFiltered for the live color-grade approximation.
    text = replace_once(
        text,
        "            child: Stack(\n"
        "              fit: StackFit.expand,\n"
        "              children: [\n"
        "                // PATCH_S51_BG_CROSSFADE: the AI-art/custom-photo background\n",
        f"            child: ColorFiltered(\n"
        f"              // {MARKER}: approximates the export's color-grade chain\n"
        "              // live -- see _liveColorFilter below for how close each grade\n"
        "              // gets. The exported MP4 stays the authoritative render.\n"
        "              colorFilter: _liveColorFilter(state.colorGrade),\n"
        "              child: Stack(\n"
        "              fit: StackFit.expand,\n"
        "              children: [\n"
        "                // PATCH_S51_BG_CROSSFADE: the AI-art/custom-photo background\n",
        "wrap Stack in ColorFiltered",
    )

    # 5. Ken Burns breathing zoom on the custom/AI-art background image.
    text = replace_once(
        text,
        "                      child: Image.file(\n"
        "                        File(state.customBgPath!),\n"
        "                        key: ValueKey(state.customBgPath),\n"
        "                        fit: BoxFit.cover,\n"
        "                      ),\n"
        "                    ),\n"
        "                  ),\n"
        "                // PATCH_S28_ANIMATED_BACKGROUND: only over the plain preset gradient --\n",
        f"                      child: state.kenBurnsEnabled\n"
        f"                          ? AnimatedBuilder(\n"
        "                              // {marker}: only the photo/AI-art background is a\n"
        "                              // discrete image widget in the preview tree, so\n"
        "                              // that's the only case previewed here -- the flat\n"
        "                              // preset gradient still gets Ken Burns at export\n"
        "                              // time, just not shown live.\n"
        "                              animation: _kenBurnsAnim,\n"
        "                              child: Image.file(\n"
        "                                File(state.customBgPath!),\n"
        "                                key: ValueKey(state.customBgPath),\n"
        "                                fit: BoxFit.cover,\n"
        "                              ),\n"
        "                              builder: (context, child) => Transform.scale(\n"
        "                                scale: 1.0 + 0.08 * _kenBurnsAnim.value,\n"
        "                                child: child,\n"
        "                              ),\n"
        "                            )\n"
        "                          : Image.file(\n"
        "                              File(state.customBgPath!),\n"
        "                              key: ValueKey(state.customBgPath),\n"
        "                              fit: BoxFit.cover,\n"
        "                            ),\n"
        "                    ),\n"
        "                  ),\n"
        "                // PATCH_S28_ANIMATED_BACKGROUND: only over the plain preset gradient --\n".replace(
            "{marker}", MARKER
        ),
        "Ken Burns breathing zoom on custom bg image",
    )

    # 6. vignette + grain overlays on top of everything (matches export's
    #    post-filter ordering), plus close the ColorFiltered wrapper opened
    #    in step 4.
    text = replace_once(
        text,
        "                            Text(\n"
        "                              'إيقاف تأثير ${state.effect.label}',\n"
        "                              style: const TextStyle(\n"
        "                                  fontSize: 10, color: AyatColors.goldBright),\n"
        "                            ),\n"
        "                          ],\n"
        "                        ),\n"
        "                      ),\n"
        "                    ),\n"
        "                  ),\n"
        "              ],\n"
        "            ),\n"
        "          ),\n"
        "        );\n"
        "      }),\n"
        "    );\n"
        "  }\n",
        "                            Text(\n"
        "                              'إيقاف تأثير ${state.effect.label}',\n"
        "                              style: const TextStyle(\n"
        "                                  fontSize: 10, color: AyatColors.goldBright),\n"
        "                            ),\n"
        "                          ],\n"
        "                        ),\n"
        "                      ),\n"
        "                    ),\n"
        "                  ),\n"
        f"                // {MARKER}: vignette + grain sit on top of everything,\n"
        "                // including the ayah text -- matching the export chain, where\n"
        "                // the post-filter (color grade + vignette + grain) applies to\n"
        "                // the already-composited frame with text burned in.\n"
        "                if (state.vignetteEnabled)\n"
        "                  IgnorePointer(\n"
        "                    child: DecoratedBox(\n"
        "                      decoration: BoxDecoration(\n"
        "                        gradient: RadialGradient(\n"
        "                          center: Alignment.center,\n"
        "                          radius: 0.9,\n"
        "                          colors: [\n"
        "                            Colors.transparent,\n"
        "                            Colors.black.withValues(\n"
        "                                alpha: (state.vignetteIntensity / 100 * 0.55)\n"
        "                                    .clamp(0.0, 0.55)),\n"
        "                          ],\n"
        "                          stops: const [0.45, 1.0],\n"
        "                        ),\n"
        "                      ),\n"
        "                    ),\n"
        "                  ),\n"
        "                if (state.grainEnabled)\n"
        "                  IgnorePointer(\n"
        "                    child: ValueListenableBuilder<int>(\n"
        "                      valueListenable: _grainSeed,\n"
        "                      builder: (context, seed, _) => CustomPaint(\n"
        "                        painter: _GrainPainter(\n"
        "                            seed: seed, intensity: state.grainIntensity),\n"
        "                      ),\n"
        "                    ),\n"
        "                  ),\n"
        "              ],\n"
        "            ),\n"
        f"            ), // {MARKER}: closes ColorFiltered\n"
        "          ),\n"
        "        );\n"
        "      }),\n"
        "    );\n"
        "  }\n",
        "add vignette/grain overlays + close ColorFiltered",
    )

    # 7. helper function + grain painter, appended at end of file.
    text += f"""
// {MARKER}: rough live-preview twin of ExportService._colorGradeFilter's
// ffmpeg eq/colorbalance/colorchannelmixer chains, expressed as a 4x5
// ColorMatrix Flutter can apply every frame. Sepia uses the exact same
// channel-mix coefficients as the ffmpeg filter; warmGold/nightTeal/
// softMono are tuned approximations, not pixel-identical -- the exported
// MP4 is the authoritative render.
ColorFilter _liveColorFilter(ColorGrade g) {{
  switch (g) {{
    case ColorGrade.none:
      return const ColorFilter.matrix(<double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case ColorGrade.warmGold:
      return const ColorFilter.matrix(<double>[
        1.20, -0.05, -0.05, 0, 12,
        0.00, 1.05, -0.05, 0, 4,
        -0.05, -0.10, 0.95, 0, -14,
        0, 0, 0, 1, 0,
      ]);
    case ColorGrade.nightTeal:
      return const ColorFilter.matrix(<double>[
        0.90, 0.02, -0.05, 0, -8,
        0.00, 0.95, 0.00, 0, -4,
        -0.05, 0.05, 1.15, 0, 10,
        0, 0, 0, 1, 0,
      ]);
    case ColorGrade.sepia:
      return const ColorFilter.matrix(<double>[
        0.393, 0.769, 0.189, 0, 0,
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case ColorGrade.softMono:
      return const ColorFilter.matrix(<double>[
        0.2254, 0.7581, 0.0765, 0, -5.1,
        0.2254, 0.7581, 0.0765, 0, -5.1,
        0.2254, 0.7581, 0.0765, 0, -5.1,
        0, 0, 0, 1, 0,
      ]);
  }}
}}

// {MARKER}: cheap film-grain approximation -- a fixed count of translucent
// dots redrawn from a seeded Random on every timer tick (see _grainTimer
// above), not on every animation frame. Mirrors the ffmpeg
// noise=alls=$amt:allf=t+u filter's 0..100 -> 4..30 intensity mapping
// closely enough to judge the look; grain is inherently random so an
// exact frame-for-frame match isn't meaningful anyway.
class _GrainPainter extends CustomPainter {{
  final int seed;
  final int intensity;
  const _GrainPainter({{required this.seed, required this.intensity}});

  @override
  void paint(Canvas canvas, Size size) {{
    final amt = (intensity.clamp(0, 100) / 100 * 26 + 4);
    final count = (size.width * size.height / 900 * (amt / 30))
        .round()
        .clamp(60, 1400);
    final rnd = Random(seed);
    final points = <Offset>[
      for (var i = 0; i < count; i++)
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
    ];
    final paint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: (amt / 100).clamp(0.0, 0.35));
    canvas.drawPoints(PointMode.points, points, paint);
  }}

  @override
  bool shouldRepaint(covariant _GrainPainter old) =>
      old.seed != seed || old.intensity != intensity;
}}
"""

    target.write_text(text)
    return True


def patch_home_screen(project_dir):
    target = project_dir / "lib" / "screens" / "home_screen.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "        _panelTitle('تأثيرات التصدير',\n"
        "            'كل ما هنا يُطبَّق أثناء التصدير فقط (لا يبطئ المعاينة المباشرة)، "
        "وهو بصري بحت — لا يغيّر صوت التلاوة إطلاقًا.'),\n",
        f"        // {MARKER}\n"
        "        _panelTitle('تأثيرات التصدير',\n"
        "            'معاينة تقريبية مباشرة على المسرح أعلاه — الملف المُصدَّر هو "
        "المرجع النهائي للشكل الدقيق. بصري بحت، لا يغيّر صوت التلاوة إطلاقًا.'),\n",
        "update export-effects panel intro text",
    )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

    applied_preview = patch_stage_preview(project_dir)
    applied_home = patch_home_screen(project_dir)

    print(f"{'OK  applied' if applied_preview else 'OK  already applied, skipping'}"
          "  lib/widgets/stage_preview.dart")
    print(f"{'OK  applied' if applied_home else 'OK  already applied, skipping'}"
          "  lib/screens/home_screen.dart")

    applied = int(applied_preview) + int(applied_home)
    print()
    print(f"Applied: {applied}   Skipped(already applied): {2 - applied}   Failed: 0")
    print()
    print("WHAT THIS ADDS:")
    print("  Live-preview approximations of color grade, vignette, grain, and")
    print("  Ken Burns (photo/AI-art background only) directly on the stage,")
    print("  instead of only being visible after export. Sepia is an exact")
    print("  match to the ffmpeg filter; warmGold/nightTeal/softMono are tuned")
    print("  approximations. The exported MP4 stays the authoritative render --")
    print("  the panel intro text now says so instead of claiming zero preview.")
    print()
    print("  git add lib/widgets/stage_preview.dart lib/screens/home_screen.dart")
    print('  git commit -m "S58: live preview for export effects (color grade/vignette/grain/Ken Burns)"')
    print("  git push")


if __name__ == "__main__":
    main()
