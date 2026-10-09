// PATCH_S194_CUT_FX
// Live preview of the everyday looks (see services/video_fx.dart). Wraps the
// whole stage: colour looks tint it, fades / flash / bars are drawn over it,
// shake and pulse move it.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../models/studio_state.dart';
import '../services/video_fx.dart';

class VideoFxLayer extends StatefulWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  final Widget child;
  const VideoFxLayer({
    super.key,
    required this.state,
    required this.controller,
    required this.child,
  });

  @override
  State<VideoFxLayer> createState() => _VideoFxLayerState();
}

class _VideoFxLayerState extends State<VideoFxLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _tick =
      AnimationController(vsync: this, duration: const Duration(seconds: 60));

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  bool _moves(VideoFx f) => f == VideoFx.shake || f == VideoFx.pulse;

  @override
  Widget build(BuildContext context) {
    final fx = widget.state.videoFx;
    if (fx == VideoFx.none) {
      if (_tick.isAnimating) _tick.stop();
      return widget.child;
    }
    final m = videoFxMatrix(fx);
    if (m != null) {
      if (_tick.isAnimating) _tick.stop();
      return ColorFiltered(
          colorFilter: ColorFilter.matrix(m), child: widget.child);
    }
    if (fx == VideoFx.bars) {
      return Stack(fit: StackFit.passthrough, children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: Column(children: [
              Expanded(flex: 12, child: Container(color: Colors.black)),
              const Spacer(flex: 76),
              Expanded(flex: 12, child: Container(color: Colors.black)),
            ]),
          ),
        ),
      ]);
    }
    if (_moves(fx)) {
      if (!_tick.isAnimating) _tick.repeat();
      return AnimatedBuilder(
        animation: _tick,
        child: widget.child,
        builder: (context, child) {
          final t = _tick.value * 60.0;
          if (fx == VideoFx.shake) {
            return ClipRect(
              child: Transform.scale(
                scale: 1.06,
                child: FractionalTranslation(
                  translation:
                      Offset(math.sin(t * 40) * 0.027, math.cos(t * 33) * 0.027),
                  child: child,
                ),
              ),
            );
          }
          return ClipRect(
            child: Transform.scale(
                scale: 1 + 0.05 * math.sin(t * 3).abs(), child: child),
          );
        },
      );
    }
    // fades / flash follow the playhead of the main clip
    if (_tick.isAnimating) _tick.stop();
    final c = widget.controller;
    if (c == null) return widget.child;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      child: widget.child,
      builder: (context, v, child) {
        final s = widget.state;
        final dur = v.duration.inMilliseconds / 1000.0;
        final start = s.trimManualStart;
        final end = s.trimManualEnd < 0 ? dur : math.min(s.trimManualEnd, dur);
        final len = math.max(0.1, end - start);
        final t = v.position.inMilliseconds / 1000.0 - start;
        final fadeLen = (len / 3).clamp(0.1, kVideoFxFade).toDouble();
        var black = 0.0;
        var white = 0.0;
        if (fx == VideoFx.fadeIn || fx == VideoFx.fadeBoth) {
          black = math.max(black, 1 - (t / fadeLen).clamp(0.0, 1.0));
        }
        if (fx == VideoFx.fadeOut || fx == VideoFx.fadeBoth) {
          black = math.max(black, ((t - (len - fadeLen)) / fadeLen).clamp(0.0, 1.0));
        }
        if (fx == VideoFx.flash) {
          white = 1 - (t / kVideoFxFlash).clamp(0.0, 1.0);
        }
        return Stack(fit: StackFit.passthrough, children: [
          child!,
          if (black > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                    color: Colors.black.withValues(alpha: black.toDouble())),
              ),
            ),
          if (white > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                    color: Colors.white.withValues(alpha: white.toDouble())),
              ),
            ),
        ]);
      },
    );
  }
}
