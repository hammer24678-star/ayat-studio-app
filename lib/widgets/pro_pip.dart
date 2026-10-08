// PATCH_S188_PIP
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
