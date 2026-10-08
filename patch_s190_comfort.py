#!/usr/bin/env python3
"""
patch_s190_comfort.py - Ayat Studio S190 (run from repo root, after S189)

Control + smoothness.

  * Scrubbing: the timeline ruler keeps one seek in flight and only the newest
    target waits, so the picture stays with the finger instead of trailing it.
  * Jog: drag the time readout (left of the transport) sideways - one frame
    per ~5 px, tick every second, playback pauses while you jog.
  * «إزاحة دقيقة» in the action bar of a selected ayah / text block / PIP:
    a short sheet (preview stays visible) - choose start / end / whole block
    and step by 1 frame, 0.1 s or 1 s; hold to repeat. Every step moves the
    playhead to the edited edge. Keeps the block inside the clip; undo works.

Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S190_COMFORT'
if not os.path.exists('lib/screens/home_screen.dart'):
    sys.exit('Run from the repo root (missing lib/screens/home_screen.dart).')

NEW_FILES = {
'lib/widgets/nudge_sheet.dart': r'''// PATCH_S190_COMFORT: precise placement of the selected block.
//
// A short sheet that leaves the preview visible. Pick what to move (start,
// end, or the whole block) and tap - or hold - the step buttons:
// 1 frame, 0.1 s, 1 s, both directions. Holding repeats, and every step shows
// the result at once because the caller moves the playhead to the edge.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ayat_theme.dart';

Future<void> showNudgeSheet(
  BuildContext context, {
  required String title,
  required bool canMove,
  required double frame,
  required (double, double) Function() range,
  required void Function(int mode, double delta) onNudge,
}) {
  return showModalBottomSheet<void>(
    context: context,
    barrierColor: Colors.transparent,
    backgroundColor: AyatColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _NudgeSheet(
      title: title,
      canMove: canMove,
      frame: frame,
      range: range,
      onNudge: onNudge,
    ),
  );
}

class _NudgeSheet extends StatefulWidget {
  final String title;
  final bool canMove;
  final double frame;
  final (double, double) Function() range;
  final void Function(int mode, double delta) onNudge;
  const _NudgeSheet({
    required this.title,
    required this.canMove,
    required this.frame,
    required this.range,
    required this.onNudge,
  });

  @override
  State<_NudgeSheet> createState() => _NudgeSheetState();
}

class _NudgeSheetState extends State<_NudgeSheet> {
  late int _mode = widget.canMove ? 2 : 0; // 0 start, 1 end, 2 whole block

  static String _fmt(double s) {
    final m = s ~/ 60;
    final sec = s - m * 60;
    return '$m:${sec.toStringAsFixed(2).padLeft(5, '0')}';
  }

  void _step(double d) {
    widget.onNudge(_mode, d);
    if (mounted) setState(() {});
  }

  Widget _btn(String label, double d) => Expanded(
        child: _Hold(
          onStep: () => _step(d),
          child: Container(
            height: 46,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AyatColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AyatColors.hairline),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AyatColors.parchment)),
          ),
        ),
      );

  Widget _modeChip(int m, String label) {
    final on = _mode == m;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _mode = m);
        },
        child: Container(
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AyatColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: on ? AyatColors.gold : AyatColors.hairline),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: on ? AyatColors.ink : AyatColors.parchmentDim)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = widget.range();
    final f = widget.frame;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AyatColors.parchment)),
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('${_fmt(a)}  →  ${_fmt(b)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AyatColors.goldBright,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _modeChip(0, 'البداية'),
                _modeChip(1, 'النهاية'),
                if (widget.canMove) _modeChip(2, 'الكل'),
              ]),
              const SizedBox(height: 10),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  _btn('−1ث', -1.0),
                  _btn('−0.1', -0.1),
                  _btn('−إطار', -f),
                  _btn('+إطار', f),
                  _btn('+0.1', 0.1),
                  _btn('+1ث', 1.0),
                ]),
              ),
              const SizedBox(height: 6),
              const Text('اضغط مطولًا للتكرار',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AyatColors.parchmentDim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap = one step; hold = steps repeat, getting out of the way of the finger.
class _Hold extends StatefulWidget {
  final Widget child;
  final VoidCallback onStep;
  const _Hold({required this.child, required this.onStep});

  @override
  State<_Hold> createState() => _HoldState();
}

class _HoldState extends State<_Hold> {
  Timer? _t;

  void _start() {
    HapticFeedback.selectionClick();
    widget.onStep();
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 380), () {
      _t = Timer.periodic(
          const Duration(milliseconds: 70), (_) => widget.onStep());
    });
  }

  void _stop() {
    _t?.cancel();
    _t = null;
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: widget.child,
      );
}
''',
}

FILES = {
  'lib/widgets/pro_timeline.dart': [
    ('seek', '  void _seekSec(double sec) {\n    final ms = (sec.clamp(0.0, _dur) * 1000).round();\n    widget.controller.seekTo(Duration(milliseconds: ms));\n  }\n', '  // PATCH_S190_COMFORT: one seek in flight, only the newest target waits.\n  // Dragging the ruler used to queue a seek per touch event on the player, so\n  // the picture trailed the finger; now it always jumps to where it is now.\n  bool _seekBusy = false;\n  int? _seekPend;\n\n  void _seekMs(int ms) {\n    if (_seekBusy) {\n      _seekPend = ms;\n      return;\n    }\n    _seekBusy = true;\n    widget.controller\n        .seekTo(Duration(milliseconds: ms))\n        .catchError((_) {})\n        .whenComplete(() {\n      _seekBusy = false;\n      final p = _seekPend;\n      _seekPend = null;\n      if (p != null && mounted) _seekMs(p);\n    });\n  }\n\n  void _seekSec(double sec) {\n    _seekMs((sec.clamp(0.0, _dur) * 1000).round());\n  }\n'),
  ],
  'lib/screens/home_screen.dart': [
    ('import', "import '../widgets/quran_text_sheet.dart'; // PATCH_S189_QURAN_TYPE\n", "import '../widgets/quran_text_sheet.dart'; // PATCH_S189_QURAN_TYPE\nimport '../widgets/nudge_sheet.dart'; // PATCH_S190_COMFORT\n"),
    ('methods', '  Widget _proTransport() {\n', "  // ---- PATCH_S190_COMFORT ----------------------------------------------\n  // Newest-wins seeking for jogging, and the fine-nudge sheet.\n  bool _seekBusyH = false;\n  int? _seekPendH;\n\n  void _seekCoalesced(int ms) {\n    final c = _video;\n    if (c == null || !c.value.isInitialized) return;\n    if (_seekBusyH) {\n      _seekPendH = ms;\n      return;\n    }\n    _seekBusyH = true;\n    c.seekTo(Duration(milliseconds: ms)).catchError((_) {}).whenComplete(() {\n      _seekBusyH = false;\n      final p = _seekPendH;\n      _seekPendH = null;\n      if (p != null && mounted) _seekCoalesced(p);\n    });\n  }\n\n  double _jogAcc = 0;\n  int _jogBaseMs = 0;\n  int _jogLastSec = -1;\n\n  void _jogStart() {\n    final c = _video;\n    if (c == null || !c.value.isInitialized) return;\n    if (c.value.isPlaying) c.pause();\n    _jogAcc = 0;\n    _jogBaseMs = c.value.position.inMilliseconds;\n    _jogLastSec = _jogBaseMs ~/ 1000;\n    HapticFeedback.selectionClick();\n  }\n\n  // Drag the time readout: one frame per ~5 px, a tick every second crossed.\n  void _jogUpdate(double dx) {\n    final c = _video;\n    if (c == null || !c.value.isInitialized) return;\n    _jogAcc += dx;\n    final fps = state.exportFps.clamp(24, 60);\n    final frames = (_jogAcc / 5.0).round();\n    final total = c.value.duration.inMilliseconds;\n    final ms = (_jogBaseMs + (frames * 1000 / fps).round()).clamp(0, total);\n    if (ms ~/ 1000 != _jogLastSec) {\n      _jogLastSec = ms ~/ 1000;\n      HapticFeedback.selectionClick();\n    }\n    _seekCoalesced(ms);\n  }\n\n  Future<void> _openNudgeSheet() async {\n    final isSeg = _hasSelSeg;\n    final isCue = !isSeg && _hasSelCue;\n    final isPip = !isSeg && !isCue && state.hasPipSel;\n    if (!isSeg && !isCue && !isPip) return;\n    final si = _selSeg, ci = _selCue, pi = state.pipSel;\n    final total = (_video?.value.duration.inMilliseconds ?? 0) / 1000.0;\n    final fps = state.exportFps.clamp(24, 60);\n\n    (double, double) range() {\n      if (isSeg && si < state.timeline.length) {\n        return (state.timeline[si].start, state.timeline[si].end);\n      }\n      if (isCue && ci < state.textTimeCues.length) {\n        return (state.textTimeCues[ci].start, state.textTimeCues[ci].end);\n      }\n      if (isPip && pi < state.pipClips.length) {\n        return (state.pipClips[pi].start, state.pipClips[pi].end);\n      }\n      return (0.0, 0.0);\n    }\n\n    void nudge(int mode, double d) {\n      final (s0, e0) = range();\n      if (e0 <= s0) return;\n      // keep the whole block inside the clip when moving it\n      var dd = d;\n      if (mode == 2) {\n        if (s0 + dd < 0) dd = -s0;\n        if (total > 0 && e0 + dd > total) dd = total - e0;\n      }\n      if (mode == 1 && total > 0 && e0 + dd > total) dd = total - e0;\n      if (dd == 0) return;\n      if (isSeg) {\n        state.nudgeTimelineSegment(si,\n            startDelta: mode == 0 ? dd : 0, endDelta: mode == 1 ? dd : 0);\n      } else if (isCue) {\n        state.pushHistory();\n        state.setTextCueWindow(ci,\n            start: mode == 1 ? null : s0 + dd, end: mode == 0 ? null : e0 + dd);\n      } else {\n        state.pushHistory();\n        if (mode == 2) {\n          state.movePipTo(pi, s0 + dd);\n        } else {\n          state.setPipWindow(pi,\n              start: mode == 0 ? s0 + dd : null,\n              end: mode == 1 ? e0 + dd : null);\n        }\n      }\n      final (s1, e1) = range();\n      final at = mode == 1 ? max(s1, e1 - 0.05) : s1;\n      _seekCoalesced((at * 1000).round());\n    }\n\n    await showNudgeSheet(\n      context,\n      title: isSeg ? 'إزاحة دقيقة — آية' : (isCue ? 'إزاحة دقيقة — نص' : 'إزاحة دقيقة — PIP'),\n      canMove: !isSeg,\n      frame: 1.0 / fps,\n      range: range,\n      onNudge: nudge,\n    );\n  }\n\n  Widget _proTransport() {\n"),
    ('jog', '                    onTap: _goToTime, // PATCH_S179_AAA\n', '                    onTap: _goToTime, // PATCH_S179_AAA\n                    onHorizontalDragStart: (_) => _jogStart(), // PATCH_S190_COMFORT\n                    onHorizontalDragUpdate: (d) => _jogUpdate(d.delta.dx),\n'),
    ('seg bar', "      (Icons.tune, 'التوقيت', () => _editSegmentTiming(i), false),\n", "      (Icons.tune, 'التوقيت', () => _editSegmentTiming(i), false),\n      (Icons.straighten, 'إزاحة دقيقة', _openNudgeSheet, false), // PATCH_S190_COMFORT\n"),
    ('cue bar', "      (Icons.edit_outlined, 'تعديل النص', () => _cueEditText(i), false),\n", "      (Icons.edit_outlined, 'تعديل النص', () => _cueEditText(i), false),\n      (Icons.straighten, 'إزاحة دقيقة', _openNudgeSheet, false), // PATCH_S190_COMFORT\n"),
    ('pip bar', "      (Icons.content_copy, 'نسخ', () => state.duplicatePipAt(i), false),\n", "      (Icons.straighten, 'إزاحة دقيقة', _openNudgeSheet, false), // PATCH_S190_COMFORT\n      (Icons.content_copy, 'نسخ', () => state.duplicatePipAt(i), false),\n"),
  ],
}

def read(p):
    return open(p, encoding='utf-8').read()

if all(os.path.exists(p) for p in NEW_FILES) and MARK in read('lib/screens/home_screen.dart'):
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
for p in NEW_FILES:
    if os.path.exists(p):
        bad.append('%s already exists' % p)
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for path, edits in FILES.items():
    t = texts[path]
    for label, old, new in edits:
        t = t.replace(old, new, 1)
        print('  PATCHED %s - %s' % (path, label))
    open(path, 'w', encoding='utf-8').write(t)
for p, body in NEW_FILES.items():
    os.makedirs(os.path.dirname(p) or '.', exist_ok=True)
    open(p, 'w', encoding='utf-8').write(body)
    print('  CREATED %s' % p)
print('S190 applied. Next: git add -A && git commit -m "S190: smooth scrub, jog, fine nudge" && git push')
