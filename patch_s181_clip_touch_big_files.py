#!/usr/bin/env python3
"""
patch_s181_clip_touch_big_files.py - Ayat Studio S181 (run from repo root, after S180)

What this patch does
  1. Big files: the waveform is decoded in a background isolate (no more UI
     freeze after uploading a long recording), heavy jobs (waveform, filmstrip)
     run one at a time, and the timeline only paints what is on screen.
  2. Timeline clips you can really touch: ayah blocks AND text blocks show their
     text, get big gold edge handles you drag with your finger, auto-zoom when a
     clip is too narrow to grab, and the toolbar gets cut / trim-to-playhead /
     transition / zoom / duplicate / delete. The main clip can be selected too
     (trim head / tail, reset, transform, speed). A gold "+" sits at the end of
     the clip to add a video or a picture after it.
  3. آيات tab: only the essentials stay on top (text, mushaf, surah, ayah); the
     rest moves into a folded "خيارات متقدمة" card. Nothing was deleted.
  4. Touching text on the stage dresses the stage in its روح (Ayah Mood) by
     itself - with an undo action and an on/off switch in the روح card.
  5. Everything called "music" is renamed (UI text, icons, i18n, code, tests).
     Saved settings keep working (old saved keys are still read once).

Idempotent; every anchor is verified before anything is written.
"""
import os, re, sys

MARK = 'PATCH_S181_CLIPTOUCH'

if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

P = {
    'home': 'lib/screens/home_screen.dart',
    'state': 'lib/models/studio_state.dart',
    'tl': 'lib/widgets/pro_timeline.dart',
    'stage': 'lib/widgets/stage_preview.dart',
    'magic': 'lib/widgets/magic_card.dart',
    'media': 'lib/services/media_service.dart',
    'wave': 'lib/services/waveform_service.dart',
    'thumb': 'lib/services/thumb_service.dart',
    'export': 'lib/services/export_service.dart',
    'settings': 'lib/services/settings_service.dart',
    'panels': 'lib/widgets/pro_panels.dart',
    'i18n': 'lib/i18n/app_strings.dart',
    'test': 'test/export_graph_test.dart',
    'doc': 'docs/ayat_studio225.html',
}
rd = lambda p: open(p, encoding='utf-8').read()
for k, p in P.items():
    if k == 'doc':
        continue
    if not os.path.exists(p):
        sys.exit('missing ' + p)
T = {k: rd(p) for k, p in P.items() if os.path.exists(p)}

if MARK in T['state']:
    print('  OK      already applied'); sys.exit(0)
if 'PATCH_S180_TRANSFORM' not in T['state']:
    sys.exit('S180 not applied yet.')

# --------------------------------------------------------------- new files
HEAVY_GATE = r"""// PATCH_S181_CLIPTOUCH
// One-at-a-time queue for the heavy background jobs that start right after a
// big file is opened (waveform decode, filmstrip). Running them side by side,
// right while the player is starting, is what made the editor stutter for a
// while after an upload and then "become normal".
class HeavyGate {
  HeavyGate._();

  static Future<void> _tail = Future<void>.value();

  /// Runs [job] after every job queued before it has finished, and after a
  /// short pause so the first frames of the player are not competing with it.
  static Future<T> run<T>(Future<T> Function() job) {
    final Future<T> done = _tail
        .then<void>((_) => Future<void>.delayed(const Duration(milliseconds: 350)))
        .then<T>((_) => job());
    _tail = done.then<void>((_) {}, onError: (Object _) {});
    return done;
  }
}
"""

WAVE_NEW = r"""// PATCH_S181_CLIPTOUCH (replaces the S174 version; same public API)
// Audio peaks for the timeline's waveform lanes (the Premiere / Resolve /
// CapCut look). One ffmpeg pass decodes the file to 2 kHz mono PCM, then a
// background isolate reads it in small chunks and collapses every 20 samples
// to one peak = 100 peaks per second. Nothing here runs on the UI isolate and
// the raw file is never loaded whole, so a very long recording no longer
// freezes the editor. Cached per path; null = could not decode and the lane
// just draws a flat bar.
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'heavy_gate.dart';

class WaveformService {
  WaveformService._();

  /// Peaks per second of audio.
  static const int peaksPerSec = 100;

  /// Decode rate for the peak pass. Display only, so 2 kHz is plenty.
  static const int _rate = 2000;

  static final Map<String, List<double>> _cache = {};
  static final Map<String, Future<List<double>?>> _pending = {};

  static List<double>? cached(String path) => _cache[path];

  static Future<List<double>?> peaks(String path) {
    final hit = _cache[path];
    if (hit != null) return Future<List<double>?>.value(hit);
    final running = _pending[path];
    if (running != null) return running;
    final job = HeavyGate.run<List<double>?>(() => _compute(path));
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
          '-y -threads 2 -i "$path" -vn -ac 1 -ar $_rate -f s16le "$rawPath"');
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc) || !rawFile.existsSync()) return null;
      const per = _rate ~/ peaksPerSec;
      final res = await Isolate.run<List<double>>(() => _reduce(rawPath, per));
      try {
        rawFile.deleteSync();
      } catch (_) {}
      if (res.isEmpty) return null;
      _cache[path] = res;
      return res;
    } catch (_) {
      return null;
    }
  }

  /// Runs inside the background isolate: s16le mono file -> normalised peaks.
  static List<double> _reduce(String rawPath, int per) {
    final raf = File(rawPath).openSync();
    try {
      final n = raf.lengthSync() ~/ 2;
      if (n == 0) return <double>[];
      final count = (n / per).ceil();
      final res = List<double>.filled(count, 0);
      final chunk = Uint8List(per * 2 * 4000); // whole peaks per read
      var idx = 0;
      var maxPeak = 0.0;
      while (idx < count) {
        final got = raf.readIntoSync(chunk);
        if (got <= 0) break;
        final bd = ByteData.sublistView(chunk, 0, got);
        final samples = got ~/ 2;
        for (var s = 0; s < samples && idx < count; s += per) {
          final e = math.min(samples, s + per);
          var peak = 0;
          for (var j = s; j < e; j++) {
            final v = bd.getInt16(j * 2, Endian.little).abs();
            if (v > peak) peak = v;
          }
          final d = peak / 32768.0;
          res[idx++] = d;
          if (d > maxPeak) maxPeak = d;
        }
      }
      final used = res.sublist(0, idx);
      // Display-normalise so quiet recitations still read as a waveform.
      if (maxPeak > 0.02) {
        final k = 1.0 / maxPeak;
        for (var i = 0; i < used.length; i++) {
          used[i] = (used[i] * k).clamp(0.0, 1.0);
        }
      }
      return used;
    } finally {
      raf.closeSync();
    }
  }
}
"""

THUMB_NEW = r"""// PATCH_S181_CLIPTOUCH (replaces the S179 version; same public API)
// Video thumbnails for the timeline's video lane (the filmstrip every pro
// editor shows). One ffmpeg pass writes at most ~40 small JPEG frames, one
// every `step` seconds; cached per path for the session. null = could not
// decode (audio-only files land here), and the lane keeps its plain bar.
// Long videos only decode keyframes, and the job waits its turn behind the
// waveform so a big upload is never doing both at once.
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'heavy_gate.dart';

class ThumbStrip {
  /// Seconds between two thumbnails.
  final double step;
  final List<String> files;
  const ThumbStrip(this.step, this.files);
}

class ThumbService {
  ThumbService._();

  static final Map<String, ThumbStrip> _cache = {};
  static final Map<String, Future<ThumbStrip?>> _pending = {};

  static ThumbStrip? cached(String path) => _cache[path];

  static Future<ThumbStrip?> strip(String path, double durSec) {
    final hit = _cache[path];
    if (hit != null) return Future<ThumbStrip?>.value(hit);
    final running = _pending[path];
    if (running != null) return running;
    final job = HeavyGate.run<ThumbStrip?>(() => _compute(path, durSec));
    _pending[path] = job;
    job.whenComplete(() {
      _pending.remove(path);
    });
    return job;
  }

  static Future<ThumbStrip?> _compute(String path, double durSec) async {
    try {
      final tmp = await getTemporaryDirectory();
      final dir = Directory('${tmp.path}/thumbs_${path.hashCode.abs()}');
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);
      final stepI = math.max(1, (durSec / 40).ceil());
      final fast = durSec > 120 ? '-skip_frame nokey ' : '';
      final session = await FFmpegKit.execute(
          '-y -threads 2 $fast-i "$path" -an -vf "fps=1/$stepI,scale=-2:72" '
          '-q:v 7 -frames:v 60 "${dir.path}/t_%03d.jpg"');
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) return null;
      final files = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.path)
          .where((p) => p.endsWith('.jpg'))
          .toList()
        ..sort();
      if (files.isEmpty) return null;
      final res = ThumbStrip(stepI.toDouble(), files);
      _cache[path] = res;
      return res;
    } catch (_) {
      return null;
    }
  }
}
"""

RUH_TOUCH = r"""// PATCH_S181_CLIPTOUCH
// Touching the text on the stage lets its روح dress the stage by itself - the
// very same recipe the «روح الآية» card applies by hand (effect, text colour,
// grade, vignette). One undo step; the switch lives in the روح card.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';
import 'ayah_mood.dart';

class RuhTouch {
  RuhTouch._();

  static void apply(BuildContext context, StudioState s, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final r = AyahMood.analyze(clean);
    // Already dressed in this روح: touching again must not nag.
    if (s.effect == r.effect && s.textColor == r.textColor) return;
    HapticFeedback.selectionClick();
    s.update(() {
      s.effect = r.effect;
      s.effectIntensity = r.intensity;
      s.textColor = r.textColor;
      s.colorGrade = r.grade;
      s.vignetteEnabled = r.vignette > 0;
      if (r.vignette > 0) s.vignetteIntensity = r.vignette;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('اكتست الآية روح «${r.labelAr}» ${r.emoji}',
            textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: AyatColors.goldBright,
          onPressed: s.undoStep,
        ),
      ));
  }
}
"""

# ===================================================================== TIMELINE
TL_FIELDS = r"""  /// Fewer lanes / shorter lanes while a tool panel is open.
  final bool compact;

  // PATCH_S181_CLIPTOUCH: text blocks and the main clip are selectable too, and
  // the gold "+" at the end of the clip adds a video / picture.
  final int selectedCue;
  final ValueChanged<int>? onSelectCue;
  final bool selectedMain;
  final ValueChanged<bool>? onSelectMain;
  final VoidCallback? onAddMedia;
"""

TL_CTOR = r"""    required this.markers,
    this.compact = false,
    this.selectedCue = -1, // PATCH_S181_CLIPTOUCH
    this.onSelectCue,
    this.selectedMain = false,
    this.onSelectMain,
    this.onAddMedia,
  });
"""

TL_ZOOM_API = r"""  // PATCH_S181_CLIPTOUCH: zoom so [a, b] (seconds) fills most of the view and
  // centre it - the toolbar's تكبير button, and the automatic zoom that runs
  // when a clip too narrow to grab gets selected.
  void zoomToRange(double a, double b) => _zoomTo(a, b, fill: 0.78, force: true);

  void _zoomIfNarrow(double a, double b) {
    if ((b - a) * _pps >= 90) return;
    _zoomTo(a, b, fill: 0.5, force: false);
  }

  void _zoomTo(double a, double b, {required double fill, required bool force}) {
    final span = b - a;
    if (span <= 0.05) return;
    final target = ((_viewW * fill) / span).clamp(_minPps, _maxPps).toDouble();
    if (!force && target <= _pps) return;
    _setPps(target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final mid = (a + b) / 2 * _pps;
      _scroll.animateTo(
        (mid - _viewW / 2).clamp(0.0, _scroll.position.maxScrollExtent).toDouble(),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void zoomBy(double factor) => _setPps(_pps * factor);
"""

TL_TEXT_LANE = r"""  // PATCH_S181_CLIPTOUCH: text blocks show their text, can be selected, and
  // their edges are dragged with the finger.
  Widget _textLane(double h, double w) {
    final cues = widget.state.textTimeCues;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        widget.onSelectSeg(-1);
        _seekSec(d.localPosition.dx / _pps);
      },
      child: Stack(
        children: [
          for (var i = 0; i < cues.length; i++) _cueClip(i, h),
        ],
      ),
    );
  }

  Widget _cueClip(int i, double h) {
    final cues = widget.state.textTimeCues;
    if (i >= cues.length) return const SizedBox.shrink();
    final cue = cues[i];
    final sel = widget.selectedCue == i;
    final w = math.max(6.0, (cue.end - cue.start) * _pps - 1);
    return Positioned(
      left: cue.start * _pps,
      width: w,
      top: 2,
      height: h - 4,
      child: GestureDetector(
        onTapUp: (d) {
          widget.onSelectSeg(-1);
          widget.onSelectCue?.call(sel ? -1 : i);
          _seekSec(cue.start + d.localPosition.dx / _pps);
          if (!sel) _zoomIfNarrow(cue.start, cue.end);
          HapticFeedback.selectionClick();
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: sel ? 24 : 6),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: const Color(0xFF2C6B5A),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: sel
                        ? AyatColors.goldBright
                        : const Color(0x66ECC875),
                    width: sel ? 2 : 1,
                  ),
                ),
                child: ClipRect(
                  child: Text(
                    cue.text,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AyatColors.parchment),
                  ),
                ),
              ),
            ),
            if (sel) ...[
              _cueHandle(i, true, w),
              _cueHandle(i, false, w),
            ],
          ],
        ),
      ),
    );
  }

  double _cueBase = 0;
  double _cueAccum = 0;

  Widget _cueHandle(int i, bool isStart, double clipW) {
    return Positioned(
      left: isStart ? 0 : null,
      right: isStart ? null : 0,
      top: 0,
      bottom: 0,
      width: _handleW(clipW),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          final cues = widget.state.textTimeCues;
          if (i >= cues.length) return;
          widget.state.pushHistory();
          _cueBase = isStart ? cues[i].start : cues[i].end;
          _cueAccum = 0;
          HapticFeedback.selectionClick();
        },
        onHorizontalDragUpdate: (d) {
          _cueAccum += d.delta.dx;
          _moveCueEdge(i, isStart);
        },
        child: _handleBody(isStart),
      ),
    );
  }

  void _moveCueEdge(int i, bool isStart) {
    final cues = widget.state.textTimeCues;
    if (i < 0 || i >= cues.length) return;
    final cue = cues[i];
    var target = _cueBase + _cueAccum / _pps;
    final snaps = <double>[
      widget.controller.value.position.inMilliseconds / 1000.0,
      ...widget.markers,
      for (var k = 0; k < cues.length; k++)
        if (k != i) ...[cues[k].start, cues[k].end],
      for (final s in widget.state.timeline) ...[s.start, s.end],
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
    target = target.clamp(0.0, _dur).toDouble();
    if (isStart) {
      if ((target - cue.start).abs() < 0.001) return;
      widget.state.setTextCueWindow(i, start: target);
    } else {
      if ((target - cue.end).abs() < 0.001) return;
      widget.state.setTextCueWindow(i, end: target);
    }
  }

"""

TL_SEG_BLOCK = r"""  // PATCH_S181_CLIPTOUCH: ayah blocks - taller, the text is easy to read, the
  // selected one wears big gold edge handles, and a clip too narrow to grab
  // zooms itself in first.
  Widget _segClip(int i, double h, bool locked) {
    final s = widget.state.timeline[i];
    final sel = widget.selectedSeg == i;
    final w = math.max(3.0, (s.end - s.start) * _pps - 1);
    final alpha = s.inferred
        ? 0.30
        : (0.35 + 0.55 * s.confidence.clamp(0.0, 1.0)).toDouble();
    final showHandles = sel && !locked;
    return Positioned(
      left: s.start * _pps,
      width: w,
      top: 2,
      height: h - 4,
      child: GestureDetector(
        onTapUp: (d) {
          widget.onSelectSeg(sel ? -1 : i);
          _seekSec(s.start + d.localPosition.dx / _pps);
          if (!sel) {
            _zoomIfNarrow(s.start, s.end);
            HapticFeedback.selectionClick();
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: showHandles ? 24 : 6),
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
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: AyatColors.ink),
                  ),
                ),
              ),
            ),
            if (showHandles) ...[
              _edgeHandle(i, true, w),
              _edgeHandle(i, false, w),
            ],
          ],
        ),
      ),
    );
  }

  /// Width of an edge handle: big enough for a thumb, never wider than half
  /// the clip.
  double _handleW(double clipW) =>
      math.min(clipW / 2, math.min(28.0, math.max(16.0, clipW / 2.5)));

  Widget _handleBody(bool isStart) {
    return Container(
      decoration: BoxDecoration(
        color: AyatColors.goldBright,
        borderRadius: isStart
            ? const BorderRadius.horizontal(left: Radius.circular(6))
            : const BorderRadius.horizontal(right: Radius.circular(6)),
      ),
      child: Center(
        child: Container(
          width: 3,
          height: 18,
          decoration: BoxDecoration(
            color: AyatColors.ink,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  Widget _edgeHandle(int i, bool isStart, double clipW) {
    return Positioned(
      left: isStart ? 0 : null,
      right: isStart ? null : 0,
      top: 0,
      bottom: 0,
      width: _handleW(clipW),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) {
          final tl = widget.state.timeline;
          if (i >= tl.length) return;
          _dragBase = isStart ? tl[i].start : tl[i].end;
          _dragAccum = 0;
          HapticFeedback.selectionClick();
        },
        onHorizontalDragUpdate: (d) {
          _dragAccum += d.delta.dx;
          _moveEdge(i, isStart);
        },
        child: _handleBody(isStart),
      ),
    );
  }

"""

TL_ADD_BUTTON = r"""          // PATCH_S181_CLIPTOUCH: the gold "+" after the clip adds a video / picture
          if (widget.onAddMedia != null)
            Positioned(
              left: dur * _pps + 10,
              top: (h - 4) / 2 - 12,
              width: 28,
              height: 28,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.onAddMedia!();
                },
                child: Container(
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AyatColors.goldBright,
                  ),
                  child: const Icon(Icons.add, size: 18, color: AyatColors.ink),
                ),
              ),
            ),
          // dim whatever the export will cut away
"""

TL_PAINTERS = r"""class _RulerPainter extends CustomPainter {
  final double pps;
  final double dur;
  final List<double> markers;
  final ScrollController scroll; // PATCH_S181_CLIPTOUCH: paint only what is on screen
  final double viewW;
  _RulerPainter({
    required this.pps,
    required this.dur,
    required this.markers,
    required this.scroll,
    required this.viewW,
  }) : super(repaint: scroll);

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
    final off = scroll.hasClients ? scroll.offset : 0.0;
    final span = step * pps;
    final firstK = math.max(0, ((off - 80) / span).floor());
    final lastK = math.min(n, ((off + viewW + 80) / span).ceil());
    for (var k = firstK; k <= lastK; k++) {
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
      old.pps != pps ||
      old.dur != dur ||
      old.viewW != viewW ||
      old.markers.join(',') != markers.join(',');
}

class _WavePainter extends CustomPainter {
  final List<double>? peaks;
  final double pps;
  final bool loop;
  final Color color;
  final ScrollController scroll; // PATCH_S181_CLIPTOUCH: paint only what is on screen
  final double viewW;
  _WavePainter({
    required this.peaks,
    required this.pps,
    required this.loop,
    required this.color,
    required this.scroll,
    required this.viewW,
  }) : super(repaint: scroll);

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
    final off = scroll.hasClients ? scroll.offset : 0.0;
    final from = (math.max(0.0, off - 40) / 2).floor() * 2.0;
    final to = math.min(size.width, off + viewW + 40);
    for (double x = from; x < to; x += 2) {
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
      old.color != color ||
      old.viewW != viewW;
}
"""

def slice_replace(text, start, end, new, label):
    if text.count(start) != 1:
        sys.exit('Anchor check failed (%s start, found %d)' % (label, text.count(start)))
    a = text.index(start)
    if end is None:
        return text[:a] + new
    if text.count(end) != 1:
        sys.exit('Anchor check failed (%s end, found %d)' % (label, text.count(end)))
    b = text.index(end)
    if b < a:
        sys.exit('Anchor order wrong (%s)' % label)
    return text[:a] + new + text[b:]

# ======================================================================== HOME
HOME_FIELDS = r"""  int _selSeg = -1;
  int _selCue = -1; // PATCH_S181_CLIPTOUCH: selected text block on the timeline
  bool _selMain = false; // PATCH_S181_CLIPTOUCH: the main clip is selected
  bool _ayahAdvOpen = false; // PATCH_S181_CLIPTOUCH: آيات tab "advanced" fold
  final List<double> _markers = [];
"""

HOME_GETTERS = r"""  bool get _hasSelSeg => _selSeg >= 0 && _selSeg < state.timeline.length;
  // PATCH_S181_CLIPTOUCH
  bool get _hasSelCue => _selCue >= 0 && _selCue < state.textTimeCues.length;
  bool get _hasSelMain => _selMain && _video != null && _video!.value.isInitialized;
  bool get _hasAnySel => _hasSelSeg || _hasSelCue || _hasSelMain;
"""

HOME_TL_WIRING = r"""          selectedSeg: _selSeg,
          // PATCH_S181_CLIPTOUCH: any selection change on the ayah lane first
          // clears the other kinds; text / main selections set theirs after it.
          onSelectSeg: (i) => setState(() {
            _selSeg = i;
            _selCue = -1;
            _selMain = false;
          }),
          selectedCue: _hasSelCue ? _selCue : -1,
          onSelectCue: (i) => setState(() {
            _selCue = i;
            _selSeg = -1;
            _selMain = false;
          }),
          selectedMain: _hasSelMain,
          onSelectMain: (v) => setState(() {
            _selMain = v;
            if (v) {
              _selSeg = -1;
              _selCue = -1;
            }
          }),
          onAddMedia: _addMediaSheet,
          markers: _markers,
          compact: compact,
"""

HOME_METHODS = r"""  // ---------------------------------------------------------------------
  // PATCH_S181_CLIPTOUCH: touchable clips (ayah blocks, text blocks, the main
  // clip), trim-to-playhead, transitions, zoom, add video / picture, and the
  // folded "advanced" card of the آيات tab.
  // ---------------------------------------------------------------------

  double get _playheadSec {
    final c = _video;
    if (c == null || !c.value.isInitialized) return 0;
    return c.value.position.inMilliseconds / 1000.0;
  }

  Widget _clipBar(List<(IconData, String, VoidCallback, bool)> items) {
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

  /// Extra actions for a selected ayah block (placed after «تقسيم»).
  List<(IconData, String, VoidCallback, bool)> _segExtraItems(int i) => [
        (Icons.first_page, 'قص البداية', () => _trimSeg(i, head: true), false),
        (Icons.last_page, 'قص النهاية', () => _trimSeg(i, head: false), false),
        (Icons.animation, 'انتقال', _openTransitionSheet, false),
        (Icons.zoom_in, 'تكبير', _zoomToSelection, false),
      ];

  void _trimSeg(int i, {required bool head}) {
    if (i < 0 || i >= state.timeline.length) return;
    final seg = state.timeline[i];
    final t = _playheadSec;
    if (t <= seg.start + 0.3 || t >= seg.end - 0.3) {
      _toast('ضع المؤشر داخل الآية المحددة ثم اقصّ');
      return;
    }
    HapticFeedback.mediumImpact();
    if (head) {
      state.nudgeTimelineSegment(i, startDelta: t - seg.start);
    } else {
      state.nudgeTimelineSegment(i, endDelta: t - seg.end);
    }
  }

  // ---- text blocks --------------------------------------------------------

  List<(IconData, String, VoidCallback, bool)> _cueItems() {
    final i = _selCue;
    return [
      (Icons.check_circle_outline, 'تم', () => setState(() => _selCue = -1), false),
      (Icons.content_cut, 'تقسيم', () => _cueSplit(i), false),
      (Icons.first_page, 'قص البداية', () => _cueTrim(i, head: true), false),
      (Icons.last_page, 'قص النهاية', () => _cueTrim(i, head: false), false),
      (Icons.animation, 'انتقال', _openTransitionSheet, false),
      (Icons.edit_outlined, 'تعديل النص', () => _cueEditText(i), false),
      (Icons.zoom_in, 'تكبير', _zoomToSelection, false),
      (Icons.content_copy, 'نسخ', () => _cueDuplicate(i), false),
      (Icons.delete_outline, 'حذف', () => _cueDelete(i), false),
    ];
  }

  void _cueSplit(int i) {
    if (i < 0 || i >= state.textTimeCues.length) return;
    final t = _playheadSec;
    state.pushHistory();
    if (state.splitTextCueAt(i, t)) {
      HapticFeedback.mediumImpact();
      setState(() {
        _selCue = i + 1;
        _selSeg = -1;
        _selMain = false;
      });
    } else {
      _toast('ضع المؤشر داخل النص المحدد ثم قسّم');
    }
  }

  void _cueTrim(int i, {required bool head}) {
    if (i < 0 || i >= state.textTimeCues.length) return;
    final c = state.textTimeCues[i];
    final t = _playheadSec;
    if (t <= c.start + 0.3 || t >= c.end - 0.3) {
      _toast('ضع المؤشر داخل النص المحدد ثم اقصّ');
      return;
    }
    HapticFeedback.mediumImpact();
    state.pushHistory();
    state.setTextCueWindow(i, start: head ? t : null, end: head ? null : t);
  }

  void _cueDuplicate(int i) {
    if (i < 0 || i >= state.textTimeCues.length) return;
    state.pushHistory();
    state.duplicateTextCue(i);
    HapticFeedback.selectionClick();
    setState(() => _selCue = i + 1);
  }

  void _cueDelete(int i) {
    if (i < 0 || i >= state.textTimeCues.length) return;
    state.pushHistory();
    state.removeTextTimeCueAt(i);
    setState(() => _selCue = -1);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('تم حذف النص من الخط الزمني',
            textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: AyatColors.goldBright,
          onPressed: state.undoStep,
        ),
      ));
  }

  Future<void> _cueEditText(int i) async {
    if (i < 0 || i >= state.textTimeCues.length) return;
    final cue = state.textTimeCues[i];
    final ctrl = TextEditingController(text: cue.text);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AyatColors.surface,
        title: const Text('تعديل النص'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 4,
          textAlign: TextAlign.right,
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text),
              child: const Text('حفظ')),
        ],
      ),
    );
    ctrl.dispose();
    if (result == null || result.trim().isEmpty) return;
    state.update(() => cue.text = result.trim());
  }

  // ---- the main clip ------------------------------------------------------

  List<(IconData, String, VoidCallback, bool)> _mainItems() => [
        (Icons.check_circle_outline, 'تم', () => setState(() => _selMain = false), false),
        (Icons.first_page, 'قص البداية', () => _trimMain(head: true), false),
        (Icons.last_page, 'قص النهاية', () => _trimMain(head: false), false),
        (
          Icons.restart_alt,
          'إعادة القص',
          _trimMainReset,
          state.manualTrimSet || state.trimFromIndex >= 0
        ),
        (Icons.add_photo_alternate_outlined, 'إضافة', _addMediaSheet, false),
        (Icons.animation, 'انتقال', _openTransitionSheet, false),
        (Icons.open_with, 'التحويل', () => _openToolFromClip(112), false),
        (Icons.speed, 'السرعة', () => _openToolFromClip(107), false),
        (Icons.fit_screen_outlined, 'ملاءمة', () => _tlKey.currentState?.fit(), false),
      ];

  void _openToolFromClip(int id) {
    setState(() => _selMain = false);
    if (_toolOpen != id) _openTool(id);
  }

  void _trimMain({required bool head}) {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration.inMilliseconds / 1000.0;
    final t = _playheadSec;
    final end = state.trimManualEnd < 0 ? dur : min(state.trimManualEnd, dur);
    final start = min(state.trimManualStart, end);
    if (head ? t >= end - 0.5 : t <= start + 0.5) {
      _toast('ضع المؤشر داخل المقطع المحدد ثم اقصّ');
      return;
    }
    HapticFeedback.mediumImpact();
    state.update(() {
      state.trimFromIndex = -1;
      state.trimToIndex = -1;
      if (head) {
        state.trimManualStart = max(0.0, t);
        state.trimManualEnd = end;
      } else {
        state.trimManualStart = start;
        state.trimManualEnd = min(t, dur);
      }
    });
  }

  void _trimMainReset() {
    HapticFeedback.selectionClick();
    state.update(() {
      state.trimFromIndex = -1;
      state.trimToIndex = -1;
      state.trimManualStart = 0;
      state.trimManualEnd = -1;
    });
  }

  void _zoomToSelection() {
    double? a;
    double? b;
    if (_hasSelSeg) {
      a = state.timeline[_selSeg].start;
      b = state.timeline[_selSeg].end;
    } else if (_hasSelCue) {
      a = state.textTimeCues[_selCue].start;
      b = state.textTimeCues[_selCue].end;
    } else if (_hasSelMain) {
      a = 0;
      b = max(0.5, state.videoDurationSec);
    }
    if (a == null || b == null) return;
    _tlKey.currentState?.zoomToRange(a, b);
  }

  // ---- transitions --------------------------------------------------------

  /// Quick access to the entrance / exit style from any selected clip. The
  /// style is one setting for all text (that is how the exporter works), and
  /// the sheet says so.
  void _openTransitionSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AyatColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.72),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('الانتقال يُطبَّق على ظهور كل نص واختفائه',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                          color: AyatColors.goldBright,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _textTransitionSection(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---- add a video / a picture --------------------------------------------

  Future<void> _addMediaSheet() async {
    if (!state.hasVideo) {
      _toast('ارفع ملفًا أولًا');
      return;
    }
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AyatColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إضافة بعد نهاية المقطع',
                  style: Theme.of(ctx).textTheme.headlineMedium),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.movie_outlined,
                    color: AyatColors.goldBright),
                title: const Text('فيديو'),
                onTap: () => Navigator.pop(ctx, 'video'),
              ),
              ListTile(
                leading: const Icon(Icons.image_outlined,
                    color: AyatColors.goldBright),
                title: const Text('صورة'),
                onTap: () => Navigator.pop(ctx, 'image'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final res = await FilePicker.platform
        .pickFiles(type: choice == 'image' ? FileType.image : FileType.video);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    var sec = 5.0;
    if (choice == 'image') {
      final s = await _askImageSeconds();
      if (s == null || !mounted) return;
      sec = s;
    }
    await _appendMedia(path, isImage: choice == 'image', imageSec: sec);
  }

  Future<double?> _askImageSeconds() {
    var sel = 5;
    return showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          backgroundColor: AyatColors.surface,
          title: const Text('مدة ظهور الصورة'),
          content: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in const [3, 5, 8, 10, 15])
                ChoiceChip(
                  label: Text('$s ث'),
                  selected: sel == s,
                  onSelected: (_) => setD(() => sel = s),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, sel.toDouble()),
                child: const Text('إضافة')),
          ],
        ),
      ),
    );
  }

  /// Renders "current clip + the new video / picture" into one file (the same
  /// pre-pass idea as S79 / S125), so auto-sync, text and export still see a
  /// single source. The new part goes AFTER the current clip, so everything
  /// already detected stays exactly where it was.
  Future<void> _appendMedia(String addPath,
      {required bool isImage, required double imageSec}) async {
    final basePath = state.videoPath;
    if (basePath == null) return;
    final keepTimeline = List<TimelineSegment>.of(state.timeline);
    final keepActive = state.timelineActive;
    final keepFrom = state.trimFromIndex;
    final keepTo = state.trimToIndex;
    final keepStart = state.trimManualStart;
    final keepEnd = state.trimManualEnd;
    final keepDetected = state.detectedAudioDurationSec;
    final cur = _video;
    final baseDur = (cur != null && cur.value.isInitialized)
        ? cur.value.duration.inMilliseconds / 1000.0
        : state.videoDurationSec;
    final baseHasVideo =
        cur != null && cur.value.isInitialized && cur.value.size.width > 0;
    final (fw, fh) = state.frameSize;
    final merged = await _withBusy(() async {
      _setBusyStatus(isImage ? 'جارٍ إضافة الصورة…' : 'جارٍ إضافة الفيديو…');
      return MediaService.appendClip(
        basePath,
        addPath,
        baseDurationSec: baseDur,
        baseHasVideo: baseHasVideo,
        addIsImage: isImage,
        imageSec: imageSec,
        width: fw,
        height: fh,
      );
    });
    if (merged == null || !mounted) return;
    await _video?.dispose();
    _liveOverlay.value = null;
    final controller = VideoPlayerController.file(File(merged));
    _video = controller;
    state.setVideo(merged);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      state.update(() {
        state.videoDurationSec =
            controller.value.duration.inMilliseconds / 1000.0;
        if (keepTimeline.isNotEmpty) {
          state.timeline = keepTimeline;
          state.timelineActive = keepActive;
        }
        state.trimFromIndex = keepFrom;
        state.trimToIndex = keepTo;
        state.trimManualStart = keepStart;
        // A tail that was cut off would hide what was just added.
        state.trimManualEnd = -1;
        state.detectedAudioDurationSec = keepDetected;
      });
    } catch (_) {
      // the player refusing the file must not lose the render
    }
    if (mounted) setState(() {});
    _toast(isImage ? 'أُضيفت الصورة ✓' : 'أُضيف الفيديو ✓');
  }

  // ---- آيات tab: the folded "advanced" card -----------------------------------

  Widget _advancedFold(Widget child) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      decoration: BoxDecoration(
        color: AyatColors.surface2.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AyatColors.hairline),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const PageStorageKey<String>('ayah_advanced_fold'),
          initiallyExpanded: _ayahAdvOpen,
          onExpansionChanged: (v) => _ayahAdvOpen = v,
          leading: const Icon(Icons.tune, color: AyatColors.goldBright),
          title: const Text('خيارات متقدمة',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: AyatColors.parchment)),
          subtitle: const Text(
              'جزء من آية · توقيت النص · المعالج · بطاقات البسملة والخاتمة',
              style: TextStyle(fontSize: 11.5, color: AyatColors.parchmentDim)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [child],
        ),
      ),
    );
  }

"""

# ============================================================ MEDIA / STATE / STAGE / MAGIC
MEDIA_APPEND = r"""  // PATCH_S181_CLIPTOUCH: appends a VIDEO or a PICTURE after the current clip.
  // Same idea as S79 / S125: render "clip + new part" to one file so everything
  // downstream keeps seeing a single source. Unlike mergeVideos it also works
  // when the current clip is audio-only (a black picture stands in for it), when
  // either side has no audio (silence stands in), and for still pictures.
  static Future<bool> _hasStream(String path, String type,
      {required bool fallback}) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) return fallback;
      return info.getStreams().any((s) => s.getType() == type);
    } catch (_) {
      return fallback;
    }
  }

  static Future<String> appendClip(
    String basePath,
    String addPath, {
    required double baseDurationSec,
    required bool baseHasVideo,
    required bool addIsImage,
    double imageSec = 5,
    int width = 1080,
    int height = 1920,
  }) async {
    if (!File(basePath).existsSync()) {
      throw Exception('تعذّر الوصول إلى المقطع الحالي — قد يكون تم حذفه أو نقله.\n$basePath');
    }
    if (!File(addPath).existsSync()) {
      throw Exception('تعذّر الوصول إلى الملف المضاف — قد يكون مسارًا غير مباشر (SAF) أو تم حذفه.\n$addPath');
    }
    final baseDur = baseDurationSec > 0.1
        ? baseDurationSec
        : ((await probedDurationSec(basePath)) ?? 1.0);
    final addDur =
        addIsImage ? imageSec : ((await probedDurationSec(addPath)) ?? 5.0);
    final baseHasAudio = await _hasStream(basePath, 'audio', fallback: true);
    final addHasAudio = addIsImage
        ? false
        : await _hasStream(addPath, 'audio', fallback: true);
    final addHasVideo = addIsImage
        ? true
        : await _hasStream(addPath, 'video', fallback: true);

    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/appended_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final inputs = StringBuffer('-y ');
    final filters = <String>[];
    var next = 0;
    int addInput(String args) {
      inputs.write('$args ');
      return next++;
    }

    String d(double v) => v.toStringAsFixed(3);

    (String, String) part(
      String tag,
      String path, {
      required bool image,
      required bool hasV,
      required bool hasA,
      required double dur,
    }) {
      var fileIdx = -1;
      var vSrc = '';
      if (image) {
        fileIdx = addInput('-loop 1 -framerate 30 -t ${d(dur)} -i "$path"');
        vSrc = '[$fileIdx:v]';
      } else {
        fileIdx = addInput('-i "$path"');
        if (hasV) vSrc = '[$fileIdx:v]';
      }
      if (vSrc.isEmpty) {
        final b = addInput(
            '-f lavfi -t ${d(dur)} -i "color=c=black:s=${width}x$height:r=30"');
        vSrc = '[$b:v]';
      }
      String aSrc;
      if (!image && hasA) {
        aSrc = '[$fileIdx:a]';
      } else {
        final s = addInput(
            '-f lavfi -t ${d(dur)} -i "anullsrc=r=44100:cl=stereo"');
        aSrc = '[$s:a]';
      }
      filters.add('${vSrc}scale=$width:$height:force_original_aspect_ratio=decrease,'
          'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30,format=yuv420p,'
          'tpad=stop_mode=clone:stop_duration=${d(dur)},'
          'trim=duration=${d(dur)},setpts=PTS-STARTPTS[v$tag]');
      filters.add('${aSrc}aresample=44100,aformat=channel_layouts=stereo,'
          'apad,atrim=duration=${d(dur)},asetpts=PTS-STARTPTS[a$tag]');
      return ('[v$tag]', '[a$tag]');
    }

    final a = part('0', basePath,
        image: false, hasV: baseHasVideo, hasA: baseHasAudio, dur: baseDur);
    final b = part('1', addPath,
        image: addIsImage, hasV: addHasVideo, hasA: addHasAudio, dur: addDur);
    filters.add('${a.$1}${a.$2}${b.$1}${b.$2}concat=n=2:v=1:a=1[outv][outa]');
    final cmd = '$inputs-filter_complex "${filters.join(';')}" '
        '-map "[outv]" -map "[outa]" -c:v libx264 -preset ultrafast -crf 23 '
        '-pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$outPath"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final rawLog = (await session.getOutput()) ?? '';
      final log =
          rawLog.length > 900 ? rawLog.substring(rawLog.length - 900) : rawLog;
      throw Exception('تعذّرت الإضافة (ffmpeg rc=$rc)\n$log');
    }
    return outPath;
  }

  // PATCH_S125_SEQUENCE: S79's merge took exactly two clips, whole, butted
"""

STATE_CUE_METHODS = r"""    final next = [...textTimeCues]..removeAt(index);
    textTimeCues = next;
    notifyListeners();
  }

  // PATCH_S181_CLIPTOUCH: shaping text blocks on the timeline.
  /// Moves one or both edges of a text block (seconds). The block never gets
  /// shorter than 0.3 s and never starts before 0.
  void setTextCueWindow(int index, {double? start, double? end}) {
    if (index < 0 || index >= textTimeCues.length) return;
    final c = textTimeCues[index];
    var s = start ?? c.start;
    var e = end ?? c.end;
    if (s < 0) s = 0;
    if (e - s < 0.3) {
      if (start != null) {
        s = e - 0.3;
      } else {
        e = s + 0.3;
      }
    }
    if (s < 0) {
      s = 0;
      e = 0.3;
    }
    c.start = s;
    c.end = e;
    notifyListeners();
  }

  /// Splits a text block in two at [atSec]. False when the point is too close
  /// to an edge (or outside the block).
  bool splitTextCueAt(int index, double atSec) {
    if (index < 0 || index >= textTimeCues.length) return false;
    final c = textTimeCues[index];
    if (atSec < c.start + 0.3 || atSec > c.end - 0.3) return false;
    final second = TextTimeCue(
        text: c.text, translation: c.translation, start: atSec, end: c.end);
    c.end = atSec;
    final next = [...textTimeCues]..insert(index + 1, second);
    textTimeCues = next;
    notifyListeners();
    return true;
  }

  /// A copy of the block right after it (same length), nudged to start where
  /// the original ends.
  void duplicateTextCue(int index) {
    if (index < 0 || index >= textTimeCues.length) return;
    final c = textTimeCues[index];
    final len = c.end - c.start;
    final copy = TextTimeCue(
        text: c.text,
        translation: c.translation,
        start: c.end,
        end: c.end + len);
    final next = [...textTimeCues]..insert(index + 1, copy);
    textTimeCues = next;
    notifyListeners();
  }
"""

STATE_RUH_FIELD = r"""  bool stageTextSelected = false;
  // PATCH_S181_CLIPTOUCH: touching the text on the stage dresses the stage in
  // its روح (Ayah Mood) by itself. Switch lives in the روح card.
  bool autoRuhOnTouch = true;
"""

MAGIC_TOGGLE = r"""            _ghostButton('فاجئني', Icons.casino_outlined, () => _surprise(r)),
          ]),
          const SizedBox(height: 10),
          // PATCH_S181_CLIPTOUCH: touching text on the stage applies its روح
          ToggleRow(
            label: 'تطبيق الروح تلقائيًا عند لمس النص',
            value: widget.state.autoRuhOnTouch,
            onChanged: (v) =>
                widget.state.update(() => widget.state.autoRuhOnTouch = v),
          ),
"""

STAGE_TAP_NEW = r"""        } else {
          state.selectStageText(liveSegment);
          // PATCH_S181_CLIPTOUCH: touching the text lets its روح dress the stage
          if (state.autoRuhOnTouch) {
            RuhTouch.apply(
                context, state, liveSegment?.displayText ?? state.ayahText);
          }
        }
      },
      onScaleStart: (_) => gestureStartUserScale = state.textUserScale,
"""

SPLIT_NEW = r"""    final seg = state.segmentAt(t);
    // PATCH_S181_CLIPTOUCH: a selected text block is split in preference to
    // whatever ayah happens to sit under the playhead.
    if (_hasSelCue) {
      final sc = state.textTimeCues[_selCue];
      if (t > sc.start + 0.3 && t < sc.end - 0.3) {
        _cueSplit(_selCue);
        return;
      }
    }
    if (seg == null) {
      final ci = state.textTimeCues
          .indexWhere((c) => t > c.start + 0.3 && t < c.end - 0.3);
      if (ci >= 0) {
        _cueSplit(ci);
        return;
      }
      _toast('ضع المؤشر داخل آية أو نص لتقسيمه');
      return;
    }
"""

# ---------------------------------------------------------------- music rename
REN = [
    ('hasMusicBed', 'hasAmbienceBed'),
    ('musicBedPath', 'ambienceBedPath'),
    ('musicBedVolume', 'ambienceBedVolume'),
    ('musicBedFade', 'ambienceBedFade'),
    ('_musicBedSection', '_ambienceBedSection'),
    ('_pickMusicBed', '_pickAmbienceBed'),
    ('onPickMusic', 'onPickAmbience'),
    ('hasMusic', 'hasAmbience'),
    ('home.backgroundMusicAmbience', 'home.backgroundAudioAmbience'),
    ('home.bgMusicLoopNote', 'home.bgAudioLoopNote'),
    ('Icons.library_music_outlined', 'Icons.graphic_eq'),
    ('Icons.music_note_outlined', 'Icons.waves'),
    ("'music'", "'ambience'"),
    ('خلفية موسيقية / أجواء', 'خلفية صوتية / أجواء'),
    ('إزالة الخلفية الموسيقية', 'إزالة الخلفية الصوتية'),
    ('تمت إضافة خلفية موسيقية', 'تمت إضافة خلفية صوتية'),
    ('إضافة خلفية موسيقية', 'إضافة خلفية صوتية'),
    ('الخلفية الموسيقية', 'الخلفية الصوتية'),
    ('أو أي موسيقى', 'أو أي خلفية صوتية'),
    ('Background music / ambience', 'Background audio / ambience'),
    ('Musique de fond / ambiance', 'Audio de fond / ambiance'),
    ('Musik latar / suasana', 'Audio latar / suasana'),
    ('پس منظر موسیقی / ماحول', 'پس منظر آڈیو / ماحول'),
    ('a music bed', 'an ambience bed'),
    ('music bed', 'ambience bed'),
    ('music-bed', 'ambience-bed'),
    ('background music / ambience', 'background audio / ambience'),
    ('the video, music, or', 'the video, an ambience track, or'),
]

def rename_music(text):
    for a, b in REN:
        text = text.replace(a, b)
    text = re.sub(r'\b_mus\b', '_amb', text)
    return text

# ====================================================================== EDITS
NEW = {
    'lib/services/heavy_gate.dart': HEAVY_GATE,
    'lib/services/ruh_touch.dart': RUH_TOUCH,
}
# These two already exist (S174 / S179) and are replaced by faster versions.
REPLACE = {
    P['wave']: (WAVE_NEW, 'PATCH_S174_PRO_EDITOR'),
    P['thumb']: (THUMB_NEW, 'PATCH_S179_AAA'),
}
for path, (_, sig) in REPLACE.items():
    if sig not in T['wave' if path == P['wave'] else 'thumb']:
        sys.exit('%s is not the expected version (missing %s)' % (path, sig))

edits = {
 'state': [
  ('ruh switch field', "  bool stageTextSelected = false;\n",
   STATE_RUH_FIELD),
  ('text block methods',
   "    final next = [...textTimeCues]..removeAt(index);\n    textTimeCues = next;\n    notifyListeners();\n  }\n",
   STATE_CUE_METHODS),
 ],
 'media': [
  ('append clip', "  // PATCH_S125_SEQUENCE: S79's merge took exactly two clips, whole, butted\n",
   MEDIA_APPEND),
 ],
 'stage': [
  ('stage import', "import 'pro_transform.dart'; // PATCH_S180_TRANSFORM\n",
   "import 'pro_transform.dart'; // PATCH_S180_TRANSFORM\nimport '../services/ruh_touch.dart'; // " + MARK + "\n"),
  ('touch text -> ruh',
   "        } else {\n          state.selectStageText(liveSegment);\n        }\n      },\n      onScaleStart: (_) => gestureStartUserScale = state.textUserScale,\n",
   STAGE_TAP_NEW),
 ],
 'magic': [
  ('magic import', "import 'motion.dart';\n",
   "import 'motion.dart';\nimport 'gold_switch.dart'; // " + MARK + "\n"),
  ('ruh switch',
   "            _ghostButton('فاجئني', Icons.casino_outlined, () => _surprise(r)),\n          ]),\n",
   MAGIC_TOGGLE),
 ],
 'tl': [
  ('fields', "  /// Fewer lanes / shorter lanes while a tool panel is open.\n  final bool compact;\n", TL_FIELDS),
  ('ctor', "    required this.markers,\n    this.compact = false,\n  });\n", TL_CTOR),
  ('zoom api', "  void zoomBy(double factor) => _setPps(_pps * factor);\n", TL_ZOOM_API),
  ('lane heights',
   "      if (!c && s.textTimeCues.isNotEmpty)\n        const _LaneSpec('text', Icons.title, 26),\n      const _LaneSpec('ayah', Icons.menu_book_outlined, 36),\n",
   "      if (!c && s.textTimeCues.isNotEmpty)\n        const _LaneSpec('text', Icons.title, 32), // " + MARK + "\n      _LaneSpec('ayah', Icons.menu_book_outlined, c ? 36 : 44),\n"),
  ('ruler painter use',
   "          painter: _RulerPainter(\n            pps: _pps,\n            dur: _dur,\n            markers: List<double>.of(widget.markers),\n          ),\n",
   "          painter: _RulerPainter(\n            pps: _pps,\n            dur: _dur,\n            markers: List<double>.of(widget.markers),\n            scroll: _scroll, // " + MARK + "\n            viewW: _viewW,\n          ),\n"),
  ('audio lane selects main',
   "      'audio' => _waveLane(l.h, w, _vid, const Color(0xFF6FA8DC),\n          widget.state.muteAudio),\n",
   "      'audio' => _waveLane(l.h, w, _vid, const Color(0xFF6FA8DC),\n          widget.state.muteAudio,\n          main: true), // " + MARK + "\n"),
  ('video lane tap',
   "    final canTrim = !locked && !byAyah;\n    return GestureDetector(\n      behavior: HitTestBehavior.opaque,\n      onTapUp: (d) {\n        widget.onSelectSeg(-1);\n        _seekSec(d.localPosition.dx / _pps);\n      },\n",
   "    final canTrim = !locked && !byAyah;\n    return GestureDetector(\n      behavior: HitTestBehavior.opaque,\n      onTapUp: (d) {\n        widget.onSelectSeg(-1);\n        widget.onSelectMain?.call(true); // " + MARK + "\n        _seekSec(d.localPosition.dx / _pps);\n      },\n"),
  ('video lane border',
   "                color: const Color(0xFF1E4B3F),\n                borderRadius: BorderRadius.circular(6),\n                border: Border.all(color: const Color(0x55ECC875)),\n",
   "                color: const Color(0xFF1E4B3F),\n                borderRadius: BorderRadius.circular(6),\n                border: widget.selectedMain // " + MARK + "\n                    ? Border.all(color: AyatColors.goldBright, width: 2)\n                    : Border.all(color: const Color(0x55ECC875)),\n"),
  ('add media button', "          // dim whatever the export will cut away\n", TL_ADD_BUTTON),
  ('trim handle size', "      left: at * _pps - (isStart ? 0 : 14),\n      width: 14,\n",
   "      left: at * _pps - (isStart ? 0 : 22), // " + MARK + "\n      width: 22,\n"),
  ('wave lane signature',
   "  Widget _waveLane(double h, double w, _PeakSlot slot, Color color, bool dim,\n      {bool loop = false}) {\n",
   "  Widget _waveLane(double h, double w, _PeakSlot slot, Color color, bool dim,\n      {bool loop = false, bool main = false}) {\n"),
  ('wave lane tap',
   "        : math.min(dur, peaks.length / WaveformService.peaksPerSec);\n    return GestureDetector(\n      behavior: HitTestBehavior.opaque,\n      onTapUp: (d) {\n        widget.onSelectSeg(-1);\n",
   "        : math.min(dur, peaks.length / WaveformService.peaksPerSec);\n    return GestureDetector(\n      behavior: HitTestBehavior.opaque,\n      onTapUp: (d) {\n        widget.onSelectSeg(-1);\n        if (main) widget.onSelectMain?.call(true); // " + MARK + "\n"),
  ('wave painter use',
   "                  painter: _WavePainter(\n                    peaks: peaks,\n                    pps: _pps,\n                    loop: loop,\n                    color: color.withValues(alpha: dim ? 0.30 : 0.95),\n                  ),\n",
   "                  painter: _WavePainter(\n                    peaks: peaks,\n                    pps: _pps,\n                    loop: loop,\n                    color: color.withValues(alpha: dim ? 0.30 : 0.95),\n                    scroll: _scroll, // " + MARK + "\n                    viewW: _viewW,\n                  ),\n"),
 ],
 'home': [
  ('fields', "  int _selSeg = -1;\n  final List<double> _markers = [];\n", HOME_FIELDS),
  ('getters', "  bool get _hasSelSeg => _selSeg >= 0 && _selSeg < state.timeline.length;\n", HOME_GETTERS),
  ('timeline wiring',
   "          selectedSeg: _selSeg,\n          onSelectSeg: (i) => setState(() => _selSeg = i),\n          markers: _markers,\n          compact: compact,\n",
   HOME_TL_WIRING),
  ('bottom bar swap',
   "              key: ValueKey(_hasSelSeg),\n              child: _hasSelSeg ? _clipToolStrip() : _toolStrip(),\n",
   "              key: ValueKey(_hasAnySel), // " + MARK + "\n              child: _hasAnySel ? _clipToolStrip() : _toolStrip(),\n"),
  ('clip bar dispatch',
   "  Widget _clipToolStrip() {\n    final i = _selSeg;\n",
   "  Widget _clipToolStrip() {\n    // " + MARK + ": text blocks and the main clip have their own bars\n    if (!_hasSelSeg) return _clipBar(_hasSelCue ? _cueItems() : _mainItems());\n    final i = _selSeg;\n"),
  ('ayah clip extra actions',
   "      (Icons.content_cut, 'تقسيم', _splitAtPlayhead, false),\n      (Icons.tune, 'التوقيت', () => _editSegmentTiming(i), false),\n",
   "      (Icons.content_cut, 'تقسيم', _splitAtPlayhead, false),\n      ..._segExtraItems(i), // " + MARK + "\n      (Icons.tune, 'التوقيت', () => _editSegmentTiming(i), false),\n"),
  ('split text too',
   "    final seg = state.segmentAt(t);\n    if (seg == null) {\n      _toast('ضع المؤشر داخل آية لتقسيمها');\n      return;\n    }\n",
   SPLIT_NEW),
  ('new methods', "  // PATCH_S175_CAPCUT: fullscreen preview (the player's corner button).\n", HOME_METHODS + "  // PATCH_S175_CAPCUT: fullscreen preview (the player's corner button).\n"),
  ('ayat fold open',
   "        if (_partialSourceAyah != null) _partialAyahSection(),\n",
   "        // " + MARK + ": everything below is folded away; nothing was removed\n        _advancedFold(Column(\n          crossAxisAlignment: CrossAxisAlignment.stretch,\n          children: [\n        if (_partialSourceAyah != null) _partialAyahSection(),\n"),
  ('ayat fold close',
   "        )),\n      ],\n    );\n  }\n\n  // ---------------------------------------------------------- tab: خلفيات\n",
   "        )),\n          ],\n        )), // " + MARK + ": closes the advanced fold\n      ],\n    );\n  }\n\n  // ---------------------------------------------------------- tab: خلفيات\n"),
 ],
}

# 1) every anchor must match exactly once (nothing is written otherwise)
bad = []
for key, eds in edits.items():
    for label, old, _ in eds:
        n = T[key].count(old)
        if n != 1:
            bad.append('%s: %s (found %d)' % (P[key], label, n))
for start, end, label in [
    ('class _RulerPainter extends CustomPainter {', None, 'painters'),
    ('  Widget _textLane(double h, double w) {', '  Widget _ayahLane(double h, double w) {', 'text lane'),
    ('  Widget _segClip(int i, double h, bool locked) {', '  void _moveEdge(int i, bool isStart) {', 'ayah clips'),
]:
    if T['tl'].count(start) != 1 or (end and T['tl'].count(end) != 1):
        bad.append('%s: %s anchors' % (P['tl'], label))
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

# 2) apply
out = dict(T)
for key, eds in edits.items():
    for label, old, new in eds:
        out[key] = out[key].replace(old, new, 1)
        print('  PATCHED', P[key].split('/')[-1], '-', label)
out['tl'] = slice_replace(out['tl'], '  Widget _textLane(double h, double w) {',
                          '  Widget _ayahLane(double h, double w) {', TL_TEXT_LANE, 'text lane')
out['tl'] = slice_replace(out['tl'], '  Widget _segClip(int i, double h, bool locked) {',
                          '  void _moveEdge(int i, bool isStart) {', TL_SEG_BLOCK, 'ayah clips')
out['tl'] = slice_replace(out['tl'], 'class _RulerPainter extends CustomPainter {', None,
                          TL_PAINTERS, 'painters')
print('  PATCHED pro_timeline.dart - text blocks, ayah blocks, painters')

# 3) "music" -> neutral names (UI text, icons, i18n, identifiers, tests)
for key in ('home', 'state', 'tl', 'export', 'settings', 'panels', 'i18n', 'test', 'doc'):
    if key in out:
        out[key] = rename_music(out[key])
legacy = [
    ("read<double>('ambienceBedVolume') ?? state.ambienceBedVolume",
     "read<double>('ambienceBedVolume') ??\n              read<double>('musicBedVolume') ?? // legacy saved name\n              state.ambienceBedVolume"),
    ("read<bool>('ambienceBedFade') ?? state.ambienceBedFade",
     "read<bool>('ambienceBedFade') ??\n          read<bool>('musicBedFade') ?? // legacy saved name\n          state.ambienceBedFade"),
    ("read<String>('ambienceBedPath');",
     "read<String>('ambienceBedPath') ??\n          read<String>('musicBedPath'); // legacy saved name"),
]
for old, new in legacy:
    if out['settings'].count(old) != 1:
        sys.exit('Anchor check failed, nothing written: settings legacy read (%s)' % old)
    out['settings'] = out['settings'].replace(old, new, 1)
print('  RENAMED music -> ambience (UI, icons, i18n, code, tests); old saved settings still load')

# 4) write
for key in out:
    if out[key] != T[key]:
        open(P[key], 'w', encoding='utf-8').write(out[key])
for path, (body, _) in REPLACE.items():
    open(path, 'w', encoding='utf-8').write(body)
    print('  REWROTE ', path)
for path, body in NEW.items():
    open(path, 'w', encoding='utf-8').write(body)
    print('  WROTE   ', path)

left = []
for key in ('home', 'state', 'tl', 'export', 'settings', 'panels', 'i18n', 'test', 'doc'):
    for n, line in enumerate(out[key].splitlines(), 1):
        if re.search('music|موسيق', line, re.I) and 'PATCH_S127_MUSIC_BED' not in line:
            left.append('%s:%d: %s' % (P[key], n, line.strip()[:100]))
if left:
    print('  NOTE: words still containing "music" (comments / legacy saved names only):')
    for l in left:
        print('     ', l)
print('S181 applied. Next: git add -A && git commit -m "S181: touchable clips, big-file speed, simple ayat tab, ruh on touch, add media, music renamed" && git push')
