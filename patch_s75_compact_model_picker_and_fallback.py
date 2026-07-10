#!/usr/bin/env python3
"""
patch_s75_compact_model_picker_and_fallback.py

TWO THINGS, requested together:

  1. UI: replace the S50 vertical stack of 5 full-width "دقة التعرّف على
     الكلام" cards with a single compact selector button (current choice +
     chevron) that opens a bottom-sheet picker -- the same interaction
     pattern as Claude's own model picker. Same 5 tiers, same
     WhisperService.setModelSize() wiring, just far less vertical space.

  2. BUG FIX: the "دقة القرآن (~148MB)" tier 404s because its asset
     (ggml-quran-lora-base.bin) is only published by the separate,
     manually-triggered prepare-quran-model.yml workflow added in S66 --
     and that workflow has apparently never been run from the Actions tab
     (or was run before the release exhttps://td, or failed silently).
     This patch does NOT publish the asset for you (nothing running in
     Termux can trigger a GitHub Actions workflow_dispatch on your
     behalf) -- see "REQUIRED MANUAL STEP" below. What it DOES fix in
     code: today a 404 on any tier's download throws bare and kills
     whatever you were doing (auto-sync / mic detect / video audio
     detect) with a raw HTTP-404 toast. WhisperService.ensureReady() now
     catches a failed download and, unless the failing tier is already
     `small` (the safe baseline), automatically falls back to `small`,
     downloads/verifies THAT instead, and reports what happened via
     onStatus -- so a still-unpublished تجريبي tier degrades gracefully
     instead of breaking the feature. The picker sheet also syncs its
     displayed selection back to whatever tier actually ended up ready.

REQUIRED MANUAL STEP (this is the actual root cause of the 404):
  GitHub repo -> Actions tab -> "Prepare Quran-tuned Whisper model
  (one-time / on-demand)" -> Run workflow. Wait for it to finish, then
  check the repo's "models" Release page lists ggml-quran-lora-base.bin
  alongside the other 4 .bin files. Until that's done, دقة القرآن will
  keep falling back to دقيق (small) -- gracefully now instead of erroring.

WHAT THIS PATCH DOES:
  1. lib/services/whisper_service.dart
     - splits ensureReady()'s download/verify body into a private
       _downloadAndVerify(size, onStatus) helper
     - ensureReady() now tries the currently selected tier; on failure,
       if that tier isn't already `small`, it falls back to `small` and
       retries once, reporting the switch via onStatus. If `small`
       itself fails, the original exception still propagates (nothing
       left to fall back to).
  2. lib/screens/home_screen.dart
     - replaces the vertical list-of-cards under "دقة التعرّف على الكلام"
       with one compact selector row (current tier + chevron) that opens
       a showModalBottomSheet listing all 5 tiers -- same selected-state
       styling as before, just collapsed until tapped.
     - after any detect/auto-sync job finishes, re-syncs
       state.whisperModelSize to WhisperService.currentSize (in case
       ensureReady() silently fell back) and toasts if it changed.

Usage:
  python3 patch_s75_compact_model_picker_and_fallback.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S75_COMPACT_PICKER_FALLBACK"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S75 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1. lib/services/whisper_service.dart
# ---------------------------------------------------------------------------

def patch_whisper_service(project_dir):
    target = project_dir / "lib" / "services" / "whisper_service.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    old_ensure = (
        "  static Future<void> ensureReady({void Function(String status)? onStatus}) async {\n"
        "    if (_modelReady) return;\n"
        "\n"
        "    final path = await _controller.getPath(_model);\n"
        "    final file = File(path);\n"
        "    final needsDownload =\n"
        "        !(await file.exists()) || (await file.length()) < _minExpectedBytes;\n"
        "\n"
        "    if (needsDownload) {\n"
        "      onStatus?.call('جارٍ تنزيل نموذج التعرّف على الكلام من GitHub (أول تشغيل فقط)…');\n"
        "      await file.parent.create(recursive: true);\n"
        "      final uri = Uri.parse('$_releaseBaseUrl/$_assetName');\n"
        "      final request = http.Request('GET', uri);\n"
        "      final response = await http.Client().send(request);\n"
        "      if (response.statusCode != 200) {\n"
        "        throw Exception('تعذّر تنزيل نموذج التعرّف من GitHub (HTTP ${response.statusCode})');\n"
        "      }\n"
        "      final sink = file.openWrite();\n"
        "      await response.stream.pipe(sink);\n"
        "      await sink.close();\n"
        "      if (await file.length() < _minExpectedBytes) {\n"
        "        await file.delete();\n"
        "        throw Exception('اكتمل التنزيل لكن حجم الملف غير سليم — أعد المحاولة');\n"
        "      }\n"
        "    }\n"
        "\n"
        "    _modelReady = true;\n"
        "    onStatus?.call('النموذج جاهز');\n"
        "  }\n"
    )
    new_ensure = (
        f"  // {MARKER}: download/verify for whichever tier `size` currently points at.\n"
        "  // Pulled out of ensureReady() so it can be attempted for the selected tier\n"
        "  // first, then retried for a fallback tier without duplicating this logic.\n"
        "  static Future<void> _downloadAndVerify(\n"
        "      WhisperModelSize size, {void Function(String status)? onStatus}) async {\n"
        "    final spec = _modelSpecs[size]!;\n"
        "    final path = await _controller.getPath(spec.model);\n"
        "    final file = File(path);\n"
        "    final needsDownload =\n"
        "        !(await file.exists()) || (await file.length()) < spec.minExpectedBytes;\n"
        "\n"
        "    if (needsDownload) {\n"
        "      onStatus?.call('جارٍ تنزيل نموذج التعرّف على الكلام من GitHub (أول تشغيل فقط)…');\n"
        "      await file.parent.create(recursive: true);\n"
        "      final uri = Uri.parse('$_releaseBaseUrl/${spec.assetName}');\n"
        "      final request = http.Request('GET', uri);\n"
        "      final response = await http.Client().send(request);\n"
        "      if (response.statusCode != 200) {\n"
        "        throw Exception('تعذّر تنزيل نموذج التعرّف من GitHub (HTTP ${response.statusCode})');\n"
        "      }\n"
        "      final sink = file.openWrite();\n"
        "      await response.stream.pipe(sink);\n"
        "      await sink.close();\n"
        "      if (await file.length() < spec.minExpectedBytes) {\n"
        "        await file.delete();\n"
        "        throw Exception('اكتمل التنزيل لكن حجم الملف غير سليم — أعد المحاولة');\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "\n"
        f"  // {MARKER}: if the selected tier can't be downloaded/verified (e.g. a tier\n"
        "  // whose asset isn't published yet, or a transient network/HTTP error) this\n"
        "  // no longer throws straight into the caller's face. Unless the failing tier\n"
        "  // is already `small` (the long-standing safe default, always published),\n"
        "  // it falls back to `small` and retries once, so auto-sync/detect still\n"
        "  // works. `_size` itself is updated on fallback so the UI can re-sync its\n"
        "  // displayed selection via currentSize.\n"
        "  static Future<void> ensureReady({void Function(String status)? onStatus}) async {\n"
        "    if (_modelReady) return;\n"
        "    try {\n"
        "      await _downloadAndVerify(_size, onStatus: onStatus);\n"
        "    } catch (e) {\n"
        "      if (_size == WhisperModelSize.small) rethrow;\n"
        "      final failedLabel = labelFor(_size).split(' — ').first;\n"
        "      onStatus?.call('تعذّر تحميل \"$failedLabel\" — سيتم استخدام \"دقيق\" مؤقتًا…');\n"
        "      _size = WhisperModelSize.small;\n"
        "      await _downloadAndVerify(_size, onStatus: onStatus);\n"
        "    }\n"
        "    _modelReady = true;\n"
        "    onStatus?.call('النموذج جاهز');\n"
        "  }\n"
    )
    text = replace_once(text, old_ensure, new_ensure, "whisper_service ensureReady")

    target.write_text(text)
    return True


# ---------------------------------------------------------------------------
# 2. lib/screens/home_screen.dart -- compact picker
# ---------------------------------------------------------------------------

def patch_home_screen(project_dir):
    target = project_dir / "lib" / "screens" / "home_screen.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    old_block = (
        "        // PATCH_S43_MODEL_SIZE_PICKER: model-size picker -- controls every detect/auto-sync\n"
        "        // button below via WhisperService.setModelSize().\n"
        "        // PATCH_S50_MODEL_SIZE_CARDS: one full-width card per tier instead of four\n"
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
        "        const SizedBox(height: 8),\n"
    )
    new_block = (
        f"        // {MARKER}: model-size picker -- controls every detect/auto-sync\n"
        "        // button below via WhisperService.setModelSize(). Collapsed to one\n"
        "        // compact row (current tier + chevron) that opens a bottom-sheet list\n"
        "        // on tap -- same interaction pattern as a model picker, instead of\n"
        "        // permanently occupying 5 full-width cards' worth of vertical space.\n"
        "        _fieldLabel('دقة التعرّف على الكلام'),\n"
        "        _modelSizeSelector(),\n"
        "        const SizedBox(height: 8),\n"
    )
    text = replace_once(text, old_block, new_block, "home_screen model-size picker block")

    # Insert the new _modelSizeSelector() + _showModelSizePicker() methods
    # right before _mediaButtons() so they live next to where they're used.
    old_anchor = "  Widget _mediaButtons() {\n"
    new_anchor = (
        f"  // {MARKER}: compact selector button shown inline; opens the full tier\n"
        "  // list in a bottom sheet instead of always showing all 5 cards.\n"
        "  Widget _modelSizeSelector() {\n"
        "    final parts = WhisperService.labelFor(state.whisperModelSize).split(' — ');\n"
        "    final sizeLabel = parts.first;\n"
        "    final qualityLabel = parts.length > 1 ? parts[1] : '';\n"
        "    return Material(\n"
        "      color: AyatColors.ink.withValues(alpha: 0.4),\n"
        "      borderRadius: BorderRadius.circular(10),\n"
        "      child: InkWell(\n"
        "        borderRadius: BorderRadius.circular(10),\n"
        "        onTap: _busy ? null : _showModelSizePicker,\n"
        "        child: Container(\n"
        "          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),\n"
        "          decoration: BoxDecoration(\n"
        "            borderRadius: BorderRadius.circular(10),\n"
        "            border: Border.all(color: AyatColors.hairline, width: 1),\n"
        "          ),\n"
        "          child: Row(\n"
        "            children: [\n"
        "              Expanded(\n"
        "                child: Column(\n"
        "                  crossAxisAlignment: CrossAxisAlignment.start,\n"
        "                  children: [\n"
        "                    Text(sizeLabel,\n"
        "                        style: const TextStyle(\n"
        "                            fontWeight: FontWeight.bold,\n"
        "                            color: AyatColors.goldBright)),\n"
        "                    if (qualityLabel.isNotEmpty) ...[\n"
        "                      const SizedBox(height: 2),\n"
        "                      Text(qualityLabel,\n"
        "                          style: TextStyle(\n"
        "                              fontSize: 12,\n"
        "                              color: Colors.white.withValues(alpha: 0.6))),\n"
        "                    ],\n"
        "                  ],\n"
        "                ),\n"
        "              ),\n"
        "              Icon(Icons.unfold_more,\n"
        "                  color: Colors.white.withValues(alpha: 0.5), size: 20),\n"
        "            ],\n"
        "          ),\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n"
        "\n"
        f"  // {MARKER}: bottom-sheet with all 5 tiers -- same card styling S50 used\n"
        "  // inline, just shown on demand. Tapping a tier updates selection and\n"
        "  // closes the sheet; the actual model file is still only fetched lazily\n"
        "  // the next time a detect/auto-sync job runs ensureReady().\n"
        "  void _showModelSizePicker() {\n"
        "    showModalBottomSheet(\n"
        "      context: context,\n"
        "      backgroundColor: AyatColors.surface,\n"
        "      shape: const RoundedRectangleBorder(\n"
        "        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),\n"
        "      ),\n"
        "      builder: (sheetContext) {\n"
        "        return SafeArea(\n"
        "          child: Padding(\n"
        "            padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),\n"
        "            child: Column(\n"
        "              mainAxisSize: MainAxisSize.min,\n"
        "              crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "              children: [\n"
        "                _fieldLabel('دقة التعرّف على الكلام'),\n"
        "                const SizedBox(height: 8),\n"
        "                for (final size in WhisperModelSize.values)\n"
        "                  Builder(builder: (context) {\n"
        "                    final selected = state.whisperModelSize == size;\n"
        "                    final parts = WhisperService.labelFor(size).split(' — ');\n"
        "                    final sizeLabel = parts.first;\n"
        "                    final qualityLabel = parts.length > 1 ? parts[1] : '';\n"
        "                    return Padding(\n"
        "                      padding: const EdgeInsets.only(bottom: 8),\n"
        "                      child: Material(\n"
        "                        color: selected\n"
        "                            ? AyatColors.gold.withValues(alpha: 0.12)\n"
        "                            : AyatColors.ink.withValues(alpha: 0.4),\n"
        "                        borderRadius: BorderRadius.circular(10),\n"
        "                        child: InkWell(\n"
        "                          borderRadius: BorderRadius.circular(10),\n"
        "                          onTap: () {\n"
        "                            state.update(() => state.whisperModelSize = size);\n"
        "                            WhisperService.setModelSize(size);\n"
        "                            Navigator.of(sheetContext).pop();\n"
        "                          },\n"
        "                          child: Container(\n"
        "                            padding: const EdgeInsets.symmetric(\n"
        "                                horizontal: 14, vertical: 12),\n"
        "                            decoration: BoxDecoration(\n"
        "                              borderRadius: BorderRadius.circular(10),\n"
        "                              border: Border.all(\n"
        "                                color: selected\n"
        "                                    ? AyatColors.gold\n"
        "                                    : AyatColors.hairline,\n"
        "                                width: selected ? 1.4 : 1,\n"
        "                              ),\n"
        "                            ),\n"
        "                            child: Row(\n"
        "                              children: [\n"
        "                                Expanded(\n"
        "                                  child: Column(\n"
        "                                    crossAxisAlignment:\n"
        "                                        CrossAxisAlignment.start,\n"
        "                                    children: [\n"
        "                                      Text(\n"
        "                                        sizeLabel,\n"
        "                                        style: TextStyle(\n"
        "                                          fontWeight: selected\n"
        "                                              ? FontWeight.bold\n"
        "                                              : FontWeight.w500,\n"
        "                                          color: selected\n"
        "                                              ? AyatColors.goldBright\n"
        "                                              : Colors.white,\n"
        "                                        ),\n"
        "                                      ),\n"
        "                                      if (qualityLabel.isNotEmpty) ...[\n"
        "                                        const SizedBox(height: 2),\n"
        "                                        Text(\n"
        "                                          qualityLabel,\n"
        "                                          style: TextStyle(\n"
        "                                            fontSize: 12,\n"
        "                                            color: Colors.white\n"
        "                                                .withValues(alpha: 0.6),\n"
        "                                          ),\n"
        "                                        ),\n"
        "                                      ],\n"
        "                                    ],\n"
        "                                  ),\n"
        "                                ),\n"
        "                                if (selected)\n"
        "                                  const Icon(Icons.check_circle,\n"
        "                                      color: AyatColors.goldBright, size: 20)\n"
        "                                else\n"
        "                                  Icon(Icons.circle_outlined,\n"
        "                                      color:\n"
        "                                          Colors.white.withValues(alpha: 0.3),\n"
        "                                      size: 20),\n"
        "                              ],\n"
        "                            ),\n"
        "                          ),\n"
        "                        ),\n"
        "                      ),\n"
        "                    );\n"
        "                  }),\n"
        "              ],\n"
        "            ),\n"
        "          ),\n"
        "        );\n"
        "      },\n"
        "    );\n"
        "  }\n"
        "\n"
        "  Widget _mediaButtons() {\n"
    )
    text = replace_once(text, old_anchor, new_anchor, "home_screen insert selector methods before _mediaButtons")

    # Re-sync displayed tier after any detect/auto-sync job in case ensureReady()
    # fell back silently -- hook into the existing _withBusy job wrapper's
    # success path, right after the job completes (finally-adjacent but only
    # meaningful after a job that could have touched WhisperService).
    old_toast_helper = (
        "  void _toast(String msg) {\n"
        "    if (!mounted) return;\n"
        "    ScaffoldMessenger.of(context)\n"
        "      ..hideCurrentSnackBar()\n"
        "      ..showSnackBar(SnackBar(\n"
        "        content: Text(msg, textAlign: TextAlign.center),\n"
        "        behavior: SnackBarBehavior.floating,\n"
        "        duration: const Duration(milliseconds: 2200),\n"
        "      ));\n"
        "  }\n"
    )
    new_toast_helper = (
        "  void _toast(String msg) {\n"
        "    if (!mounted) return;\n"
        "    ScaffoldMessenger.of(context)\n"
        "      ..hideCurrentSnackBar()\n"
        "      ..showSnackBar(SnackBar(\n"
        "        content: Text(msg, textAlign: TextAlign.center),\n"
        "        behavior: SnackBarBehavior.floating,\n"
        "        duration: const Duration(milliseconds: 2200),\n"
        "      ));\n"
        "  }\n"
        "\n"
        f"  // {MARKER}: WhisperService.ensureReady() can silently fall back to a\n"
        "  // different (working) tier than the one selected -- e.g. دقة القرآن isn't\n"
        "  // published yet. Call this after any job that may have run ensureReady()\n"
        "  // so the compact selector's displayed tier stays truthful, and let the\n"
        "  // user know why it changed.\n"
        "  void _syncModelSizeDisplay() {\n"
        "    final actual = WhisperService.currentSize;\n"
        "    if (actual != state.whisperModelSize) {\n"
        "      final newLabel = WhisperService.labelFor(actual).split(' — ').first;\n"
        "      state.update(() => state.whisperModelSize = actual);\n"
        "      _toast('تم التبديل تلقائيًا إلى \"$newLabel\" لأن الخيار المحدّد غير متاح حاليًا');\n"
        "    }\n"
        "  }\n"
    )
    text = replace_once(text, old_toast_helper, new_toast_helper, "home_screen add _syncModelSizeDisplay after _toast")

    # Call it from _micDetect's finally block (mirrors the existing finally there).
    old_mic_finally = (
        "    } catch (e) {\n"
        "      _toast('$e'.replaceFirst('Exception: ', ''));\n"
        "    } finally {\n"
        "      if (mounted) setState(() => _listening = false);\n"
        "    }\n"
        "  }\n"
    )
    new_mic_finally = (
        "    } catch (e) {\n"
        "      _toast('$e'.replaceFirst('Exception: ', ''));\n"
        "    } finally {\n"
        f"      _syncModelSizeDisplay(); // {MARKER}\n"
        "      if (mounted) setState(() => _listening = false);\n"
        "    }\n"
        "  }\n"
    )
    text = replace_once(text, old_mic_finally, new_mic_finally, "home_screen _micDetect finally sync")

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    results = {
        "lib/services/whisper_service.dart": patch_whisper_service(project_dir),
        "lib/screens/home_screen.dart": patch_home_screen(project_dir),
    }
    for path, changed in results.items():
        print(f"{'OK: patched' if changed else 'SKIP: already applied'} {path}")

    print()
    print("Next steps:")
    print("  git add lib/services/whisper_service.dart lib/screens/home_screen.dart")
    print("  git commit -m 'S75: compact model picker + graceful fallback on failed model download'")
    print("  git push")
    print()
    print("REQUIRED MANUAL STEP to actually fix the 404 (not something this patch")
    print("can do from Termux): GitHub repo -> Actions tab -> run")
    print("'Prepare Quran-tuned Whisper model (one-time / on-demand)'. Until that's")
    print("done, دقة القرآن will keep falling back to دقيق automatically -- gracefully")
    print("now, instead of erroring out mid auto-sync/detect.")
    print()
    print("HOW TO VERIFY: Settings should now show one compact row under 'دقة التعرّف")
    print("على الكلام' instead of 5 stacked cards; tapping it opens a bottom sheet with")
    print("all 5 tiers. Select دقة القرآن, then run mic/video detect or auto-sync --")
    print("it should silently fall back to دقيق and toast about the switch instead of")
    print("throwing an HTTP 404 at you.")


if __name__ == "__main__":
    main()
