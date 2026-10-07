// PATCH_S180_TRANSFORM
// Transform page («التحويل») + the live preview layer.
//   VideoXformLayer  - wraps the preview video: scale / move / rotate / fade,
//                      animated smoothly between keyframes while playing.
//   ProTransformPage - sliders, keyframe buttons, camera moves.
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:video_player/video_player.dart';

import '../models/studio_state.dart';
import '../models/video_transform.dart';
import '../theme/ayat_theme.dart';

// ------------------------------------------------------------ preview layer

class VideoXformLayer extends StatefulWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  final Widget child;
  const VideoXformLayer({
    super.key,
    required this.state,
    required this.controller,
    required this.child,
  });

  @override
  State<VideoXformLayer> createState() => _VideoXformLayerState();
}

class _VideoXformLayerState extends State<VideoXformLayer>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _sw = Stopwatch()..start();
  double _lastPos = -1;
  int _lastAtUs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  /// The player only reports its position a few times a second; between two
  /// reports the time is extrapolated so keyframe motion looks smooth.
  double _now() {
    final c = widget.controller;
    if (c == null) return 0;
    final v = c.value;
    final p = v.position.inMicroseconds / 1000000.0;
    if (p != _lastPos) {
      _lastPos = p;
      _lastAtUs = _sw.elapsedMicroseconds;
    }
    if (!v.isPlaying) return p;
    final el = (_sw.elapsedMicroseconds - _lastAtUs) / 1000000.0 * v.playbackSpeed;
    return p + (el < 0 ? 0.0 : (el > 0.6 ? 0.6 : el));
  }

  Widget _at(double t) {
    final v = widget.state.videoTransformAt(t);
    return Opacity(
      opacity: v.opacity.clamp(0.0, 1.0).toDouble(),
      child: FractionalTranslation(
        translation: Offset(v.x, v.y),
        child: Transform.rotate(
          angle: v.rot * 3.141592653589793 / 180.0,
          child: Transform.scale(scale: v.scale, child: widget.child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    if (!st.hasVideoTransform) {
      if (_ticker.isActive) _ticker.stop();
      return widget.child;
    }
    final c = widget.controller;
    final animating =
        st.videoKeys.length >= 2 && c != null && c.value.isPlaying;
    if (animating && !_ticker.isActive) _ticker.start();
    if (!animating && _ticker.isActive) _ticker.stop();
    if (c == null) return _at(0);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (context, _, __) => _at(_now()),
    );
  }
}

// ------------------------------------------------------------------- page

class ProTransformPage extends StatelessWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  const ProTransformPage({super.key, required this.state, required this.controller});

  double _t() =>
      controller == null ? 0.0 : controller!.value.position.inMilliseconds / 1000.0;

  Widget _title(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
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

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null || !state.hasVideo) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text('ارفع فيديو أولًا ليظهر التحويل',
              style: TextStyle(color: AyatColors.parchmentDim)),
        ),
      );
    }
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: c,
        builder: (context, _, __) {
          final t = _t();
          final v = state.videoTransformAt(t);
          final keyed = state.videoKeys.isNotEmpty;
          final onKey = state.hasKeyNear(t);
          void setScale(double s) => keyed
              ? state.setKeyAt(t, scale: s)
              : state.update(() => state.videoScale = s);
          void setX(double x) => keyed
              ? state.setKeyAt(t, x: x)
              : state.update(() => state.videoPosX = x);
          void setY(double y) => keyed
              ? state.setKeyAt(t, y: y)
              : state.update(() => state.videoPosY = y);
          void setRot(double r) => keyed
              ? state.setKeyAt(t, rot: r)
              : state.update(() => state.videoRot = r);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        state.setKeyAt(t);
                      },
                      icon: const Icon(Icons.diamond_outlined, size: 18),
                      label: Text(onKey ? 'تحديث الإطار' : 'إطار مفتاحي'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: onKey ? () => state.removeKeyNear(t) : null,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('حذف'),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  keyed
                      ? 'الإطارات: ${state.videoKeys.length} — حرّك المؤشر ثم عدّل لتُضاف إطارات جديدة'
                      : 'اسحب على المعاينة أو استعمل المنزلقات. أضف إطارين مفتاحيين أو أكثر للحركة.',
                  style: const TextStyle(
                      fontSize: 11, color: AyatColors.parchmentDim),
                ),
              ),
              _title(context, 'التحويل'),
              _slider(
                label: 'الحجم',
                shown: '${(v.scale * 100).round()}%',
                value: v.scale,
                min: 0.3,
                max: 2.0,
                onChanged: setScale,
              ),
              _slider(
                label: 'أفقي',
                shown: '${(v.x * 100).round()}%',
                value: v.x,
                min: -0.9,
                max: 0.9,
                onChanged: setX,
              ),
              _slider(
                label: 'رأسي',
                shown: '${(v.y * 100).round()}%',
                value: v.y,
                min: -0.9,
                max: 0.9,
                onChanged: setY,
              ),
              _slider(
                label: 'الدوران',
                shown: '${v.rot.round()}°',
                value: v.rot,
                min: -180,
                max: 180,
                onChanged: setRot,
              ),
              _slider(
                label: 'الشفافية',
                shown: '${(state.videoOpacity * 100).round()}%',
                value: state.videoOpacity,
                min: 0.0,
                max: 1.0,
                onChanged: (o) => state.update(() => state.videoOpacity = o),
              ),
              _title(context, 'حركات الكاميرا'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in CameraMove.values)
                    ActionChip(
                      label: Text(cameraMoveLabel(m)),
                      onPressed: state.videoDurationSec > 0.2
                          ? () {
                              HapticFeedback.selectionClick();
                              state.applyCameraMove(m);
                            }
                          : null,
                    ),
                ],
              ),
              _title(context, 'نعومة الحركة'),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('ناعمة'),
                    selected: state.videoKeyEase,
                    onSelected: (_) =>
                        state.update(() => state.videoKeyEase = true),
                  ),
                  ChoiceChip(
                    label: const Text('خطّية'),
                    selected: !state.videoKeyEase,
                    onSelected: (_) =>
                        state.update(() => state.videoKeyEase = false),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  if (keyed)
                    TextButton.icon(
                      onPressed: state.clearVideoKeys,
                      icon: const Icon(Icons.layers_clear_outlined, size: 18),
                      label: const Text('مسح الإطارات'),
                    ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: state.hasVideoTransform
                        ? state.resetVideoTransform
                        : null,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('إعادة الضبط'),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
