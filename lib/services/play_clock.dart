// PATCH_S38_SMOOTH_EDITING
// video_player only refreshes `value.position` about every 500 ms, so
// anything driven directly from it (the karaoke word lighting, the seek bar
// thumb) advances in visible steps. PlayClock interpolates between those
// updates with a monotonic stopwatch so consumers get a smooth, frame-rate
// position while playing, and the exact reported position when paused or
// after a seek.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

class PlayClock {
  PlayClock(this.controller) {
    _wasPlaying = controller.value.isPlaying;
    _lastPosMs = controller.value.position.inMilliseconds;
    controller.addListener(_onValue);
  }

  final VideoPlayerController controller;
  final Stopwatch _sw = Stopwatch()..start();
  int _lastPosMs = -1;
  int _stampMs = 0;
  bool _wasPlaying = false;
  double _lastShown = -1;

  /// The plugin polls roughly every 500 ms; never extrapolate further than
  /// this past the last real sample.
  static const int _maxExtrapolationMs = 700;

  void _onValue() {
    final v = controller.value;
    final p = v.position.inMilliseconds;
    if (p != _lastPosMs || v.isPlaying != _wasPlaying) {
      _lastPosMs = p;
      _stampMs = _sw.elapsedMilliseconds;
      _wasPlaying = v.isPlaying;
    }
  }

  /// Best estimate of the current playback position, in seconds.
  double get seconds {
    final v = controller.value;
    final baseMs = v.position.inMilliseconds;
    if (!v.isInitialized || !v.isPlaying) {
      _lastShown = baseMs / 1000.0;
      return _lastShown;
    }
    var extra = (_sw.elapsedMilliseconds - _stampMs) * v.playbackSpeed;
    if (extra < 0) extra = 0;
    if (extra > _maxExtrapolationMs) extra = _maxExtrapolationMs.toDouble();
    var ms = baseMs + extra;
    final durMs = v.duration.inMilliseconds;
    if (durMs > 0 && ms > durMs) ms = durMs.toDouble();
    var est = ms / 1000.0;
    // A fresh real sample can land slightly behind our estimate; hold the
    // value instead of stepping backwards (but accept real seeks/loops).
    if (_lastShown >= 0 && est < _lastShown && _lastShown - est < 0.25) {
      est = _lastShown;
    }
    _lastShown = est;
    return est;
  }

  void dispose() => controller.removeListener(_onValue);
}

/// Rebuilds [builder] every frame while the video plays (and once on every
/// controller change otherwise), handing it the interpolated position. Wrap
/// only the small piece that needs to glide (seek thumb, playhead).
class ClockBuilder extends StatefulWidget {
  final VideoPlayerController controller;
  final PlayClock clock;
  final Widget Function(BuildContext context, double seconds) builder;
  const ClockBuilder({
    super.key,
    required this.controller,
    required this.clock,
    required this.builder,
  });

  @override
  State<ClockBuilder> createState() => _ClockBuilderState();
}

class _ClockBuilderState extends State<ClockBuilder>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {
    if (mounted) setState(() {});
  });

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onValue);
    _sync();
  }

  @override
  void didUpdateWidget(ClockBuilder old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onValue);
      widget.controller.addListener(_onValue);
      _sync();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onValue);
    _ticker.dispose();
    super.dispose();
  }

  void _sync() {
    final playing = widget.controller.value.isPlaying;
    if (playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onValue() {
    _sync();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(child: widget.builder(context, widget.clock.seconds));
}
