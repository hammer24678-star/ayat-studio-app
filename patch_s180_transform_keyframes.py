#!/usr/bin/env python3
"""
patch_s180_transform_keyframes.py - Ayat Studio S180 (run from repo root, after S179)

Free transform + keyframes for the video layer (CapCut "Basic + Keyframe"):
  scale 0.3x..2.0x / position X,Y / rotation / opacity, keyframes with smooth
  easing, ready-made camera moves (zoom in/out, drift, rise, tilt), pinch /
  drag / twist directly on the preview, keyframe diamonds on the timeline,
  undo/redo, and the SAME maths in the exporter (one ffmpeg `perspective`
  filter, fixed frame size), so export == preview.

New page «التحويل» in the tool strip.
Limits (on purpose): opacity is one value per clip; with chroma key on, the key
is applied first and the transform after it.
Idempotent; every anchor is verified before anything is written.
"""
import os, sys

MARK = 'PATCH_S180_TRANSFORM'
HOME, STATE, EXPORT = 'lib/screens/home_screen.dart', 'lib/models/studio_state.dart', 'lib/services/export_service.dart'
STAGE, TL = 'lib/widgets/stage_preview.dart', 'lib/widgets/pro_timeline.dart'

if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
rd = lambda p: open(p, encoding='utf-8').read()
for p in (HOME, STATE, EXPORT, STAGE, TL):
    if not os.path.exists(p):
        sys.exit('missing ' + p)
home, state, export, stage, tl = (rd(p) for p in (HOME, STATE, EXPORT, STAGE, TL))
if MARK in state:
    print('  OK      already applied'); sys.exit(0)
if 'PATCH_S179_AAA' not in home:
    sys.exit('S179 not applied yet.')

NEW = {
    'lib/models/video_transform.dart': r"""// PATCH_S180_TRANSFORM
// Free transform + keyframes for the video layer (CapCut "Basic + Keyframe").
// Pure Dart: the preview (VideoXformLayer) and the exporter (ffmpeg
// `perspective` expressions) both evaluate THIS maths, so export == preview.
//
//   scale 0.3x..2.0x, position X/Y as a fraction of the frame, rotation in
//   degrees, opacity 0..1 (one value per clip). Keyframes (scale/x/y/rot) are
//   stored in SOURCE-video seconds and eased with smoothstep or linearly.

/// One keyframe on the video layer.
class VideoKey {
  /// Source-video seconds (the same clock the timeline uses).
  final double t;
  double scale;
  double x; // fraction of frame width, + = right
  double y; // fraction of frame height, + = down
  double rot; // degrees, + = clockwise

  VideoKey(this.t, {this.scale = 1.0, this.x = 0.0, this.y = 0.0, this.rot = 0.0});

  VideoKey copy() => VideoKey(t, scale: scale, x: x, y: y, rot: rot);
}

/// The transform at one instant.
class VideoXform {
  final double scale, x, y, rot, opacity;
  const VideoXform(this.scale, this.x, this.y, this.rot, this.opacity);
}

/// Ready-made camera moves (they write two keyframes over the clip).
enum CameraMove { zoomIn, zoomOut, driftRight, driftLeft, riseUp, tilt }

String cameraMoveLabel(CameraMove m) => switch (m) {
      CameraMove.zoomIn => 'تقريب تدريجي',
      CameraMove.zoomOut => 'ابتعاد تدريجي',
      CameraMove.driftRight => 'انجراف يمينًا',
      CameraMove.driftLeft => 'انجراف يسارًا',
      CameraMove.riseUp => 'صعود',
      CameraMove.tilt => 'ميلان خفيف',
    };

/// Start / end keyframes of a camera move. Every move keeps scale >= 1 so
/// the picture never reveals empty edges while it travels.
(VideoKey, VideoKey) cameraMoveKeys(CameraMove m, double a, double b) {
  switch (m) {
    case CameraMove.zoomIn:
      return (VideoKey(a, scale: 1.0), VideoKey(b, scale: 1.25));
    case CameraMove.zoomOut:
      return (VideoKey(a, scale: 1.25), VideoKey(b, scale: 1.0));
    case CameraMove.driftRight:
      return (VideoKey(a, scale: 1.12, x: -0.04), VideoKey(b, scale: 1.12, x: 0.04));
    case CameraMove.driftLeft:
      return (VideoKey(a, scale: 1.12, x: 0.04), VideoKey(b, scale: 1.12, x: -0.04));
    case CameraMove.riseUp:
      return (VideoKey(a, scale: 1.12, y: 0.04), VideoKey(b, scale: 1.12, y: -0.04));
    case CameraMove.tilt:
      return (VideoKey(a, scale: 1.12, rot: -2.0), VideoKey(b, scale: 1.12, rot: 2.0));
  }
}

double _clip01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Value of the transform at source-time [t].
///   no keys  -> the static values
///   one key  -> that key's values
///   2+ keys  -> interpolated (clamped before the first / after the last)
VideoXform evalVideoXform({
  required List<VideoKey> keys,
  required bool ease,
  required double scale,
  required double x,
  required double y,
  required double rot,
  required double opacity,
  required double t,
}) {
  if (keys.isEmpty) return VideoXform(scale, x, y, rot, opacity);
  if (keys.length == 1) {
    final k = keys.first;
    return VideoXform(k.scale, k.x, k.y, k.rot, opacity);
  }
  if (t <= keys.first.t) {
    final k = keys.first;
    return VideoXform(k.scale, k.x, k.y, k.rot, opacity);
  }
  if (t >= keys.last.t) {
    final k = keys.last;
    return VideoXform(k.scale, k.x, k.y, k.rot, opacity);
  }
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i];
    final b = keys[i + 1];
    if (t < b.t) {
      final dt = (b.t - a.t) < 0.001 ? 0.001 : (b.t - a.t);
      var p = _clip01((t - a.t) / dt);
      if (ease) p = p * p * (3 - 2 * p);
      double mix(double u, double v) => u + (v - u) * p;
      return VideoXform(mix(a.scale, b.scale), mix(a.x, b.x), mix(a.y, b.y),
          mix(a.rot, b.rot), opacity);
    }
  }
  final k = keys.last;
  return VideoXform(k.scale, k.x, k.y, k.rot, opacity);
}
""",
    'lib/widgets/pro_transform.dart': r"""// PATCH_S180_TRANSFORM
// Transform page («التحويل») + the live preview layer.
//   VideoXformLayer  - wraps the preview video: scale / move / rotate / fade,
//                      animated smoothly between keyframes while playing.
//   ProTransformPage - sliders, keyframe buttons, camera moves.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:video_player/video_player.dart';

import '../models/studio_state.dart';
import '../models/video_transform.dart';
import '../theme/ayat_theme.dart';

// ------------------------------------------------------------ preview layer

class VideoXformLayer extends StatefulWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  final Widget child;
  const VideoXformLayer({
    super.key,
    required this.state,
    required this.controller,
    required this.child,
  });

  @override
  State<VideoXformLayer> createState() => _VideoXformLayerState();
}

class _VideoXformLayerState extends State<VideoXformLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _sw = Stopwatch()..start();
  double _lastPos = -1;
  int _lastAtUs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// The player only reports its position a few times a second; between two
  /// reports the time is extrapolated so keyframe motion looks smooth.
  double _now() {
    final c = widget.controller;
    if (c == null) return 0;
    final v = c.value;
    final p = v.position.inMicroseconds / 1000000.0;
    if (p != _lastPos) {
      _lastPos = p;
      _lastAtUs = _sw.elapsedMicroseconds;
    }
    if (!v.isPlaying) return p;
    final el = (_sw.elapsedMicroseconds - _lastAtUs) / 1000000.0 * v.playbackSpeed;
    return p + (el < 0 ? 0.0 : (el > 0.6 ? 0.6 : el));
  }

  Widget _at(double t) {
    final v = widget.state.videoTransformAt(t);
    return Opacity(
      opacity: v.opacity.clamp(0.0, 1.0).toDouble(),
      child: FractionalTranslation(
        translation: Offset(v.x, v.y),
        child: Transform.rotate(
          angle: v.rot * 3.141592653589793 / 180.0,
          child: Transform.scale(scale: v.scale, child: widget.child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    if (!st.hasVideoTransform) {
      if (_ticker.isActive) _ticker.stop();
      return widget.child;
    }
    final c = widget.controller;
    final animating =
        st.videoKeys.length >= 2 && c != null && c.value.isPlaying;
    if (animating && !_ticker.isActive) _ticker.start();
    if (!animating && _ticker.isActive) _ticker.stop();
    if (c == null) return _at(0);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, _, __) => _at(_now()),
    );
  }
}

// ------------------------------------------------------------------- page

class ProTransformPage extends StatelessWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  const ProTransformPage({super.key, required this.state, required this.controller});

  double _t() =>
      controller == null ? 0.0 : controller!.value.position.inMilliseconds / 1000.0;

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 14,
              decoration: BoxDecoration(
                color: AyatColors.goldBright,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 8),
            Text(text, style: Theme.of(context).textTheme.labelLarge),
          ],
        ),
      );

  Widget _slider({
    required String label,
    required String shown,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(label,
              style: const TextStyle(fontSize: 12, color: AyatColors.parchment)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(shown,
              textAlign: TextAlign.end,
              style: const TextStyle(
                  fontSize: 11.5, color: AyatColors.parchmentDim)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || !state.hasVideo) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text('ارفع فيديو أولًا ليظهر التحويل',
              style: TextStyle(color: AyatColors.parchmentDim)),
        ),
      );
    }
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: c,
        builder: (context, _, __) {
          final t = _t();
          final v = state.videoTransformAt(t);
          final keyed = state.videoKeys.isNotEmpty;
          final onKey = state.hasKeyNear(t);
          void setScale(double s) => keyed
              ? state.setKeyAt(t, scale: s)
              : state.update(() => state.videoScale = s);
          void setX(double x) => keyed
              ? state.setKeyAt(t, x: x)
              : state.update(() => state.videoPosX = x);
          void setY(double y) => keyed
              ? state.setKeyAt(t, y: y)
              : state.update(() => state.videoPosY = y);
          void setRot(double r) => keyed
              ? state.setKeyAt(t, rot: r)
              : state.update(() => state.videoRot = r);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        state.setKeyAt(t);
                      },
                      icon: const Icon(Icons.diamond_outlined, size: 18),
                      label: Text(onKey ? 'تحديث الإطار' : 'إطار مفتاحي'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onKey ? () => state.removeKeyNear(t) : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('حذف'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  keyed
                      ? 'الإطارات: ${state.videoKeys.length} — حرّك المؤشر ثم عدّل لتُضاف إطارات جديدة'
                      : 'اسحب على المعاينة أو استعمل المنزلقات. أضف إطارين مفتاحيين أو أكثر للحركة.',
                  style: const TextStyle(
                      fontSize: 11, color: AyatColors.parchmentDim),
                ),
              ),
              _title(context, 'التحويل'),
              _slider(
                label: 'الحجم',
                shown: '${(v.scale * 100).round()}%',
                value: v.scale,
                min: 0.3,
                max: 2.0,
                onChanged: setScale,
              ),
              _slider(
                label: 'أفقي',
                shown: '${(v.x * 100).round()}%',
                value: v.x,
                min: -0.9,
                max: 0.9,
                onChanged: setX,
              ),
              _slider(
                label: 'رأسي',
                shown: '${(v.y * 100).round()}%',
                value: v.y,
                min: -0.9,
                max: 0.9,
                onChanged: setY,
              ),
              _slider(
                label: 'الدوران',
                shown: '${v.rot.round()}°',
                value: v.rot,
                min: -180,
                max: 180,
                onChanged: setRot,
              ),
              _slider(
                label: 'الشفافية',
                shown: '${(state.videoOpacity * 100).round()}%',
                value: state.videoOpacity,
                min: 0.0,
                max: 1.0,
                onChanged: (o) => state.update(() => state.videoOpacity = o),
              ),
              _title(context, 'حركات الكاميرا'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in CameraMove.values)
                    ActionChip(
                      label: Text(cameraMoveLabel(m)),
                      onPressed: state.videoDurationSec > 0.2
                          ? () {
                              HapticFeedback.selectionClick();
                              state.applyCameraMove(m);
                            }
                          : null,
                    ),
                ],
              ),
              _title(context, 'نعومة الحركة'),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('ناعمة'),
                    selected: state.videoKeyEase,
                    onSelected: (_) =>
                        state.update(() => state.videoKeyEase = true),
                  ),
                  ChoiceChip(
                    label: const Text('خطّية'),
                    selected: !state.videoKeyEase,
                    onSelected: (_) =>
                        state.update(() => state.videoKeyEase = false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (keyed)
                    TextButton.icon(
                      onPressed: state.clearVideoKeys,
                      icon: const Icon(Icons.layers_clear_outlined, size: 18),
                      label: const Text('مسح الإطارات'),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: state.hasVideoTransform
                        ? state.resetVideoTransform
                        : null,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('إعادة الضبط'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
""",
}
STATE_ADD = r"""  // ---- PATCH_S180_TRANSFORM: free transform + keyframes of the video layer ----
  double videoScale = 1.0; // 0.3..2.0 (used when there are no keyframes)
  double videoPosX = 0.0; // -0.9..0.9 of the frame width
  double videoPosY = 0.0; // -0.9..0.9 of the frame height
  double videoRot = 0.0; // degrees, -180..180
  double videoOpacity = 1.0; // 0..1, one value for the whole clip
  List<VideoKey> videoKeys = []; // sorted by time; 2+ = animated
  bool videoKeyEase = true; // smoothstep between keys (false = linear)

  bool get hasVideoTransform =>
      hasVideo &&
      (videoKeys.isNotEmpty ||
          (videoScale - 1).abs() > 0.001 ||
          videoPosX.abs() > 0.001 ||
          videoPosY.abs() > 0.001 ||
          videoRot.abs() > 0.05 ||
          videoOpacity < 0.999);

  VideoXform videoTransformAt(double t) => evalVideoXform(
        keys: videoKeys,
        ease: videoKeyEase,
        scale: videoScale,
        x: videoPosX,
        y: videoPosY,
        rot: videoRot,
        opacity: videoOpacity,
        t: t,
      );

  /// The part of the source video that gets exported (same rules as the exporter).
  (double, double) videoClipRange() {
    final ts = trimStart;
    final te = trimEnd;
    if (ts != null && te != null) return (ts, te);
    if (manualTrimSet) {
      final end = trimManualEnd < 0
          ? videoDurationSec
          : (trimManualEnd < videoDurationSec ? trimManualEnd : videoDurationSec);
      return (trimManualStart, end);
    }
    return (0.0, videoDurationSec);
  }

  /// Write a keyframe at [t]; anything not given keeps its current value.
  void setKeyAt(double t, {double? scale, double? x, double? y, double? rot}) {
    pushHistory();
    final tt = (t * 1000).round() / 1000.0;
    final cur = videoTransformAt(tt);
    final k = VideoKey(tt,
        scale: scale ?? cur.scale, x: x ?? cur.x, y: y ?? cur.y, rot: rot ?? cur.rot);
    videoKeys.removeWhere((e) => (e.t - tt).abs() < 0.05);
    videoKeys.add(k);
    videoKeys.sort((a, b) => a.t.compareTo(b.t));
    notifyListeners();
  }

  /// True when a keyframe sits within [tol] seconds of [t].
  bool hasKeyNear(double t, [double tol = 0.12]) =>
      videoKeys.any((e) => (e.t - t).abs() <= tol);

  void removeKeyNear(double t, [double tol = 0.12]) {
    if (!hasKeyNear(t, tol)) return;
    pushHistory();
    videoKeys.removeWhere((e) => (e.t - t).abs() <= tol);
    notifyListeners();
  }

  void clearVideoKeys() {
    if (videoKeys.isEmpty) return;
    pushHistory();
    videoKeys = [];
    notifyListeners();
  }

  void applyCameraMove(CameraMove m) {
    final (a, b) = videoClipRange();
    if (b - a < 0.2) return;
    pushHistory();
    final (k0, k1) = cameraMoveKeys(m, a, b);
    videoKeys = [k0, k1];
    notifyListeners();
  }

  void resetVideoTransform() {
    pushHistory();
    videoScale = 1.0;
    videoPosX = 0.0;
    videoPosY = 0.0;
    videoRot = 0.0;
    videoOpacity = 1.0;
    videoKeys = [];
    notifyListeners();
  }

"""
EXPORT_HELPERS = r"""  // PATCH_S180_TRANSFORM: keyframe track -> one ffmpeg expression of the
  // frame time [tv]. Same smoothstep (or linear) maths as
  // StudioState.videoTransformAt, so the export matches the preview.
  static String _kfExpr(List<({double t, double v})> pts, bool ease, String tv) {
    String f(double v) => v.toStringAsFixed(4);
    if (pts.length == 1) return f(pts.first.v);
    var e = f(pts.last.v);
    for (var i = pts.length - 2; i >= 0; i--) {
      final a = pts[i];
      final b = pts[i + 1];
      final dt = (b.t - a.t) < 0.001 ? 0.001 : (b.t - a.t);
      final p =
          'clip(($tv-${a.t.toStringAsFixed(3)})/${dt.toStringAsFixed(3)},0,1)';
      final s = ease ? '($p*$p*(3-2*$p))' : p;
      e = 'if(lt($tv,${b.t.toStringAsFixed(3)}),${f(a.v)}+(${f(b.v - a.v)})*$s,$e)';
    }
    return e;
  }

  /// One filter that scales, rotates and moves the video layer on a
  /// full-frame canvas (ffmpeg `perspective`, corners mapped from the
  /// transform): fixed frame size, so it stays fast even when animated.
  /// Order = scale, then rotate, then move -- same as the preview.
  static String _xformFilter(StudioState st, double clipStart) {
    String f(double v) => v.toStringAsFixed(4);
    final keys = st.videoKeys;
    final animated = keys.length >= 2;
    final tv = '(in/$_fps)'; // frame time in seconds, relative to the clip
    double sv = st.videoScale, xv = st.videoPosX, yv = st.videoPosY, rv = st.videoRot;
    if (keys.length == 1) {
      sv = keys.first.scale;
      xv = keys.first.x;
      yv = keys.first.y;
      rv = keys.first.rot;
    }
    List<({double t, double v})> track(double Function(VideoKey) g) =>
        [for (final k in keys) (t: k.t - clipStart, v: g(k))];
    final sE = animated ? _kfExpr(track((k) => k.scale), st.videoKeyEase, tv) : f(sv);
    final xE = animated ? _kfExpr(track((k) => k.x), st.videoKeyEase, tv) : f(xv);
    final yE = animated ? _kfExpr(track((k) => k.y), st.videoKeyEase, tv) : f(yv);
    final rE = animated ? _kfExpr(track((k) => k.rot), st.videoKeyEase, tv) : f(rv);
    String corner(int sx, int sy, bool isX) {
      final pre = 'st(0,$sE);st(1,($rE)*PI/180);st(2,cos(ld(1)));st(3,sin(ld(1)));';
      final body = isX
          ? 'W/2+($xE)*W+ld(0)*(($sx)*W/2*ld(2)-($sy)*H/2*ld(3))'
          : 'H/2+($yE)*H+ld(0)*(($sx)*W/2*ld(3)+($sy)*H/2*ld(2))';
      return "'$pre$body'";
    }

    const cx = [-1, 1, -1, 1];
    const cy = [-1, -1, 1, 1];
    final p = StringBuffer();
    for (var i = 0; i < 4; i++) {
      p.write('x$i=${corner(cx[i], cy[i], true)}:y$i=${corner(cx[i], cy[i], false)}:');
    }
    final op = st.videoOpacity < 0.999
        ? ',colorchannelmixer=aa=${f(st.videoOpacity)}'
        : '';
    return 'format=rgba$op,perspective=${p}sense=destination:'
        'eval=${animated ? 'frame' : 'init'}:interpolation=linear';
  }

  static List<String> _audioFadeFilters(StudioState state, double duration) {
"""
EXPORT_CHAIN = r"""        // PATCH_S180_TRANSFORM: free transform / keyframes of the video layer.
        // Order: chroma key (if on) -> transform -> composite over the background.
        final xf = state.hasVideoTransform ? _xformFilter(state, clipStart) : null;
        if (state.chromaEnabled) {
          filters.add('[v0]chromakey=0x$keyHex:$sim:$blend[${xf == null ? 'fg' : 'fgk'}]');
        }
        if (xf != null) {
          filters.add('[${state.chromaEnabled ? 'fgk' : 'v0'}]$xf[fg]');
        }
"""
GESTURE_METHODS = r"""  // PATCH_S180_TRANSFORM: touch transform on the preview (page «التحويل»):
  // drag = move, pinch = scale, twist = rotate. With keyframes present each
  // gesture writes a keyframe at the playhead.
  double _gBaseScale = 1, _gBaseRot = 0, _gBaseX = 0, _gBaseY = 0;
  Offset _gStart = Offset.zero;

  Widget _xformGestureLayer() {
    return LayoutBuilder(builder: (context, c) {
      final aspect = _frameAspect();
      var pw = c.maxWidth;
      var ph = pw / aspect;
      if (ph > c.maxHeight) {
        ph = c.maxHeight;
        pw = ph * aspect;
      }
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onScaleStart: (d) {
          final vc = _video;
          if (vc == null) return;
          vc.pause();
          final t = vc.value.position.inMilliseconds / 1000.0;
          final cur = state.videoTransformAt(t);
          _gBaseScale = cur.scale;
          _gBaseRot = cur.rot;
          _gBaseX = cur.x;
          _gBaseY = cur.y;
          _gStart = d.focalPoint;
        },
        onScaleUpdate: (d) {
          final vc = _video;
          if (vc == null) return;
          final t = vc.value.position.inMilliseconds / 1000.0;
          final ns = (_gBaseScale * d.scale).clamp(0.3, 2.0).toDouble();
          final nx = (_gBaseX + (d.focalPoint.dx - _gStart.dx) / pw)
              .clamp(-0.9, 0.9)
              .toDouble();
          final ny = (_gBaseY + (d.focalPoint.dy - _gStart.dy) / ph)
              .clamp(-0.9, 0.9)
              .toDouble();
          var nr = _gBaseRot + d.rotation * 180 / pi;
          nr = ((nr + 180) % 360) - 180;
          if (nr.abs() < 2.5) nr = 0; // snap upright
          if (state.videoKeys.isNotEmpty) {
            state.setKeyAt(t, scale: ns, x: nx, y: ny, rot: nr);
          } else {
            state.update(() {
              state.videoScale = ns;
              state.videoPosX = nx;
              state.videoPosY = ny;
              state.videoRot = nr;
            });
          }
        },
        child: Align(
          alignment: Alignment.topCenter,
          child: IgnorePointer(
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xB3050F0D),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x55ECC875)),
              ),
              child: const Text('اسحب · قرّب · لُفّ',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AyatColors.parchment)),
            ),
          ),
        ),
      );
    });
  }

"""
DIAMONDS = r"""          // PATCH_S180_TRANSFORM: keyframe diamonds
          for (final k in s.videoKeys)
            Positioned(
              left: k.t * _pps - 6,
              top: (h - 4) / 2 - 3,
              width: 12,
              height: 12,
              child: GestureDetector(
                onTap: () => _seekSec(k.t),
                child: Transform.rotate(
                  angle: 0.7853981633974483,
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: AyatColors.goldBright,
                      border: Border.all(color: AyatColors.ink, width: 1),
                    ),
                  ),
                ),
              ),
            ),
          if (canTrim) ...[
"""

edits = {
 STATE: (state, [
  ('state import', "import '../data/text_transitions.dart'; // PATCH_S126_TEXT_TRANSITIONS\n",
   "import '../data/text_transitions.dart'; // PATCH_S126_TEXT_TRANSITIONS\nimport 'video_transform.dart'; // " + MARK + "\n"),
  ('state fields', "  bool audioNormalize = false; // loudness normalize (export)\n",
   "  bool audioNormalize = false; // loudness normalize (export)\n" + STATE_ADD),
  ('new clip resets', "    videoRotationQuarterTurns = 0;\n    videoMirror = false;\n    notifyListeners();\n",
   "    videoRotationQuarterTurns = 0;\n    videoMirror = false;\n"
   "    // " + MARK + ": the transform is per clip too.\n"
   "    videoScale = 1.0;\n    videoPosX = 0.0;\n    videoPosY = 0.0;\n    videoRot = 0.0;\n    videoOpacity = 1.0;\n    videoKeys = [];\n"
   "    notifyListeners();\n"),
  ('capture', "        'videoMirror': videoMirror,\n",
   "        'videoMirror': videoMirror,\n"
   "        // " + MARK + "\n"
   "        'videoXform': <double>[videoScale, videoPosX, videoPosY, videoRot, videoOpacity],\n"
   "        'videoKeys': [for (final k in videoKeys) k.copy()],\n"
   "        'videoKeyEase': videoKeyEase,\n"),
  ('apply', "    videoMirror = s['videoMirror'] as bool;\n",
   "    videoMirror = s['videoMirror'] as bool;\n"
   "    // " + MARK + "\n"
   "    final vx = s['videoXform'] as List<double>;\n"
   "    videoScale = vx[0];\n    videoPosX = vx[1];\n    videoPosY = vx[2];\n    videoRot = vx[3];\n    videoOpacity = vx[4];\n"
   "    videoKeys = [for (final k in (s['videoKeys'] as List).cast<VideoKey>()) k.copy()];\n"
   "    videoKeyEase = s['videoKeyEase'] as bool;\n"),
 ]),
 STAGE: (stage, [
  ('stage import', "import 'selection_box_overlay.dart'; // PATCH_S133_STAGE_TEXT_SELECT_EDIT\n",
   "import 'selection_box_overlay.dart'; // PATCH_S133_STAGE_TEXT_SELECT_EDIT\nimport 'pro_transform.dart'; // " + MARK + "\n"),
  ('stage head',
   "                  ImageFiltered(\n                    imageFilter: state.videoBlur > 0.05\n                        ? ui.ImageFilter.blur(\n                            sigmaX: state.videoBlur * scale,",
   "                  VideoXformLayer( // " + MARK + "\n                    state: state,\n                    controller: controller,\n                    child: ImageFiltered(\n                    imageFilter: state.videoBlur > 0.05\n                        ? ui.ImageFilter.blur(\n                            sigmaX: state.videoBlur * scale,"),
  ('stage tail',
   "                  ), // PATCH_S85_VIDEO_ADJUST: closes ImageFiltered\n                // PATCH_S34_STAGE_EFFECTS: particles over the video/background,",
   "                  )), // PATCH_S85_VIDEO_ADJUST: closes ImageFiltered + VideoXformLayer\n                // PATCH_S34_STAGE_EFFECTS: particles over the video/background,"),
 ]),
 EXPORT: (export, [
  ('export helpers', "  static List<String> _audioFadeFilters(StudioState state, double duration) {\n", EXPORT_HELPERS),
  ('export block', "      if (state.chromaEnabled) {\n        // PATCH_S40_MULTI_BG_CYCLE: single bgPng",
   "      if (state.chromaEnabled || state.hasVideoTransform) { // " + MARK + "\n        // PATCH_S40_MULTI_BG_CYCLE: single bgPng"),
  ('export chain', "        filters.add('[v0]chromakey=0x$keyHex:$sim:$blend[fg]');\n", EXPORT_CHAIN),
  ('export import', "import '../models/studio_state.dart';\n",
   "import '../models/studio_state.dart';\nimport '../models/video_transform.dart'; // " + MARK + "\n"),
 ]),
 TL: (tl, [
  ('diamonds', "          if (canTrim) ...[\n", DIAMONDS),
 ]),
 HOME: (home, [
  ('home import', "import '../widgets/pro_extras.dart'; // PATCH_S179_AAA\n",
   "import '../widgets/pro_extras.dart'; // PATCH_S179_AAA\nimport '../widgets/pro_transform.dart'; // " + MARK + "\n"),
  ('tool list', "        (111, Icons.high_quality_outlined, 'تحسين'),\n",
   "        (111, Icons.high_quality_outlined, 'تحسين'),\n        (112, Icons.open_with, 'التحويل'), // " + MARK + "\n"),
  ('tool body', "      case 111:\n        return ProEnhance(state: state);\n",
   "      case 111:\n        return ProEnhance(state: state);\n      case 112: // " + MARK + "\n        return ProTransformPage(state: state, controller: _video);\n"),
  ('gesture layer', "                  if (_guides)\n                    Positioned.fill(\n",
   "                  if (_toolOpen == 112 && _video != null && _video!.value.isInitialized) // " + MARK + "\n                    Positioned.fill(child: _xformGestureLayer()),\n                  if (_guides)\n                    Positioned.fill(\n"),
  ('gesture methods', "  Widget _toolPanel(double h) {\n", GESTURE_METHODS + "  Widget _toolPanel(double h) {\n"),
 ]),
}

bad = []
for path, (text, eds) in edits.items():
    for label, old, _ in eds:
        n = text.count(old)
        if n != 1:
            bad.append('%s: %s (found %d)' % (path, label, n))
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for path, (text, eds) in edits.items():
    for label, old, new in eds:
        text = text.replace(old, new, 1)
        print('  PATCHED', path.split('/')[-1], '-', label)
    open(path, 'w', encoding='utf-8').write(text)
for path, body in NEW.items():
    open(path, 'w', encoding='utf-8').write(body)
    print('  WROTE  ', path)
print('S180 applied. Next: git add -A && git commit -m "S180: transform + keyframes" && git push')
