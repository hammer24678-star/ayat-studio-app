// PATCH_S42_SYNC_QOL
// Visual map of the detected auto-sync timeline: one slim bar spanning the
// whole clip, a gold block per detected ayah (brightness follows detection
// confidence, inferred ayat get an outlined/dimmer look), dark gaps where
// nothing was detected, and a live playhead. Tap or drag anywhere to seek —
// this makes reviewing a long recitation dramatically faster than scrubbing
// the plain seek bar blind.
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';

class TimelineRibbon extends StatelessWidget {
  final StudioState state;
  final VideoPlayerController controller;
  const TimelineRibbon({
    super.key,
    required this.state,
    required this.controller,
  });

  void _seekToDx(BuildContext context, double dx) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width <= 0) return;
    final durMs = controller.value.duration.inMilliseconds;
    if (durMs <= 0) return;
    final frac = (dx / box.size.width).clamp(0.0, 1.0);
    controller.seekTo(Duration(milliseconds: (frac * durMs).round()));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, v, _) {
        final durSec = v.duration.inMilliseconds / 1000.0;
        if (durSec <= 0 || state.timeline.isEmpty) {
          return const SizedBox.shrink();
        }
        final posSec = v.position.inMilliseconds / 1000.0;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _seekToDx(context, d.localPosition.dx),
          onHorizontalDragUpdate: (d) =>
              _seekToDx(context, d.localPosition.dx),
          child: SizedBox(
            height: 22,
            width: double.infinity,
            child: CustomPaint(
              painter: _RibbonPainter(
                timeline: state.timeline,
                durationSec: durSec,
                playheadSec: posSec,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RibbonPainter extends CustomPainter {
  final List<TimelineSegment> timeline;
  final double durationSec;
  final double playheadSec;
  _RibbonPainter({
    required this.timeline,
    required this.durationSec,
    required this.playheadSec,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 4, size.width, size.height - 8),
        const Radius.circular(6));
    canvas.drawRRect(track, Paint()..color = AyatColors.surface3);
    canvas.save();
    canvas.clipRRect(track);

    for (final s in timeline) {
      final l = (s.start / durationSec * size.width).clamp(0.0, size.width);
      final r = (s.end / durationSec * size.width).clamp(0.0, size.width);
      if (r - l < 1) continue;
      final active = playheadSec >= s.start && playheadSec < s.end;
      final rect = Rect.fromLTRB(l + 0.5, 4, r - 0.5, size.height - 4);
      if (s.inferred) {
        // inferred (never acoustically matched) — hollow look for review
        canvas.drawRect(
            rect,
            Paint()
              ..color = AyatColors.gold.withValues(alpha: active ? 0.30 : 0.15));
        canvas.drawRect(
            rect.deflate(0.75),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1
              ..color = AyatColors.goldDim);
      } else {
        // brightness tracks detection confidence (0.3..1 → visible range)
        final alpha =
            (0.35 + 0.55 * s.confidence.clamp(0.0, 1.0)).clamp(0.0, 1.0);
        canvas.drawRect(
            rect,
            Paint()
              ..color = (active ? AyatColors.goldBright : AyatColors.gold)
                  .withValues(alpha: alpha));
      }
    }
    canvas.restore();

    // playhead
    final x = (playheadSec / durationSec * size.width).clamp(0.0, size.width);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 1, 0, 2, size.height), const Radius.circular(1)),
      Paint()..color = AyatColors.parchment,
    );
  }

  // Segments are nudged/deleted IN PLACE by the timeline editor, so no cheap
  // equality can prove the paint is stale — and this bar is 22px tall, so
  // just repaint whenever the controller or the state notifies.
  @override
  bool shouldRepaint(_RibbonPainter old) => true;
}
