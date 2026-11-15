// PATCH_S38_SMOOTH_EDITING
// Play/pause + seek bar. Differences from the old inline version:
//  * the thumb glides (frame-rate position from PlayClock, not 500 ms steps);
//  * scrubbing no longer fights the player: the thumb follows the finger,
//    playback pauses while dragging, seeks are throttled, and the clip
//    resumes from the release point if it was playing;
//  * only this small widget repaints each frame, not the whole studio.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:video_player/video_player.dart';

import '../services/play_clock.dart';
import '../theme/ayat_theme.dart';

class TransportBar extends StatefulWidget {
  final VideoPlayerController controller;
  final PlayClock clock;
  final VoidCallback? onPrevAyah;
  final VoidCallback? onNextAyah;
  const TransportBar({
    super.key,
    required this.controller,
    required this.clock,
    this.onPrevAyah,
    this.onNextAyah,
  });

  @override
  State<TransportBar> createState() => _TransportBarState();
}

class _TransportBarState extends State<TransportBar>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) {
    if (mounted && !_scrubbing) setState(() {});
  });
  bool _scrubbing = false;
  bool _wasPlaying = false;
  double _scrubMs = 0;
  int _lastSeekAt = 0;
  bool _seekInFlight = false;
  final Stopwatch _sw = Stopwatch()..start();

  VideoPlayerController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onValue);
    _syncTicker();
  }

  @override
  void didUpdateWidget(TransportBar old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onValue);
      widget.controller.addListener(_onValue);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onValue);
    _ticker.dispose();
    super.dispose();
  }

  void _onValue() {
    _syncTicker();
    if (mounted && !_scrubbing) setState(() {});
  }

  void _syncTicker() {
    final playing = _c.value.isPlaying && !_scrubbing;
    if (playing && !_ticker.isActive) {
      _ticker.start();
    } else if (!playing && _ticker.isActive) {
      _ticker.stop();
    }
  }

  static String _fmt(double s) {
    final total = s.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  Future<void> _seek(double ms) async {
    _seekInFlight = true;
    try {
      await _c.seekTo(Duration(milliseconds: ms.round()));
    } finally {
      _seekInFlight = false;
    }
  }

  void _onStart(double _) {
    _wasPlaying = _c.value.isPlaying;
    if (_wasPlaying) _c.pause();
    setState(() {
      _scrubbing = true;
      _scrubMs = widget.clock.seconds * 1000;
    });
    _syncTicker();
  }

  void _onChanged(double x) {
    setState(() => _scrubMs = x);
    // throttle: at most one seek per ~70 ms, and never stack them
    final now = _sw.elapsedMilliseconds;
    if (!_seekInFlight && now - _lastSeekAt >= 70) {
      _lastSeekAt = now;
      _seek(x);
    }
  }

  Future<void> _onEnd(double x) async {
    await _seek(x);
    if (!mounted) return;
    setState(() => _scrubbing = false);
    if (_wasPlaying) await _c.play();
    _syncTicker();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    final durMs = max(1, v.duration.inMilliseconds).toDouble();
    final posMs = _scrubbing
        ? _scrubMs
        : (widget.clock.seconds * 1000).clamp(0.0, durMs);
    return RepaintBoundary(
      child: Row(
        children: [
          if (widget.onPrevAyah != null)
            IconButton(
              onPressed: widget.onPrevAyah,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
              icon: const Icon(Icons.skip_previous_outlined,
                  color: AyatColors.parchmentDim, size: 20),
              tooltip: 'الآية السابقة',
            ),
          IconButton(
            onPressed: () => v.isPlaying ? _c.pause() : _c.play(),
            icon: Icon(
              v.isPlaying
                  ? Icons.pause_circle_outline
                  : Icons.play_circle_outline,
              color: AyatColors.goldBright,
            ),
            tooltip: 'تشغيل/إيقاف',
          ),
          if (widget.onNextAyah != null)
            IconButton(
              onPressed: widget.onNextAyah,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 40),
              icon: const Icon(Icons.skip_next_outlined,
                  color: AyatColors.parchmentDim, size: 20),
              tooltip: 'الآية التالية',
            ),
          Text(_fmt(posMs / 1000),
              style: const TextStyle(
                  fontSize: 11, color: AyatColors.parchmentDim)),
          Expanded(
            child: Slider(
              value: posMs.toDouble().clamp(0.0, durMs),
              max: durMs,
              onChangeStart: _onStart,
              onChanged: _onChanged,
              onChangeEnd: _onEnd,
            ),
          ),
          Text(_fmt(durMs / 1000),
              style: const TextStyle(
                  fontSize: 11, color: AyatColors.parchmentDim)),
        ],
      ),
    );
  }
}
