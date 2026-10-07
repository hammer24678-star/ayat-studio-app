// PATCH_S174_PRO_EDITOR
// Multi-track timeline in the style of CapCut / Premiere Pro / DaVinci Resolve:
// time ruler, a playhead that follows playback, one lane per kind of media
// (text cues, ayah clips, video, original audio, reciter audio, music bed),
// real audio waveforms, trim handles with snapping, markers, pinch-to-zoom.
//
// Time always runs left to right (the whole widget is forced LTR); only the
// Arabic labels inside clips are laid out right to left.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback; // PATCH_S179_AAA
import 'package:video_player/video_player.dart';

import '../models/studio_state.dart';
import '../services/thumb_service.dart';
import '../services/waveform_service.dart';
import '../theme/ayat_theme.dart';

class ProTimeline extends StatefulWidget {
  final StudioState state;
  final VideoPlayerController controller;

  /// Index into state.timeline of the selected ayah clip, or -1.
  final int selectedSeg;
  final ValueChanged<int> onSelectSeg;

  /// Marker positions in seconds (owned by the parent, mutated in place).
  final List<double> markers;

  /// Fewer lanes / shorter lanes while a tool panel is open.
  final bool compact;

  const ProTimeline({
    super.key,
    required this.state,
    required this.controller,
    required this.selectedSeg,
    required this.onSelectSeg,
    required this.markers,
    this.compact = false,
  });

  @override
  State<ProTimeline> createState() => ProTimelineState();
}

class _LaneSpec {
  final String id;
  final IconData icon;
  final double h;
  const _LaneSpec(this.id, this.icon, this.h);
}

class _PeakSlot {
  String? path;
  List<double>? peaks;
}

class ProTimelineState extends State<ProTimeline> {
  static const double _gutter = 48;
  static const double _rulerH = 24;
  static const double _minPps = 6;
  static const double _maxPps = 400;

  double _pps = 36;
  double _viewW = 300;
  final ScrollController _scroll = ScrollController();

  // two-finger pinch zoom (Listener only, so it never fights the scroll view)
  final Map<int, Offset> _ptrs = {};
  double _lastPinch = 0;
  bool _pinching = false;

  final Set<String> _locked = {};
  final _PeakSlot _vid = _PeakSlot();
  final _PeakSlot _rec = _PeakSlot();
  final _PeakSlot _mus = _PeakSlot();
  // PATCH_S179_AAA
  bool _snap = true;
  bool _scrubbing = false;
  int _lastScrubSeg = -2;
  String? _thumbPath;
  ThumbStrip? _thumbs;

  // edge-drag bookkeeping
  double _dragBase = 0;
  double _dragAccum = 0;

  double get _dur => math.max(
      1.0,
      math.max(widget.controller.value.duration.inMilliseconds / 1000.0,
          widget.state.videoDurationSec));

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_follow);
  }

  @override
  void didUpdateWidget(ProTimeline old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_follow);
      widget.controller.addListener(_follow);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ behaviour

  /// While playing, keep the playhead on screen.
  void _follow() {
    final v = widget.controller.value;
    if (!v.isPlaying || !_scroll.hasClients || _pinching) return;
    final x = v.position.inMilliseconds / 1000.0 * _pps;
    final off = _scroll.offset;
    if (x < off + 24 || x > off + _viewW - 48) {
      final target = (x - _viewW * 0.3)
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      _scroll.jumpTo(target);
    }
  }

  void _seekSec(double sec) {
    final ms = (sec.clamp(0.0, _dur) * 1000).round();
    widget.controller.seekTo(Duration(milliseconds: ms));
  }

  void zoomBy(double factor) => _setPps(_pps * factor);

  /// Fit the whole clip in the visible width.
  void fit() {
    final w = math.max(60.0, _viewW - 24);
    _setPps(w / _dur);
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _setPps(double v) {
    final nv = v.clamp(_minPps, _maxPps).toDouble();
    if ((nv - _pps).abs() < 0.01) return;
    final posSec = widget.controller.value.position.inMilliseconds / 1000.0;
    final screenX = posSec * _pps - (_scroll.hasClients ? _scroll.offset : 0);
    setState(() => _pps = nv);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final off = (posSec * nv - screenX)
          .clamp(0.0, _scroll.position.maxScrollExtent)
          .toDouble();
      _scroll.jumpTo(off);
    });
  }

  void _ensure(_PeakSlot slot, String? path) {
    if (path == slot.path) return;
    slot.path = path;
    slot.peaks = null;
    if (path == null) return;
    final hit = WaveformService.cached(path);
    if (hit != null) {
      slot.peaks = hit;
      return;
    }
    WaveformService.peaks(path).then((p) {
      if (!mounted || slot.path != path) return;
      setState(() => slot.peaks = p);
    });
  }

  // PATCH_S179_AAA
  void _ensureThumbs() {
    final path = widget.state.videoPath;
    if (path == _thumbPath) return;
    _thumbPath = path;
    _thumbs = null;
    if (path == null) return;
    final hit = ThumbService.cached(path);
    if (hit != null) {
      _thumbs = hit;
      return;
    }
    ThumbService.strip(path, _dur).then((t) {
      if (!mounted || _thumbPath != path) return;
      setState(() => _thumbs = t);
    });
  }

  Widget _thumbRow(double h) {
    final t = _thumbs!;
    final tileW = t.step * _pps;
    return Stack(
      children: [
        for (var i = 0; i < t.files.length; i++)
          Positioned(
            left: i * tileW,
            top: 0,
            width: tileW + 0.5,
            height: h,
            child: Image.file(
              File(t.files[i]),
              fit: BoxFit.cover,
              cacheHeight: 72,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
      ],
    );
  }

  double _pinchDist() {
    final pts = _ptrs.values.toList();
    if (pts.length < 2) return 0;
    return (pts[0] - pts[1]).distance;
  }

  // ---------------------------------------------------------------- build

  List<_LaneSpec> _lanes() {
    final s = widget.state;
    final c = widget.compact;
    return [
      if (!c && s.textTimeCues.isNotEmpty)
        const _LaneSpec('text', Icons.title, 26),
      const _LaneSpec('ayah', Icons.menu_book_outlined, 36),
      _LaneSpec('video', Icons.movie_outlined, c ? 30 : 40),
      _LaneSpec('audio',
          s.muteAudio ? Icons.volume_off : Icons.volume_up_outlined, c ? 26 : 34),
      if (!c && s.selectedReciterAudio != null)
        const _LaneSpec('reciter', Icons.graphic_eq, 30),
      if (!c && s.musicBedPath != null)
        const _LaneSpec('music', Icons.music_note_outlined, 26),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    _ensure(_vid, s.videoPath);
    _ensure(_rec, s.selectedReciterAudio);
    _ensure(_mus, s.musicBedPath);
    _ensureThumbs();
    final lanes = _lanes();
    final h = _rulerH + lanes.fold<double>(0, (a, l) => a + l.h);

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        height: h,
        decoration: const BoxDecoration(
          color: AyatColors.ink,
          border: Border(
            top: BorderSide(color: AyatColors.hairline),
            bottom: BorderSide(color: AyatColors.hairline),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: _gutter,
              decoration: const BoxDecoration(
                color: AyatColors.surface,
                border: Border(right: BorderSide(color: AyatColors.hairline)),
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: _rulerH,
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            onTap: fit,
                            child: const Center(
                              child: Icon(Icons.fit_screen_outlined,
                                  size: 16, color: AyatColors.parchmentDim),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell( // PATCH_S179_AAA: snap on/off
                            onTap: () => setState(() => _snap = !_snap),
                            child: Center(
                              child: Icon(Icons.align_horizontal_center,
                                  size: 16,
                                  color: _snap
                                      ? AyatColors.goldBright
                                      : AyatColors.parchmentDim),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  for (final l in lanes) _header(l),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, cons) {
                _viewW = cons.maxWidth;
                final contentW =
                    math.max(cons.maxWidth, _dur * _pps + 72).toDouble();
                return Listener(
                  onPointerDown: (e) {
                    _ptrs[e.pointer] = e.position;
                    if (_ptrs.length == 2) {
                      _lastPinch = _pinchDist();
                      setState(() => _pinching = true);
                    }
                  },
                  onPointerMove: (e) {
                    if (!_ptrs.containsKey(e.pointer)) return;
                    _ptrs[e.pointer] = e.position;
                    if (_ptrs.length == 2) {
                      final d = _pinchDist();
                      if (_lastPinch > 0 && d > 0) {
                        _setPps(_pps * d / _lastPinch);
                      }
                      _lastPinch = d;
                    }
                  },
                  onPointerUp: _pointerGone,
                  onPointerCancel: _pointerGone,
                  child: SingleChildScrollView(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: _pinching
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: contentW,
                      height: h,
                      child: Stack(
                        children: [
                          Column(
                            children: [
                              _ruler(contentW),
                              for (final l in lanes) _laneBody(l, contentW),
                            ],
                          ),
                          _playhead(),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ],
        ),
      ),
    );
  }

  void _pointerGone(PointerEvent e) {
    _ptrs.remove(e.pointer);
    if (_ptrs.length < 2) {
      _lastPinch = 0;
      if (_pinching) setState(() => _pinching = false);
    }
  }

  // --------------------------------------------------------------- header

  Widget _header(_LaneSpec l) {
    final lockable = l.id == 'ayah' || l.id == 'video';
    final locked = _locked.contains(l.id);
    final isAudio = l.id == 'audio';
    final muted = widget.state.muteAudio;
    final hot = locked || (isAudio && !muted);
    return SizedBox(
      height: l.h,
      child: InkWell(
        onTap: () {
          if (lockable) {
            setState(() {
              if (!_locked.add(l.id)) _locked.remove(l.id);
            });
          } else if (isAudio) {
            widget.state.update(() => widget.state.muteAudio = !muted);
          }
        },
        child: Center(
          child: Icon(
            locked ? Icons.lock : l.icon,
            size: 16,
            color: hot ? AyatColors.goldBright : AyatColors.parchmentDim,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- ruler

  void _rulerSeek(double x) {
    final t = x / _pps;
    _seekSec(t);
    // PATCH_S179_AAA: a tick each time the scrub crosses into another ayah
    final tl = widget.state.timeline;
    var idx = -1;
    for (var i = 0; i < tl.length; i++) {
      if (t >= tl[i].start && t < tl[i].end) {
        idx = i;
        break;
      }
    }
    if (idx != _lastScrubSeg) {
      if (_lastScrubSeg != -2) HapticFeedback.selectionClick();
      _lastScrubSeg = idx;
    }
  }

  void _rulerTap(double x) {
    for (final m in widget.markers) {
      if ((m * _pps - x).abs() < 10) {
        _seekSec(m);
        return;
      }
    }
    _rulerSeek(x);
  }

  Widget _ruler(double w) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (d) => _rulerTap(d.localPosition.dx),
      onHorizontalDragStart: (d) {
        setState(() => _scrubbing = true);
        _lastScrubSeg = -2;
        _rulerSeek(d.localPosition.dx);
      },
      onHorizontalDragUpdate: (d) => _rulerSeek(d.localPosition.dx),
      onHorizontalDragEnd: (_) => setState(() => _scrubbing = false),
      onHorizontalDragCancel: () => setState(() => _scrubbing = false),
      child: SizedBox(
        height: _rulerH,
        width: w,
        child: CustomPaint(
          painter: _RulerPainter(
            pps: _pps,
            dur: _dur,
            markers: List<double>.of(widget.markers),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------- playhead

  Widget _playhead() {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: widget.controller,
      builder: (context, v, _) {
        final x = v.position.inMilliseconds / 1000.0 * _pps;
        return Positioned(
          left: x - 6,
          top: 0,
          bottom: 0,
          width: 12,
          child: IgnorePointer(
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                if (_scrubbing) // PATCH_S179_AAA: time bubble while scrubbing
                  Positioned(
                    left: 14,
                    top: 1,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AyatColors.goldBright,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _fmtTick(v.position.inMilliseconds / 1000.0, 0.5),
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AyatColors.ink),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: Center(
                    child: Container(width: 2, color: AyatColors.parchment),
                  ),
                ),
                Container(
                  width: 12,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AyatColors.goldBright,
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(6)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----------------------------------------------------------------- lanes

  Widget _laneBody(_LaneSpec l, double w) {
    final child = switch (l.id) {
      'text' => _textLane(l.h, w),
      'ayah' => _ayahLane(l.h, w),
      'video' => _videoLane(l.h, w),
      'audio' => _waveLane(l.h, w, _vid, const Color(0xFF6FA8DC),
          widget.state.muteAudio),
      'reciter' => _waveLane(l.h, w, _rec, AyatColors.gold, false),
      _ => _waveLane(l.h, w, _mus, const Color(0xFF8BC48A), false, loop: true),
    };
    return Container(
      height: l.h,
      width: w,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0x14C9A24B))),
      ),
      child: child,
    );
  }

  Widget _textLane(double h, double w) {
    final cues = widget.state.textTimeCues;
    return Stack(
      children: [
        for (final cue in cues)
          Positioned(
            left: cue.start * _pps,
            width: math.max(4.0, (cue.end - cue.start) * _pps - 1),
            top: 2,
            height: h - 4,
            child: GestureDetector(
              onTapUp: (d) => _seekSec(cue.start + 0.03),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C6B5A),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: const Color(0x66ECC875)),
                ),
                child: Text(
                  cue.text,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AyatColors.parchment),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _ayahLane(double h, double w) {
    final tl = widget.state.timeline;
    final locked = _locked.contains('ayah');
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        widget.onSelectSeg(-1);
        _seekSec(d.localPosition.dx / _pps);
      },
      child: Stack(
        children: [
          if (tl.isEmpty)
            const Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(left: 10),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'المزامنة التلقائية تملأ هذا المسار بالآيات',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                        fontSize: 10.5, color: AyatColors.parchmentDim),
                  ),
                ),
              ),
            ),
          for (var i = 0; i < tl.length; i++) _segClip(i, h, locked),
        ],
      ),
    );
  }

  Widget _segClip(int i, double h, bool locked) {
    final s = widget.state.timeline[i];
    final sel = widget.selectedSeg == i;
    final w = math.max(3.0, (s.end - s.start) * _pps - 1);
    final alpha = s.inferred
        ? 0.30
        : (0.35 + 0.55 * s.confidence.clamp(0.0, 1.0)).toDouble();
    return Positioned(
      left: s.start * _pps,
      width: w,
      top: 2,
      height: h - 4,
      child: GestureDetector(
        onTapUp: (d) {
          widget.onSelectSeg(sel ? -1 : i);
          _seekSec(s.start + d.localPosition.dx / _pps);
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: AyatColors.gold.withValues(alpha: alpha),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: sel
                        ? AyatColors.goldBright
                        : (s.inferred ? AyatColors.goldDim : Colors.transparent),
                    width: sel ? 2 : 1,
                  ),
                ),
                child: ClipRect(
                  child: Text(
                    '${s.ayah.num}  ${s.displayText}',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AyatColors.ink),
                  ),
                ),
              ),
            ),
            if (sel && !locked) ...[
              _edgeHandle(i, true, w),
              _edgeHandle(i, false, w),
            ],
          ],
        ),
      ),
    );
  }

  Widget _edgeHandle(int i, bool isStart, double clipW) {
    final hw = math.min(16.0, clipW / 3);
    return Positioned(
      left: isStart ? 0 : null,
      right: isStart ? null : 0,
      top: 0,
      bottom: 0,
      width: hw,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          final tl = widget.state.timeline;
          if (i >= tl.length) return;
          _dragBase = isStart ? tl[i].start : tl[i].end;
          _dragAccum = 0;
        },
        onHorizontalDragUpdate: (d) {
          _dragAccum += d.delta.dx;
          _moveEdge(i, isStart);
        },
        child: Container(
          decoration: BoxDecoration(
            color: AyatColors.goldBright,
            borderRadius: isStart
                ? const BorderRadius.horizontal(left: Radius.circular(6))
                : const BorderRadius.horizontal(right: Radius.circular(6)),
          ),
          child: Center(
            child: Container(width: 2, height: 12, color: AyatColors.ink),
          ),
        ),
      ),
    );
  }

  void _moveEdge(int i, bool isStart) {
    final tl = widget.state.timeline;
    if (i < 0 || i >= tl.length) return;
    final seg = tl[i];
    var target = _dragBase + _dragAccum / _pps;
    final snaps = <double>[
      widget.controller.value.position.inMilliseconds / 1000.0,
      ...widget.markers,
      if (i > 0) tl[i - 1].end,
      if (i + 1 < tl.length) tl[i + 1].start,
      0,
      _dur,
    ];
    final tol = _snap ? 8 / _pps : -1.0;
    for (final x in snaps) {
      if ((x - target).abs() <= tol) {
        target = x;
        break;
      }
    }
    final cur = isStart ? seg.start : seg.end;
    final delta = target - cur;
    if (delta.abs() < 0.001) return;
    widget.state.nudgeTimelineSegment(i,
        startDelta: isStart ? delta : 0, endDelta: isStart ? 0 : delta);
  }

  Widget _videoLane(double h, double w) {
    final s = widget.state;
    final dur = _dur;
    final locked = _locked.contains('video');
    var ts = 0.0;
    var te = dur;
    var byAyah = false;
    if (s.trimFromIndex >= 0 &&
        s.trimToIndex >= s.trimFromIndex &&
        s.trimToIndex < s.timeline.length) {
      ts = s.timeline[s.trimFromIndex].start;
      te = s.timeline[s.trimToIndex].end;
      byAyah = true;
    } else if (s.manualTrimSet) {
      ts = s.trimManualStart;
      te = s.trimManualEnd < 0 ? dur : math.min(s.trimManualEnd, dur);
    }
    final name = (s.videoPath ?? '').split('/').last;
    final canTrim = !locked && !byAyah;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        widget.onSelectSeg(-1);
        _seekSec(d.localPosition.dx / _pps);
      },
      child: Stack(
        children: [
          Positioned(
            left: 0,
            width: dur * _pps,
            top: 2,
            height: h - 4,
            child: Container(
              clipBehavior: Clip.antiAlias, // PATCH_S179_AAA: filmstrip
              decoration: BoxDecoration(
                color: const Color(0xFF1E4B3F),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x55ECC875)),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_thumbs != null) _thumbRow(h - 4),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x00000000), Color(0xAA000000)],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: AyatColors.parchment),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // dim whatever the export will cut away
          if (ts > 0.01)
            Positioned(
              left: 0,
              width: ts * _pps,
              top: 2,
              height: h - 4,
              child: Container(color: const Color(0xAA050F0D)),
            ),
          if (te < dur - 0.01)
            Positioned(
              left: te * _pps,
              width: (dur - te) * _pps,
              top: 2,
              height: h - 4,
              child: Container(color: const Color(0xAA050F0D)),
            ),
          // PATCH_S180_TRANSFORM: keyframe diamonds
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
            _trimHandle(h, ts, true, dur),
            _trimHandle(h, te, false, dur),
          ],
        ],
      ),
    );
  }

  Widget _trimHandle(double h, double at, bool isStart, double dur) {
    return Positioned(
      left: at * _pps - (isStart ? 0 : 14),
      width: 14,
      top: 2,
      height: h - 4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) {
          final st = widget.state;
          st.update(() {
            final end = st.trimManualEnd < 0
                ? dur
                : math.min(st.trimManualEnd, dur);
            final start = math.min(st.trimManualStart, end);
            final dt = d.delta.dx / _pps;
            if (isStart) {
              st.trimManualStart =
                  (start + dt).clamp(0.0, math.max(0.0, end - 0.5)).toDouble();
              st.trimManualEnd = end;
            } else {
              st.trimManualStart = start;
              st.trimManualEnd =
                  (end + dt).clamp(start + 0.5, dur).toDouble();
            }
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: AyatColors.goldBright,
            borderRadius: isStart
                ? const BorderRadius.horizontal(left: Radius.circular(6))
                : const BorderRadius.horizontal(right: Radius.circular(6)),
          ),
          child: Center(
            child: Container(width: 2, height: 14, color: AyatColors.ink),
          ),
        ),
      ),
    );
  }

  Widget _waveLane(double h, double w, _PeakSlot slot, Color color, bool dim,
      {bool loop = false}) {
    final peaks = slot.peaks;
    final dur = _dur;
    final clipSec = (peaks == null || loop)
        ? dur
        : math.min(dur, peaks.length / WaveformService.peaksPerSec);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        widget.onSelectSeg(-1);
        _seekSec(d.localPosition.dx / _pps);
      },
      child: Stack(
        children: [
          Positioned(
            left: 0,
            width: math.max(2.0, clipSec * _pps),
            top: 2,
            height: h - 4,
            child: Container(
              decoration: BoxDecoration(
                color: color.withValues(alpha: dim ? 0.05 : 0.12),
                borderRadius: BorderRadius.circular(5),
              ),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _WavePainter(
                    peaks: peaks,
                    pps: _pps,
                    loop: loop,
                    color: color.withValues(alpha: dim ? 0.30 : 0.95),
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- painters

String _fmtTick(double t, double step) {
  final m = t ~/ 60;
  final sec = t - m * 60;
  if (step < 1) return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';
  return '$m:${sec.floor().toString().padLeft(2, '0')}';
}

class _RulerPainter extends CustomPainter {
  final double pps;
  final double dur;
  final List<double> markers;
  _RulerPainter({required this.pps, required this.dur, required this.markers});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = AyatColors.surface);
    const steps = <double>[
      0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600, 1200
    ];
    var step = steps.last;
    for (final s in steps) {
      if (s * pps >= 64) {
        step = s;
        break;
      }
    }
    final major = Paint()
      ..color = AyatColors.parchmentDim
      ..strokeWidth = 1;
    final minor = Paint()
      ..color = const Color(0x559C9280)
      ..strokeWidth = 1;
    final n = (dur / step).ceil() + 1;
    if (n <= 3000) {
      for (var k = 0; k <= n; k++) {
        final t = k * step;
        final x = t * pps;
        canvas.drawLine(Offset(x, size.height - 10), Offset(x, size.height), major);
        for (var j = 1; j < 4; j++) {
          final xm = x + step * pps * j / 4;
          canvas.drawLine(
              Offset(xm, size.height - 5), Offset(xm, size.height), minor);
        }
        final tp = TextPainter(
          text: TextSpan(
            text: _fmtTick(t, step),
            style: const TextStyle(fontSize: 9, color: AyatColors.parchmentDim),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 3, 2));
      }
    }
    final mk = Paint()..color = AyatColors.goldBright;
    for (final m in markers) {
      final x = m * pps;
      final y = size.height - 7;
      final path = Path()
        ..moveTo(x, y - 5)
        ..lineTo(x + 4, y)
        ..lineTo(x, y + 5)
        ..lineTo(x - 4, y)
        ..close();
      canvas.drawPath(path, mk);
    }
  }

  @override
  bool shouldRepaint(_RulerPainter old) =>
      old.pps != pps || old.dur != dur || old.markers.join(',') != markers.join(',');
}

class _WavePainter extends CustomPainter {
  final List<double>? peaks;
  final double pps;
  final bool loop;
  final Color color;
  _WavePainter(
      {required this.peaks,
      required this.pps,
      required this.loop,
      required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final mid = size.height / 2;
    final p = peaks;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    if (p == null || p.isEmpty) {
      canvas.drawLine(Offset(0, mid), Offset(size.width, mid), paint);
      return;
    }
    final per = WaveformService.peaksPerSec;
    for (double x = 0; x < size.width; x += 2) {
      final a = (x / pps * per).floor();
      final b = math.max(a + 1, ((x + 2) / pps * per).ceil());
      if (!loop && a >= p.length) break;
      var m = 0.0;
      for (var j = a; j < b; j++) {
        final idx = loop ? j % p.length : j;
        if (idx >= p.length) break;
        if (p[idx] > m) m = p[idx];
      }
      final hh = math.max(1.0, m * (size.height - 4) / 2);
      canvas.drawLine(Offset(x, mid - hh), Offset(x, mid + hh), paint);
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.peaks != peaks ||
      old.pps != pps ||
      old.loop != loop ||
      old.color != color;
}
