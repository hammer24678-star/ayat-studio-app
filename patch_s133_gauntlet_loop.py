# patch_s133_gauntlet_loop.py
# Gauntlet Loop S133 — scoped to exactly the first item S132 flagged as
# "real, scoped, not guessed at": tap the ayah text on the stage -> a dashed
# gold selection box appears -> double-tap opens an edit dialog -> the
# correction is written back to the matching TimelineSegment (or to
# ayahText when nothing from the timeline is live) and flows into both the
# karaoke preview and the export with no further wiring.
#
# Every anchor below was checked with view/grep against the actual current
# source (ayat_studio_app_dump_20260828_103927.txt) before being written
# into this script — same discipline S132 used once it had the real dump.
# Run from the project root.
#
# What this pass does, and why each piece is where it is:
#
# 1. lib/models/studio_state.dart
#    - TimelineSegment.textOverride loses `final`. It was write-once from
#      the constructor (S118's partial-ayah slicing); the edit dialog now
#      corrects it in place instead of rebuilding the segment.
#    - New StudioState.selectedSegment field + selectStageText() /
#      clearStageSelection() / applyStageTextEdit(). stageTextSelected
#      already existed (S128) but, like SelectionBoxPainter/WordHitTester,
#      was never wired to anything real — grep confirms the only two hits
#      in the whole repo are its own declaration and a dead comment in
#      overlay_renderer.dart.
#    - applyStageTextEdit() writes to selectedSegment.textOverride when a
#      timeline segment is live. karaoke.dart's buildKaraokeChunks() ALREADY
#      reads `seg.textOverride ?? seg.ayah.ar` (confirmed at the real
#      source, not assumed) and that function is shared verbatim by the
#      live preview (home_screen._tickAutoSync) and the exporter
#      (export_service._renderKaraokeSequence) per its own file header —
#      so a correction reaches both automatically. No exporter change
#      needed for this pass; the exporter was already reading the field
#      S118 added, it just had nothing upstream ever writing to it after
#      construction.
#    - Bug found while wiring this, fixed in the same file since it
#      directly undermines the new feature's correctness: _capture()'s
#      undo/redo snapshot rebuilds every TimelineSegment WITHOUT its
#      `inferred`/`textOverride` fields, so any stage-text correction (or
#      an inferred-gap flag) silently reverted on the next unrelated
#      undo/redo. Fixed by carrying both over. undoStep()/redoStep() also
#      now drop the live selection, since _apply() replaces `timeline`
#      with fresh TimelineSegment objects and a selection pointing at the
#      old ones would otherwise dangle.
#
# 2. lib/widgets/selection_box_overlay.dart
#    - SelectionBoxPainter previously did nothing when `box` was empty,
#      even if `active` was true — it expected a caller to hand it an
#      already-computed on-screen Rect. Rather than have the stage
#      reimplement that Rect by hand (a second source of truth for
#      exactly where the text painted, guaranteed to drift from Flutter's
#      own text layout), an empty box now means "draw around whatever
#      this CustomPaint was sized to" — see (3).
#
# 3. lib/widgets/stage_preview.dart
#    - _overlay()'s existing GestureDetector (the one that already handles
#      drag-to-reposition and pinch-to-resize on the ayah text, plus a
#      double-tap that reset them) gets onTap (toggle selection) and a
#      revised onDoubleTap (open the editor once selected; falls back to
#      the old reset-position behavior otherwise, so nothing already
#      relying on it breaks).
#    - The Container holding the ayah/translation Column is wrapped in a
#      CustomPaint(foregroundPainter: SelectionBoxPainter(...)). CustomPaint
#      sizes a foregroundPainter to match its child automatically, which is
#      what lets (2) use an empty box — no manual text-metrics duplication
#      of WordHitTester's coordinate space was needed for this box-level
#      (not per-word) selection.
#    - New _liveSegment() mirrors home_screen._tickAutoSync's own
#      `state.segmentAt(t)` lookup so the editor targets the exact segment
#      on screen. New _openStageTextEditor() is styled like
#      home_screen._pickAyahCandidate's AlertDialog (same backgroundColor/
#      shape/border) so it reads as part of the same app.
#    - _togglePlayback() (the full-stage tap-to-pause/resume handler)
#      dismisses an open selection first instead of also pausing the
#      video underneath it, since a tap just outside the text's own
#      GestureDetector still lands on this translucent layer.
#
# 4. lib/i18n/app_strings.dart — 'stage.editText' / 'stage.editSave' keys,
#    5 languages each, matching the file's existing convention exactly.
#    'common.cancel' already existed and is reused rather than duplicated.
#
# NOT covered by this pass (still real, still scoped, still not guessed at):
#   - AI auto-segmentation wizard (screenshots: Auto-Segmentation Wizard —
#     AI Version / Runtime / Models / Segmentation / Run). No wizard exists;
#     whisper_service.dart/speech_service.dart give the underlying
#     transcription, but the multi-step version/runtime/model/preset/review
#     UI is a new build, not a patch — S132's note on this stands unchanged.
#   - Full-page i18n. home_screen.dart alone has ~226 hardcoded Arabic
#     string literals vs the handful of real _t()/AppStrings calls; still
#     too large to guess through safely in one patch.
#
# Strict anchors abort; nothing here is soft — every literal was verified
# against the real file with `view`/`grep` before being written into this
# script.

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

def _log(label, status, detail=""):
    LEDGER.append((label, status))
    print(f" [{status}] {label}" + (f" — {detail}" if detail else ""))

def apply_literal(rel, old, new, label, skip_if=None):
    p = ROOT / rel
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel} does not exist")
    text = p.read_text(encoding="utf-8")
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY"); return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")

def main():
    # ======================================================================
    # 1) lib/models/studio_state.dart
    # ======================================================================

    # 1a) TimelineSegment.textOverride: final -> mutable
    apply_literal("lib/models/studio_state.dart",
        "  // ayah, the sliced text lives here -- null means \"use ayah.ar as-is\".\n"
        "  final String? textOverride;\n"
        "  TimelineSegment({\n",
        "  // ayah, the sliced text lives here -- null means \"use ayah.ar as-is\".\n"
        "  // PATCH_S133_STAGE_TEXT_SELECT_EDIT: no longer final -- the stage-text\n"
        "  // edit dialog corrects it in place instead of rebuilding the segment.\n"
        "  String? textOverride;\n"
        "  TimelineSegment({\n",
        "TimelineSegment.textOverride: final -> mutable",
        skip_if="PATCH_S133_STAGE_TEXT_SELECT_EDIT: no longer final")

    # 1b) StudioState: selectedSegment field + select/clear/apply-edit methods
    apply_literal("lib/models/studio_state.dart",
        "  List<String> unifiedTexts = const [];\n"
        "  bool stageTextSelected = false;\n"
        "  // PATCH_S128_FIX1_BUILD_ERRORS: fields the S128 glow tab/settings persistence needed\n",
        "  List<String> unifiedTexts = const [];\n"
        "  bool stageTextSelected = false;\n"
        "  // PATCH_S133_STAGE_TEXT_SELECT_EDIT: which TimelineSegment the selection\n"
        "  // box on the stage is currently around -- null while stageTextSelected\n"
        "  // is showing the statically-picked ayah (no auto-sync timeline playing,\n"
        "  // or playback is between segments) rather than a live timeline part.\n"
        "  TimelineSegment? selectedSegment;\n"
        "\n"
        "  void selectStageText([TimelineSegment? segment]) {\n"
        "    stageTextSelected = true;\n"
        "    selectedSegment = segment;\n"
        "    notifyListeners();\n"
        "  }\n"
        "\n"
        "  void clearStageSelection() {\n"
        "    if (!stageTextSelected && selectedSegment == null) return;\n"
        "    stageTextSelected = false;\n"
        "    selectedSegment = null;\n"
        "    notifyListeners();\n"
        "  }\n"
        "\n"
        "  /// Writes a correction back to whichever text is currently selected on\n"
        "  /// the stage: the segment's textOverride during auto-sync playback --\n"
        "  /// buildKaraokeChunks() already reads textOverride ahead of ayah.ar, so\n"
        "  /// the live karaoke preview and the exporter both pick this up with no\n"
        "  /// further wiring -- or ayahText when nothing from the timeline is\n"
        "  /// selected (the statically-picked ayah).\n"
        "  void applyStageTextEdit(String newText) {\n"
        "    final trimmed = newText.trim();\n"
        "    if (trimmed.isEmpty) return;\n"
        "    pushHistory();\n"
        "    if (selectedSegment != null) {\n"
        "      selectedSegment!.textOverride = trimmed;\n"
        "    } else {\n"
        "      ayahText = trimmed;\n"
        "      // PATCH_S133_STAGE_TEXT_SELECT_EDIT: a hand correction can change the\n"
        "      // word count/order -- a previous red-word selection almost never\n"
        "      // still lines up (same reasoning as setAyah()).\n"
        "      redWordIndices = {};\n"
        "    }\n"
        "    notifyListeners();\n"
        "  }\n"
        "  // PATCH_S128_FIX1_BUILD_ERRORS: fields the S128 glow tab/settings persistence needed\n",
        "StudioState: selectedSegment field + select/clear/apply-edit methods",
        skip_if="TimelineSegment? selectedSegment;")

    # 1c) _capture(): carry inferred/textOverride into the undo/redo snapshot
    #     (real bug: they were dropped, which would silently revert a
    #     stage-text edit on the next unrelated undo/redo)
    apply_literal("lib/models/studio_state.dart",
        "        'timeline': [\n"
        "          for (final s in timeline)\n"
        "            TimelineSegment(\n"
        "                start: s.start,\n"
        "                end: s.end,\n"
        "                ayah: s.ayah,\n"
        "                confidence: s.confidence,\n"
        "                wordStarts: List.of(s.wordStarts)),\n"
        "        ],\n",
        "        'timeline': [\n"
        "          for (final s in timeline)\n"
        "            TimelineSegment(\n"
        "                start: s.start,\n"
        "                end: s.end,\n"
        "                ayah: s.ayah,\n"
        "                confidence: s.confidence,\n"
        "                wordStarts: List.of(s.wordStarts),\n"
        "                // PATCH_S133_STAGE_TEXT_SELECT_EDIT: undo/redo rebuilds the\n"
        "                // timeline from this snapshot -- without carrying these\n"
        "                // over, a stage-text correction (or an inferred-gap flag)\n"
        "                // would silently vanish on the next unrelated undo/redo.\n"
        "                inferred: s.inferred,\n"
        "                textOverride: s.textOverride),\n"
        "        ],\n",
        "_capture(): carry inferred/textOverride into undo/redo snapshot",
        skip_if="undo/redo rebuilds the\n                // timeline from this snapshot")

    # 1d) undoStep()/redoStep(): drop a dangling selection after _apply()
    #     replaces `timeline` with fresh TimelineSegment objects
    apply_literal("lib/models/studio_state.dart",
        "  void undoStep() {\n"
        "    if (_undoStack.isEmpty) return;\n"
        "    _redoStack.add(_capture());\n"
        "    _restoring = true;\n"
        "    _apply(_undoStack.removeLast());\n"
        "    _restoring = false;\n"
        "    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);\n"
        "    notifyListeners();\n"
        "  }\n"
        "\n"
        "  void redoStep() {\n"
        "    if (_redoStack.isEmpty) return;\n"
        "    _undoStack.add(_capture());\n"
        "    _restoring = true;\n"
        "    _apply(_redoStack.removeLast());\n"
        "    _restoring = false;\n"
        "    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);\n"
        "    notifyListeners();\n"
        "  }\n"
        "}\n",
        "  void undoStep() {\n"
        "    if (_undoStack.isEmpty) return;\n"
        "    _redoStack.add(_capture());\n"
        "    _restoring = true;\n"
        "    _apply(_undoStack.removeLast());\n"
        "    // PATCH_S133_STAGE_TEXT_SELECT_EDIT: _apply() rebuilds `timeline` with\n"
        "    // fresh TimelineSegment objects, so any selection pointing at the old\n"
        "    // ones is now dangling -- drop it rather than risk editing a segment\n"
        "    // that is no longer part of the timeline.\n"
        "    selectedSegment = null;\n"
        "    stageTextSelected = false;\n"
        "    _restoring = false;\n"
        "    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);\n"
        "    notifyListeners();\n"
        "  }\n"
        "\n"
        "  void redoStep() {\n"
        "    if (_redoStack.isEmpty) return;\n"
        "    _undoStack.add(_capture());\n"
        "    _restoring = true;\n"
        "    _apply(_redoStack.removeLast());\n"
        "    // PATCH_S133_STAGE_TEXT_SELECT_EDIT: same as undoStep() above.\n"
        "    selectedSegment = null;\n"
        "    stageTextSelected = false;\n"
        "    _restoring = false;\n"
        "    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);\n"
        "    notifyListeners();\n"
        "  }\n"
        "}\n",
        "undoStep()/redoStep(): drop dangling selection after _apply()",
        skip_if="_apply() rebuilds `timeline` with\n    // fresh TimelineSegment objects")

    # ======================================================================
    # 2) lib/widgets/selection_box_overlay.dart — empty box = "use my own size"
    # ======================================================================
    apply_literal("lib/widgets/selection_box_overlay.dart",
        "  void paint(Canvas c, Size size) {\n"
        "    if (!active || box.isEmpty) return;\n"
        "    final r = box.inflate(10);\n",
        "  void paint(Canvas c, Size size) {\n"
        "    if (!active) return;\n"
        "    // PATCH_S133_STAGE_TEXT_SELECT_EDIT: an empty box now means \"draw\n"
        "    // around whatever this CustomPaint was sized to\" -- the stage wiring\n"
        "    // sizes the painter to exactly the selected text's own Container via\n"
        "    // CustomPaint's foregroundPainter auto-sizing, so it never has to\n"
        "    // compute the text's on-screen Rect by hand.\n"
        "    final r = (box.isEmpty ? Offset.zero & size : box).inflate(10);\n",
        "SelectionBoxPainter: empty box draws around own paint size",
        skip_if="an empty box now means")

    # ======================================================================
    # 3) lib/widgets/stage_preview.dart
    # ======================================================================

    # 3a) import
    apply_literal("lib/widgets/stage_preview.dart",
        "import '../services/app_settings.dart';\n"
        "import 'motion.dart'; // PATCH_S126_TEXT_TRANSITIONS\n",
        "import '../services/app_settings.dart';\n"
        "import 'motion.dart'; // PATCH_S126_TEXT_TRANSITIONS\n"
        "import 'selection_box_overlay.dart'; // PATCH_S133_STAGE_TEXT_SELECT_EDIT\n",
        "stage_preview.dart: import selection_box_overlay.dart",
        skip_if="import 'selection_box_overlay.dart';")

    # 3b) _togglePlayback(): dismiss an open selection instead of also
    #     pausing/resuming the video underneath it
    apply_literal("lib/widgets/stage_preview.dart",
        "  void _togglePlayback() {\n"
        "    final c = widget.videoController;\n"
        "    if (c == null || !c.value.isInitialized) return;\n"
        "    final nowPlaying = !c.value.isPlaying;\n",
        "  void _togglePlayback() {\n"
        "    // PATCH_S133_STAGE_TEXT_SELECT_EDIT: the ayah text's own GestureDetector\n"
        "    // sits above this full-stage one and normally wins any tap that lands\n"
        "    // on the text itself -- but a tap that lands just outside it (still\n"
        "    // within this translucent layer) should close the selection box\n"
        "    // instead of also pausing/resuming the video underneath it.\n"
        "    if (widget.state.stageTextSelected) {\n"
        "      widget.state.clearStageSelection();\n"
        "      return;\n"
        "    }\n"
        "    final c = widget.videoController;\n"
        "    if (c == null || !c.value.isInitialized) return;\n"
        "    final nowPlaying = !c.value.isPlaying;\n",
        "_togglePlayback(): dismiss selection before pause/resume",
        skip_if="close the selection box")

    # 3c) new helper methods: _liveSegment() + _openStageTextEditor()
    apply_literal("lib/widgets/stage_preview.dart",
        "    c.seekTo(target);\n"
        "    _flash(forward ? Icons.forward_5 : Icons.replay_5);\n"
        "  }\n"
        "\n"
        "  @override\n"
        "  Widget build(BuildContext context) {\n",
        "    c.seekTo(target);\n"
        "    _flash(forward ? Icons.forward_5 : Icons.replay_5);\n"
        "  }\n"
        "\n"
        "  // PATCH_S133_STAGE_TEXT_SELECT_EDIT: the TimelineSegment currently on\n"
        "  // screen during auto-sync playback (same lookup home_screen._tickAutoSync\n"
        "  // uses), or null when just the statically-picked ayah is showing -- no\n"
        "  // active timeline, or playback is between two detected segments.\n"
        "  TimelineSegment? _liveSegment() {\n"
        "    final c = widget.videoController;\n"
        "    if (c == null || !c.value.isInitialized || !widget.state.timelineActive) {\n"
        "      return null;\n"
        "    }\n"
        "    return widget.state.segmentAt(c.value.position.inMilliseconds / 1000.0);\n"
        "  }\n"
        "\n"
        "  // PATCH_S133_STAGE_TEXT_SELECT_EDIT: opens once the stage text is\n"
        "  // selected (single tap) and then double-tapped. Styled like\n"
        "  // _pickAyahCandidate's AlertDialog in home_screen.dart so it reads as\n"
        "  // part of the same app rather than a bolted-on sheet.\n"
        "  Future<void> _openStageTextEditor(\n"
        "      BuildContext context, String currentText) async {\n"
        "    final state = widget.state;\n"
        "    final s = AppStrings(AppSettings.instance.lang);\n"
        "    final ctrl = TextEditingController(text: currentText);\n"
        "    final result = await showDialog<String>(\n"
        "      context: context,\n"
        "      builder: (context) => AlertDialog(\n"
        "        backgroundColor: AyatColors.surface,\n"
        "        shape: RoundedRectangleBorder(\n"
        "          borderRadius: BorderRadius.circular(22),\n"
        "          side: const BorderSide(color: AyatColors.hairline),\n"
        "        ),\n"
        "        title: Text(s.t('stage.editText')),\n"
        "        content: TextField(\n"
        "          controller: ctrl,\n"
        "          autofocus: true,\n"
        "          maxLines: 4,\n"
        "          textAlign: TextAlign.right,\n"
        "          textDirection: TextDirection.rtl,\n"
        "          style: const TextStyle(color: AyatColors.parchment),\n"
        "          decoration: const InputDecoration(border: OutlineInputBorder()),\n"
        "        ),\n"
        "        actions: [\n"
        "          TextButton(\n"
        "            onPressed: () => Navigator.pop(context),\n"
        "            child: Text(s.t('common.cancel')),\n"
        "          ),\n"
        "          TextButton(\n"
        "            onPressed: () => Navigator.pop(context, ctrl.text),\n"
        "            child: Text(s.t('stage.editSave')),\n"
        "          ),\n"
        "        ],\n"
        "      ),\n"
        "    );\n"
        "    ctrl.dispose();\n"
        "    if (result == null) return;\n"
        "    state.applyStageTextEdit(result);\n"
        "    state.clearStageSelection();\n"
        "  }\n"
        "\n"
        "  @override\n"
        "  Widget build(BuildContext context) {\n",
        "stage_preview.dart: add _liveSegment() + _openStageTextEditor()",
        skip_if="Future<void> _openStageTextEditor(")

    # 3d) _overlay(): onTap to select, onDoubleTap to edit-once-selected,
    #     CustomPaint(SelectionBoxPainter) wrapped around the text Container
    apply_literal("lib/widgets/stage_preview.dart",
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
        "    double gestureStartUserScale = state.textUserScale;\n"
        "    // PATCH_S133_STAGE_TEXT_SELECT_EDIT: the segment (if any) this specific\n"
        "    // build of the overlay is showing -- captured once here so onTap and\n"
        "    // onDoubleTap below both act on the exact text currently on screen,\n"
        "    // not a re-lookup that could have moved on by the time the user's\n"
        "    // second tap lands.\n"
        "    final liveSegment = _liveSegment();\n"
        "    return GestureDetector(\n"
        "      onTap: () {\n"
        "        if (state.stageTextSelected) {\n"
        "          state.clearStageSelection();\n"
        "        } else {\n"
        "          state.selectStageText(liveSegment);\n"
        "        }\n"
        "      },\n"
        "      onScaleStart: (_) => gestureStartUserScale = state.textUserScale,\n"
        "      onScaleUpdate: (details) {\n"
        "        state.update(() {\n"
        "          state.textOffset += details.focalPointDelta / scale;\n"
        "          state.textUserScale =\n"
        "              (gestureStartUserScale * details.scale).clamp(0.6, 1.8);\n"
        "        });\n"
        "      },\n"
        "      // PATCH_S133_STAGE_TEXT_SELECT_EDIT: double-tap now opens the text\n"
        "      // editor once the box is up (single-tap-to-select, then\n"
        "      // double-tap-to-edit) -- the old \"double-tap resets drag position\"\n"
        "      // shortcut still fires the rest of the time, so nothing already\n"
        "      // relying on it breaks.\n"
        "      onDoubleTap: () {\n"
        "        if (state.stageTextSelected) {\n"
        "          _openStageTextEditor(context, text);\n"
        "        } else {\n"
        "          state.update(() {\n"
        "            state.textOffset = Offset.zero;\n"
        "            state.textUserScale = 1.0;\n"
        "          });\n"
        "        }\n"
        "      },\n"
        "      child: Transform.translate(\n"
        "        offset: Offset(\n"
        "            state.textOffset.dx * scale, state.textOffset.dy * scale),\n"
        "        child: Align(\n"
        "          alignment: Alignment(0, alignY),\n"
        "          // PATCH_S133_STAGE_TEXT_SELECT_EDIT: dashed gold selection box +\n"
        "          // corner handles, reusing SelectionBoxPainter as-is (already\n"
        "          // themed with AyatColors) -- CustomPaint's foregroundPainter\n"
        "          // sizes itself to match its child automatically, so this never\n"
        "          // has to compute the text's on-screen Rect by hand.\n"
        "          child: CustomPaint(\n"
        "            foregroundPainter: SelectionBoxPainter(\n"
        "              box: Rect.zero,\n"
        "              active: state.stageTextSelected,\n"
        "            ),\n"
        "            child: Container(\n"
        "              margin: EdgeInsets.symmetric(horizontal: 0.07 * 270 * scale / 2),\n"
        "              padding: deco != null\n"
        "                  ? EdgeInsets.symmetric(\n"
        "                      horizontal: 14 * scale, vertical: 10 * scale)\n"
        "                  : EdgeInsets.zero,\n"
        "              decoration: deco,\n"
        "              child: Column(\n"
        "                mainAxisSize: MainAxisSize.min,\n"
        "                children: [\n"
        "                  ayahWidget,\n"
        "                  if (state.showTranslation && trans.isNotEmpty) ...[\n"
        "                    SizedBox(height: 4 * scale),\n"
        "                    Text(\n"
        "                      trans,\n"
        "                      textAlign: TextAlign.center,\n"
        "                      style: translationTextStyle(\n"
        "                        fontSize:\n"
        "                            state.transFontSize * scale * state.textUserScale,\n"
        "                        color: state.textColor.withValues(alpha: 0.88),\n"
        "                        shadows: shadows,\n"
        "                      ),\n"
        "                    ),\n"
        "                  ],\n"
        "                ],\n"
        "              ),\n"
        "            ),\n"
        "          ),\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n"
        "}\n",
        "_overlay(): onTap select / onDoubleTap edit / CustomPaint selection box",
        skip_if="final liveSegment = _liveSegment();")

    # ======================================================================
    # 4) lib/i18n/app_strings.dart: new translation keys (5 languages each)
    # ======================================================================
    apply_literal("lib/i18n/app_strings.dart",
        "'stage.hint': ['اختر آية، أو ارفع فيديو واستخدم التعرّف أو المزامنة التلقائية', 'Pick an ayah, or upload a video and use detection or auto-sync', 'Choisissez un verset, ou importez une vidéo avec détection ou synchro auto', 'Pilih ayat, atau unggah video dan gunakan deteksi atau sinkron otomatis', 'آیت منتخب کریں، یا ویڈیو اپ لوڈ کر کے شناخت یا آٹو سنک استعمال کریں'],\n",
        "'stage.hint': ['اختر آية، أو ارفع فيديو واستخدم التعرّف أو المزامنة التلقائية', 'Pick an ayah, or upload a video and use detection or auto-sync', 'Choisissez un verset, ou importez une vidéo avec détection ou synchro auto', 'Pilih ayat, atau unggah video dan gunakan deteksi atau sinkron otomatis', 'آیت منتخب کریں، یا ویڈیو اپ لوڈ کر کے شناخت یا آٹو سنک استعمال کریں'],\n"
        "// PATCH_S133_STAGE_TEXT_SELECT_EDIT: tap-to-select + double-tap-to-edit dialog.\n"
        "'stage.editText': ['تعديل النص الظاهر', 'Edit displayed text', 'Modifier le texte affiché', 'Edit teks yang ditampilkan', 'ظاہر ہونے والا متن ترمیم کریں'],\n"
        "'stage.editSave': ['حفظ', 'Save', 'Enregistrer', 'Simpan', 'محفوظ کریں'],\n",
        "app_strings.dart: add stage.editText/stage.editSave keys",
        skip_if="'stage.editText'")

    print()
    print("=" * 60)
    print(f"S133 LEDGER — {sum(1 for _, s in LEDGER if s == 'APPLIED')} applied, "
          f"{sum(1 for _, s in LEDGER if s == 'SKIPPED-ALREADY')} already-applied, "
          f"out of {len(LEDGER)} operations")
    print("=" * 60)
    for label, status in LEDGER:
        print(f"  [{status:16}] {label}")
    print()
    print("NOT covered by this pass (real, scoped, not guessed at):")
    print("  - AI auto-segmentation wizard. No wizard exists;")
    print("    whisper_service.dart/speech_service.dart give the underlying")
    print("    transcription, but the multi-step UI (version/runtime/models/")
    print("    presets/review) is a new build, not a patch.")
    print("  - Full-page i18n. home_screen.dart alone has ~226 hardcoded Arabic")
    print("    string literals vs a handful of real _t()/AppStrings calls --")
    print("    still too large to guess through safely in one patch.")
    print("  - Word-level (rather than box/segment-level) selection.")
    print("    WordHitTester exists and is untouched by this pass; the tap flow")
    print("    built here selects/edits a whole segment's text at once, which is")
    print("    what \"an edit dialog that writes back to the TimelineSegment\"")
    print("    asked for. Per-word tap targets are a separate, smaller follow-up")
    print("    if ever wanted -- not guessed at here.")

if __name__ == "__main__":
    main()
