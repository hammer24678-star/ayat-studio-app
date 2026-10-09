// PATCH_S188_PIP
// PATCH_S193_PIP_POWER
// Picture-in-picture («PIP»).
//   PipLayer   - the live layer on the stage: plays the little clips in step
//                with the main clip and lets you drag / pinch / twist them
//                with the finger, or grab the corner handles (✕ delete,
//                ⤢ size + turn, ⇋ mirror, ⧉ copy). While the finger is down
//                only this layer repaints; the change is committed once, when
//                you let go.
//   ProPipPage - the tool panel (add, size, shape, frame, transparent
//                background, entrance / exit, picture adjust, timing, order).
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:video_player/video_player.dart';

import '../models/pip_clip.dart';
import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';
import 'color_picker_dialog.dart' show showAyatColorPicker;
import 'gold_switch.dart';
import 'motion.dart';

// ----------------------------------------------------- transparent background

/// Makes one colour (and its neighbours) of a picture transparent for the live
/// preview. The exporter does the same with ffmpeg's colorkey filter, using the
/// same distance and softness, so the two agree.
class PipKeyer {
  static final Map<String, ui.Image> _cache = {};
  static final List<String> _order = [];
  static final Set<String> _bad = {};

  static String keyOf(PipClip c) =>
      '${c.path}|${c.keyColor}|${(c.keySim * 1000).round()}|${(c.keyBlend * 1000).round()}';

  /// The keyed picture if it is ready.
  static ui.Image? cached(PipClip c) => _cache[keyOf(c)];

  /// True when there is nothing left to wait for (ready, or it cannot be done).
  static bool settled(PipClip c) {
    final k = keyOf(c);
    return _cache.containsKey(k) || _bad.contains(k);
  }

  static Future<ui.Image?> build(PipClip c) async {
    final k = keyOf(c);
    final hit = _cache[k];
    if (hit != null) return hit;
    try {
      final bytes = await File(c.path).readAsBytes();
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final big = desc.width > 720;
      final codec = await desc.instantiateCodec(targetWidth: big ? 720 : null);
      final frame = await codec.getNextFrame();
      final src = frame.image;
      final w = src.width;
      final h = src.height;
      final bd = await src.toByteData(format: ui.ImageByteFormat.rawRgba);
      src.dispose();
      codec.dispose();
      desc.dispose();
      buf.dispose();
      if (bd == null) {
        _bad.add(k);
        return null;
      }
      final px = Uint8List.fromList(
          bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes));
      final kr = (c.keyColor >> 16) & 0xFF;
      final kg = (c.keyColor >> 8) & 0xFF;
      final kb = c.keyColor & 0xFF;
      final sim = c.keySim;
      final blend = c.keyBlend;
      for (var i = 0; i + 3 < px.length; i += 4) {
        final a = px[i + 3];
        if (a == 0) continue;
        // the bytes are premultiplied: undo that to compare real colours
        final r = a == 255 ? px[i] : (px[i] * 255 / a);
        final g = a == 255 ? px[i + 1] : (px[i + 1] * 255 / a);
        final b = a == 255 ? px[i + 2] : (px[i + 2] * 255 / a);
        final dr = r - kr;
        final dg = g - kg;
        final db = b - kb;
        final diff = math.sqrt(dr * dr + dg * dg + db * db) / 441.6729559;
        final double keep = blend > 0.001
            ? ((diff - sim) / blend).clamp(0.0, 1.0).toDouble()
            : (diff > sim ? 1.0 : 0.0);
        if (keep >= 0.999) continue;
        px[i] = (px[i] * keep).round();
        px[i + 1] = (px[i + 1] * keep).round();
        px[i + 2] = (px[i + 2] * keep).round();
        px[i + 3] = (a * keep).round();
      }
      final done = Completer<ui.Image>();
      ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, done.complete);
      final img = await done.future;
      _cache[k] = img;
      _order.add(k);
      while (_order.length > 6) {
        _cache.remove(_order.removeAt(0));
      }
      return img;
    } catch (_) {
      _bad.add(k);
      return null;
    }
  }

  /// The colour of the top-left pixel of a picture (usually its background),
  /// as 0xFFRRGGBB, or null when it cannot be read.
  static Future<int?> cornerColor(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final codec = await desc.instantiateCodec(targetWidth: 32);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      codec.dispose();
      desc.dispose();
      buf.dispose();
      if (bd == null || bd.lengthInBytes < 4) return null;
      final r = bd.getUint8(0);
      final g = bd.getUint8(1);
      final b = bd.getUint8(2);
      return 0xFF000000 | (r << 16) | (g << 8) | b;
    } catch (_) {
      return null;
    }
  }
}

// ------------------------------------------------------------ preview layer

class PipLayer extends StatefulWidget {
  final StudioState state;
  final VideoPlayerController? main;
  const PipLayer({super.key, required this.state, required this.main});

  @override
  State<PipLayer> createState() => _PipLayerState();
}

class _PipLayerState extends State<PipLayer>
    with SingleTickerProviderStateMixin {
  /// Margin around every box: the corner handles live in it, so they stay
  /// inside the widget that receives the touches.
  static const double _pad = 22.0;

  final Map<int, VideoPlayerController> _ctl = {};
  final Map<int, String> _ctlPath = {};
  final Set<int> _booting = {};
  final Map<int, int> _seekAtUs = {};
  late final Ticker _ticker;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final Stopwatch _sw = Stopwatch()..start();
  double _lastPos = -1;
  int _lastAtUs = 0;
  VideoPlayerController? _hooked;
  StudioState? _hookedState;
  bool _keyBusy = false;

  // finger gesture (kept local until the finger lifts)
  int _dragId = -1;
  double _dCx = 0.5, _dCy = 0.5, _dW = 0.5, _dRot = 0;
  double _bCx = 0.5, _bCy = 0.5, _bW = 0.5, _bRot = 0;
  Offset _gStart = Offset.zero;
  bool _snapV = false, _snapH = false;
  double _hD0 = 1, _hA0 = 0; // corner-handle gesture: start distance / angle

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _hook();
    _reconcile();
  }

  @override
  void didUpdateWidget(covariant PipLayer old) {
    super.didUpdateWidget(old);
    _hook();
    _reconcile();
  }

  void _hook() {
    if (_hookedState != widget.state) {
      _hookedState?.removeListener(_onState);
      _hookedState = widget.state;
      widget.state.addListener(_onState);
    }
    if (_hooked != widget.main) {
      _hooked?.removeListener(_onMain);
      _hooked = widget.main;
      _hooked?.addListener(_onMain);
    }
  }

  @override
  void dispose() {
    _hookedState?.removeListener(_onState);
    _hooked?.removeListener(_onMain);
    _ticker.dispose();
    _frame.dispose();
    for (final c in _ctl.values) {
      c.dispose();
    }
    _ctl.clear();
    super.dispose();
  }

  // ---------------------------------------------------------- controllers

  void _onState() {
    if (!mounted) return;
    _reconcile();
    _syncAll();
    setState(() {});
  }

  void _reconcile() {
    final want = <int, PipClip>{
      for (final c in widget.state.pipClips)
        if (!c.isImage) c.id: c
    };
    for (final id in _ctl.keys.toList()) {
      final w = want[id];
      if (w == null || _ctlPath[id] != w.path) {
        _ctl.remove(id)?.dispose();
        _ctlPath.remove(id);
        _seekAtUs.remove(id);
      }
    }
    for (final c in want.values) {
      if (_ctl.containsKey(c.id) || _booting.contains(c.id)) continue;
      _boot(c);
    }
    _ensureKeyed();
  }

  /// Prepares the transparent-background copy of every picture that asks for
  /// one, one at a time (a slider drag just keeps the newest).
  void _ensureKeyed() {
    if (_keyBusy) return;
    for (final c in widget.state.pipClips) {
      if (!c.isImage || !c.keyOn || PipKeyer.settled(c)) continue;
      _keyBusy = true;
      PipKeyer.build(c).then((_) {
        _keyBusy = false;
        if (!mounted) return;
        setState(() {});
        _ensureKeyed();
      });
      return;
    }
  }

  Future<void> _boot(PipClip c) async {
    _booting.add(c.id);
    final vc = VideoPlayerController.file(File(c.path),
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true));
    try {
      await vc.initialize();
      await vc.setVolume(0);
      await vc.setLooping(true);
    } catch (_) {
      _booting.remove(c.id);
      await vc.dispose();
      return;
    }
    _booting.remove(c.id);
    final stillThere = widget.state.pipClips.any((e) => e.id == c.id);
    if (!mounted || !stillThere) {
      await vc.dispose();
      return;
    }
    _ctl[c.id] = vc;
    _ctlPath[c.id] = c.path;
    _syncAll();
    setState(() {});
  }

  // ----------------------------------------------------------------- time

  /// The player reports its position a few times a second; between two
  /// reports the time is extrapolated so the little clips glide.
  double _now() {
    final m = widget.main;
    if (m == null || !m.value.isInitialized) return 0;
    final v = m.value;
    final p = v.position.inMicroseconds / 1000000.0;
    if (p != _lastPos) {
      _lastPos = p;
      _lastAtUs = _sw.elapsedMicroseconds;
    }
    if (!v.isPlaying) return p;
    final el =
        (_sw.elapsedMicroseconds - _lastAtUs) / 1000000.0 * v.playbackSpeed;
    return p + (el < 0 ? 0.0 : (el > 0.6 ? 0.6 : el));
  }

  void _onMain() {
    final m = widget.main;
    if (m == null || !mounted) return;
    final run = m.value.isPlaying && widget.state.pipClips.isNotEmpty;
    if (run && !_ticker.isActive) _ticker.start();
    if (!run && _ticker.isActive) _ticker.stop();
    _syncAll();
    _frame.value++;
  }

  void _onTick(Duration _) {
    final m = widget.main;
    if (m == null || !m.value.isPlaying) {
      _ticker.stop();
      return;
    }
    _syncAll();
    _frame.value++;
  }

  void _seek(VideoPlayerController vc, int id, double sec, int nowUs) {
    _seekAtUs[id] = nowUs;
    vc.seekTo(Duration(milliseconds: (sec * 1000).round()));
  }

  /// Keeps every little video in step with the main clip.
  void _syncAll() {
    final m = widget.main;
    if (m == null || !m.value.isInitialized) return;
    final playing = m.value.isPlaying;
    final speed = m.value.playbackSpeed;
    final t = _now();
    final nowUs = _sw.elapsedMicroseconds;
    for (final c in widget.state.pipClips) {
      final vc = _ctl[c.id];
      if (vc == null || !vc.value.isInitialized) continue;
      if (!c.activeAt(t)) {
        if (vc.value.isPlaying) vc.pause();
        continue;
      }
      final dur = vc.value.duration.inMilliseconds / 1000.0;
      final want = dur > 0.05 ? (c.srcIn + (t - c.start)) % dur : 0.0;
      final cur = vc.value.position.inMilliseconds / 1000.0;
      var diff = (cur - want).abs();
      if (dur > 0.05 && dur - diff < diff) diff = dur - diff; // loop seam
      final since = nowUs - (_seekAtUs[c.id] ?? -1000000000);
      if (playing) {
        if ((vc.value.playbackSpeed - speed).abs() > 0.01) {
          vc.setPlaybackSpeed(speed);
        }
        if (!vc.value.isPlaying) {
          _seek(vc, c.id, want, nowUs);
          vc.play();
        } else if (diff > 0.35 && since > 500000) {
          _seek(vc, c.id, want, nowUs);
        }
      } else {
        if (vc.value.isPlaying) vc.pause();
        if (diff > 0.03 && since > 60000) _seek(vc, c.id, want, nowUs);
      }
    }
  }

  // -------------------------------------------------------------- gesture

  void _onStart(PipClip c, int i, ScaleStartDetails d) {
    widget.state.selectPip(i);
    _dragId = c.id;
    _bCx = _dCx = c.cx;
    _bCy = _dCy = c.cy;
    _bW = _dW = c.width;
    _bRot = _dRot = c.rot;
    _gStart = d.focalPoint;
    _snapV = _snapH = false;
    HapticFeedback.selectionClick();
  }

  void _onUpdate(ScaleUpdateDetails d, double fw, double fh) {
    if (_dragId < 0) return;
    var cx = _bCx + (d.focalPoint.dx - _gStart.dx) / fw;
    var cy = _bCy + (d.focalPoint.dy - _gStart.dy) / fh;
    final w = (_bW * d.scale).clamp(0.08, 1.5).toDouble();
    var r = _bRot + d.rotation * 180 / math.pi;
    r = _snapAngle(r);
    // magnet to the middle of the frame, with a tick
    final sv = (cx - 0.5).abs() < 0.018;
    final sh = (cy - 0.5).abs() < 0.018;
    if (sv) cx = 0.5;
    if (sh) cy = 0.5;
    if ((sv && !_snapV) || (sh && !_snapH)) HapticFeedback.selectionClick();
    cx = cx.clamp(0.0, 1.0).toDouble();
    cy = cy.clamp(0.0, 1.0).toDouble();
    setState(() {
      _snapV = sv;
      _snapH = sh;
      _dCx = cx;
      _dCy = cy;
      _dW = w;
      _dRot = r;
    });
  }

  double _snapAngle(double deg) {
    var r = ((deg + 180) % 360) - 180;
    for (final s in const [0.0, 90.0, -90.0, 180.0, -180.0]) {
      if ((r - s).abs() < 3) {
        r = s;
        break;
      }
    }
    return r;
  }

  Offset? _local(Offset global) {
    final rb = context.findRenderObject();
    if (rb is RenderBox && rb.hasSize) return rb.globalToLocal(global);
    return null;
  }

  // The corner handle: drag away from the centre = bigger, around it = turn.
  void _hStart(PipClip c, int i, Offset global, double fw, double fh) {
    final p = _local(global);
    if (p == null) return;
    widget.state.selectPip(i);
    _dragId = c.id;
    _bCx = _dCx = c.cx;
    _bCy = _dCy = c.cy;
    _bW = _dW = c.width;
    _bRot = _dRot = c.rot;
    final ctr = Offset(c.cx * fw, c.cy * fh);
    _hD0 = math.max(8.0, (p - ctr).distance);
    _hA0 = math.atan2(p.dy - ctr.dy, p.dx - ctr.dx);
    _snapV = _snapH = false;
    HapticFeedback.selectionClick();
  }

  void _hUpdate(Offset global, double fw, double fh) {
    if (_dragId < 0) return;
    final p = _local(global);
    if (p == null) return;
    final ctr = Offset(_bCx * fw, _bCy * fh);
    final d = (p - ctr).distance;
    final a = math.atan2(p.dy - ctr.dy, p.dx - ctr.dx);
    final w = (_bW * d / _hD0).clamp(0.08, 1.5).toDouble();
    final r = _snapAngle(_bRot + (a - _hA0) * 180 / math.pi);
    setState(() {
      _dW = w;
      _dRot = r;
    });
  }

  void _onEnd(PipClip c) {
    if (_dragId != c.id) return;
    final moved = (_dCx - c.cx).abs() > 0.0005 ||
        (_dCy - c.cy).abs() > 0.0005 ||
        (_dW - c.width).abs() > 0.0005 ||
        (_dRot - c.rot).abs() > 0.05;
    final nx = _dCx, ny = _dCy, nw = _dW, nr = _dRot;
    setState(() {
      _dragId = -1;
      _snapV = _snapH = false;
    });
    if (moved) {
      widget.state.update(() {
        c.cx = nx;
        c.cy = ny;
        c.width = nw;
        c.rot = nr;
      });
    }
  }

  void _delete(int i) {
    HapticFeedback.mediumImpact();
    final m = ScaffoldMessenger.maybeOf(context);
    widget.state.removePipAt(i);
    m
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('تم حذف المقطع الصغير', textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: AyatColors.goldBright,
          onPressed: widget.state.undoStep,
        ),
      ));
  }

  // ---------------------------------------------------------------- build

  Widget _media(PipClip c, VideoPlayerController? vc) {
    if (c.isImage) {
      if (c.keyOn) {
        final keyed = PipKeyer.cached(c);
        if (keyed != null) {
          return RawImage(
            image: keyed,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.medium,
          );
        }
      }
      return Image.file(
        File(c.path),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0B1512)),
      );
    }
    if (vc != null && vc.value.isInitialized && vc.value.size.width > 0) {
      return FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: vc.value.size.width,
          height: vc.value.size.height,
          child: VideoPlayer(vc),
        ),
      );
    }
    return const ColoredBox(
      color: Color(0xFF0B1512),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  /// brightness / contrast / saturation as one colour matrix (same maths as
  /// the stage's picture adjust and ffmpeg's eq).
  static ColorFilter _adjust(PipClip c) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final s = c.saturation;
    final k = c.contrast;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    final o = 255 * (c.brightness + (1 - k) / 2);
    return ColorFilter.matrix(<double>[
      k * (sr + s), k * sg, k * sb, 0, o,
      k * sr, k * (sg + s), k * sb, 0, o,
      k * sr, k * sg, k * (sb + s), 0, o,
      0, 0, 0, 1, 0,
    ]);
  }

  /// Everything the clip looks like: picture, flip, adjust, shape, frame and
  /// shadow, at visibility [a].
  Widget _look(PipClip c, double bw, double bh, double a,
      VideoPlayerController? vc) {
    final m = math.min(bw, bh);
    final isCircle = c.shape == PipShape.circle;
    final BorderRadius? br =
        c.shape == PipShape.rounded ? BorderRadius.circular(m * c.radiusFrac) : null;
    Widget media = SizedBox.expand(child: _media(c, vc));
    if (c.flipH || c.flipV) {
      media = Transform.flip(flipX: c.flipH, flipY: c.flipV, child: media);
    }
    if (c.hasAdjust) {
      media = ColorFiltered(colorFilter: _adjust(c), child: media);
    }
    final Widget clipped = switch (c.shape) {
      PipShape.rect => ClipRect(child: media),
      PipShape.rounded => ClipRRect(borderRadius: br!, child: media),
      PipShape.circle => ClipOval(child: media),
    };
    final layers = <Widget>[
      if (c.shadow)
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: isCircle ? null : br,
              boxShadow: [
                BoxShadow(
                  color: const Color(0x99000000),
                  blurRadius: math.min(24.0, m * 0.14),
                  offset: Offset(0, m * 0.04),
                ),
              ],
            ),
          ),
        ),
      Positioned.fill(child: clipped),
      if (c.hasBorder)
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isCircle ? null : br,
                border: Border.all(
                    color: Color(c.borderColor),
                    width: math.max(1.0, c.borderW * m)),
              ),
            ),
          ),
        ),
    ];
    Widget out = Stack(clipBehavior: Clip.none, children: layers);
    if (a < 0.999) out = Opacity(opacity: a, child: out);
    return out;
  }

  Widget _frameOutline(PipClip c, double bw, double bh) {
    final border = Border.all(color: AyatColors.goldBright, width: 1.6);
    final m = math.min(bw, bh);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: switch (c.shape) {
          PipShape.rect => BoxDecoration(border: border),
          PipShape.rounded => BoxDecoration(
              border: border,
              borderRadius: BorderRadius.circular(m * c.radiusFrac)),
          PipShape.circle => BoxDecoration(border: border, shape: BoxShape.circle),
        },
      ),
    );
  }

  Widget _dot(IconData icon) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: const Color(0xE6050F0D),
          shape: BoxShape.circle,
          border: Border.all(color: AyatColors.goldBright, width: 1.4),
        ),
        child: Icon(icon, size: 16, color: AyatColors.goldBright),
      );

  List<Widget> _handles(
      PipClip c, int i, double bw, double bh, double fw, double fh) {
    final big = bw >= 70;
    return [
      // ✕ delete
      Positioned(
        left: _pad - 15,
        top: _pad - 15,
        width: 30,
        height: 30,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _delete(i),
          child: _dot(Icons.close),
        ),
      ),
      // ⤢ size + turn
      Positioned(
        left: _pad + bw - 15,
        top: _pad + bh - 15,
        width: 30,
        height: 30,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _hStart(c, i, d.globalPosition, fw, fh),
          onPanUpdate: (d) => _hUpdate(d.globalPosition, fw, fh),
          onPanEnd: (_) => _onEnd(c),
          onPanCancel: () => _onEnd(c),
          child: _dot(Icons.open_in_full),
        ),
      ),
      // ⇋ mirror
      if (big)
        Positioned(
          left: _pad + bw - 15,
          top: _pad - 15,
          width: 30,
          height: 30,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.state.update(() => c.flipH = !c.flipH);
            },
            child: _dot(Icons.flip),
          ),
        ),
      // ⧉ copy
      if (big)
        Positioned(
          left: _pad - 15,
          top: _pad + bh - 15,
          width: 30,
          height: 30,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.state.duplicatePipAt(i);
            },
            child: _dot(Icons.content_copy),
          ),
        ),
    ];
  }

  Widget? _clipWidget(StudioState st, int i, double t, double fw, double fh) {
    final c = st.pipClips[i];
    final sel = st.pipSel == i;
    final dragging = _dragId == c.id;
    final active = c.activeAt(t);
    // while the finger is on it the box stays put instead of animating
    final pose = (active && !dragging) ? c.poseAt(t) : PipPose.still;
    var a = active
        ? c.opacity.clamp(0.0, 1.0).toDouble() * (dragging ? 1.0 : pose.alpha)
        : 0.0;
    // a selected clip outside its window stays reachable as a ghost
    if (a < 0.01 && sel) a = 0.28;
    if (a < 0.01) return null;
    final cx = dragging ? _dCx : c.cx;
    final cy = dragging ? _dCy : c.cy;
    final w = dragging ? _dW : c.width;
    final rot = dragging ? _dRot : c.rot;
    final bw = w * fw;
    final bh = bw / c.boxAspect;
    final px = cx * fw + pose.dx * fw;
    final py = cy * fh + pose.dy * fh;
    final boxW = bw + 2 * _pad;
    final boxH = bh + 2 * _pad;
    final idx = i;
    final body = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.selectionClick();
        st.selectPip(idx);
      },
      onScaleStart: (d) => _onStart(c, idx, d),
      onScaleUpdate: (d) => _onUpdate(d, fw, fh),
      onScaleEnd: (_) => _onEnd(c),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: _look(c, bw, bh, a, _ctl[c.id])),
          if (sel) Positioned.fill(child: _frameOutline(c, bw, bh)),
        ],
      ),
    );
    Widget box = SizedBox(
      width: boxW,
      height: boxH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
              left: _pad, top: _pad, width: bw, height: bh, child: body),
          if (sel) ..._handles(c, idx, bw, bh, fw, fh),
        ],
      ),
    );
    if ((pose.scale - 1.0).abs() > 0.001) {
      box = Transform.scale(scale: pose.scale, child: box);
    }
    return Positioned(
      left: px - boxW / 2,
      top: py - boxH / 2,
      width: boxW,
      height: boxH,
      child: Transform.rotate(
        angle: (rot + pose.rot) * math.pi / 180.0,
        child: box,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    if (st.pipClips.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, box) {
      final fw = box.maxWidth;
      final fh = box.maxHeight;
      return ListenableBuilder(
        listenable: _frame,
        builder: (context, _) {
          final t = _now();
          final kids = <Widget>[];
          for (var i = 0; i < st.pipClips.length; i++) {
            final k = _clipWidget(st, i, t, fw, fh);
            if (k != null) kids.add(k);
          }
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ...kids,
              if (_snapV)
                Positioned(
                  left: fw / 2 - 0.5,
                  top: 0,
                  bottom: 0,
                  width: 1,
                  child: IgnorePointer(
                    child: ColoredBox(
                        color: AyatColors.goldBright.withValues(alpha: 0.7)),
                  ),
                ),
              if (_snapH)
                Positioned(
                  top: fh / 2 - 0.5,
                  left: 0,
                  right: 0,
                  height: 1,
                  child: IgnorePointer(
                    child: ColoredBox(
                        color: AyatColors.goldBright.withValues(alpha: 0.7)),
                  ),
                ),
            ],
          );
        },
      );
    });
  }
}

// ------------------------------------------------------------------- panel

class ProPipPage extends StatelessWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  final VoidCallback onAddVideo;
  final VoidCallback onAddImage;
  final void Function(String) onToast;
  const ProPipPage({
    super.key,
    required this.state,
    required this.controller,
    required this.onAddVideo,
    required this.onAddImage,
    required this.onToast,
  });

  double _t() => controller == null
      ? 0.0
      : controller!.value.position.inMilliseconds / 1000.0;

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
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

  Widget _btn(IconData icon, String label, VoidCallback onTap,
      {bool gold = false}) {
    return PressableScale(
      borderRadius: BorderRadius.circular(12),
      pressedScale: 0.92,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: gold ? AyatColors.gold.withValues(alpha: 0.22) : AyatColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: gold ? AyatColors.goldBright : AyatColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 17,
                color: gold ? AyatColors.goldBright : AyatColors.parchmentDim),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: gold ? AyatColors.goldBright : AyatColors.parchment)),
          ],
        ),
      ),
    );
  }

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5, color: AyatColors.parchment)),
          ),
          GoldSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _swatch(int argb, bool on, VoidCallback onTap) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Color(argb),
          shape: BoxShape.circle,
          border: Border.all(
              color: on ? AyatColors.goldBright : AyatColors.hairline,
              width: on ? 2.5 : 1),
        ),
      ),
    );
  }

  Widget _animChips(PipAnim current, ValueChanged<PipAnim> onPick) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        for (final a in PipAnim.values)
          ChoiceChip(
            label: Text(pipAnimLabel(a)),
            selected: current == a,
            onSelected: (_) => onPick(a),
          ),
      ],
    );
  }

  void _place(PipClip c, String where) {
    final (fw, fh) = state.frameSize;
    final fa = fw / fh;
    const m = 0.04;
    final hFrac = c.width * fa / c.boxAspect; // box height / frame height
    final my = m * fa;
    state.update(() {
      switch (where) {
        case 'c':
          c.cx = 0.5;
          c.cy = 0.5;
        case 'tl':
          c.cx = m + c.width / 2;
          c.cy = my + hFrac / 2;
        case 'tr':
          c.cx = 1 - m - c.width / 2;
          c.cy = my + hFrac / 2;
        case 'bl':
          c.cx = m + c.width / 2;
          c.cy = 1 - my - hFrac / 2;
        case 'br':
          c.cx = 1 - m - c.width / 2;
          c.cy = 1 - my - hFrac / 2;
      }
      c.cx = c.cx.clamp(0.0, 1.0).toDouble();
      c.cy = c.cy.clamp(0.0, 1.0).toDouble();
    });
  }

  void _playMotion(PipClip c) {
    final v = controller;
    if (v == null || !v.value.isInitialized) return;
    final from = math.max(0.0, c.start - 0.5);
    v.seekTo(Duration(milliseconds: (from * 1000).round())).then((_) => v.play());
  }

  Future<void> _pickKeyColor(BuildContext context, PipClip sel) async {
    final c = await showAyatColorPicker(context, Color(sel.keyColor));
    if (c == null) return;
    final argb = 0xFF000000 |
        ((c.r * 255).round() << 16) |
        ((c.g * 255).round() << 8) |
        (c.b * 255).round();
    state.update(() {
      sel.keyOn = true;
      sel.keyColor = argb;
    });
  }

  Future<void> _pickBorderColor(BuildContext context, PipClip sel) async {
    final c = await showAyatColorPicker(context, Color(sel.borderColor));
    if (c == null) return;
    final argb = 0xFF000000 |
        ((c.r * 255).round() << 16) |
        ((c.g * 255).round() << 8) |
        (c.b * 255).round();
    state.update(() {
      sel.borderColor = argb;
      if (!sel.hasBorder) sel.borderW = 0.03;
    });
  }

  Future<void> _keyFromCorner(PipClip sel) async {
    final argb = await PipKeyer.cornerColor(sel.path);
    if (argb == null) {
      onToast('تعذّر قراءة لون الخلفية');
      return;
    }
    state.update(() {
      sel.keyOn = true;
      sel.keyColor = argb;
    });
    onToast('تم اختيار لون الخلفية من زاوية الصورة');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final sel = state.selectedPip;
        final i = state.pipSel;
        final total = state.videoDurationSec > 0
            ? state.videoDurationSec
            : math.max(10.0, sel == null ? 10.0 : sel.end + 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                    child: _btn(Icons.video_library_outlined, 'إضافة فيديو',
                        onAddVideo,
                        gold: true)),
                const SizedBox(width: 10),
                Expanded(
                    child: _btn(Icons.image_outlined, 'إضافة صورة', onAddImage,
                        gold: true)),
              ],
            ),
            if (state.pipClips.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
                child: Text(
                  'أضف فيديو أو صورة تظهر فوق المقطع الأساسي، ثم اسحبها على الشاشة: '
                  'بإصبع واحد للتحريك، وبإصبعين للتكبير والتدوير، '
                  'أو استخدم الأزرار على زواياها.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.6,
                      color: AyatColors.parchmentDim),
                ),
              ),
            if (state.pipClips.isNotEmpty) ...[
              _title(context, 'المقاطع (${state.pipClips.length})'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var k = 0; k < state.pipClips.length; k++)
                    ChoiceChip(
                      avatar: Icon(
                          state.pipClips[k].isImage
                              ? Icons.image_outlined
                              : Icons.movie_outlined,
                          size: 16),
                      label: Text('PIP ${k + 1}'),
                      selected: k == i,
                      onSelected: (_) {
                        state.selectPip(k);
                        controller?.seekTo(Duration(
                            milliseconds:
                                (state.pipClips[k].start * 1000).round()));
                      },
                    ),
                ],
              ),
            ],
            if (sel != null) ...[
              // ------------------------------------------- size & place
              _title(context, 'الحجم والموضع'),
              _slider(
                label: 'الحجم',
                shown: '${(sel.width * 100).round()}%',
                value: sel.width,
                min: 0.08,
                max: 1.5,
                onChanged: (v) => state.update(() => sel.width = v),
              ),
              _slider(
                label: 'أفقي',
                shown: '${(sel.cx * 100).round()}%',
                value: sel.cx,
                min: 0,
                max: 1,
                onChanged: (v) => state.update(
                    () => sel.cx = (v - 0.5).abs() < 0.012 ? 0.5 : v),
              ),
              _slider(
                label: 'رأسي',
                shown: '${(sel.cy * 100).round()}%',
                value: sel.cy,
                min: 0,
                max: 1,
                onChanged: (v) => state.update(
                    () => sel.cy = (v - 0.5).abs() < 0.012 ? 0.5 : v),
              ),
              _slider(
                label: 'الدوران',
                shown: '${sel.rot.round()}°',
                value: sel.rot,
                min: -180,
                max: 180,
                onChanged: (v) => state.update(
                    () => sel.rot = v.abs() < 3 ? 0.0 : v.roundToDouble()),
              ),
              _slider(
                label: 'الشفافية',
                shown: '${(sel.opacity * 100).round()}%',
                value: sel.opacity,
                min: 0.05,
                max: 1.0,
                onChanged: (v) => state.update(() => sel.opacity = v),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn(Icons.center_focus_strong_outlined, 'وسط',
                      () => _place(sel, 'c')),
                  _btn(Icons.north_east, 'أعلى يمين', () => _place(sel, 'tr')),
                  _btn(Icons.north_west, 'أعلى يسار', () => _place(sel, 'tl')),
                  _btn(Icons.south_east, 'أسفل يمين', () => _place(sel, 'br')),
                  _btn(Icons.south_west, 'أسفل يسار', () => _place(sel, 'bl')),
                ],
              ),
              // ------------------------------------------- shape & frame
              _title(context, 'الشكل والإطار'),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in PipShape.values)
                    ChoiceChip(
                      label: Text(pipShapeLabel(s)),
                      selected: sel.shape == s,
                      onSelected: (_) => state.update(() => sel.shape = s),
                    ),
                ],
              ),
              if (sel.shape == PipShape.rounded)
                _slider(
                  label: 'الاستدارة',
                  shown: '${(sel.radiusFrac * 200).round()}%',
                  value: sel.radiusFrac,
                  min: 0,
                  max: 0.5,
                  onChanged: (v) => state.update(() => sel.radius = v),
                ),
              _slider(
                label: 'سمك الإطار',
                shown: sel.hasBorder ? '${(sel.borderW * 100).round()}' : 'بدون',
                value: sel.borderW,
                min: 0,
                max: 0.08,
                onChanged: (v) => state.update(() => sel.borderW = v),
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text('لون الإطار',
                        style: TextStyle(
                            fontSize: 12.5, color: AyatColors.parchment)),
                  ),
                  for (final col in const [
                    0xFFECC875,
                    0xFFFFFFFF,
                    0xFF000000,
                    0xFF2C6B5A,
                  ]) ...[
                    _swatch(col, sel.borderColor == col, () {
                      state.update(() {
                        sel.borderColor = col;
                        if (!sel.hasBorder) sel.borderW = 0.03;
                      });
                    }),
                    const SizedBox(width: 8),
                  ],
                  _btn(Icons.palette_outlined, 'لون',
                      () => _pickBorderColor(context, sel)),
                ],
              ),
              _switchRow('ظل خلف الصورة', sel.shadow,
                  (v) => state.update(() => sel.shadow = v)),
              Row(
                children: [
                  Expanded(
                    child: _switchRow('قلب أفقي', sel.flipH,
                        (v) => state.update(() => sel.flipH = v)),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _switchRow('قلب رأسي', sel.flipV,
                        (v) => state.update(() => sel.flipV = v)),
                  ),
                ],
              ),
              // ------------------------------------------- transparent bg
              _title(context, 'خلفية شفافة'),
              _switchRow('إزالة لون الخلفية', sel.keyOn,
                  (v) => state.update(() => sel.keyOn = v)),
              if (sel.keyOn) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final col in const [
                      0xFFFFFFFF,
                      0xFF000000,
                      0xFF00FF00,
                      0xFF0000FF,
                    ])
                      _swatch(col, sel.keyColor == col,
                          () => state.update(() => sel.keyColor = col)),
                    _btn(Icons.palette_outlined, 'لون آخر',
                        () => _pickKeyColor(context, sel)),
                    if (sel.isImage)
                      _btn(Icons.colorize, 'من زاوية الصورة',
                          () => _keyFromCorner(sel)),
                  ],
                ),
                _slider(
                  label: 'التسامح',
                  shown: '${(sel.keySim * 100).round()}%',
                  value: sel.keySim,
                  min: 0.02,
                  max: 0.60,
                  onChanged: (v) => state.update(() => sel.keySim = v),
                ),
                _slider(
                  label: 'نعومة الحافة',
                  shown: '${(sel.keyBlend * 100).round()}%',
                  value: sel.keyBlend,
                  min: 0,
                  max: 0.40,
                  onChanged: (v) => state.update(() => sel.keyBlend = v),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    sel.isImage
                        ? 'اللون المختار يصير شفافًا فتظهر الخلفية من خلفه — في المعاينة وفي الفيديو المُصدَّر.'
                        : 'للفيديو الصغير: تُطبَّق الشفافية في الفيديو المُصدَّر (المعاينة تعرض الفيديو كما هو).',
                    style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.5,
                        color: AyatColors.parchmentDim),
                  ),
                ),
              ],
              // ------------------------------------------- motion
              _title(context, 'الظهور'),
              _animChips(sel.inAnim,
                  (a) => state.update(() => sel.inAnim = a)),
              if (sel.inAnim != PipAnim.none)
                _slider(
                  label: 'المدة',
                  shown: '${sel.inDur.toStringAsFixed(1)} ث',
                  value: sel.inDur,
                  min: 0.1,
                  max: 2.0,
                  onChanged: (v) => state.update(
                      () => sel.inDur = (v * 10).round() / 10.0),
                ),
              _title(context, 'الاختفاء'),
              _animChips(sel.outAnim,
                  (a) => state.update(() => sel.outAnim = a)),
              if (sel.outAnim != PipAnim.none)
                _slider(
                  label: 'المدة',
                  shown: '${sel.outDur.toStringAsFixed(1)} ث',
                  value: sel.outDur,
                  min: 0.1,
                  max: 2.0,
                  onChanged: (v) => state.update(
                      () => sel.outDur = (v * 10).round() / 10.0),
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn(Icons.play_circle_outline, 'عرض الحركة',
                      () => _playMotion(sel),
                      gold: true),
                ],
              ),
              // ------------------------------------------- picture
              _title(context, 'ضبط الصورة'),
              _slider(
                label: 'السطوع',
                shown: sel.brightness.toStringAsFixed(2),
                value: sel.brightness,
                min: -0.4,
                max: 0.4,
                onChanged: (v) => state.update(
                    () => sel.brightness = v.abs() < 0.015 ? 0.0 : v),
              ),
              _slider(
                label: 'التباين',
                shown: sel.contrast.toStringAsFixed(2),
                value: sel.contrast,
                min: 0.5,
                max: 1.8,
                onChanged: (v) => state.update(
                    () => sel.contrast = (v - 1).abs() < 0.02 ? 1.0 : v),
              ),
              _slider(
                label: 'التشبّع',
                shown: sel.saturation.toStringAsFixed(2),
                value: sel.saturation,
                min: 0,
                max: 2,
                onChanged: (v) => state.update(
                    () => sel.saturation = (v - 1).abs() < 0.03 ? 1.0 : v),
              ),
              // ------------------------------------------- timing
              _title(context, 'التوقيت'),
              _slider(
                label: 'البداية',
                shown: '${sel.start.toStringAsFixed(1)} ث',
                value: sel.start,
                min: 0,
                max: total,
                onChanged: (v) {
                  state.pushHistory();
                  state.setPipWindow(i, start: (v * 10).round() / 10.0);
                },
              ),
              _slider(
                label: 'النهاية',
                shown: '${sel.end.toStringAsFixed(1)} ث',
                value: sel.end,
                min: 0,
                max: total,
                onChanged: (v) {
                  state.pushHistory();
                  state.setPipWindow(i, end: (v * 10).round() / 10.0);
                },
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn(Icons.first_page, 'ابدأ هنا', () {
                    state.pushHistory();
                    state.setPipWindow(i, start: _t());
                  }),
                  _btn(Icons.last_page, 'انتهِ هنا', () {
                    state.pushHistory();
                    state.setPipWindow(i, end: _t());
                  }),
                  _btn(Icons.fit_screen_outlined, 'حتى نهاية المقطع', () {
                    final d = state.videoDurationSec;
                    if (d <= 0) return;
                    state.pushHistory();
                    state.setPipWindow(i, end: d);
                  }),
                ],
              ),
              // ------------------------------------------- layer
              _title(context, 'الطبقة'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _btn(Icons.flip_to_front, 'إلى الأمام',
                      () => state.movePipLayer(i, 1)),
                  _btn(Icons.flip_to_back, 'إلى الخلف',
                      () => state.movePipLayer(i, -1)),
                  _btn(Icons.content_copy, 'نسخ', () {
                    state.duplicatePipAt(i);
                    onToast('تم النسخ');
                  }),
                  _btn(Icons.restart_alt, 'إعادة الضبط', () {
                    state.update(() {
                      sel.rot = 0;
                      sel.opacity = 1;
                      sel.flipH = false;
                      sel.flipV = false;
                      sel.borderW = 0;
                      sel.shadow = false;
                      sel.keyOn = false;
                      sel.brightness = 0;
                      sel.contrast = 1;
                      sel.saturation = 1;
                      sel.radius = kPipRounded;
                      sel.inAnim = PipAnim.fade;
                      sel.outAnim = PipAnim.fade;
                      sel.inDur = kPipFade;
                      sel.outDur = kPipFade;
                    });
                  }),
                  _btn(Icons.delete_outline, 'حذف', () {
                    state.removePipAt(i);
                  }),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'صوت المقطع الصغير مكتوم؛ يبقى صوت المقطع الأساسي والقارئ كما هما.',
                  style: TextStyle(
                      fontSize: 11.5,
                      height: 1.5,
                      color: AyatColors.parchmentDim),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
