// PATCH_S179_AAA
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
  final tenths = (s * 10).round(); // PATCH_S197_DETAILS
  final m = tenths ~/ 600;
  final sec = (tenths % 600) / 10;
  return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';
}

double? _parseTime(String raw) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  var t = raw.trim();
  for (var i = 0; i < ar.length; i++) {
    t = t.replaceAll(ar[i], '$i');
  }
  t = t.replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.'); // PATCH_S197_DETAILS
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
  ctl.selection = TextSelection(baseOffset: 0, extentOffset: ctl.text.length); // PATCH_S197_DETAILS
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
          keyboardType: TextInputType.datetime, // PATCH_S197_DETAILS
          textInputAction: TextInputAction.go,
          autocorrect: false,
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
