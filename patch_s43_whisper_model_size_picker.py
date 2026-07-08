#!/usr/bin/env python3
"""
patch_s43_whisper_model_size_picker.py

PLAN PART 1, item 1.1 -- selectable Whisper model size (speed/accuracy
tradeoff). S41 hardcoded WhisperModel.small as a const, which is the right
default but leaves no fast option for quick previews or older phones, and
no "go even more accurate" option for users who want the best possible
sync and don't mind a bigger download + slower scan.

Changes:
  1. lib/services/whisper_service.dart -- introduces WhisperModelSize
     {tiny, base, small, medium}, a spec table (model/asset/min-size/label),
     and WhisperService.setModelSize()/currentSize/labelFor(). `small`
     stays the default (matches S41's baseline exactly -- no behavior
     change for anyone who never touches the new picker).
  2. lib/models/studio_state.dart -- persistable `whisperModelSize` field.
  3. lib/services/settings_service.dart -- restore/persist that field,
     following the existing enum-as-int pattern already used for
     textPosition/effect/colorGrade/etc.
  4. lib/screens/home_screen.dart -- a compact chip row above the
     detect/auto-sync buttons to pick the tier, wired to
     WhisperService.setModelSize(); the restored preference is also
     applied once at startup right after SettingsService.restore().
  5. .github/workflows/build-apk.yml -- the model re-host step now loops
     over all four asset tiers instead of just ggml-small.bin, so
     switching tiers on-device always has something to download.

Usage:
  python3 patch_s43_whisper_model_size_picker.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S43_MODEL_SIZE_PICKER"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S43 was written.")
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
        "import 'package:http/http.dart' as http;\n"
        "import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';\n"
        "\n"
        "class WhisperService {\n"
        "  static const WhisperModel _model = WhisperModel.small; // PATCH_S41_UPGRADE_ASR_MODEL: base -> small, big ASR accuracy jump on tajweed-style Quranic Arabic\n"
        "  static final WhisperController _controller = WhisperController();\n"
        "  static bool _modelReady = false;\n",
        "import 'package:http/http.dart' as http;\n"
        "import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';\n"
        "\n"
        f"// {MARKER}: selectable accuracy/speed tiers. `small` stays the default\n"
        "// (matches S41's baseline), `tiny`/`base` trade accuracy for a much faster\n"
        "// scan on older devices or quick previews, `medium` is a further accuracy\n"
        "// step up for users who want the best possible sync and don't mind the\n"
        "// extra download size + scan time.\n"
        "enum WhisperModelSize { tiny, base, small, medium }\n"
        "\n"
        "class _ModelSpec {\n"
        "  final WhisperModel model;\n"
        "  final String assetName;\n"
        "  final int minExpectedBytes;\n"
        "  final String labelAr;\n"
        "  const _ModelSpec(this.model, this.assetName, this.minExpectedBytes, this.labelAr);\n"
        "}\n"
        "\n"
        "const Map<WhisperModelSize, _ModelSpec> _modelSpecs = {\n"
        "  WhisperModelSize.tiny: _ModelSpec(\n"
        "      WhisperModel.tiny, 'ggml-tiny.bin', 50 * 1024 * 1024, 'سريع جدًا (~75MB) — أقل دقة'),\n"
        "  WhisperModelSize.base: _ModelSpec(\n"
        "      WhisperModel.base, 'ggml-base.bin', 100 * 1024 * 1024, 'سريع (~148MB) — دقة متوسطة'),\n"
        "  WhisperModelSize.small: _ModelSpec(\n"
        "      WhisperModel.small, 'ggml-small.bin', 400 * 1024 * 1024, 'دقيق (الافتراضي، ~466MB)'),\n"
        "  WhisperModelSize.medium: _ModelSpec(\n"
        "      WhisperModel.medium, 'ggml-medium.bin', 1300 * 1024 * 1024, 'الأدق (~1.5GB) — أبطأ'),\n"
        "};\n"
        "\n"
        "class WhisperService {\n"
        f"  // {MARKER}: mutable (was a S41 const) so the user can switch tiers at\n"
        "  // runtime; setModelSize() below is the only writer.\n"
        "  static WhisperModelSize _size = WhisperModelSize.small;\n"
        "  static final WhisperController _controller = WhisperController();\n"
        "  static bool _modelReady = false;\n"
        "\n"
        "  static WhisperModel get _model => _modelSpecs[_size]!.model;\n"
        f"  static WhisperModelSize get currentSize => _size; // {MARKER}\n"
        f"  static String labelFor(WhisperModelSize size) => _modelSpecs[size]!.labelAr; // {MARKER}\n"
        "\n"
        f"  /// {MARKER}: switch model tier. Safe to call any time (including\n"
        "  /// mid-session); forces the next ensureReady() call to re-verify/\n"
        "  /// re-download the newly selected tier's model file instead of trusting\n"
        "  /// the previous tier's \"ready\" flag.\n"
        "  static void setModelSize(WhisperModelSize size) {\n"
        "    if (size == _size) return;\n"
        "    _size = size;\n"
        "    _modelReady = false;\n"
        "  }\n",
        "WhisperService class header -- const _model -> selectable _size + spec table",
    )

    text = replace_once(
        text,
        "  static const String _assetName = 'ggml-small.bin'; // PATCH_S41_UPGRADE_ASR_MODEL\n"
        "\n"
        "  // ggml-small.bin is ~466MB (bumped from base's ~148MB by PATCH_S41_UPGRADE_ASR_MODEL);\n"
        "  // anything much smaller sitting at the target path is almost certainly\n"
        "  // a partial/failed previous download, not a real cached model, so we\n"
        "  // redo it rather than trust it.\n"
        "  static const int _minExpectedBytes = 400 * 1024 * 1024;\n",
        f"  // {MARKER}: derived from the selected tier instead of a fixed S41 const --\n"
        "  // each tier's own expected size gates its own partial-download check.\n"
        "  static String get _assetName => _modelSpecs[_size]!.assetName;\n"
        "  static int get _minExpectedBytes => _modelSpecs[_size]!.minExpectedBytes;\n",
        "asset name + min-size floor -- fixed consts -> per-tier getters",
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
        "import '../services/stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS\n",
        "import '../services/stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS\n"
        f"import '../services/whisper_service.dart'; // {MARKER}\n",
        "studio_state.dart imports -- add whisper_service.dart",
    )

    text = replace_once(
        text,
        "  // ---- auto-sync timeline ----\n"
        "  List<TimelineSegment> timeline = [];\n"
        "  bool timelineActive = false;\n",
        f"  // ---- {MARKER}: which Whisper tier drives detection/auto-sync ----\n"
        "  WhisperModelSize whisperModelSize = WhisperModelSize.small;\n"
        "\n"
        "  // ---- auto-sync timeline ----\n"
        "  List<TimelineSegment> timeline = [];\n"
        "  bool timelineActive = false;\n",
        "StudioState fields -- add whisperModelSize",
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
        "      state.aiArtEnabled = read<bool>('aiArtEnabled') ?? state.aiArtEnabled;\n"
        "      // PATCH_S38_VIDEO_EFFECTS\n",
        "      state.aiArtEnabled = read<bool>('aiArtEnabled') ?? state.aiArtEnabled;\n"
        f"      // {MARKER}\n"
        "      final modelSize = read<int>('whisperModelSize');\n"
        "      if (modelSize != null &&\n"
        "          modelSize >= 0 &&\n"
        "          modelSize < WhisperModelSize.values.length) {\n"
        "        state.whisperModelSize = WhisperModelSize.values[modelSize];\n"
        "      }\n"
        "      // PATCH_S38_VIDEO_EFFECTS\n",
        "settings_service.dart restore() -- read whisperModelSize",
    )

    text = replace_once(
        text,
        "      p.setBool('${_prefix}aiArtEnabled', state.aiArtEnabled),\n"
        "      // PATCH_S38_VIDEO_EFFECTS\n",
        "      p.setBool('${_prefix}aiArtEnabled', state.aiArtEnabled),\n"
        f"      // {MARKER}\n"
        "      p.setInt('${_prefix}whisperModelSize', state.whisperModelSize.index),\n"
        "      // PATCH_S38_VIDEO_EFFECTS\n",
        "settings_service.dart persist() -- write whisperModelSize",
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

    # Apply the restored/default tier to WhisperService as soon as settings
    # are loaded, so it's honored even before the user opens the picker.
    text = replace_once(
        text,
        "      await SettingsService.restore(state);\n"
        "      if (!mounted) return;\n",
        "      await SettingsService.restore(state);\n"
        f"      WhisperService.setModelSize(state.whisperModelSize); // {MARKER}\n"
        "      if (!mounted) return;\n",
        "initState -- apply restored whisperModelSize on startup",
    )

    # Make sure a mid-session change to state.whisperModelSize (from the new
    # picker) always takes effect right before the transcription that uses it.
    text = replace_once(
        text,
        "  Future<void> _detectFromVideo() async {\n"
        "    final matcher = state.matcher;\n",
        "  Future<void> _detectFromVideo() async {\n"
        f"    WhisperService.setModelSize(state.whisperModelSize); // {MARKER}\n"
        "    final matcher = state.matcher;\n",
        "_detectFromVideo -- apply whisperModelSize before transcribing",
    )

    text = replace_once(
        text,
        "  Future<void> _autoSync() async {\n"
        "    final matcher = state.matcher;\n",
        "  Future<void> _autoSync() async {\n"
        f"    WhisperService.setModelSize(state.whisperModelSize); // {MARKER}\n"
        "    final matcher = state.matcher;\n",
        "_autoSync -- apply whisperModelSize before scanning",
    )

    # The picker itself: a compact chip row above the detect/auto-sync
    # buttons in _mediaButtons(), so it's visible right where it matters.
    text = replace_once(
        text,
        "  Widget _mediaButtons() {\n"
        "    return Column(\n"
        "      crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "      children: [\n"
        "        ElevatedButton.icon(\n"
        "          onPressed: _busy ? null : _pickVideo,\n",
        "  Widget _mediaButtons() {\n"
        "    return Column(\n"
        "      crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "      children: [\n"
        f"        // {MARKER}: model-size picker -- controls every detect/auto-sync\n"
        "        // button below via WhisperService.setModelSize().\n"
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
        "        const SizedBox(height: 8),\n"
        "        ElevatedButton.icon(\n"
        "          onPressed: _busy ? null : _pickVideo,\n",
        "_mediaButtons -- insert model-size chip row",
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
        "        run: |\n"
        "          set -e\n"
        "          TAG=models\n"
        "          ASSET=ggml-small.bin # PATCH_S41_UPGRADE_ASR_MODEL: was ggml-base.bin\n"
        "          URL=\"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$ASSET\"\n"
        "          if ! gh release view \"$TAG\" >/dev/null 2>&1; then\n"
        "            gh release create \"$TAG\" --title \"ASR model assets\" \\\n"
        "              --notes \"Whisper GGML models re-hosted here so the on-device app fetches from github.com instead of huggingface.co. Source: https://huggingface.co/ggerganov/whisper.cpp\"\n"
        "          fi\n"
        "          if gh release view \"$TAG\" --json assets -q '.assets[].name' | grep -qx \"$ASSET\"; then\n"
        "            echo \"$ASSET already attached to release $TAG — skipping re-upload\"\n"
        "          else\n"
        "            curl -fL -o \"$ASSET\" \"$URL\"\n"
        "            gh release upload \"$TAG\" \"$ASSET\"\n"
        "          fi\n",
        "        run: |\n"
        "          set -e\n"
        "          TAG=models\n"
        f"          # {MARKER}: re-host every selectable tier, not just small, so\n"
        "          # switching tiers on-device always has an asset to download.\n"
        "          ASSETS=\"ggml-tiny.bin ggml-base.bin ggml-small.bin ggml-medium.bin\"\n"
        "          if ! gh release view \"$TAG\" >/dev/null 2>&1; then\n"
        "            gh release create \"$TAG\" --title \"ASR model assets\" \\\n"
        "              --notes \"Whisper GGML models re-hosted here so the on-device app fetches from github.com instead of huggingface.co. Source: https://huggingface.co/ggerganov/whisper.cpp\"\n"
        "          fi\n"
        "          for ASSET in $ASSETS; do\n"
        "            URL=\"https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$ASSET\"\n"
        "            if gh release view \"$TAG\" --json assets -q '.assets[].name' | grep -qx \"$ASSET\"; then\n"
        "              echo \"$ASSET already attached to release $TAG — skipping re-upload\"\n"
        "            else\n"
        "              curl -fL -o \"$ASSET\" \"$URL\"\n"
        "              gh release upload \"$TAG\" \"$ASSET\"\n"
        "            fi\n"
        "          done\n",
        "CI re-host step -- single ASSET -> loop over all four tiers",
    )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

    results = {
        "lib/services/whisper_service.dart": patch_whisper_service(project_dir),
        "lib/models/studio_state.dart": patch_studio_state(project_dir),
        "lib/services/settings_service.dart": patch_settings_service(project_dir),
        "lib/screens/home_screen.dart": patch_home_screen(project_dir),
        ".github/workflows/build-apk.yml": patch_ci_workflow(project_dir),
    }

    applied = [f for f, ok in results.items() if ok]
    skipped = [f for f, ok in results.items() if not ok]

    for f in applied:
        print(f"OK  {f}: applied [S43 -- selectable Whisper model-size picker]")
    for f in skipped:
        print(f"OK  {f}: S43 already applied, skipping.")

    print()
    print(f"Applied: {len(applied)}   Skipped(already applied): {len(skipped)}   Failed: 0")
    print()
    print("OK  S43 applied.")
    print()
    print("NOTE: switching to tiny/base/medium on-device downloads that tier's")
    print("      model the first time it's selected -- same one-time-download")
    print("      pattern S41 already used for small.")
    print()
    print("  git add lib/services/whisper_service.dart lib/models/studio_state.dart \\")
    print("          lib/services/settings_service.dart lib/screens/home_screen.dart \\")
    print("          .github/workflows/build-apk.yml")
    print('  git commit -m "S43: selectable Whisper model-size picker (tiny/base/small/medium)"')
    print("  git push")


if __name__ == "__main__":
    main()
