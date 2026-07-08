#!/usr/bin/env python3
"""
patch_s41_upgrade_whisper_model.py

Root-cause fix for "ayah detection is very bad": the whole pipeline (live
timeline scan, one-shot detection, everything in ayah_matcher.dart /
timeline_builder.dart) is downstream of one text transcript per audio
window, and that transcript comes from whisper.cpp's smallest real model
(WhisperModel.base, ~74M params). Base is fine for clean conversational
English; for elongated tajweed-style Quranic Arabic recitation it
regularly mis-hears whole words, which no amount of matcher tuning
(IDF weighting, phonetic folding, mushaf-order context re-scoring, etc.)
can recover from -- the matcher is already working hard to compensate for
bad input text. This bumps the model one tier up to WhisperModel.small
(~244M params), which is a large, well-documented accuracy jump for
Arabic ASR specifically, while still being realistic to run on-device on
a mid/high-end phone (Samsung S22 class) in the existing batch-per-window
scan (no live/streaming requirement here).

Changes:
  1. lib/services/whisper_service.dart -- WhisperModel.base -> .small,
     asset name ggml-base.bin -> ggml-small.bin, and the "is this a real
     cached model or a partial download" size floor bumped from 100MB to
     400MB to match the bigger file.
  2. .github/workflows/build-apk.yml -- the CI step that re-hosts the
     model as a GitHub Release asset (so the app downloads from
     github.com instead of huggingface.co) now fetches/re-hosts
     ggml-small.bin instead of ggml-base.bin. Note this asset is
     ADDITIVE under the same "models" release tag -- ggml-base.bin stays
     attached too, it's just no longer referenced by the app.

This does NOT touch matcher thresholds (minConfidence / highConfidence /
contextMinConfidence in timeline_builder.dart) -- re-tune those AFTER
this lands and you can see real transcripts again, not before; tuning
thresholds against base-model garbage would just be re-fitting noise.

Usage:
  python3 patch_s41_upgrade_whisper_model.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S41_UPGRADE_ASR_MODEL"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S41 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


# ---------------------------------------------------------- whisper_service.dart

def patch_whisper_service(project_dir):
    target = project_dir / "lib" / "services" / "whisper_service.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "class WhisperService {\n"
        "  static const WhisperModel _model = WhisperModel.base;\n",
        "class WhisperService {\n"
        f"  static const WhisperModel _model = WhisperModel.small; // {MARKER}: base -> small, big ASR accuracy jump on tajweed-style Quranic Arabic\n",
        "WhisperModel field -- base -> small",
    )

    text = replace_once(
        text,
        "  static const String _assetName = 'ggml-base.bin';\n"
        "\n"
        "  // ggml-base.bin is ~148MB; anything much smaller sitting at the target\n"
        "  // path is almost certainly a partial/failed previous download, not a\n"
        "  // real cached model, so we redo it rather than trust it.\n"
        "  static const int _minExpectedBytes = 100 * 1024 * 1024;\n",
        f"  static const String _assetName = 'ggml-small.bin'; // {MARKER}\n"
        "\n"
        f"  // ggml-small.bin is ~466MB (bumped from base's ~148MB by {MARKER});\n"
        "  // anything much smaller sitting at the target path is almost certainly\n"
        "  // a partial/failed previous download, not a real cached model, so we\n"
        "  // redo it rather than trust it.\n"
        "  static const int _minExpectedBytes = 400 * 1024 * 1024;\n",
        "asset name + min-size floor -- ggml-base.bin -> ggml-small.bin",
    )

    target.write_text(text)
    return True


# ---------------------------------------------------------- build-apk.yml

def patch_ci_workflow(project_dir):
    target = project_dir / ".github" / "workflows" / "build-apk.yml"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    text = replace_once(
        text,
        "          TAG=models\n"
        "          ASSET=ggml-base.bin\n"
        "          URL=\"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$ASSET\"\n",
        "          TAG=models\n"
        f"          ASSET=ggml-small.bin # {MARKER}: was ggml-base.bin\n"
        "          URL=\"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$ASSET\"\n",
        "CI re-host step -- ASSET ggml-base.bin -> ggml-small.bin",
    )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

    results = {
        "lib/services/whisper_service.dart": patch_whisper_service(project_dir),
        ".github/workflows/build-apk.yml": patch_ci_workflow(project_dir),
    }

    applied = [f for f, ok in results.items() if ok]
    skipped = [f for f, ok in results.items() if not ok]

    for f in applied:
        print(f"OK  {f}: applied [S41 -- upgrade on-device Whisper model base -> small]")
    for f in skipped:
        print(f"OK  {f}: S41 already applied, skipping.")

    print()
    print(f"Applied: {len(applied)}   Skipped(already applied): {len(skipped)}   Failed: 0")
    print()
    print("OK  S41 applied.")
    print()
    print("NOTE: first run after this lands will download a new ~466MB model")
    print("      file on-device (one-time) -- ggml-small.bin, re-hosted by CI")
    print("      the same way ggml-base.bin was.")
    print()
    print("  git add lib/services/whisper_service.dart .github/workflows/build-apk.yml")
    print('  git commit -m "S41: upgrade on-device Whisper model base -> small for real ayah-detection accuracy"')
    print("  git push")


if __name__ == "__main__":
    main()
