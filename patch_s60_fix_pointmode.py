#!/usr/bin/env python3
"""
patch_s60_fix_pointmode_build_error.py

Build failure from S58 (GitHub Actions run for PR #56):

  lib/widgets/stage_preview.dart:676:23: Error: The getter 'PointMode' isn't
  defined for the type '_GrainPainter'.
      canvas.drawPoints(PointMode.points, points, paint);

Cause: `PointMode` lives in dart:ui. material.dart re-exports most of the
dart:ui types S58's _GrainPainter needed (Canvas, Offset, Paint, Colors,
StrokeCap) but not PointMode, so the reference resolved to nothing rather
than to a class member (there's no such getter on _GrainPainter either,
hence the odd "getter" wording in the error).

Fix: import dart:ui with a prefix (kept prefixed everywhere, rather than
unprefixed, since dart:ui's own Color/TextStyle/etc. would otherwise clash
with the ones material.dart already brings in) and qualify the one call
site that needs it.

  lib/widgets/stage_preview.dart
    - add `import 'dart:ui' as ui;`
    - canvas.drawPoints(PointMode.points, ...) -> canvas.drawPoints(ui.PointMode.points, ...)

Usage:
  python3 patch_s60_fix_pointmode_build_error.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S60_FIX_POINTMODE"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S60 was written.")
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

    if "PointMode.points" not in text:
        die("could not find 'PointMode.points' in stage_preview.dart -- "
            "S58 may not be applied yet, or this was already fixed differently.")

    # 1. dart:ui import, prefixed to avoid clashing with material.dart's
    #    own Color/TextStyle/etc.
    text = replace_once(
        text,
        "import 'dart:math'; // PATCH_S58_LIVE_EFFECTS_PREVIEW\n"
        "\n"
        "import 'package:flutter/material.dart';\n",
        "import 'dart:math'; // PATCH_S58_LIVE_EFFECTS_PREVIEW\n"
        f"import 'dart:ui' as ui; // {MARKER}\n"
        "\n"
        "import 'package:flutter/material.dart';\n",
        "add dart:ui import",
    )

    # 2. qualify the one PointMode reference.
    text = replace_once(
        text,
        "canvas.drawPoints(PointMode.points, points, paint);",
        f"canvas.drawPoints(ui.PointMode.points, points, paint); // {MARKER}",
        "qualify PointMode.points",
    )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    changed = patch_stage_preview(project_dir)
    if changed:
        print(f"OK: patched {project_dir / 'lib' / 'widgets' / 'stage_preview.dart'}")
    else:
        print("SKIP: S60 marker already present, no changes made.")


if __name__ == "__main__":
    main()
