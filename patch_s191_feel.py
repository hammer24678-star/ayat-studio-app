#!/usr/bin/env python3
"""
patch_s191_feel.py - Ayat Studio S191 (run from repo root, after S190)

  * Text on the stage (drag / pinch): no more state change + full rebuild on
    every touch event. A live copy follows the finger and only that overlay
    repaints; the change is committed once on lift (one clean undo step).
    New magnets with a tick: horizontal centre, the preset line, 100% size.
  * Back button is gentle: closes an open tool panel first, then clears the
    selection, then needs a second press (2 s) to leave the studio, so a
    stray swipe no longer throws the project away.
  * Undo / redo give a tick.

Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S191_FEEL'
if not os.path.exists('lib/screens/home_screen.dart'):
    sys.exit('Run from the repo root (missing lib/screens/home_screen.dart).')

FILES = {
  'lib/widgets/stage_preview.dart': [
    ('import', "import 'package:flutter/material.dart';\nimport 'package:video_player/video_player.dart';\n", "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart' show HapticFeedback; // PATCH_S191_FEEL\nimport 'package:video_player/video_player.dart';\n"),
    ('fields', '  Timer? _grainTimer;\n', '  Timer? _grainTimer;\n  // PATCH_S191_FEEL\n  final ValueNotifier<_TextLive?> _textLive = ValueNotifier<_TextLive?>(null);\n  Offset _rawOff = Offset.zero;\n  bool _snapX = false, _snapY = false, _snapS = false;\n'),
    ('dispose', '    _tapFlashTimer?.cancel();\n    super.dispose();\n', '    _tapFlashTimer?.cancel();\n    _textLive.dispose(); // PATCH_S191_FEEL\n    super.dispose();\n'),
    ('gesture', '      onScaleStart: (_) => gestureStartUserScale = state.textUserScale,\n      onScaleUpdate: (details) {\n        state.update(() {\n          state.textOffset += details.focalPointDelta / scale;\n          state.textUserScale =\n              (gestureStartUserScale * details.scale).clamp(0.4, 3.0); // PATCH_S183_TEXT_BAR\n        });\n      },\n', '      onScaleStart: (_) {\n        gestureStartUserScale = state.textUserScale;\n        _rawOff = state.textOffset;\n        _snapX = _snapY = _snapS = false;\n        _textLive.value = _TextLive(state.textOffset, state.textUserScale);\n      },\n      onScaleUpdate: (details) {\n        // PATCH_S191_FEEL: no per-frame state change. The finger moves a live\n        // copy; centre / preset line / 100% size magnet with a tick.\n        _rawOff += details.focalPointDelta / (scale <= 0 ? 1.0 : scale);\n        final tol = 8 / (scale <= 0 ? 1.0 : scale);\n        var ox = _rawOff.dx, oy = _rawOff.dy;\n        final sx = ox.abs() < tol, sy = oy.abs() < tol;\n        if (sx) ox = 0;\n        if (sy) oy = 0;\n        var s = (gestureStartUserScale * details.scale).clamp(0.4, 3.0).toDouble();\n        final ss = (s - 1.0).abs() < 0.04;\n        if (ss) s = 1.0;\n        if ((sx && !_snapX) || (sy && !_snapY) || (ss && !_snapS)) {\n          HapticFeedback.selectionClick();\n        }\n        _snapX = sx;\n        _snapY = sy;\n        _snapS = ss;\n        _textLive.value = _TextLive(Offset(ox, oy), s);\n      },\n      onScaleEnd: (_) {\n        final l = _textLive.value;\n        _textLive.value = null;\n        if (l == null) return;\n        if (l.offset == state.textOffset && l.scale == state.textUserScale) return;\n        state.update(() {\n          state.textOffset = l.offset;\n          state.textUserScale = l.scale;\n        });\n      },\n'),
    ('head', '      child: Transform.translate(\n        offset: Offset(\n            state.textOffset.dx * scale, state.textOffset.dy * scale),\n        child: Align(\n          alignment: Alignment(0, alignY),\n', '      // PATCH_S191_FEEL: while a finger is down only this builder repaints\n      // (live offset / size); the change is committed once, on lift.\n      child: ValueListenableBuilder<_TextLive?>(\n        valueListenable: _textLive,\n        builder: (context, liveT, inner) {\n          final off = liveT?.offset ?? state.textOffset;\n          final k = liveT == null ? 1.0 : liveT.scale / state.textUserScale;\n          return Transform.translate(\n            offset: Offset(off.dx * scale, off.dy * scale),\n            child: Align(\n              alignment: Alignment(0, alignY),\n              child: Transform.scale(scale: k, child: inner),\n            ),\n          );\n        },\n'),
    ('tail', '          ),\n        ),\n      ),\n    );\n  }\n}\n\n\n// PATCH_S126_TEXT_TRANSITIONS', '          ),\n      ),\n    );\n  }\n}\n\n\n// PATCH_S126_TEXT_TRANSITIONS'),
    ('live class', 'class _MotionScope extends InheritedWidget {\n', "// PATCH_S191_FEEL: the text's position / size while a finger is on it.\nclass _TextLive {\n  final Offset offset;\n  final double scale;\n  const _TextLive(this.offset, this.scale);\n}\n\nclass _MotionScope extends InheritedWidget {\n"),
  ],
  'lib/screens/home_screen.dart': [
    ('services import', 'show HapticFeedback, SystemChrome, SystemUiMode, rootBundle;', 'show HapticFeedback, SystemChrome, SystemNavigator, SystemUiMode, rootBundle;'),
    ('back methods', '  void _showInfo() => showAyatInfoDialog(context);\n', "  // ---- PATCH_S191_FEEL: back does the gentle thing first ----------------\n  DateTime _lastBack = DateTime.fromMillisecondsSinceEpoch(0);\n\n  void _onBack(bool didPop, Object? result) {\n    if (didPop) return;\n    if (_toolOpen != -1) {\n      setState(() => _toolOpen = -1);\n      return;\n    }\n    if (_hasSelSeg ||\n        _hasSelCue ||\n        _hasSelMain ||\n        state.stageTextSelected ||\n        state.hasPipSel) {\n      state.clearStageSelection();\n      state.selectPip(-1);\n      setState(() {\n        _selSeg = -1;\n        _selCue = -1;\n        _selMain = false;\n      });\n      return;\n    }\n    final now = DateTime.now();\n    if (state.hasVideo &&\n        now.difference(_lastBack) > const Duration(seconds: 2)) {\n      _lastBack = now;\n      _toast('اضغط رجوع مرة أخرى للخروج');\n      return;\n    }\n    SystemNavigator.pop();\n  }\n\n  void _showInfo() => showAyatInfoDialog(context);\n"),
    ('popscope', '  Widget build(BuildContext context) {\n    return Scaffold(\n      backgroundColor: AyatColors.ink,\n', '  Widget build(BuildContext context) => PopScope(\n        canPop: false,\n        onPopInvokedWithResult: _onBack, // PATCH_S191_FEEL\n        child: _studioScaffold(context),\n      );\n\n  Widget _studioScaffold(BuildContext context) {\n    return Scaffold(\n      backgroundColor: AyatColors.ink,\n'),
    ('undo haptic', 'onPressed: state.canUndo ? state.undoStep : null,', 'onPressed: state.canUndo ? () { HapticFeedback.selectionClick(); state.undoStep(); } : null, // PATCH_S191_FEEL'),
    ('redo haptic', 'onPressed: state.canRedo ? state.redoStep : null,', 'onPressed: state.canRedo ? () { HapticFeedback.selectionClick(); state.redoStep(); } : null, // PATCH_S191_FEEL'),
  ],
}

def read(p):
    return open(p, encoding='utf-8').read()

if all(MARK in read(p) for p in FILES):
    print('  OK      already applied'); sys.exit(0)

bad = []
texts = {}
for path, edits in FILES.items():
    if not os.path.exists(path):
        bad.append('%s (file missing)' % path); continue
    t = read(path)
    if MARK in t:
        bad.append('%s (already contains %s - restore it with git checkout first)' % (path, MARK)); continue
    for label, old, new in edits:
        n = t.count(old)
        if n != 1:
            bad.append('%s - %s (found %d)' % (path, label, n))
    texts[path] = t
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for path, edits in FILES.items():
    t = texts[path]
    for label, old, new in edits:
        t = t.replace(old, new, 1)
        print('  PATCHED %s - %s' % (path, label))
    open(path, 'w', encoding='utf-8').write(t)
print('S191 applied. Next: git add -A && git commit -m "S191: stage text feel, gentle back" && git push')
