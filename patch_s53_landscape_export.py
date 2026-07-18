#!/usr/bin/env python3
"""
patch_s53_landscape_export.py

16:9 landscape export. `state.squareRatio` was a bool (9:16 story vs. 1:1
square), which only has room for two shapes. This turns it into a 3-way
`AyatAspectRatio` enum (story916 / square11 / landscape169) so 16:9 --
needed for YouTube/desktop-oriented exports -- becomes a normal third
choice everywhere the old bool was read, following the same
enum-plus-labeled-const-list pattern already used for ColorGrade/
BgSwitchTrigger in studio_presets.dart.

Changes:
  1. lib/data/studio_presets.dart -- new `AyatAspectRatio` enum + a
     `kAspectRatios` list of (enum, Arabic label, canvas width, canvas
     height) records, matching the kColorGrades/kBgSwitchTriggers style.
  2. lib/models/studio_state.dart -- `bool squareRatio` -> `AyatAspectRatio
     aspectRatio` (defaults to story916, i.e. identical behavior to the old
     `false` default).
  3. lib/services/settings_service.dart -- persist/restore the enum by
     index, same pattern as textPosition/effect/colorGrade.
  4. lib/screens/home_screen.dart -- `_ratioToggle()` now renders all three
     choices from `kAspectRatios` instead of two hardcoded chips.
  5. lib/services/export_service.dart -- the static/audio-only export
     canvas size now comes from `kAspectRatios` instead of a `? 1080 :
     1920` bool ternary, so landscape exports without an uploaded video get
     a real 1920x1080 canvas.
  6. lib/widgets/stage_preview.dart -- the live preview's AspectRatio now
     covers all three shapes.

Known limitation (unchanged from before this patch, not introduced by it):
when a video IS uploaded, the exported canvas already follows the source
video's own resolution (see the PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS
comment in export_service.dart) regardless of the aspect-ratio picker --
that picker has only ever governed the live-preview frame shape and the
audio-only/static-image export canvas. Forcing an uploaded video to crop/
pad into a *different* chosen ratio is a separate, larger feature (a real
crop-to-fit step in the ffmpeg filter chain) and is not part of this patch.

Usage:
  python3 patch_s53_landscape_export.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S53_LANDSCAPE_EXPORT"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S53 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


# ---------------------------------------------------------- studio_presets.dart

def patch_studio_presets(project_dir):
    target = project_dir / "lib" / "data" / "studio_presets.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "enum AyahTextPosition { top, center, bottom }\n",
        "enum AyahTextPosition { top, center, bottom }\n"
        "\n"
        f"// {MARKER}: the three export/preview canvas shapes. Width/height here\n"
        "// are the audio-only/static-export canvas AND the source of truth for\n"
        "// the live-preview frame's AspectRatio -- see export_service.dart and\n"
        "// stage_preview.dart.\n"
        "enum AyatAspectRatio { story916, square11, landscape169 }\n"
        "\n"
        "const List<(AyatAspectRatio, String, int, int)> kAspectRatios = [\n"
        "  (AyatAspectRatio.story916, '9:16 قصة', 1080, 1920),\n"
        "  (AyatAspectRatio.square11, '1:1 مربع', 1080, 1080),\n"
        f"  (AyatAspectRatio.landscape169, '16:9 عريض', 1920, 1080), // {MARKER}\n"
        "];\n",
        "studio_presets.dart -- add AyatAspectRatio enum + kAspectRatios",
    )

    target.write_text(text)
    return True


# ---------------------------------------------------------- studio_state.dart

def patch_studio_state(project_dir):
    target = project_dir / "lib" / "models" / "studio_state.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "  // ---- output ----\n"
        "  bool squareRatio = false; // false = 9:16, true = 1:1\n",
        "  // ---- output ----\n"
        f"  // {MARKER}: was `bool squareRatio` (9:16 vs. 1:1 only); story916 is the\n"
        "  // same default the old `false` gave.\n"
        "  AyatAspectRatio aspectRatio = AyatAspectRatio.story916;\n",
        "studio_state.dart -- squareRatio bool -> aspectRatio enum",
    )

    target.write_text(text)
    return True


# ---------------------------------------------------------- settings_service.dart

def patch_settings_service(project_dir):
    target = project_dir / "lib" / "services" / "settings_service.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "      state.squareRatio = read<bool>('squareRatio') ?? state.squareRatio;\n",
        f"      // {MARKER}: was a bool key; a stale 'squareRatio' bool from before\n"
        "      // this patch is simply never read again (harmless orphan pref).\n"
        "      final ratio = read<int>('aspectRatio');\n"
        "      if (ratio != null && ratio >= 0 && ratio < AyatAspectRatio.values.length) {\n"
        "        state.aspectRatio = AyatAspectRatio.values[ratio];\n"
        "      }\n",
        "settings_service.dart restore() -- read aspectRatio",
    )

    text = replace_once(
        text,
        "      p.setBool('${_prefix}squareRatio', state.squareRatio),\n",
        f"      p.setInt('${{_prefix}}aspectRatio', state.aspectRatio.index), // {MARKER}\n",
        "settings_service.dart persist() -- write aspectRatio",
    )

    target.write_text(text)
    return True


# ---------------------------------------------------------- home_screen.dart

def patch_home_screen(project_dir):
    target = project_dir / "lib" / "screens" / "home_screen.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "  Widget _ratioToggle() {\n"
        "    return Row(\n"
        "      mainAxisAlignment: MainAxisAlignment.center,\n"
        "      children: [\n"
        "        ChoiceChip(\n"
        "          label: const Text('9:16 قصة'),\n"
        "          selected: !state.squareRatio,\n"
        "          onSelected: (_) => state.update(() => state.squareRatio = false),\n"
        "        ),\n"
        "        const SizedBox(width: 8),\n"
        "        ChoiceChip(\n"
        "          label: const Text('1:1 مربع'),\n"
        "          selected: state.squareRatio,\n"
        "          onSelected: (_) => state.update(() => state.squareRatio = true),\n"
        "        ),\n"
        "      ],\n"
        "    );\n"
        "  }\n",
        "  Widget _ratioToggle() {\n"
        f"    // {MARKER}: renders all three shapes from kAspectRatios instead of\n"
        "    // two hardcoded chips.\n"
        "    return Wrap(\n"
        "      alignment: WrapAlignment.center,\n"
        "      spacing: 8,\n"
        "      runSpacing: 8,\n"
        "      children: [\n"
        "        for (final entry in kAspectRatios)\n"
        "          ChoiceChip(\n"
        "            label: Text(entry.$2),\n"
        "            selected: state.aspectRatio == entry.$1,\n"
        "            onSelected: (_) =>\n"
        "                state.update(() => state.aspectRatio = entry.$1),\n"
        "          ),\n"
        "      ],\n"
        "    );\n"
        "  }\n",
        "_ratioToggle() -- 2 hardcoded chips -> kAspectRatios loop",
    )

    target.write_text(text)
    return True


# ---------------------------------------------------------- export_service.dart

def patch_export_service(project_dir):
    target = project_dir / "lib" / "services" / "export_service.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "      var w = 1080;\n"
        "      var h = state.squareRatio ? 1080 : 1920;\n",
        f"      // {MARKER}: canvas size for the audio-only/static-export case now\n"
        "      // comes from the 3-way ratio picker instead of a squareRatio bool.\n"
        "      final ratioSpec =\n"
        "          kAspectRatios.firstWhere((r) => r.$1 == state.aspectRatio);\n"
        "      var w = ratioSpec.$3;\n"
        "      var h = ratioSpec.$4;\n",
        "export_service.dart -- squareRatio ternary -> kAspectRatios lookup",
    )

    target.write_text(text)
    return True


# ---------------------------------------------------------- stage_preview.dart

def patch_stage_preview(project_dir):
    target = project_dir / "lib" / "widgets" / "stage_preview.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "    return AspectRatio(\n"
        "      aspectRatio: state.squareRatio ? 1 : 9 / 16,\n",
        f"    return AspectRatio(\n"
        f"      // {MARKER}: covers all three shapes now instead of just 9:16/1:1.\n"
        "      aspectRatio: switch (state.aspectRatio) {\n"
        "        AyatAspectRatio.square11 => 1.0,\n"
        "        AyatAspectRatio.landscape169 => 16 / 9,\n"
        "        AyatAspectRatio.story916 => 9 / 16,\n"
        "      },\n",
        "stage_preview.dart -- squareRatio ternary -> aspectRatio switch",
    )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

    results = {
        "lib/data/studio_presets.dart": patch_studio_presets(project_dir),
        "lib/models/studio_state.dart": patch_studio_state(project_dir),
        "lib/services/settings_service.dart": patch_settings_service(project_dir),
        "lib/screens/home_screen.dart": patch_home_screen(project_dir),
        "lib/services/export_service.dart": patch_export_service(project_dir),
        "lib/widgets/stage_preview.dart": patch_stage_preview(project_dir),
    }

    applied = [f for f, ok in results.items() if ok]
    skipped = [f for f, ok in results.items() if not ok]

    for f in applied:
        print(f"OK  {f}: applied [S53 -- 16:9 landscape export]")
    for f in skipped:
        print(f"OK  {f}: S53 already applied, skipping.")

    print()
    print(f"Applied: {len(applied)}   Skipped(already applied): {len(skipped)}   Failed: 0")
    print()
    print("OK  S53 applied.")
    print()
    print("NOTE: landscape169 only forces a real 1920x1080 canvas when there is")
    print("      NO uploaded video (audio-only/static export) or in the live")
    print("      preview frame shape. An uploaded video still exports at its own")
    print("      native resolution regardless of this picker -- see the docstring")
    print("      at the top of this script.")
    print()
    print("  git add lib/data/studio_presets.dart lib/models/studio_state.dart \\")
    print("          lib/services/settings_service.dart lib/screens/home_screen.dart \\")
    print("          lib/services/export_service.dart lib/widgets/stage_preview.dart")
    print('  git commit -m "S53: 16:9 landscape export -- squareRatio bool -> AyatAspectRatio enum"')
    print("  git push")


if __name__ == "__main__":
    main()
