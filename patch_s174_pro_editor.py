#!/usr/bin/env python3
"""
patch_s174_pro_editor.py - Ayat Studio S174 (run from repo root, after S173)

WHY: the studio looked like InShot (S173) but edited like a slideshow: one
thin ribbon, no real timeline. This brings the pro-editor model of CapCut,
Premiere Pro and DaVinci Resolve to the phone, using ONLY fields the preview
and exporter already read (no export-pipeline changes):

  NEW  lib/services/waveform_service.dart  audio peaks via ffmpeg (cached)
  NEW  lib/widgets/pro_timeline.dart       multi-track timeline: ruler,
       playhead (auto-follow), ayah / text / video / audio / reciter / music
       lanes, real waveforms, trim handles with snapping, markers, lane lock,
       pinch-zoom + fit
  NEW  lib/widgets/pro_panels.dart         Color page (Resolve), Audio mixer
       (Fairlight), Transcript editing (Premiere text-based), platform export
       presets (CapCut / Deliver)
  EDIT lib/screens/home_screen.dart        timecode transport + timeline dock,
       contextual clip toolbar, 4 new tool pages

Idempotent; anchor-checked: nothing is written unless every anchor exists.
"""
import os, sys

HOME = 'lib/screens/home_screen.dart'
MARK = 'PATCH_S174_PRO_EDITOR'

if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
if not os.path.exists(HOME):
    sys.exit('missing ' + HOME)
if 'PATCH_S173_INSHOT_LAYOUT' not in open(HOME, encoding='utf-8').read():
    sys.exit('S173 not applied yet - run patch_s173_inshot_layout.py first.')

src = open(HOME, encoding='utf-8').read()
if MARK in src:
    print('  OK      already applied')
    sys.exit(0)

NEW_FILES = {
    'lib/services/waveform_service.dart': r"""// PATCH_S174_PRO_EDITOR
// Audio peaks for the timeline's waveform lanes (the Premiere / Resolve /
// CapCut look). One ffmpeg pass decodes the file to 4 kHz mono PCM, then
// every 40 samples collapse to one peak = 100 peaks per second. Results are
// cached per path for the session; null means "could not decode" and the
// lane simply draws a flat bar instead of failing.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class WaveformService {
  WaveformService._();

  /// Peaks per second of audio.
  static const int peaksPerSec = 100;

  static final Map<String, List<double>> _cache = {};
  static final Map<String, Future<List<double>?>> _pending = {};

  static List<double>? cached(String path) => _cache[path];

  static Future<List<double>?> peaks(String path) {
    final hit = _cache[path];
    if (hit != null) return Future<List<double>?>.value(hit);
    final running = _pending[path];
    if (running != null) return running;
    final job = _compute(path);
    _pending[path] = job;
    job.whenComplete(() {
      _pending.remove(path);
    });
    return job;
  }

  static Future<List<double>?> _compute(String path) async {
    try {
      final dir = await getTemporaryDirectory();
      final rawPath = '${dir.path}/wf_${path.hashCode.abs()}.raw';
      final rawFile = File(rawPath);
      if (rawFile.existsSync()) rawFile.deleteSync();
      final session = await FFmpegKit.execute(
          '-y -i "$path" -vn -ac 1 -ar 4000 -f s16le "$rawPath"');
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc) || !rawFile.existsSync()) return null;
      final bytes = await rawFile.readAsBytes();
      try {
        rawFile.deleteSync();
      } catch (_) {}
      final n = bytes.length ~/ 2;
      if (n == 0) return null;
      final bd = ByteData.sublistView(bytes);
      const per = 4000 ~/ peaksPerSec; // samples per peak
      final count = (n / per).ceil();
      final res = List<double>.filled(count, 0);
      var maxPeak = 0.0;
      for (var i = 0; i < count; i++) {
        final s = i * per;
        final e = math.min(n, s + per);
        var peak = 0;
        for (var j = s; j < e; j++) {
          final v = bd.getInt16(j * 2, Endian.little).abs();
          if (v > peak) peak = v;
        }
        final d = peak / 32768.0;
        res[i] = d;
        if (d > maxPeak) maxPeak = d;
      }
      // Display-normalise so quiet recitations still read as a waveform.
      if (maxPeak > 0.02) {
        final k = 1.0 / maxPeak;
        for (var i = 0; i < count; i++) {
          res[i] = (res[i] * k).clamp(0.0, 1.0);
        }
      }
      _cache[path] = res;
      return res;
    } catch (_) {
      return null;
    }
  }
}
""",
    'lib/widgets/pro_timeline.dart': r"""// PATCH_S174_PRO_EDITOR
// Multi-track timeline in the style of CapCut / Premiere Pro / DaVinci Resolve:
// time ruler, a playhead that follows playback, one lane per kind of media
// (text cues, ayah clips, video, original audio, reciter audio, music bed),
// real audio waveforms, trim handles with snapping, markers, pinch-to-zoom.
//
// Time always runs left to right (the whole widget is forced LTR); only the
// Arabic labels inside clips are laid out right to left.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/studio_state.dart';
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
  static const double _gutter = 40;
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
                    child: InkWell(
                      onTap: fit,
                      child: const Center(
                        child: Icon(Icons.fit_screen_outlined,
                            size: 16, color: AyatColors.parchmentDim),
                      ),
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

  void _rulerSeek(double x) => _seekSec(x / _pps);

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
      onHorizontalDragStart: (d) => _rulerSeek(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _rulerSeek(d.localPosition.dx),
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
              alignment: Alignment.topCenter,
              children: [
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
    final tol = 8 / _pps;
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
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: const Color(0xFF1E4B3F),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0x55ECC875)),
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: AyatColors.parchment),
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
""",
    'lib/widgets/pro_panels.dart': r"""// PATCH_S174_PRO_EDITOR
// The "pages" of the pro editor, as bottom-sheet panels:
//   ProColorPage      - Resolve's Color page / Premiere's Lumetri basics
//   ProAudioMixer     - Resolve's Fairlight / Premiere's Essential Sound: faders
//   ProTranscript     - Premiere's text-based editing, driven by the ayah timeline
//   ProExportPresets  - CapCut / Resolve "Deliver" one-tap platform presets
// Every control here edits a field the preview and the exporter already read.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../services/app_settings.dart';
import '../theme/ayat_theme.dart';
import 'gold_switch.dart';

// ------------------------------------------------------------------ shared

Widget _proTitle(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
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

/// Slider row in the Resolve style: label, numeric readout, and a
/// double-tap on the label resets the control to its neutral value.
class _ProSlider extends StatelessWidget {
  final String label;
  final String readout;
  final double value;
  final double min;
  final double max;
  final double neutral;
  final ValueChanged<double> onChanged;
  const _ProSlider({
    required this.label,
    required this.readout,
    required this.value,
    required this.min,
    required this.max,
    required this.neutral,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final changed = (value - neutral).abs() > (max - min) * 0.004;
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => onChanged(neutral),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AyatColors.surface3,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  readout,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color:
                        changed ? AyatColors.goldBright : AyatColors.parchmentDim,
                  ),
                ),
              ),
            ],
          ),
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- color

class ProColorPage extends StatelessWidget {
  final StudioState state;
  const ProColorPage({super.key, required this.state});

  static const Map<ColorGrade, List<Color>> _swatch = {
    ColorGrade.none: [Color(0xFF3A4A44), Color(0xFF14211D)],
    ColorGrade.warmGold: [Color(0xFFE8B84A), Color(0xFF7A4A12)],
    ColorGrade.nightTeal: [Color(0xFF1E6F78), Color(0xFF07202A)],
    ColorGrade.sepia: [Color(0xFFC9A877), Color(0xFF5B4126)],
    ColorGrade.softMono: [Color(0xFFBDBDBD), Color(0xFF3A3A3A)],
  };

  @override
  Widget build(BuildContext context) {
    final t = AppSettings.instance.strings;
    String signed(double v) =>
        '${v >= 0 ? '+' : ''}${v.round()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _proTitle(context, 'اللوكات'),
        SizedBox(
          height: 82,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final g in kColorGrades)
                GestureDetector(
                  onTap: () => state.update(() => state.colorGrade = g.$1),
                  child: Container(
                    width: 76,
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _swatch[g.$1] ??
                            const [Color(0xFF3A4A44), Color(0xFF14211D)],
                      ),
                      border: Border.all(
                        color: state.colorGrade == g.$1
                            ? AyatColors.goldBright
                            : AyatColors.hairline,
                        width: state.colorGrade == g.$1 ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      t.t(g.$2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _proTitle(context, 'التصحيح الأساسي'),
        _ProSlider(
          label: 'السطوع',
          readout: signed(state.adjustBrightness * 400),
          value: state.adjustBrightness,
          min: -0.25,
          max: 0.25,
          neutral: 0,
          onChanged: (v) => state.update(() => state.adjustBrightness = v),
        ),
        _ProSlider(
          label: 'التباين',
          readout: signed((state.adjustContrast - 1) * 250),
          value: state.adjustContrast,
          min: 0.7,
          max: 1.4,
          neutral: 1,
          onChanged: (v) => state.update(() => state.adjustContrast = v),
        ),
        _ProSlider(
          label: 'التشبّع',
          readout: signed((state.adjustSaturation - 1) * 100),
          value: state.adjustSaturation,
          min: 0,
          max: 2,
          neutral: 1,
          onChanged: (v) => state.update(() => state.adjustSaturation = v),
        ),
        _ProSlider(
          label: 'ضبابية الخلفية',
          readout: state.videoBlur.toStringAsFixed(1),
          value: state.videoBlur,
          min: 0,
          max: 6,
          neutral: 0,
          onChanged: (v) => state.update(() => state.videoBlur = v),
        ),
        _proTitle(context, 'مؤثرات الصورة'),
        ToggleRow(
          label: 'تعتيم الحواف (فينييت)',
          value: state.vignetteEnabled,
          onChanged: (v) => state.update(() => state.vignetteEnabled = v),
        ),
        if (state.vignetteEnabled)
          _ProSlider(
            label: 'قوة التعتيم',
            readout: '${state.vignetteIntensity}',
            value: state.vignetteIntensity.toDouble(),
            min: 0,
            max: 100,
            neutral: 50,
            onChanged: (v) =>
                state.update(() => state.vignetteIntensity = v.round()),
          ),
        ToggleRow(
          label: 'حبيبات الفيلم',
          value: state.grainEnabled,
          onChanged: (v) => state.update(() => state.grainEnabled = v),
        ),
        if (state.grainEnabled)
          _ProSlider(
            label: 'كمية الحبيبات',
            readout: '${state.grainIntensity}',
            value: state.grainIntensity.toDouble(),
            min: 0,
            max: 100,
            neutral: 30,
            onChanged: (v) =>
                state.update(() => state.grainIntensity = v.round()),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => state.update(() {
              state.colorGrade = ColorGrade.none;
              state.vignetteEnabled = false;
              state.grainEnabled = false;
              state.resetManualAdjust();
            }),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('إعادة ضبط اللون'),
          ),
        ),
        const SizedBox(height: 4),
        Text('اضغط مرتين على اسم أي شريط لإعادته إلى قيمته الأصلية.',
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

// ------------------------------------------------------------------- audio

class ProAudioMixer extends StatelessWidget {
  final StudioState state;
  final VoidCallback onPickMusic;
  const ProAudioMixer(
      {super.key, required this.state, required this.onPickMusic});

  static String _db(double v) {
    if (v <= 0.001) return '-∞ dB';
    final d = 20 * math.log(v) / math.ln10;
    return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)} dB';
  }

  Widget _strip(
    BuildContext context, {
    required String label,
    required String readout,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required Color accent,
    bool dim = false,
  }) {
    return Expanded(
      child: Opacity(
        opacity: dim ? 0.45 : 1,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AyatColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AyatColors.hairline),
          ),
          child: Column(
            children: [
              Text(readout,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: accent)),
              SizedBox(
                height: 150,
                width: 44,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accent,
                      thumbColor: accent,
                    ),
                    child: Slider(
                      value: value.clamp(min, max).toDouble(),
                      min: min,
                      max: max,
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AyatColors.parchment)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasReciter = state.selectedReciterAudio != null;
    final hasMusic = state.musicBedPath != null;
    final muted = state.muteAudio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _proTitle(context, 'مازج الصوت'),
        SizedBox(
          height: 218,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _strip(
                context,
                label: hasReciter ? 'التلاوة' : 'صوت المقطع',
                readout: _db(state.audioVolume),
                value: state.audioVolume,
                min: 0,
                max: 2,
                accent: AyatColors.goldBright,
                dim: muted,
                onChanged: (v) => state.update(() => state.audioVolume = v),
              ),
              if (hasReciter && state.hasVideo)
                _strip(
                  context,
                  label: 'صوت المقطع تحت التلاوة',
                  readout: '${(state.originalAudioMix * 100).round()}٪',
                  value: state.originalAudioMix,
                  min: 0,
                  max: 1,
                  accent: const Color(0xFF6FA8DC),
                  dim: muted,
                  onChanged: (v) =>
                      state.update(() => state.originalAudioMix = v),
                ),
              if (hasMusic)
                _strip(
                  context,
                  label: 'الخلفية الموسيقية',
                  readout: '${(state.musicBedVolume * 100).round()}٪',
                  value: state.musicBedVolume,
                  min: 0,
                  max: 1,
                  accent: const Color(0xFF8BC48A),
                  dim: muted,
                  onChanged: (v) =>
                      state.update(() => state.musicBedVolume = v),
                ),
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      state.update(() => state.muteAudio = !state.muteAudio),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: muted
                          ? const Color(0x33E53935)
                          : AyatColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: muted
                              ? const Color(0xFFE53935)
                              : AyatColors.hairline),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          muted ? Icons.volume_off : Icons.volume_up_outlined,
                          size: 30,
                          color: muted
                              ? const Color(0xFFE53935)
                              : AyatColors.goldBright,
                        ),
                        const SizedBox(height: 6),
                        Text(muted ? 'مكتوم' : 'كتم الكل',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ToggleRow(
          label: 'دخول تدريجي للصوت',
          value: state.audioFadeIn,
          onChanged: (v) => state.update(() => state.audioFadeIn = v),
        ),
        ToggleRow(
          label: 'خفوت تدريجي في النهاية',
          value: state.audioFadeOut,
          onChanged: (v) => state.update(() => state.audioFadeOut = v),
        ),
        if (hasMusic)
          ToggleRow(
            label: 'دخول وخروج تدريجي للخلفية',
            value: state.musicBedFade,
            onChanged: (v) => state.update(() => state.musicBedFade = v),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickMusic,
                icon: const Icon(Icons.library_music_outlined, size: 18),
                label: Text(hasMusic ? 'تغيير الخلفية' : 'إضافة خلفية موسيقية'),
              ),
            ),
            if (hasMusic) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'إزالة الخلفية',
                onPressed: () => state.update(() => state.musicBedPath = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- transcript

class ProTranscript extends StatefulWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  final ValueChanged<String> onToast;
  final ValueChanged<int> onSelectSeg;
  const ProTranscript({
    super.key,
    required this.state,
    required this.controller,
    required this.onToast,
    required this.onSelectSeg,
  });

  @override
  State<ProTranscript> createState() => _ProTranscriptState();
}

class _ProTranscriptState extends State<ProTranscript> {
  final Set<int> _sel = {};
  String _q = '';

  static String _fmt(double s) {
    final m = s ~/ 60;
    final sec = s - m * 60;
    return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';
  }

  void _seek(double sec) {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;
    c.seekTo(Duration(milliseconds: (sec * 1000).round() + 30));
  }

  void _deleteSelected() {
    final st = widget.state;
    final idx = _sel.where((i) => i < st.timeline.length).toList()
      ..sort((a, b) => b.compareTo(a));
    if (idx.isEmpty) return;
    for (final i in idx) {
      st.removeTimelineSegment(i);
    }
    setState(_sel.clear);
    widget.onSelectSeg(-1);
    widget.onToast('تم حذف ${idx.length} من الخط الزمني (يمكن التراجع)');
  }

  void _trimToSelection() {
    final st = widget.state;
    final idx = _sel.where((i) => i < st.timeline.length).toList()..sort();
    if (idx.isEmpty) return;
    st.update(() {
      st.trimFromIndex = idx.first;
      st.trimToIndex = idx.last;
    });
    widget.onToast(
        'سيُصدَّر من آية ${st.timeline[idx.first].ayah.num} حتى آية ${st.timeline[idx.last].ayah.num}');
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final tl = st.timeline;
    if (tl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'شغّل المزامنة التلقائية أولًا — ستظهر هنا الآيات المرصودة كنص تحرّره مباشرة: علّم، احذف، أو اقصّ النطاق.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final q = _q.trim();
    final rows = <int>[
      for (var i = 0; i < tl.length; i++)
        if (q.isEmpty || tl[i].displayText.contains(q) || '${tl[i].ayah.num}' == q)
          i,
    ];
    final selDur = _sel
        .where((i) => i < tl.length)
        .fold<double>(0, (a, i) => a + (tl[i].end - tl[i].start));
    final hasTrim = st.trimFromIndex >= 0 && st.trimToIndex >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'ابحث في نص التلاوة أو رقم الآية…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: AyatColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AyatColors.hairline),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _sel.isEmpty
                  ? 'اضغط الآية للانتقال إليها · علّم الصناديق للتحرير'
                  : 'محدد: ${_sel.length} · ${selDur.toStringAsFixed(1)} ث',
              style: const TextStyle(
                  fontSize: 11, color: AyatColors.parchmentDim),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: _sel.isEmpty ? null : _trimToSelection,
              icon: const Icon(Icons.content_cut, size: 16),
              label: const Text('قصّ النطاق'),
            ),
            FilledButton.tonalIcon(
              onPressed: _sel.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('حذف المحدد'),
            ),
            TextButton(
              onPressed: () => setState(() {
                if (_sel.length == rows.length) {
                  _sel.clear();
                } else {
                  _sel
                    ..clear()
                    ..addAll(rows);
                }
              }),
              child: Text(_sel.length == rows.length ? 'إلغاء التحديد' : 'تحديد الكل'),
            ),
            if (hasTrim)
              TextButton(
                onPressed: () => st.update(() {
                  st.trimFromIndex = -1;
                  st.trimToIndex = -1;
                }),
                child: const Text('إلغاء القص'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (final i in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: (hasTrim && i >= st.trimFromIndex && i <= st.trimToIndex)
                  ? const Color(0x22ECC875)
                  : AyatColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _sel.contains(i)
                    ? AyatColors.goldBright
                    : AyatColors.hairline,
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _sel.contains(i),
                  activeColor: AyatColors.gold,
                  checkColor: AyatColors.ink,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _sel.add(i);
                    } else {
                      _sel.remove(i);
                    }
                  }),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      _seek(tl[i].start);
                      widget.onSelectSeg(i);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tl[i].displayText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${tl[i].ayah.num} · ${_fmt(tl[i].start)} – ${_fmt(tl[i].end)}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: tl[i].confidence < 0.4
                                  ? AyatColors.goldBright
                                  : AyatColors.parchmentDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------- presets

class _ExportPreset {
  final String title;
  final String sub;
  final IconData icon;
  final AyatAspectRatio aspect;
  final ExportResolutionCap res;
  final ExportQuality quality;
  const _ExportPreset(
      this.title, this.sub, this.icon, this.aspect, this.res, this.quality);
}

const List<_ExportPreset> _kPresets = [
  _ExportPreset('ريلز · تيك توك · شورتس', '9:16 · 1080p · جودة عالية',
      Icons.smartphone, AyatAspectRatio.story916, ExportResolutionCap.hd1080,
      ExportQuality.high),
  _ExportPreset('يوتيوب', '16:9 · 1080p · جودة عالية', Icons.smart_display_outlined,
      AyatAspectRatio.landscape169, ExportResolutionCap.hd1080,
      ExportQuality.high),
  _ExportPreset('منشور إنستغرام', '4:5 · 1080p · متوازن',
      Icons.crop_portrait, AyatAspectRatio.portrait45,
      ExportResolutionCap.hd1080, ExportQuality.balanced),
  _ExportPreset('مربع', '1:1 · 1080p · متوازن', Icons.crop_square,
      AyatAspectRatio.square11, ExportResolutionCap.hd1080,
      ExportQuality.balanced),
  _ExportPreset('حالة واتساب · تيليجرام', '9:16 · 720p · حجم صغير',
      Icons.chat_bubble_outline, AyatAspectRatio.story916,
      ExportResolutionCap.hd720, ExportQuality.compact),
];

class ProExportPresets extends StatelessWidget {
  final StudioState state;
  final bool busy;
  final VoidCallback onExport;
  const ProExportPresets({
    super.key,
    required this.state,
    required this.busy,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final fs = state.frameSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _proTitle(context, 'إعدادات جاهزة للمنصات'),
        for (final p in _kPresets)
          Builder(builder: (context) {
            final on = state.aspectRatio == p.aspect &&
                state.exportResolution == p.res &&
                state.exportQuality == p.quality;
            return GestureDetector(
              onTap: () => state.update(() {
                state.aspectRatio = p.aspect;
                state.exportResolution = p.res;
                state.exportQuality = p.quality;
              }),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: on ? const Color(0x22ECC875) : AyatColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: on ? AyatColors.goldBright : AyatColors.hairline,
                    width: on ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(p.icon,
                        color: on
                            ? AyatColors.goldBright
                            : AyatColors.parchmentDim),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title,
                              style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(height: 2),
                          Text(p.sub,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AyatColors.parchmentDim)),
                        ],
                      ),
                    ),
                    if (on)
                      const Icon(Icons.check_circle,
                          size: 20, color: AyatColors.goldBright),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 4),
        Text('الإطار الحالي: ${fs.$1}×${fs.$2}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: busy ? null : onExport,
          icon: const Icon(Icons.movie_creation_outlined, size: 18),
          label: const Text('تصدير ثم مشاركة'),
        ),
      ],
    );
  }
}
""",
}

HOME_METHODS = r"""  // ---------------------------------------------------------------------
  // PATCH_S174_PRO_EDITOR: CapCut / Premiere / Resolve style timeline dock
  // (transport with timecode + multi-track timeline) and the contextual
  // clip toolbar that replaces the tool strip while an ayah clip is selected.
  // ---------------------------------------------------------------------

  final GlobalKey<ProTimelineState> _tlKey = GlobalKey<ProTimelineState>();

  bool get _hasSelSeg => _selSeg >= 0 && _selSeg < state.timeline.length;

  Widget _proDock(bool compact) {
    final c = _video!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _proTransport(),
        ProTimeline(
          key: _tlKey,
          state: state,
          controller: c,
          selectedSeg: _selSeg,
          onSelectSeg: (i) => setState(() => _selSeg = i),
          markers: _markers,
          compact: compact,
        ),
      ],
    );
  }

  Widget _tIcon(IconData ic, VoidCallback onTap, String tip,
      {bool on = false}) {
    return IconButton(
      onPressed: onTap,
      tooltip: tip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
      icon: Icon(ic,
          size: 20,
          color: on ? AyatColors.goldBright : AyatColors.parchmentDim),
    );
  }

  Widget _proTransport() {
    final c = _video!;
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        color: AyatColors.surface,
        border: Border(top: BorderSide(color: AyatColors.hairline)),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: c,
          builder: (context, v, _) {
            final durS = max(0.1, v.duration.inMilliseconds / 1000.0);
            final posS = (v.position.inMilliseconds / 1000.0)
                .clamp(0.0, durS)
                .toDouble();
            return Row(
              children: [
                SizedBox(
                  width: 84,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmtSecFine(posS),
                          style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: AyatColors.goldBright,
                              fontFeatures: [FontFeature.tabularFigures()])),
                      Text('/ ${_fmtSecFine(durS)}',
                          style: const TextStyle(
                              fontSize: 10,
                              color: AyatColors.parchmentDim,
                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
                _tIcon(Icons.skip_previous_rounded,
                    () => _seekToAdjacentAyah(-1), 'الآية السابقة'),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    if (v.isPlaying) {
                      c.pause();
                    } else {
                      c.play();
                    }
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [AyatColors.goldBright, AyatColors.gold],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AyatColors.gold
                              .withValues(alpha: v.isPlaying ? 0.55 : 0.3),
                          blurRadius: v.isPlaying ? 18 : 10,
                        ),
                      ],
                    ),
                    child: Icon(
                      v.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 26,
                      color: AyatColors.ink,
                    ),
                  ),
                ),
                _tIcon(Icons.skip_next_rounded, () => _seekToAdjacentAyah(1),
                    'الآية التالية'),
                const Spacer(),
                _tIcon(Icons.content_cut, _splitAtPlayhead, 'تقسيم عند المؤشر'),
                _tIcon(Icons.bookmark_border, _toggleMarker, 'علامة'),
                _tIcon(Icons.repeat_one, () {
                  HapticFeedback.selectionClick();
                  setState(() => _loopAyah = !_loopAyah);
                  _toast(_loopAyah
                      ? 'تكرار الآية الحالية مفعّل'
                      : 'تم إيقاف تكرار الآية');
                }, 'تكرار الآية', on: _loopAyah),
                TextButton(
                  onPressed: _cycleSpeed,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(34, 40),
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    _speedLabel(_playbackSpeed),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _playbackSpeed == 1.0
                            ? AyatColors.parchmentDim
                            : AyatColors.goldBright),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Split the ayah clip under the playhead in two (CapCut's scissors).
  void _splitAtPlayhead() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    final t = c.value.position.inMilliseconds / 1000.0;
    final seg = state.segmentAt(t);
    if (seg == null) {
      _toast('ضع المؤشر داخل آية لتقسيمها');
      return;
    }
    final i = state.timeline.indexOf(seg);
    state.pushHistory();
    if (state.splitTimelineSegment(i, t)) {
      HapticFeedback.mediumImpact();
      setState(() => _selSeg = i + 1);
    } else {
      _toast('المؤشر قريب جدًا من حافة الآية');
    }
  }

  /// Drop / remove a marker at the playhead (Premiere + Resolve markers).
  void _toggleMarker() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    final t = c.value.position.inMilliseconds / 1000.0;
    final near = _markers.indexWhere((m) => (m - t).abs() < 0.3);
    setState(() {
      if (near >= 0) {
        _markers.removeAt(near);
      } else {
        _markers.add(t);
        _markers.sort();
      }
    });
    HapticFeedback.selectionClick();
  }

  void _deleteSegWithUndo(int i) {
    final removed = state.removeTimelineSegment(i);
    if (removed == null) return;
    setState(() => _selSeg = -1);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('تم حذف الآية من الخط الزمني',
            textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: AyatColors.goldBright,
          onPressed: () => state.insertTimelineSegment(i, removed),
        ),
      ));
  }

  /// CapCut-style contextual toolbar: while an ayah clip is selected the
  /// bottom strip turns into that clip's actions.
  Widget _clipToolStrip() {
    final i = _selSeg;
    final items = <(IconData, String, VoidCallback, bool)>[
      (Icons.check_circle_outline, 'تم', () => setState(() => _selSeg = -1),
          false),
      (Icons.content_cut, 'تقسيم', _splitAtPlayhead, false),
      (Icons.tune, 'التوقيت', () => _editSegmentTiming(i), false),
      (Icons.swap_horiz, 'تغيير الآية', () => _changeSegmentAyahDialog(i),
          false),
      if (i + 1 < state.timeline.length)
        (
          Icons.call_merge,
          'دمج',
          () {
            state.pushHistory();
            state.mergeTimelineSegments(i);
            _toast('تم دمج المقطعين');
          },
          false
        ),
      (
        Icons.repeat_one,
        'تكرار',
        () {
          HapticFeedback.selectionClick();
          setState(() => _loopAyah = !_loopAyah);
        },
        _loopAyah
      ),
      (Icons.delete_outline, 'حذف', () => _deleteSegWithUndo(i), false),
    ];
    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: AyatColors.ink,
        border: Border(top: BorderSide(color: AyatColors.hairline)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: items.length,
          itemBuilder: (context, k) {
            final it = items[k];
            final col = it.$4 ? AyatColors.goldBright : AyatColors.parchmentDim;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: it.$3,
              child: SizedBox(
                width: 76,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(it.$1, size: 23, color: col),
                    const SizedBox(height: 4),
                    Text(it.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: col)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

"""

edits = []  # (label, old, new)

edits.append(('imports',
    "import '../widgets/timeline_ribbon.dart'; // PATCH_S83_SYNC_QOL\n",
    "import '../widgets/timeline_ribbon.dart'; // PATCH_S83_SYNC_QOL\n"
    "import '../widgets/pro_timeline.dart'; // " + MARK + "\n"
    "import '../widgets/pro_panels.dart'; // " + MARK + "\n"))

edits.append(('state fields',
    "  int _toolOpen = -1;\n",
    "  int _toolOpen = -1;\n"
    "  // " + MARK + ": selected ayah clip on the timeline (-1 = none) and\n"
    "  // the playhead markers (session only, like a scratch pad).\n"
    "  int _selSeg = -1;\n"
    "  final List<double> _markers = [];\n"))

edits.append(('tool list',
    "        for (var i = 0; i < _tabs.length; i++) (i, _tabs[i].$1, _tabs[i].$2),\n"
    "        (102, Icons.auto_fix_high, 'لمسات'),\n",
    "        for (var i = 0; i < _tabs.length; i++) (i, _tabs[i].$1, _tabs[i].$2),\n"
    "        // " + MARK + ": Resolve-style pages\n"
    "        (103, Icons.palette_outlined, 'اللون'),\n"
    "        (104, Icons.equalizer, 'الصوت'),\n"
    "        (105, Icons.subtitles_outlined, 'النص المفرَّغ'),\n"
    "        (106, Icons.ios_share, 'تصدير سريع'),\n"
    "        (102, Icons.auto_fix_high, 'لمسات'),\n"))

edits.append(('tool body',
    "      case 101:\n        return _ratioToggle();\n",
    "      case 101:\n        return _ratioToggle();\n"
    "      case 103: // " + MARK + "\n"
    "        return ProColorPage(state: state);\n"
    "      case 104:\n"
    "        return ProAudioMixer(state: state, onPickMusic: _pickMusicBed);\n"
    "      case 105:\n"
    "        return ProTranscript(\n"
    "          state: state,\n"
    "          controller: _video,\n"
    "          onToast: _toast,\n"
    "          onSelectSeg: (i) => setState(() => _selSeg = i),\n"
    "        );\n"
    "      case 106:\n"
    "        return ProExportPresets(\n"
    "            state: state, busy: _busy, onExport: _export);\n"))

edits.append(('panel height + compact flag',
    "      final panelH = (c.maxHeight * 0.42).clamp(0.0, 460.0);\n"
    "      final hasStatus = _busy || state.corpusStatus.isNotEmpty;\n",
    "      final panelH = (c.maxHeight * 0.36).clamp(0.0, 420.0);\n"
    "      final hasStatus = _busy || state.corpusStatus.isNotEmpty;\n"
    "      final dockCompact = _toolOpen != -1 || c.maxHeight < 560; // " + MARK + "\n"))

edits.append(('transport -> dock',
    "          if (_video != null && _video!.value.isInitialized)\n"
    "            Padding(\n"
    "              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),\n"
    "              child: _transportBar(),\n"
    "            ),\n",
    "          if (_video != null && _video!.value.isInitialized)\n"
    "            _proDock(dockCompact), // " + MARK + "\n"))

edits.append(('contextual strip',
    "          _toolStrip(),\n        ],\n      );\n    });\n  }\n",
    "          _hasSelSeg ? _clipToolStrip() : _toolStrip(), // " + MARK + "\n"
    "        ],\n      );\n    });\n  }\n"))

edits.append(('new methods',
    "  Widget _toolPanel(double h) {\n",
    HOME_METHODS + "  Widget _toolPanel(double h) {\n"))

# ---- verify every anchor exactly once BEFORE writing anything ----
bad = []
for label, old, _ in edits:
    n = src.count(old)
    if n != 1:
        bad.append('%s (found %d)' % (label, n))
if bad:
    sys.exit('Anchor check failed, nothing written: ' + '; '.join(bad))

for label, old, new in edits:
    src = src.replace(old, new, 1)
    print('  PATCHED', label)

for path, body in NEW_FILES.items():
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(body)
    print('  WROTE  ', path)

with open(HOME, 'w', encoding='utf-8') as f:
    f.write(src)
print('S174 applied. Next: git add -A && git commit -m "S174: pro editor" && git push')
