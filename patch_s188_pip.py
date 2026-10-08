#!/usr/bin/env python3
"""
patch_s188_pip.py - Ayat Studio S188 (run from repo root, after S187)

PIP (picture-in-picture), InShot style, plus the smoothness that goes with it.

  * New tool «PIP» in the tool strip (after الملصقات) and in the main clip's
    action bar: add a video or a picture from the gallery; it lands on the
    timeline at the playhead and floats over the main clip.
  * On the stage: one finger drags, two fingers resize and twist, it magnets
    to the centre and to upright / 90 degrees with a tick. While the finger is
    down only the PIP layer repaints (the change is committed once, on lift),
    so it follows the finger at full frame rate. Little videos play in step
    with the main clip (speed, pause, scrubbing, loop when shorter).
  * Its own timeline lane: tap to select, drag to move, gold edges to trim,
    snapping to the playhead / markers / other blocks with a tick.
  * Panel: size, opacity, rotation, shape (rectangle / rounded / circle),
    soft appear + disappear, corner presets, start/end at the playhead,
    layer order, copy, delete. Action bar: split, trim, order, copy, delete
    (delete has an undo bar).
  * Export: the same geometry burned in with ffmpeg (loops short videos, masks
    for rounded / circle, fades, rotation, timed overlay). Undo / redo covers it.
  * The little clip's own sound is muted (the main clip + reciter stay as is).

Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S188_PIP'
if not os.path.exists('lib/widgets/pro_timeline.dart'):
    sys.exit('Run from the repo root (missing lib/widgets/pro_timeline.dart).')

NEW_FILES = {
'lib/models/pip_clip.dart': r'''// PATCH_S188_PIP
// Picture-in-picture clips: a small video or picture floating over the main
// clip for a stretch of the timeline (InShot "PIP").
//
// Pure Dart. The preview (PipLayer) and the exporter (PipExport) both read
// THIS geometry, so what you see on the stage is what gets burned in.
//
// Times are seconds on the main clip's own clock - the same clock the text
// blocks and the ayah blocks use.

enum PipShape { rect, rounded, circle }

String pipShapeLabel(PipShape s) => switch (s) {
      PipShape.rect => 'مستطيل',
      PipShape.rounded => 'مدوّر',
      PipShape.circle => 'دائرة',
    };

/// Corner radius of the "rounded" shape, as a fraction of the shorter side.
const double kPipRounded = 0.14;

/// Length of the soft appear / disappear (seconds).
const double kPipFade = 0.30;

const double kPipMinLen = 0.3;

class PipClip {
  static int _seq = 1;

  /// Stable identity (survives undo / redo copies).
  final int id;
  String path;
  bool isImage;

  /// width / height of the media as it plays (rotation already applied).
  double aspect;

  /// Length of the media in seconds (0 for a picture).
  double mediaDur;

  /// Window on the main clip's clock.
  double start;
  double end;

  /// Where inside the media the window begins (seconds).
  double srcIn;

  /// Centre of the box as a fraction of the frame (0..1).
  double cx;
  double cy;

  /// Width of the box as a fraction of the frame width.
  double width;

  /// Degrees, clockwise.
  double rot;
  double opacity;
  PipShape shape;

  /// Soft appear / disappear at the two ends of the window.
  bool fade;

  PipClip({
    int? id,
    required this.path,
    required this.isImage,
    required this.aspect,
    this.mediaDur = 0,
    required this.start,
    required this.end,
    this.srcIn = 0,
    this.cx = 0.5,
    this.cy = 0.5,
    this.width = 0.5,
    this.rot = 0,
    this.opacity = 1,
    this.shape = PipShape.rounded,
    this.fade = true,
  }) : id = id ?? _seq++;

  PipClip copy() => PipClip(
        id: id,
        path: path,
        isImage: isImage,
        aspect: aspect,
        mediaDur: mediaDur,
        start: start,
        end: end,
        srcIn: srcIn,
        cx: cx,
        cy: cy,
        width: width,
        rot: rot,
        opacity: opacity,
        shape: shape,
        fade: fade,
      );

  /// A fresh clip (new identity) with the same look and timing.
  PipClip duplicate() => PipClip(
        path: path,
        isImage: isImage,
        aspect: aspect,
        mediaDur: mediaDur,
        start: start,
        end: end,
        srcIn: srcIn,
        cx: cx,
        cy: cy,
        width: width,
        rot: rot,
        opacity: opacity,
        shape: shape,
        fade: fade,
      );

  double get length => end - start;

  /// The shape of the box: a circle is always square (the media is
  /// centre-cropped), everything else keeps the media's own proportions.
  double get boxAspect {
    if (shape == PipShape.circle) return 1.0;
    return aspect.isFinite && aspect > 0.05 ? aspect.clamp(0.2, 5.0).toDouble() : 1.0;
  }

  bool activeAt(double t) => t >= start && t < end;

  /// 0..1 visibility at [t]: opacity times the soft ends.
  double alphaAt(double t) {
    if (!activeAt(t)) return 0;
    var a = opacity.clamp(0.0, 1.0).toDouble();
    if (fade) {
      final f = (length / 2) < kPipFade ? length / 2 : kPipFade;
      if (f > 0.001) {
        final i = ((t - start) / f).clamp(0.0, 1.0).toDouble();
        final o = ((end - t) / f).clamp(0.0, 1.0).toDouble();
        final m = i < o ? i : o;
        a *= m * m * (3 - 2 * m);
      }
    }
    return a;
  }

  /// Where in the media the picture should be at main-clock time [t]
  /// (loops when the media is shorter than the window).
  double mediaTimeAt(double t) {
    final raw = srcIn + (t - start);
    if (isImage || mediaDur < 0.05) return raw < 0 ? 0 : raw;
    final m = raw % mediaDur;
    return m < 0 ? m + mediaDur : m;
  }
}
''',
'lib/services/pip_export.dart': r'''// PATCH_S188_PIP
// Picture-in-picture in the exported video.
//
// Every clip becomes: media input -> scale/crop to its box -> (rounded /
// circle mask) -> opacity -> soft ends -> rotation -> shifted to its place on
// the timeline -> overlaid on the video for exactly its window. Same geometry
// as PipLayer (the live preview), so export == preview.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/pip_clip.dart';
import '../models/studio_state.dart';

/// What the exporter prepared before building the command.
class PipExportPrep {
  /// clip id -> mask PNG (rounded / circle shapes only).
  final Map<int, String> masks;

  /// clip ids whose media file still exists; null = trust every clip.
  final Set<int>? usable;
  const PipExportPrep({this.masks = const {}, this.usable});
}

/// One clip as it is exported.
class PipPlan {
  final PipClip clip;

  /// Window on the OUTPUT clock (seconds from the start of the export).
  final double ws;
  final double we;

  /// Where in the media the window starts.
  final double ss;

  /// Box in output pixels (always even).
  final int pw;
  final int ph;
  const PipPlan(this.clip, this.ws, this.we, this.ss, this.pw, this.ph);
  double get len => we - ws;
}

class PipExport {
  static int _even(double v, int lo) {
    var n = v.round();
    if (n < lo) n = lo;
    if (n.isOdd) n += 1;
    return n;
  }

  /// The clips that actually show in the export, in layer order.
  static List<PipPlan> plan(StudioState st, int w, int h, double clipStart,
      double duration, Set<int>? usable) {
    final out = <PipPlan>[];
    for (final c in st.pipClips) {
      if (usable != null && !usable.contains(c.id)) continue;
      final ws = (c.start - clipStart).clamp(0.0, duration).toDouble();
      final we = (c.end - clipStart).clamp(ws, duration).toDouble();
      if (we - ws < 0.1) continue;
      final pw = _even(w * c.width.clamp(0.05, 1.6).toDouble(), 16);
      final ph = _even(pw / c.boxAspect, 16);
      out.add(PipPlan(c, ws, we, c.mediaTimeAt(math.max(c.start, clipStart)),
          pw, ph));
    }
    return out;
  }

  /// Checks the files and draws the shape masks. Call before building the
  /// ffmpeg command.
  static Future<PipExportPrep> prepare(StudioState st, String workDir, int w,
      int h, double clipStart, double duration) async {
    if (st.pipClips.isEmpty) return const PipExportPrep();
    final usable = <int>{
      for (final c in st.pipClips)
        if (File(c.path).existsSync()) c.id
    };
    final masks = <int, String>{};
    for (final p in plan(st, w, h, clipStart, duration, usable)) {
      if (p.clip.shape == PipShape.rect) continue;
      final rect = ui.Rect.fromLTWH(0, 0, p.pw.toDouble(), p.ph.toDouble());
      final rec = ui.PictureRecorder();
      final cv = ui.Canvas(rec);
      cv.drawRect(rect, ui.Paint()..color = const ui.Color(0xFF000000));
      final paint = ui.Paint()
        ..color = const ui.Color(0xFFFFFFFF)
        ..isAntiAlias = true;
      if (p.clip.shape == PipShape.circle) {
        cv.drawOval(rect, paint);
      } else {
        cv.drawRRect(
            ui.RRect.fromRectAndRadius(
                rect,
                ui.Radius.circular(
                    math.min(p.pw, p.ph).toDouble() * kPipRounded)),
            paint);
      }
      final img = await rec.endRecording().toImage(p.pw, p.ph);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bd == null) continue;
      final f = File('$workDir/pipmask_${p.clip.id}.png');
      await f.writeAsBytes(bd.buffer.asUint8List());
      masks[p.clip.id] = f.path;
    }
    return PipExportPrep(masks: masks, usable: usable);
  }

  /// Adds the inputs and filters of every clip. Returns the new video label
  /// and the next free input index.
  static ({String base, int idx}) append({
    required StringBuffer inputs,
    required List<String> filters,
    required int idx,
    required String base,
    required StudioState st,
    required int w,
    required int h,
    required double clipStart,
    required double duration,
    required int fps,
    PipExportPrep? prep,
  }) {
    var n = 0;
    for (final p in plan(st, w, h, clipStart, duration, prep?.usable)) {
      final c = p.clip;
      final len = p.len;
      final lenS = len.toStringAsFixed(3);

      // ---- media input: pictures loop, short videos loop inside the window
      final inIdx = idx++;
      if (c.isImage) {
        inputs.write('-loop 1 -t $lenS -i "${c.path}" ');
      } else {
        final runsOut = c.mediaDur > 0.05 && (c.mediaDur - p.ss) < len - 0.02;
        inputs.write('${runsOut ? '-stream_loop -1 ' : ''}'
            '-ss ${p.ss.toStringAsFixed(3)} -t $lenS -i "${c.path}" ');
      }
      filters.add('[$inIdx:v]fps=$fps,'
          'scale=${p.pw}:${p.ph}:force_original_aspect_ratio=increase,'
          'crop=${p.pw}:${p.ph},format=rgba[pa$n]');
      var cur = 'pa$n';

      // ---- rounded / circle: a black-and-white mask becomes the alpha
      final maskPath = prep?.masks[c.id];
      if (c.shape != PipShape.rect && maskPath != null) {
        inputs.write('-loop 1 -t $lenS -i "$maskPath" ');
        final mIdx = idx++;
        filters.add('[$mIdx:v]format=gray[pm$n]');
        filters.add('[$cur][pm$n]alphamerge[pb$n]');
        cur = 'pb$n';
      }

      // ---- opacity, soft ends, rotation, then slide onto the timeline
      final tail = <String>[];
      if (c.opacity < 0.999) {
        tail.add(
            'colorchannelmixer=aa=${c.opacity.clamp(0.0, 1.0).toStringAsFixed(3)}');
      }
      if (c.fade) {
        final f = math.min(kPipFade, len / 2);
        if (f > 0.05) {
          tail.add('fade=t=in:st=0:d=${f.toStringAsFixed(3)}:alpha=1');
          tail.add(
              'fade=t=out:st=${(len - f).toStringAsFixed(3)}:d=${f.toStringAsFixed(3)}:alpha=1');
        }
      }
      if (c.rot.abs() > 0.05) {
        final a = (c.rot * math.pi / 180).toStringAsFixed(5);
        tail.add("rotate=a=$a:ow='rotw($a)':oh='roth($a)':c=none");
      }
      tail.add('setpts=PTS-STARTPTS+${p.ws.toStringAsFixed(3)}/TB');
      filters.add('[$cur]${tail.join(',')}[pip$n]');

      // ---- onto the picture, only inside its window
      final out = 'pipo$n';
      filters.add("[$base][pip$n]overlay="
          "x='${(c.cx * w).toStringAsFixed(2)}-w/2':"
          "y='${(c.cy * h).toStringAsFixed(2)}-h/2':"
          "eof_action=pass:"
          "enable='between(t,${p.ws.toStringAsFixed(3)},${p.we.toStringAsFixed(3)})'"
          "[$out]");
      base = out;
      n++;
    }
    return (base: base, idx: idx);
  }
}
''',
'lib/widgets/pro_pip.dart': r'''// PATCH_S188_PIP
// Picture-in-picture («PIP»).
//   PipLayer   - the live layer on the stage: plays the little clips in step
//                with the main clip and lets you drag / pinch / twist them
//                with the finger. While the finger is down only this layer
//                repaints; the change is committed once, when you let go.
//   ProPipPage - the tool panel (add, size, shape, opacity, timing, order).
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:video_player/video_player.dart';

import '../models/pip_clip.dart';
import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';
import 'gold_switch.dart';
import 'motion.dart';

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

  // finger gesture (kept local until the finger lifts)
  int _dragId = -1;
  double _dCx = 0.5, _dCy = 0.5, _dW = 0.5, _dRot = 0;
  double _bCx = 0.5, _bCy = 0.5, _bW = 0.5, _bRot = 0;
  Offset _gStart = Offset.zero;
  bool _snapV = false, _snapH = false;

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
    r = ((r + 180) % 360) - 180;
    for (final s in const [0.0, 90.0, -90.0, 180.0, -180.0]) {
      if ((r - s).abs() < 3) {
        r = s;
        break;
      }
    }
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

  // ---------------------------------------------------------------- build

  Widget _media(PipClip c, VideoPlayerController? vc) {
    if (c.isImage) {
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

  Widget _clipped(PipClip c, double bw, double bh, Widget child) {
    switch (c.shape) {
      case PipShape.rect:
        return ClipRect(child: child);
      case PipShape.rounded:
        return ClipRRect(
          borderRadius: BorderRadius.circular(math.min(bw, bh) * kPipRounded),
          child: child,
        );
      case PipShape.circle:
        return ClipOval(child: child);
    }
  }

  Widget _frameOutline(PipClip c, double bw, double bh) {
    final border = Border.all(color: AyatColors.goldBright, width: 1.6);
    return IgnorePointer(
      child: DecoratedBox(
        decoration: switch (c.shape) {
          PipShape.rect => BoxDecoration(border: border),
          PipShape.rounded => BoxDecoration(
              border: border,
              borderRadius:
                  BorderRadius.circular(math.min(bw, bh) * kPipRounded)),
          PipShape.circle => BoxDecoration(border: border, shape: BoxShape.circle),
        },
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
            final c = st.pipClips[i];
            final sel = st.pipSel == i;
            final dragging = _dragId == c.id;
            var a = c.alphaAt(t);
            // a selected clip outside its window stays reachable as a ghost
            if (a < 0.01 && sel) a = 0.28;
            if (a < 0.01) continue;
            final cx = dragging ? _dCx : c.cx;
            final cy = dragging ? _dCy : c.cy;
            final w = dragging ? _dW : c.width;
            final rot = dragging ? _dRot : c.rot;
            final bw = w * fw;
            final bh = bw / c.boxAspect;
            Widget body = _clipped(c, bw, bh,
                SizedBox.expand(child: _media(c, _ctl[c.id])));
            if (a < 0.999) body = Opacity(opacity: a, child: body);
            final idx = i;
            kids.add(Positioned(
              left: cx * fw - bw / 2,
              top: cy * fh - bh / 2,
              width: bw,
              height: bh,
              child: Transform.rotate(
                angle: rot * math.pi / 180.0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    st.selectPip(idx);
                  },
                  onScaleStart: (d) => _onStart(c, idx, d),
                  onScaleUpdate: (d) => _onUpdate(d, fw, fh),
                  onScaleEnd: (_) => _onEnd(c),
                  child: Stack(
                    children: [
                      Positioned.fill(child: body),
                      if (sel) Positioned.fill(child: _frameOutline(c, bw, bh)),
                      if (sel && bw >= 74)
                        Positioned(
                          top: 5,
                          left: 5,
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.mediumImpact();
                              st.removePipAt(idx);
                            },
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(
                                color: Color(0xCC050F0D),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 15, color: AyatColors.goldBright),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ));
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
        padding: const EdgeInsets.only(top: 12, bottom: 6),
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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final sel = state.selectedPip;
        final i = state.pipSel;
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
                  'بإصبع واحد للتحريك، وبإصبعين للتكبير والتدوير.',
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
              _title(context, 'الحجم والمظهر'),
              _slider(
                label: 'الحجم',
                shown: '${(sel.width * 100).round()}%',
                value: sel.width,
                min: 0.08,
                max: 1.5,
                onChanged: (v) => state.update(() => sel.width = v),
              ),
              _slider(
                label: 'الشفافية',
                shown: '${(sel.opacity * 100).round()}%',
                value: sel.opacity,
                min: 0.1,
                max: 1.0,
                onChanged: (v) => state.update(() => sel.opacity = v),
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
              _title(context, 'الشكل'),
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
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(
                    child: Text('ظهور واختفاء سلس',
                        style: TextStyle(
                            fontSize: 12.5, color: AyatColors.parchment)),
                  ),
                  GoldSwitch(
                    value: sel.fade,
                    onChanged: (v) => state.update(() => sel.fade = v),
                  ),
                ],
              ),
              _title(context, 'الموضع'),
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
              _title(context, 'التوقيت'),
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
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'من ${sel.start.toStringAsFixed(1)} ث إلى ${sel.end.toStringAsFixed(1)} ث',
                  style: const TextStyle(
                      fontSize: 11.5, color: AyatColors.parchmentDim),
                ),
              ),
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
''',
'test/pip_export_test.dart': r'''// PATCH_S188_PIP: the PIP geometry + the ffmpeg graph it adds.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/models/pip_clip.dart';
import 'package:ayat_studio_app/models/studio_state.dart';
import 'package:ayat_studio_app/services/pip_export.dart';

PipClip _clip({
  bool image = false,
  double start = 2,
  double end = 6,
  double mediaDur = 3,
  PipShape shape = PipShape.rect,
}) =>
    PipClip(
      path: '/tmp/x.mp4',
      isImage: image,
      aspect: 16 / 9,
      mediaDur: image ? 0 : mediaDur,
      start: start,
      end: end,
      shape: shape,
    );

void main() {
  test('alpha: 0 outside, soft at the ends, full in the middle', () {
    final c = _clip();
    expect(c.alphaAt(1.9), 0);
    expect(c.alphaAt(6.0), 0);
    expect(c.alphaAt(2.0), 0);
    expect(c.alphaAt(2.15), inInclusiveRange(0.1, 0.9));
    expect(c.alphaAt(4.0), 1);
  });

  test('mediaTimeAt loops short videos', () {
    final c = _clip(mediaDur: 3);
    expect(c.mediaTimeAt(2.0), closeTo(0, 1e-9));
    expect(c.mediaTimeAt(4.0), closeTo(2, 1e-9));
    expect(c.mediaTimeAt(5.5), closeTo(0.5, 1e-9));
  });

  test('circle is always square', () {
    expect(_clip(shape: PipShape.circle).boxAspect, 1.0);
  });

  test('plan: even sizes, window shifted by clipStart, tiny clips dropped', () {
    final st = StudioState();
    st.pipClips = [_clip(), _clip(start: 20, end: 20.05)];
    final p = PipExport.plan(st, 1080, 1920, 1.0, 10.0, null);
    expect(p.length, 1);
    expect(p.first.ws, closeTo(1.0, 1e-9));
    expect(p.first.we, closeTo(5.0, 1e-9));
    expect(p.first.pw.isEven && p.first.ph.isEven, isTrue);
  });

  test('graph: every label consumed is produced; inputs line up', () {
    final st = StudioState();
    st.pipClips = [
      _clip(shape: PipShape.circle),
      _clip(image: true, start: 1, end: 3),
    ];
    final inputs = StringBuffer('-y -i main.mp4 ');
    final filters = <String>[];
    final prep = PipExportPrep(
      masks: {st.pipClips[0].id: '/tmp/m0.png'},
    );
    final r = PipExport.append(
      inputs: inputs,
      filters: filters,
      idx: 1,
      base: 'base',
      st: st,
      w: 1080,
      h: 1920,
      clipStart: 0,
      duration: 10,
      fps: 30,
      prep: prep,
    );
    expect(r.base, 'pipo1');
    final nInputs = RegExp(r' -i ').allMatches(' ${inputs.toString()}').length;
    expect(r.idx, nInputs);
    final produced = <String>{'base'};
    for (final f in filters) {
      final tail = RegExp(r'\[([^\]]+)\]$').firstMatch(f);
      if (tail != null) produced.add(tail.group(1)!);
    }
    for (final f in filters) {
      final lead = RegExp(r'^((?:\[[^\]]+\])+)').firstMatch(f);
      if (lead == null) continue;
      for (final m in RegExp(r'\[([^\]]+)\]').allMatches(lead.group(1)!)) {
        final l = m.group(1)!;
        if (RegExp(r'^\d+:').hasMatch(l)) {
          expect(int.parse(l.split(':').first) < r.idx, isTrue, reason: l);
        } else {
          expect(produced.contains(l), isTrue, reason: l);
        }
      }
    }
  });
}
''',
}

FILES = {
  'lib/models/studio_state.dart': [
    ('import', "import 'video_transform.dart'; // PATCH_S180_TRANSFORM\n", "import 'video_transform.dart'; // PATCH_S180_TRANSFORM\nimport 'pip_clip.dart'; // PATCH_S188_PIP\n"),
    ('pip state + methods', '  bool get hasVideoTransform =>\n', '  // ---- PATCH_S188_PIP: picture-in-picture clips -------------------------\n  List<PipClip> pipClips = []; // layer order: last = on top\n  int pipSel = -1; // selection only, not part of undo\n\n  bool get hasPipSel => pipSel >= 0 && pipSel < pipClips.length;\n  PipClip? get selectedPip => hasPipSel ? pipClips[pipSel] : null;\n\n  void selectPip(int i) {\n    final v = (i >= 0 && i < pipClips.length) ? i : -1;\n    if (v == pipSel) return;\n    pipSel = v;\n    if (v >= 0) stageTextSelected = false;\n    notifyListeners();\n  }\n\n  void addPip(PipClip c) {\n    pushHistory();\n    pipClips = [...pipClips, c];\n    pipSel = pipClips.length - 1;\n    stageTextSelected = false;\n    notifyListeners();\n  }\n\n  void removePipAt(int i) {\n    if (i < 0 || i >= pipClips.length) return;\n    pushHistory();\n    pipClips = [...pipClips]..removeAt(i);\n    pipSel = -1;\n    notifyListeners();\n  }\n\n  void duplicatePipAt(int i) {\n    if (i < 0 || i >= pipClips.length) return;\n    pushHistory();\n    final d = pipClips[i].duplicate();\n    d.cx = (d.cx + 0.06).clamp(0.0, 1.0).toDouble();\n    d.cy = (d.cy + 0.06).clamp(0.0, 1.0).toDouble();\n    pipClips = [...pipClips]..insert(i + 1, d);\n    pipSel = i + 1;\n    notifyListeners();\n  }\n\n  /// Moves one or both edges (seconds). Trimming the start keeps the picture\n  /// in step (the part of the media that plays moves with it).\n  void setPipWindow(int i, {double? start, double? end}) {\n    if (i < 0 || i >= pipClips.length) return;\n    final c = pipClips[i];\n    var s = start ?? c.start;\n    var e = end ?? c.end;\n    if (s < 0) s = 0;\n    if (e - s < kPipMinLen) {\n      if (start != null) {\n        s = e - kPipMinLen;\n      } else {\n        e = s + kPipMinLen;\n      }\n    }\n    if (s < 0) {\n      s = 0;\n      e = kPipMinLen;\n    }\n    if (start != null && !c.isImage) {\n      final ni = c.srcIn + (s - c.start);\n      c.srcIn = ni < 0 ? 0.0 : ni;\n    }\n    c.start = s;\n    c.end = e;\n    notifyListeners();\n  }\n\n  /// Slides the whole clip so it starts at [s] (length unchanged).\n  void movePipTo(int i, double s) {\n    if (i < 0 || i >= pipClips.length) return;\n    final c = pipClips[i];\n    final len = c.end - c.start;\n    c.start = s < 0 ? 0.0 : s;\n    c.end = c.start + len;\n    notifyListeners();\n  }\n\n  /// Cuts a clip in two at [t]. False when [t] is too close to an edge.\n  bool splitPipAt(int i, double t) {\n    if (i < 0 || i >= pipClips.length) return false;\n    final c = pipClips[i];\n    if (t <= c.start + kPipMinLen || t >= c.end - kPipMinLen) return false;\n    pushHistory();\n    final second = c.duplicate();\n    second.start = t;\n    second.end = c.end;\n    second.srcIn = c.isImage ? 0.0 : c.srcIn + (t - c.start);\n    c.end = t;\n    pipClips = [...pipClips]..insert(i + 1, second);\n    pipSel = i + 1;\n    notifyListeners();\n    return true;\n  }\n\n  /// [dir] +1 = one layer closer to the front, -1 = one layer back.\n  void movePipLayer(int i, int dir) {\n    final j = i + dir;\n    if (i < 0 || i >= pipClips.length || j < 0 || j >= pipClips.length) return;\n    pushHistory();\n    final next = [...pipClips];\n    final tmp = next[i];\n    next[i] = next[j];\n    next[j] = tmp;\n    pipClips = next;\n    pipSel = j;\n    notifyListeners();\n  }\n\n  bool get hasVideoTransform =>\n'),
    ('undo capture', "        'videoKeyEase': videoKeyEase,\n", "        'videoKeyEase': videoKeyEase,\n        'pipClips': [for (final c in pipClips) c.copy()], // PATCH_S188_PIP\n        'pipSel': pipSel,\n"),
    ('undo restore', "    videoKeyEase = s['videoKeyEase'] as bool;\n", "    videoKeyEase = s['videoKeyEase'] as bool;\n    // PATCH_S188_PIP\n    pipClips = [for (final c in (s['pipClips'] as List).cast<PipClip>()) c.copy()];\n    pipSel = s['pipSel'] as int;\n    if (pipSel >= pipClips.length) pipSel = -1;\n"),
  ],
  'lib/widgets/pro_timeline.dart': [
    ('import', "import '../models/studio_state.dart';\n", "import '../models/pip_clip.dart'; // PATCH_S188_PIP\nimport '../models/studio_state.dart';\n"),
    ('lane list', '    return [\n      if (s.textTimeCues.isNotEmpty ||\n', "    return [\n      if (s.pipClips.isNotEmpty) // PATCH_S188_PIP\n        _LaneSpec('pip', Icons.picture_in_picture_alt_outlined, c ? 28 : 36),\n      if (s.textTimeCues.isNotEmpty ||\n"),
    ('lane body', "      'text' => _textLane(l.h, w),\n", "      'pip' => _pipLane(l.h, w), // PATCH_S188_PIP\n      'text' => _textLane(l.h, w),\n"),
    ('lane methods', '  // PATCH_S181_CLIPTOUCH: text blocks show their text, can be selected, and\n  // their edges are dragged with the finger.\n  Widget _textLane(double h, double w) {\n', "  // ---- PATCH_S188_PIP: the lane of the little clips -------------------------\n  // tap = select, drag a selected clip = move it, the two gold edges = trim.\n  Widget _pipLane(double h, double w) {\n    final clips = widget.state.pipClips;\n    return GestureDetector(\n      behavior: HitTestBehavior.opaque,\n      onTapUp: (d) {\n        widget.state.selectPip(-1);\n        _seekSec(d.localPosition.dx / _pps);\n      },\n      child: Stack(\n        children: [\n          for (var i = 0; i < clips.length; i++) _pipClip(i, h),\n        ],\n      ),\n    );\n  }\n\n  double _pipBase = 0;\n  double _pipAccum = 0;\n  bool _pipSnapped = false;\n\n  List<double> _pipSnapPoints(int skip) => <double>[\n        widget.controller.value.position.inMilliseconds / 1000.0,\n        ...widget.markers,\n        for (var k = 0; k < widget.state.pipClips.length; k++)\n          if (k != skip) ...[\n            widget.state.pipClips[k].start,\n            widget.state.pipClips[k].end\n          ],\n        for (final s in widget.state.timeline) ...[s.start, s.end],\n        for (final q in widget.state.textTimeCues) ...[q.start, q.end],\n        0,\n        _dur,\n      ];\n\n  Widget _pipClip(int i, double h) {\n    final clips = widget.state.pipClips;\n    if (i >= clips.length) return const SizedBox.shrink();\n    final c = clips[i];\n    final sel = widget.state.pipSel == i;\n    final w = math.max(10.0, (c.end - c.start) * _pps - 1);\n    return Positioned(\n      left: c.start * _pps,\n      width: w,\n      top: 2,\n      height: h - 4,\n      child: GestureDetector(\n        behavior: HitTestBehavior.opaque,\n        onTapUp: (d) {\n          widget.onSelectSeg(-1);\n          widget.onSelectCue?.call(-1);\n          widget.onSelectMain?.call(false);\n          widget.state.selectPip(sel ? -1 : i);\n          _seekSec(c.start + d.localPosition.dx / _pps);\n          if (!sel) _zoomIfNarrow(c.start, c.end);\n          HapticFeedback.selectionClick();\n        },\n        onHorizontalDragStart: sel\n            ? (_) {\n                widget.state.pushHistory();\n                _pipBase = c.start;\n                _pipAccum = 0;\n                _pipSnapped = false;\n                HapticFeedback.selectionClick();\n              }\n            : null,\n        onHorizontalDragUpdate: sel\n            ? (d) {\n                _pipAccum += d.delta.dx;\n                _movePip(i);\n              }\n            : null,\n        child: Stack(\n          children: [\n            Positioned.fill(child: _pipBody(c, i, sel)),\n            if (sel) ...[\n              _pipHandle(i, true, w),\n              _pipHandle(i, false, w),\n            ],\n          ],\n        ),\n      ),\n    );\n  }\n\n  Widget _pipBody(PipClip c, int i, bool sel) {\n    return Container(\n      clipBehavior: Clip.antiAlias,\n      padding: EdgeInsets.symmetric(horizontal: sel ? 24 : 6),\n      alignment: Alignment.centerLeft,\n      decoration: BoxDecoration(\n        color: const Color(0xFF4A3D7A),\n        borderRadius: BorderRadius.circular(6),\n        border: Border.all(\n          color: sel ? AyatColors.goldBright : const Color(0x66C9B8FF),\n          width: sel ? 2 : 1,\n        ),\n        image: c.isImage\n            ? DecorationImage(\n                image: ResizeImage(FileImage(File(c.path)), width: 160),\n                fit: BoxFit.cover,\n                opacity: 0.45,\n              )\n            : null,\n      ),\n      child: Row(\n        mainAxisSize: MainAxisSize.min,\n        children: [\n          Icon(c.isImage ? Icons.image_outlined : Icons.movie_outlined,\n              size: 13, color: AyatColors.parchment),\n          const SizedBox(width: 4),\n          Flexible(\n            child: Text(\n              'PIP ${i + 1}',\n              maxLines: 1,\n              overflow: TextOverflow.clip,\n              style: const TextStyle(\n                  fontSize: 11.5,\n                  fontWeight: FontWeight.w700,\n                  color: AyatColors.parchment),\n            ),\n          ),\n        ],\n      ),\n    );\n  }\n\n  Widget _pipHandle(int i, bool isStart, double clipW) {\n    return Positioned(\n      left: isStart ? 0 : null,\n      right: isStart ? null : 0,\n      top: 0,\n      bottom: 0,\n      width: _handleW(clipW),\n      child: GestureDetector(\n        behavior: HitTestBehavior.opaque,\n        onHorizontalDragStart: (_) {\n          final clips = widget.state.pipClips;\n          if (i >= clips.length) return;\n          widget.state.pushHistory();\n          _pipBase = isStart ? clips[i].start : clips[i].end;\n          _pipAccum = 0;\n          _pipSnapped = false;\n          HapticFeedback.selectionClick();\n        },\n        onHorizontalDragUpdate: (d) {\n          _pipAccum += d.delta.dx;\n          _movePipEdge(i, isStart);\n        },\n        child: _handleBody(isStart),\n      ),\n    );\n  }\n\n  void _movePip(int i) {\n    final clips = widget.state.pipClips;\n    if (i < 0 || i >= clips.length) return;\n    final c = clips[i];\n    final len = c.end - c.start;\n    var s = _pipBase + _pipAccum / _pps;\n    final tol = _snap ? 8 / _pps : -1.0;\n    var hit = false;\n    for (final x in _pipSnapPoints(i)) {\n      if ((x - s).abs() <= tol) {\n        s = x;\n        hit = true;\n        break;\n      }\n      if ((x - (s + len)).abs() <= tol) {\n        s = x - len;\n        hit = true;\n        break;\n      }\n    }\n    if (hit && !_pipSnapped) HapticFeedback.selectionClick();\n    _pipSnapped = hit;\n    s = s.clamp(0.0, math.max(0.0, _dur - len)).toDouble();\n    if ((s - c.start).abs() < 0.001) return;\n    widget.state.movePipTo(i, s);\n  }\n\n  void _movePipEdge(int i, bool isStart) {\n    final clips = widget.state.pipClips;\n    if (i < 0 || i >= clips.length) return;\n    final c = clips[i];\n    var target = _pipBase + _pipAccum / _pps;\n    final tol = _snap ? 8 / _pps : -1.0;\n    var hit = false;\n    for (final x in _pipSnapPoints(i)) {\n      if ((x - target).abs() <= tol) {\n        target = x;\n        hit = true;\n        break;\n      }\n    }\n    if (hit && !_pipSnapped) HapticFeedback.selectionClick();\n    _pipSnapped = hit;\n    target = target.clamp(0.0, _dur).toDouble();\n    if (isStart) {\n      if ((target - c.start).abs() < 0.001) return;\n      widget.state.setPipWindow(i, start: target);\n    } else {\n      if ((target - c.end).abs() < 0.001) return;\n      widget.state.setPipWindow(i, end: target);\n    }\n  }\n\n  // PATCH_S181_CLIPTOUCH: text blocks show their text, can be selected, and\n  // their edges are dragged with the finger.\n  Widget _textLane(double h, double w) {\n"),
  ],
  'lib/widgets/stage_preview.dart': [
    ('import', "import 'pro_transform.dart'; // PATCH_S180_TRANSFORM\n", "import 'pro_transform.dart'; // PATCH_S180_TRANSFORM\nimport 'pro_pip.dart'; // PATCH_S188_PIP\n"),
    ('pip layer', '                  )), // PATCH_S85_VIDEO_ADJUST: closes ImageFiltered + VideoXformLayer\n', '                  )), // PATCH_S85_VIDEO_ADJUST: closes ImageFiltered + VideoXformLayer\n                // PATCH_S188_PIP: the little clips float above the video (and its blur),\n                // under the particles and the text - same order as the export.\n                if (state.pipClips.isNotEmpty)\n                  Positioned.fill(\n                    child: PipLayer(state: state, main: controller),\n                  ),\n'),
  ],
  'lib/screens/home_screen.dart': [
    ('imports', "import '../widgets/pro_transform.dart'; // PATCH_S180_TRANSFORM\n", "import '../widgets/pro_transform.dart'; // PATCH_S180_TRANSFORM\nimport '../widgets/pro_pip.dart'; // PATCH_S188_PIP\nimport '../models/pip_clip.dart'; // PATCH_S188_PIP\n"),
    ('tool strip', "        (110, Icons.emoji_emotions_outlined, 'ملصقات'),\n", "        (110, Icons.emoji_emotions_outlined, 'ملصقات'),\n        (113, Icons.picture_in_picture_alt_outlined, 'PIP'), // PATCH_S188_PIP\n"),
    ('tool body', '      case 112: // PATCH_S180_TRANSFORM\n        return ProTransformPage(state: state, controller: _video);\n', '      case 112: // PATCH_S180_TRANSFORM\n        return ProTransformPage(state: state, controller: _video);\n      case 113: // PATCH_S188_PIP\n        return ProPipPage(\n          state: state,\n          controller: _video,\n          onAddVideo: () => _addPip(image: false),\n          onAddImage: () => _addPip(image: true),\n          onToast: _toast,\n        );\n'),
    ('main clip bar', "        (Icons.open_with, 'التحويل', () => _openToolFromClip(112), false),\n", "        (Icons.open_with, 'التحويل', () => _openToolFromClip(112), false),\n        (Icons.picture_in_picture_alt_outlined, 'PIP', () => _openToolFromClip(113), _toolOpen == 113), // PATCH_S188_PIP\n"),
    ('pip clip bar', '    if (state.stageTextSelected && !_hasSelSeg) return _clipBar(_textItems());\n', '    if (state.stageTextSelected && !_hasSelSeg) return _clipBar(_textItems());\n    if (state.hasPipSel && !_hasSelSeg) return _clipBar(_pipItems()); // PATCH_S188_PIP\n'),
    ('any selection', '      _hasSelSeg || _hasSelCue || _hasSelMain || state.stageTextSelected; // PATCH_S183_TEXT_BAR', '      _hasSelSeg || _hasSelCue || _hasSelMain || state.stageTextSelected || state.hasPipSel; // PATCH_S183_TEXT_BAR + PATCH_S188_PIP'),
    ('timeline: seg', '          onSelectSeg: (i) {\n            state.clearStageSelection(); // PATCH_S183_TEXT_BAR\n', '          onSelectSeg: (i) {\n            state.clearStageSelection(); // PATCH_S183_TEXT_BAR\n            if (i >= 0) state.selectPip(-1); // PATCH_S188_PIP\n'),
    ('timeline: cue + main', '          onSelectCue: (i) => setState(() {\n            _selCue = i;\n            _selSeg = -1;\n            _selMain = false;\n          }),\n          selectedMain: _hasSelMain,\n          onSelectMain: (v) => setState(() {\n            _selMain = v;\n            if (v) {\n              _selSeg = -1;\n              _selCue = -1;\n            }\n          }),\n', '          onSelectCue: (i) {\n            if (i >= 0) state.selectPip(-1); // PATCH_S188_PIP\n            setState(() {\n              _selCue = i;\n              _selSeg = -1;\n              _selMain = false;\n            });\n          },\n          selectedMain: _hasSelMain,\n          onSelectMain: (v) {\n            if (v) state.selectPip(-1); // PATCH_S188_PIP\n            setState(() {\n              _selMain = v;\n              if (v) {\n                _selSeg = -1;\n                _selCue = -1;\n              }\n            });\n          },\n'),
    ('pip methods', '  Future<void> _addMediaSheet() async {\n', "  // ---------------------------------------------------------------------\n  // PATCH_S188_PIP: a little video / picture floating over the main clip.\n  // ---------------------------------------------------------------------\n\n  Future<void> _addPip({required bool image}) async {\n    final main = _video;\n    if (!state.hasVideo || main == null || !main.value.isInitialized) {\n      _toast('ارفع فيديو أولًا');\n      return;\n    }\n    final res = await FilePicker.platform\n        .pickFiles(type: image ? FileType.image : FileType.video);\n    final path = res?.files.single.path;\n    if (path == null || !mounted) return;\n    var aspect = 9 / 16;\n    var mediaDur = 0.0;\n    try {\n      if (image) {\n        final bytes = await File(path).readAsBytes();\n        final img = await decodeImageFromList(bytes);\n        aspect = img.width / img.height;\n        img.dispose();\n      } else {\n        final probe = VideoPlayerController.file(File(path));\n        try {\n          await probe.initialize();\n          aspect = probe.value.size.width / probe.value.size.height;\n          mediaDur = probe.value.duration.inMilliseconds / 1000.0;\n        } finally {\n          await probe.dispose();\n        }\n      }\n    } catch (_) {\n      _toast('تعذّر فتح الملف');\n      return;\n    }\n    if (!aspect.isFinite || aspect <= 0.05) {\n      _toast('هذا الملف لا يحتوي على صورة');\n      return;\n    }\n    if (!mounted) return;\n    final total = main.value.duration.inMilliseconds / 1000.0;\n    final want = image ? 4.0 : (mediaDur > 0.5 ? mediaDur : 4.0);\n    var start = _playheadSec;\n    var end = start + want;\n    if (end > total) {\n      end = total;\n      start = (total - want) < 0 ? 0.0 : (total - want);\n    }\n    if (end - start < 0.5) {\n      _toast('المقطع الأساسي قصير جدًّا');\n      return;\n    }\n    state.addPip(PipClip(\n      path: path,\n      isImage: image,\n      aspect: aspect,\n      mediaDur: mediaDur,\n      start: start,\n      end: end,\n      width: aspect < 0.8 ? 0.36 : 0.5,\n    ));\n    HapticFeedback.mediumImpact();\n    if (_toolOpen != 113) _openTool(113);\n    _toast(image ? 'أُضيفت الصورة' : 'أُضيف الفيديو');\n  }\n\n  List<(IconData, String, VoidCallback, bool)> _pipItems() {\n    final i = state.pipSel;\n    return [\n      (\n        Icons.check_circle_outline,\n        'تم',\n        () {\n          state.selectPip(-1);\n          setState(() => _toolOpen = -1);\n        },\n        false\n      ),\n      (Icons.tune, 'الخصائص', () => _openToolFromClip(113), _toolOpen == 113),\n      (Icons.content_cut, 'تقسيم', () => _pipSplit(i), false),\n      (Icons.first_page, 'قص البداية', () => _pipTrim(i, head: true), false),\n      (Icons.last_page, 'قص النهاية', () => _pipTrim(i, head: false), false),\n      (Icons.flip_to_front, 'للأمام', () => state.movePipLayer(i, 1), false),\n      (Icons.flip_to_back, 'للخلف', () => state.movePipLayer(i, -1), false),\n      (Icons.content_copy, 'نسخ', () => state.duplicatePipAt(i), false),\n      (Icons.delete_outline, 'حذف', () => _pipDelete(i), false),\n    ];\n  }\n\n  void _pipSplit(int i) {\n    if (state.splitPipAt(i, _playheadSec)) {\n      HapticFeedback.mediumImpact();\n    } else {\n      _toast('ضع المؤشر داخل المقطع الصغير ثم قسّم');\n    }\n  }\n\n  void _pipTrim(int i, {required bool head}) {\n    if (i < 0 || i >= state.pipClips.length) return;\n    final c = state.pipClips[i];\n    final t = _playheadSec;\n    if (t <= c.start + 0.3 || t >= c.end - 0.3) {\n      _toast('ضع المؤشر داخل المقطع الصغير ثم اقصّ');\n      return;\n    }\n    HapticFeedback.mediumImpact();\n    state.pushHistory();\n    state.setPipWindow(i, start: head ? t : null, end: head ? null : t);\n  }\n\n  void _pipDelete(int i) {\n    if (i < 0 || i >= state.pipClips.length) return;\n    HapticFeedback.mediumImpact();\n    state.removePipAt(i);\n    ScaffoldMessenger.of(context)\n      ..hideCurrentSnackBar()\n      ..showSnackBar(SnackBar(\n        content: const Text('تم حذف المقطع الصغير', textAlign: TextAlign.center),\n        behavior: SnackBarBehavior.floating,\n        duration: const Duration(seconds: 5),\n        action: SnackBarAction(\n          label: 'تراجع',\n          textColor: AyatColors.goldBright,\n          onPressed: state.undoStep,\n        ),\n      ));\n  }\n\n  Future<void> _addMediaSheet() async {\n"),
  ],
  'lib/services/export_service.dart': [
    ('import', "import 'overlay_renderer.dart';\n", "import 'overlay_renderer.dart';\nimport 'pip_export.dart'; // PATCH_S188_PIP\n"),
    ('signature', "    required String outPath,\n  }) {\n    final inputs = StringBuffer('-y ');\n", "    required String outPath,\n    PipExportPrep? pip, // PATCH_S188_PIP\n  }) {\n    final inputs = StringBuffer('-y ');\n"),
    ('graph', '    if (effectSeqPattern != null) {\n      inputs.write(\n          \'-framerate ${StageEffects.exportFps} -stream_loop -1 -start_number 0 -i "$effectSeqPattern" \');\n', '    // PATCH_S188_PIP: picture-in-picture clips sit above the video (and its blur),\n    // under the particles and the text - the same order as the live preview.\n    if (state.pipClips.isNotEmpty) {\n      final r = PipExport.append(\n        inputs: inputs,\n        filters: filters,\n        idx: idx,\n        base: base,\n        st: state,\n        w: w,\n        h: h,\n        clipStart: clipStart,\n        duration: duration,\n        fps: _fps,\n        prep: pip,\n      );\n      base = r.base;\n      idx = r.idx;\n    }\n\n    if (effectSeqPattern != null) {\n      inputs.write(\n          \'-framerate ${StageEffects.exportFps} -stream_loop -1 -start_number 0 -i "$effectSeqPattern" \');\n'),
    ('prepare', '      final reciterPath = state.selectedReciterAudio;\n      final cmd = buildMainCommand(\n', "      final reciterPath = state.selectedReciterAudio;\n      // PATCH_S188_PIP: check the little clips' files and draw their shape masks\n      final pipPrep = await PipExport.prepare(\n          state, work.path, w, h, clipStart, duration);\n      final cmd = buildMainCommand(\n"),
    ('pass', '        outPath: mainMp4,\n      );\n      await _run(cmd, duration', '        outPath: mainMp4,\n        pip: pipPrep, // PATCH_S188_PIP\n      );\n      await _run(cmd, duration'),
  ],
}

def read(p):
    return open(p, encoding='utf-8').read()

# already applied?
if all(os.path.exists(p) for p in NEW_FILES) and MARK in read('lib/models/studio_state.dart'):
    print('  OK      already applied'); sys.exit(0)

bad = []
texts = {}
for path, edits in FILES.items():
    if not os.path.exists(path):
        bad.append('%s (file missing)' % path); continue
    t = read(path)
    if MARK in t:
        bad.append('%s (already contains %s - half-applied? restore it with git checkout first)' % (path, MARK)); continue
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
print('S188 applied. Next: git add -A && git commit -m "S188: PIP" && git push')
