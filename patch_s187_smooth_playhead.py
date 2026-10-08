#!/usr/bin/env python3
"""
patch_s187_smooth_playhead.py - Ayat Studio S187 (run from repo root, after S186)

InShot-style playback feel on the timeline:
  * The playhead glides at the screen's frame rate (it used to hop each time the
    video player reported its position, a few times a second).
  * While playing, the timeline scrolls smoothly under the playhead and keeps it
    in the middle of the screen (it used to jump a page when the playhead hit
    the edge). Touch the timeline to scroll it yourself and it lets go.
  * Zero cost while paused: the animation only runs during playback.
Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S187_SMOOTH_PLAYHEAD'
P = 'lib/widgets/pro_timeline.dart'
if not os.path.exists(P): sys.exit('Run from the repo root (missing %s).' % P)
t = open(P, encoding='utf-8').read()
if MARK in t: print('  OK      already applied'); sys.exit(0)

FOLLOW_START = "  /// While playing, keep the playhead on screen.\n  void _follow() {\n"
FOLLOW_END = "      _scroll.jumpTo(target);\n    }\n  }\n"
FOLLOW_NEW = """  // PATCH_S187_SMOOTH_PLAYHEAD: the player reports its position only a few
  // times a second, so the playhead is predicted from the wall clock between
  // reports (and snapped back if the prediction drifts or the user seeks).
  final Stopwatch _wall = Stopwatch()..start();
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  double _anchorPos = 0;
  double _anchorAt = 0;
  bool _wasPlaying = false;

  double get _nowSec => _wall.elapsedMicroseconds / 1e6;

  double _smoothSec(VideoPlayerValue v) {
    final p = v.position.inMilliseconds / 1000.0;
    if (!v.isPlaying) return p;
    final pred = _anchorPos + (_nowSec - _anchorAt) * v.playbackSpeed;
    if ((pred - p).abs() > 0.25) {
      _anchorPos = p;
      _anchorAt = _nowSec;
      return p;
    }
    return pred.clamp(0.0, _dur).toDouble();
  }

  /// Starts / stops the frame ticker with playback.
  void _follow() {
    final v = widget.controller.value;
    if (v.isPlaying) {
      if (!_wasPlaying) {
        _anchorPos = v.position.inMilliseconds / 1000.0;
        _anchorAt = _nowSec;
      }
      if (!_ticker.isActive) _ticker.start();
    } else {
      _anchorPos = v.position.inMilliseconds / 1000.0;
      _anchorAt = _nowSec;
      if (_ticker.isActive) _ticker.stop();
    }
    _wasPlaying = v.isPlaying;
  }

  void _onTick(Duration _) {
    final v = widget.controller.value;
    if (!v.isPlaying) {
      _ticker.stop();
      return;
    }
    _frame.value++;
    if (!_scroll.hasClients ||
        _pinching ||
        _scrubbing ||
        _scroll.position.isScrollingNotifier.value) {
      return;
    }
    final x = _smoothSec(v) * _pps;
    final target = (x - _viewW * 0.5)
        .clamp(0.0, _scroll.position.maxScrollExtent)
        .toDouble();
    if ((target - _scroll.offset).abs() > 0.3) _scroll.jumpTo(target);
  }
"""
CLS_OLD = "class ProTimelineState extends State<ProTimeline> {\n"
CLS_NEW = "class ProTimelineState extends State<ProTimeline>\n    with SingleTickerProviderStateMixin { // " + MARK + "\n"
IMP_OLD = "import 'package:flutter/services.dart' show HapticFeedback; // PATCH_S179_AAA\n"
IMP_NEW = IMP_OLD + "import 'package:flutter/scheduler.dart' show Ticker; // " + MARK + "\n"
INIT_OLD = "    super.initState();\n    widget.controller.addListener(_follow);\n"
INIT_NEW = "    super.initState();\n    _ticker = createTicker(_onTick); // " + MARK + "\n    widget.controller.addListener(_follow);\n    _follow();\n"
DISP_OLD = "    widget.controller.removeListener(_follow);\n    _scroll.dispose();\n"
DISP_NEW = "    widget.controller.removeListener(_follow);\n    _ticker.dispose(); // " + MARK + "\n    _frame.dispose();\n    _scroll.dispose();\n"
PH_OLD = ("    return ValueListenableBuilder<VideoPlayerValue>(\n      valueListenable: widget.controller,\n"
          "      builder: (context, v, _) {\n        final x = v.position.inMilliseconds / 1000.0 * _pps;\n")
PH_NEW = ("    return ListenableBuilder( // " + MARK + "\n      listenable: Listenable.merge([widget.controller, _frame]),\n"
          "      builder: (context, _) {\n        final v = widget.controller.value;\n        final x = _smoothSec(v) * _pps;\n")

EDITS = [('import', IMP_OLD, IMP_NEW), ('mixin', CLS_OLD, CLS_NEW), ('init', INIT_OLD, INIT_NEW),
         ('dispose', DISP_OLD, DISP_NEW), ('playhead', PH_OLD, PH_NEW)]
bad = ['%s (found %d)' % (l, t.count(o)) for l, o, _ in EDITS if t.count(o) != 1]
if t.count(FOLLOW_START) != 1 or t.count(FOLLOW_END) != 1 or t.index(FOLLOW_START) > t.index(FOLLOW_END):
    bad.append('follow function anchors')
if bad: sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))
for l, o, n in EDITS:
    t = t.replace(o, n, 1); print('  PATCHED pro_timeline.dart -', l)
i = t.index(FOLLOW_START); j = t.index(FOLLOW_END) + len(FOLLOW_END)
t = t[:i] + FOLLOW_NEW + t[j:]
print('  PATCHED pro_timeline.dart - smooth follow')
open(P, 'w', encoding='utf-8').write(t)
print('S187 applied. Next: git add -A && git commit -m "S187: smooth playhead" && git push')
