#!/usr/bin/env python3
"""
patch_s52_more_stage_effects.py

Two more decorative stage effects, added the same way S51 added `sparkle`:
extend the StageEffect enum, give it a label/icon, add a case in
StageEffects.paint(), and a deterministic _paintXxx() method that follows
the file's established convention (periodic motion in whole cycles per
[StageEffects.loopSeconds] so the export's tiled PNG loop is seamless).

No other file needs to change: the effects panel in home_screen.dart
already iterates `StageEffect.values` to build its chip list, and
export_service.dart already renders whatever `state.effect` is generically
via StageEffects.renderEffectFramePng -- both new effects get full preview
+ export support for free.

New effects:
  - geometricShimmer ("بريق زخرفي إسلامي") -- a grid of 8-pointed star
    motifs (two overlapping rotated squares, the classic Islamic geometric
    unit) that gently counter-rotate and catch a soft diagonal shimmer
    sweep, evoking mashrabiya/zellige latticework without needing any
    image assets.
  - confetti ("قصاصات ذهبية") -- small rotating gold rectangles falling and
    tumbling in a light shower; a festive alternative to the existing plain
    `dust` effect, for e.g. Eid-themed clips.

Changes:
  lib/services/stage_effects.dart

Usage:
  python3 patch_s52_more_stage_effects.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S52_MORE_EFFECTS"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S52 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_stage_effects(project_dir):
    target = project_dir / "lib" / "services" / "stage_effects.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    # 1. enum
    text = replace_once(
        text,
        "enum StageEffect { none, rain, snow, dust, sparkle }\n",
        f"enum StageEffect {{ none, rain, snow, dust, sparkle, geometricShimmer, confetti }} // {MARKER}\n",
        "StageEffect enum -- add geometricShimmer, confetti",
    )

    # 2. label
    text = replace_once(
        text,
        "        StageEffect.sparkle => 'بريق نجمي', // PATCH_S51_MORE_EFFECTS\n"
        "      };\n",
        "        StageEffect.sparkle => 'بريق نجمي', // PATCH_S51_MORE_EFFECTS\n"
        f"        StageEffect.geometricShimmer => 'بريق زخرفي إسلامي', // {MARKER}\n"
        f"        StageEffect.confetti => 'قصاصات ذهبية', // {MARKER}\n"
        "      };\n",
        "StageEffect label extension -- add new labels",
    )

    # 3. icon
    text = replace_once(
        text,
        "        StageEffect.sparkle => Icons.star_outline, // PATCH_S51_MORE_EFFECTS\n"
        "      };\n",
        "        StageEffect.sparkle => Icons.star_outline, // PATCH_S51_MORE_EFFECTS\n"
        f"        StageEffect.geometricShimmer => Icons.auto_awesome_mosaic, // {MARKER}\n"
        f"        StageEffect.confetti => Icons.celebration_outlined, // {MARKER}\n"
        "      };\n",
        "StageEffect icon extension -- add new icons",
    )

    # 4. paint() switch case
    text = replace_once(
        text,
        "      case StageEffect.sparkle: // PATCH_S51_MORE_EFFECTS\n"
        "        _paintSparkle(canvas, size, timeSec, intensity);\n"
        "    }\n"
        "  }\n",
        "      case StageEffect.sparkle: // PATCH_S51_MORE_EFFECTS\n"
        "        _paintSparkle(canvas, size, timeSec, intensity);\n"
        f"      case StageEffect.geometricShimmer: // {MARKER}\n"
        "        _paintGeometricShimmer(canvas, size, timeSec, intensity);\n"
        f"      case StageEffect.confetti: // {MARKER}\n"
        "        _paintConfetti(canvas, size, timeSec, intensity);\n"
        "    }\n"
        "  }\n",
        "StageEffects.paint() switch -- add new cases",
    )

    # 5. the two new painters, inserted right after _paintSparkle() and its
    #    closing brace, before renderEffectFramePng().
    text = replace_once(
        text,
        "  /// One transparent frame of the export loop as PNG bytes.\n"
        "  static Future<Uint8List> renderEffectFramePng({\n",
        f"  // {MARKER}: a grid of 8-pointed star motifs (two overlapping squares\n"
        "  // rotated 45° apart -- the classic Islamic geometric-pattern building\n"
        "  // block) that gently counter-rotate and catch a soft diagonal shimmer\n"
        "  // sweep. Whole rotations and whole sweep cycles per loop keep the\n"
        "  // export tile seamless, same convention as every other effect here.\n"
        "  static void _paintGeometricShimmer(\n"
        "      Canvas canvas, Size size, double t, double intensity) {\n"
        "    final w = size.width, h = size.height;\n"
        "    final cell = w / 6; // roughly 6 motifs across regardless of canvas size\n"
        "    final cols = (w / cell).ceil() + 1;\n"
        "    final rows = (h / cell).ceil() + 1;\n"
        "    final paint = Paint()\n"
        "      ..style = PaintingStyle.stroke\n"
        "      ..strokeWidth = max(1.0, w / 540);\n"
        "    for (var row = -1; row < rows; row++) {\n"
        "      for (var col = -1; col < cols; col++) {\n"
        "        final i = row * 1000 + col; // unique deterministic index per cell\n"
        "        final cx = (col + 0.5) * cell;\n"
        "        final cy = (row + 0.5) * cell;\n"
        "        // a soft band of brightness sweeps diagonally across the grid once\n"
        "        // per loop -- whole-cycle, so the wrap is seamless.\n"
        "        final diag = (cx + cy) / (w + h); // 0..1 position along the sweep\n"
        "        final phase = _rand(i, 5) * 2 * pi;\n"
        "        final sweep = 0.5 +\n"
        "            0.5 * sin(2 * pi * (t / loopSeconds - diag) + phase * 0.15);\n"
        "        final glow = pow(sweep, 4).toDouble();\n"
        "        if (glow < 0.03) continue;\n"
        "        // gentle whole-rotation per loop, alternating direction and staggered\n"
        "        // per cell so the lattice doesn't spin in lockstep.\n"
        "        final spinDir = (i.abs() % 2 == 0) ? 1 : -1;\n"
        "        final angle =\n"
        "            spinDir * 2 * pi * t / loopSeconds + _rand(i, 6) * 2 * pi;\n"
        "        paint.color = const Color(0xFFECC875)\n"
        "            .withValues(alpha: glow * 0.55 * intensity);\n"
        "        canvas.save();\n"
        "        canvas.translate(cx, cy);\n"
        "        canvas.rotate(angle);\n"
        "        _drawEightPointStar(canvas, paint, cell * 0.30);\n"
        "        canvas.restore();\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "\n"
        f"  // {MARKER}: two squares 45° apart, the simplest way to draw an\n"
        "  // 8-pointed star outline (rub el hizb style) without needing an asset.\n"
        "  static void _drawEightPointStar(Canvas canvas, Paint paint, double r) {\n"
        "    Path square(double rot) {\n"
        "      final path = Path();\n"
        "      for (var k = 0; k < 4; k++) {\n"
        "        final a = rot + k * pi / 2;\n"
        "        final pt = Offset(cos(a) * r, sin(a) * r);\n"
        "        if (k == 0) {\n"
        "          path.moveTo(pt.dx, pt.dy);\n"
        "        } else {\n"
        "          path.lineTo(pt.dx, pt.dy);\n"
        "        }\n"
        "      }\n"
        "      path.close();\n"
        "      return path;\n"
        "    }\n"
        "\n"
        "    canvas.drawPath(square(pi / 4), paint);\n"
        "    canvas.drawPath(square(0), paint);\n"
        "  }\n"
        "\n"
        f"  // {MARKER}: small rotating gold rectangles falling and tumbling in a\n"
        "  // light shower -- a festive alternative to the plain `dust` effect.\n"
        "  // Same seamless-loop conventions as _paintRain/_paintSnow: whole\n"
        "  // traversals for the fall and whole spin/sway cycles for the tumble.\n"
        "  static void _paintConfetti(\n"
        "      Canvas canvas, Size size, double t, double intensity) {\n"
        "    final w = size.width, h = size.height;\n"
        "    final count = (60 * intensity).round();\n"
        "    final paint = Paint();\n"
        "    for (var i = 0; i < count; i++) {\n"
        "      final depth = _rand(i, 1);\n"
        "      final pw = (2.5 + 4.5 * depth) * w / 1080;\n"
        "      final ph = pw * 0.5;\n"
        "      final range = h + ph * 2;\n"
        "      final kLoops = 1 + (i % 2); // whole traversals per loop\n"
        "      final v = kLoops * range / loopSeconds;\n"
        "      final y = ((_rand(i, 2) * range + v * t) % range) - ph;\n"
        "      final swayCycles = 1 + (i % 3);\n"
        "      final phase = _rand(i, 4) * 2 * pi;\n"
        "      final sway =\n"
        "          sin(2 * pi * swayCycles * t / loopSeconds + phase) * w * 0.04;\n"
        "      final x = (_rand(i, 3) * w + sway + w) % w;\n"
        "      // whole spin cycles per loop keeps the tumble seamless too\n"
        "      final spinCycles = 2 + (i % 3);\n"
        "      final angle = 2 * pi * spinCycles * t / loopSeconds + phase;\n"
        "      final hueMix = _rand(i, 5);\n"
        "      final color = Color.lerp(\n"
        "          const Color(0xFFECC875), const Color(0xFFFFF3D6), hueMix)!;\n"
        "      paint.color = color.withValues(alpha: (0.35 + 0.5 * depth) * intensity);\n"
        "      canvas.save();\n"
        "      canvas.translate(x, y);\n"
        "      canvas.rotate(angle);\n"
        "      canvas.drawRect(\n"
        "          Rect.fromCenter(center: Offset.zero, width: pw, height: ph), paint);\n"
        "      canvas.restore();\n"
        "    }\n"
        "  }\n"
        "\n"
        "  /// One transparent frame of the export loop as PNG bytes.\n"
        "  static Future<Uint8List> renderEffectFramePng({\n",
        "insert _paintGeometricShimmer/_drawEightPointStar/_paintConfetti",
    )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

    applied = patch_stage_effects(project_dir)

    if applied:
        print("OK  lib/services/stage_effects.dart: applied [S52 -- geometric shimmer + confetti stage effects]")
    else:
        print("OK  lib/services/stage_effects.dart: S52 already applied, skipping.")

    print()
    print(f"Applied: {1 if applied else 0}   Skipped(already applied): {0 if applied else 1}   Failed: 0")
    print()
    print("OK  S52 applied.")
    print()
    print("NOTE: no UI or export-pipeline changes needed -- the effects panel")
    print("      already iterates StageEffect.values and the exporter already")
    print("      renders state.effect generically, so both new effects are")
    print("      immediately selectable and exportable.")
    print()
    print("  git add lib/services/stage_effects.dart")
    print('  git commit -m "S52: two more stage effects -- Islamic geometric shimmer, gold confetti"')
    print("  git push")


if __name__ == "__main__":
    main()
