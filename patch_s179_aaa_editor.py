#!/usr/bin/env python3
"""
patch_s179_aaa_editor.py - Ayat Studio S179 (run from repo root, after S178)

Polish + editor helpers on top of the S174 timeline:
  Timeline   video filmstrip (thumbnails), haptic tick when scrubbing into a new
             ayah, time bubble while scrubbing, snap on/off magnet
  Preview    "now playing" surah:ayah chip, guides overlay (thirds, safe
             frames, centre) with a toggle, next to fullscreen
  Transport  tap the timecode to type a time and jump; long-press previous /
             next = previous / next marker

Idempotent; every anchor is verified before anything is written.
"""
import os, sys

MARK = 'PATCH_S179_AAA'
HOME = 'lib/screens/home_screen.dart'
TL = 'lib/widgets/pro_timeline.dart'

if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
for p in (HOME, TL):
    if not os.path.exists(p):
        sys.exit('missing ' + p)
rd = lambda p: open(p, encoding='utf-8').read()
home, tl = rd(HOME), rd(TL)
if MARK in home or MARK in tl:
    print('  OK      already applied'); sys.exit(0)
if 'PATCH_S175_CAPCUT' not in home:
    sys.exit('S175 not applied yet.')

NEW = {
    'lib/services/thumb_service.dart': r"""// PATCH_S179_AAA
// Video thumbnails for the timeline's video lane (the filmstrip every pro
// editor shows). One ffmpeg pass writes at most ~40 small JPEG frames, one
// every `step` seconds; cached per path for the session. null = could not
// decode, and the lane just keeps its plain bar.
import 'dart:io';
import 'dart:math' as math;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

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
    final job = _compute(path, durSec);
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
      final session = await FFmpegKit.execute(
          '-y -i "$path" -an -vf "fps=1/$stepI,scale=-2:72" -q:v 7 '
          '-frames:v 60 "${dir.path}/t_%03d.jpg"');
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
""",
    'lib/widgets/pro_extras.dart': r"""// PATCH_S179_AAA
// Editor helpers that sit on top of the preview and transport:
//   ProGuidesOverlay  - rule-of-thirds, action/title safe frames, centre mark
//   ProNowPlayingChip - which surah:ayah is under the playhead right now
//   showGoToTimeDialog- type a timecode and jump there (Premiere's timecode box)
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';

class ProGuidesOverlay extends StatelessWidget {
  /// Frame width / height; the guides are drawn on the same contained rect
  /// the preview occupies.
  final double aspect;
  const ProGuidesOverlay({super.key, required this.aspect});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      var w = c.maxWidth;
      var h = w / aspect;
      if (h > c.maxHeight) {
        h = c.maxHeight;
        w = h * aspect;
      }
      return Center(
        child: SizedBox(
          width: w,
          height: h,
          child: CustomPaint(painter: _GuidesPainter()),
        ),
      );
    });
  }
}

class _GuidesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final thirds = Paint()
      ..color = const Color(0x47FFFFFF)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      canvas.drawLine(Offset(s.width * i / 3, 0),
          Offset(s.width * i / 3, s.height), thirds);
      canvas.drawLine(Offset(0, s.height * i / 3),
          Offset(s.width, s.height * i / 3), thirds);
    }
    final action = Paint()
      ..color = const Color(0x33FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final title = Paint()
      ..color = const Color(0x88ECC875)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(
        Rect.fromLTWH(s.width * 0.05, s.height * 0.05, s.width * 0.9,
            s.height * 0.9),
        action);
    canvas.drawRect(
        Rect.fromLTWH(s.width * 0.1, s.height * 0.1, s.width * 0.8,
            s.height * 0.8),
        title);
    final cross = Paint()
      ..color = const Color(0x80FFFFFF)
      ..strokeWidth = 1;
    final cx = s.width / 2;
    final cy = s.height / 2;
    canvas.drawLine(Offset(cx - 8, cy), Offset(cx + 8, cy), cross);
    canvas.drawLine(Offset(cx, cy - 8), Offset(cx, cy + 8), cross);
  }

  @override
  bool shouldRepaint(_GuidesPainter old) => false;
}

class ProNowPlayingChip extends StatelessWidget {
  final StudioState state;
  final VideoPlayerController controller;
  const ProNowPlayingChip(
      {super.key, required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, v, _) {
          final seg = state.segmentAt(v.position.inMilliseconds / 1000.0);
          if (seg == null) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xB3050F0D),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0x55ECC875)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.menu_book_outlined,
                    size: 13, color: AyatColors.goldBright),
                const SizedBox(width: 5),
                Text(
                  '${seg.ayah.surah} · ${seg.ayah.num}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AyatColors.parchment),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

String _fmtTime(double s) {
  final m = s ~/ 60;
  final sec = s - m * 60;
  return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';
}

double? _parseTime(String raw) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var t = raw.trim();
  for (var i = 0; i < ar.length; i++) {
    t = t.replaceAll(ar[i], '$i');
  }
  if (t.isEmpty) return null;
  if (!t.contains(':')) return double.tryParse(t);
  var total = 0.0;
  for (final p in t.split(':')) {
    final v = double.tryParse(p);
    if (v == null) return null;
    total = total * 60 + v;
  }
  return total;
}

/// Returns the chosen time in seconds (clamped to 0..max), or null.
Future<double?> showGoToTimeDialog(
  BuildContext context, {
  required double current,
  required double max,
}) {
  final ctl = TextEditingController(text: _fmtTime(current));
  return showDialog<double>(
    context: context,
    builder: (ctx) {
      void submit() {
        final v = _parseTime(ctl.text);
        Navigator.pop(ctx, v == null ? null : v.clamp(0.0, max).toDouble());
      }

      return AlertDialog(
        title: const Text('الانتقال إلى وقت'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textDirection: TextDirection.ltr,
          decoration: const InputDecoration(hintText: 'مثال: 1:25.5 أو 85'),
          onSubmitted: (_) => submit(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: submit, child: const Text('انتقال')),
        ],
      );
    },
  );
}
""",
}

TL_METHODS = r"""  // PATCH_S179_AAA
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
"""

VIDEO_OLD = """            child: Container(
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
"""
VIDEO_NEW = """            child: Container(
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
"""

GUTTER_OLD = """                  SizedBox(
                    height: _rulerH,
                    child: InkWell(
                      onTap: fit,
                      child: const Center(
                        child: Icon(Icons.fit_screen_outlined,
                            size: 16, color: AyatColors.parchmentDim),
                      ),
                    ),
                  ),
"""
GUTTER_NEW = """                  SizedBox(
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
"""

RULER_SEEK_OLD = "  void _rulerSeek(double x) => _seekSec(x / _pps);\n"
RULER_SEEK_NEW = """  void _rulerSeek(double x) {
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
"""
RULER_GEST_OLD = """      onHorizontalDragStart: (d) => _rulerSeek(d.localPosition.dx),
      onHorizontalDragUpdate: (d) => _rulerSeek(d.localPosition.dx),
"""
RULER_GEST_NEW = """      onHorizontalDragStart: (d) {
        setState(() => _scrubbing = true);
        _lastScrubSeg = -2;
        _rulerSeek(d.localPosition.dx);
      },
      onHorizontalDragUpdate: (d) => _rulerSeek(d.localPosition.dx),
      onHorizontalDragEnd: (_) => setState(() => _scrubbing = false),
      onHorizontalDragCancel: () => setState(() => _scrubbing = false),
"""
PLAYHEAD_OLD = """            child: Stack(
              alignment: Alignment.topCenter,
              children: [
"""
PLAYHEAD_NEW = """            child: Stack(
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
"""

HOME_METHODS = r"""  // PATCH_S179_AAA: type a time and jump (Premiere's timecode box).
  Future<void> _goToTime() async {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    final dur = c.value.duration.inMilliseconds / 1000.0;
    final t = await showGoToTimeDialog(context,
        current: c.value.position.inMilliseconds / 1000.0, max: dur);
    if (t == null || !mounted) return;
    await c.seekTo(Duration(milliseconds: (t * 1000).round()));
  }

  /// Long-press on previous / next in the transport.
  void _jumpMarker(int dir) {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    if (_markers.isEmpty) {
      _toast('لا توجد علامات بعد');
      return;
    }
    final t = c.value.position.inMilliseconds / 1000.0;
    double? target;
    if (dir > 0) {
      for (final m in _markers) {
        if (m > t + 0.05) {
          target = m;
          break;
        }
      }
    } else {
      for (final m in _markers.reversed) {
        if (m < t - 0.05) {
          target = m;
          break;
        }
      }
    }
    if (target == null) {
      _toast(dir > 0 ? 'لا علامة بعد المؤشر' : 'لا علامة قبل المؤشر');
      return;
    }
    HapticFeedback.selectionClick();
    c.seekTo(Duration(milliseconds: (target * 1000).round()));
  }

  double _frameAspect() {
    final fs = state.frameSize;
    return fs.$1 / fs.$2;
  }

  Widget _guidesButton() {
    return Material(
      color: const Color(0x99050F0D),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => setState(() => _guides = !_guides),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(Icons.grid_3x3,
              size: 20,
              color: _guides ? AyatColors.goldBright : AyatColors.parchment),
        ),
      ),
    );
  }

"""

PREVIEW_OLD = """                  PositionedDirectional(
                    end: 6,
                    bottom: 6,
                    child: _fullscreenButton(), // PATCH_S175_CAPCUT
                  ),
"""
PREVIEW_NEW = """                  if (_video != null && _video!.value.isInitialized) // PATCH_S179_AAA
                    PositionedDirectional(
                      start: 6,
                      top: 6,
                      child:
                          ProNowPlayingChip(state: state, controller: _video!),
                    ),
                  if (_guides)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ProGuidesOverlay(aspect: _frameAspect()),
                      ),
                    ),
                  PositionedDirectional(
                    end: 6,
                    bottom: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _guidesButton(),
                        const SizedBox(width: 6),
                        _fullscreenButton(), // PATCH_S175_CAPCUT
                      ],
                    ),
                  ),
"""

TC_A_OLD = """                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmtSecFine(posS),"""
TC_A_NEW = """                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _goToTime, // PATCH_S179_AAA
                    child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_fmtSecFine(posS),"""
TC_B_OLD = """                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
                _tIcon(Icons.skip_previous_rounded,
                    () => _seekToAdjacentAyah(-1), 'الآية السابقة'),
"""
TC_B_NEW = """                              fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                  ),
                ),
                GestureDetector(
                  onLongPress: () => _jumpMarker(-1), // PATCH_S179_AAA
                  child: IconButton(
                    onPressed: () => _seekToAdjacentAyah(-1),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 40),
                    icon: const Icon(Icons.skip_previous_rounded,
                        size: 20, color: AyatColors.parchmentDim),
                  ),
                ),
"""
NEXT_OLD = """                _tIcon(Icons.skip_next_rounded, () => _seekToAdjacentAyah(1),
                    'الآية التالية'),
"""
NEXT_NEW = """                GestureDetector(
                  onLongPress: () => _jumpMarker(1), // PATCH_S179_AAA
                  child: IconButton(
                    onPressed: () => _seekToAdjacentAyah(1),
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 40),
                    icon: const Icon(Icons.skip_next_rounded,
                        size: 20, color: AyatColors.parchmentDim),
                  ),
                ),
"""

files = [
 (HOME, home, [
  ('home import', "import '../widgets/pro_capcut.dart'; // PATCH_S175_CAPCUT\n",
   "import '../widgets/pro_capcut.dart'; // PATCH_S175_CAPCUT\nimport '../widgets/pro_extras.dart'; // " + MARK + "\n"),
  ('guides flag', "  final List<double> _markers = [];\n",
   "  final List<double> _markers = [];\n  bool _guides = false; // " + MARK + "\n"),
  ('preview overlays', PREVIEW_OLD, PREVIEW_NEW),
  ('timecode tap A', TC_A_OLD, TC_A_NEW),
  ('timecode tap B + prev', TC_B_OLD, TC_B_NEW),
  ('next', NEXT_OLD, NEXT_NEW),
  ('home methods', "  Widget _toolPanel(double h) {\n", HOME_METHODS + "  Widget _toolPanel(double h) {\n"),
 ]),
 (TL, tl, [
  ('tl imports 1', "import 'dart:math' as math;\n", "import 'dart:io';\nimport 'dart:math' as math;\n"),
  ('tl imports 2', "import 'package:flutter/material.dart';\n",
   "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart' show HapticFeedback; // " + MARK + "\n"),
  ('tl imports 3', "import '../services/waveform_service.dart';\n",
   "import '../services/thumb_service.dart';\nimport '../services/waveform_service.dart';\n"),
  ('gutter width', "  static const double _gutter = 40;\n", "  static const double _gutter = 48;\n"),
  ('tl fields', "  final _PeakSlot _mus = _PeakSlot();\n",
   "  final _PeakSlot _mus = _PeakSlot();\n  // " + MARK + "\n  bool _snap = true;\n  bool _scrubbing = false;\n  int _lastScrubSeg = -2;\n  String? _thumbPath;\n  ThumbStrip? _thumbs;\n"),
  ('tl thumbs methods', "  double _pinchDist() {\n", TL_METHODS),
  ('tl ensure call', "    _ensure(_mus, s.musicBedPath);\n", "    _ensure(_mus, s.musicBedPath);\n    _ensureThumbs();\n"),
  ('tl gutter buttons', GUTTER_OLD, GUTTER_NEW),
  ('tl ruler seek', RULER_SEEK_OLD, RULER_SEEK_NEW),
  ('tl ruler gestures', RULER_GEST_OLD, RULER_GEST_NEW),
  ('tl playhead bubble', PLAYHEAD_OLD, PLAYHEAD_NEW),
  ('tl snap', "    final tol = 8 / _pps;\n", "    final tol = _snap ? 8 / _pps : -1.0;\n"),
  ('tl video lane', VIDEO_OLD, VIDEO_NEW),
 ]),
]

bad = []
for path, text, eds in files:
    for label, old, _ in eds:
        n = text.count(old)
        if n != 1:
            bad.append('%s: %s (found %d)' % (path, label, n))
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for path, text, eds in files:
    for label, old, new in eds:
        text = text.replace(old, new, 1)
        print('  PATCHED', path.split('/')[-1], '-', label)
    open(path, 'w', encoding='utf-8').write(text)
for path, body in NEW.items():
    open(path, 'w', encoding='utf-8').write(body)
    print('  WROTE  ', path)
print('S179 applied. Next: git add -A && git commit -m "S179: AAA editor polish" && git push')
