// PATCH_S180_TRANSFORM
// Free transform + keyframes for the video layer (CapCut "Basic + Keyframe").
// Pure Dart: the preview (VideoXformLayer) and the exporter (ffmpeg
// `perspective` expressions) both evaluate THIS maths, so export == preview.
//
//   scale 0.3x..2.0x, position X/Y as a fraction of the frame, rotation in
//   degrees, opacity 0..1 (one value per clip). Keyframes (scale/x/y/rot) are
//   stored in SOURCE-video seconds and eased with smoothstep or linearly.

/// One keyframe on the video layer.
class VideoKey {
  /// Source-video seconds (the same clock the timeline uses).
  final double t;
  double scale;
  double x; // fraction of frame width, + = right
  double y; // fraction of frame height, + = down
  double rot; // degrees, + = clockwise

  VideoKey(this.t, {this.scale = 1.0, this.x = 0.0, this.y = 0.0, this.rot = 0.0});

  VideoKey copy() => VideoKey(t, scale: scale, x: x, y: y, rot: rot);
}

/// The transform at one instant.
class VideoXform {
  final double scale, x, y, rot, opacity;
  const VideoXform(this.scale, this.x, this.y, this.rot, this.opacity);
}

/// Ready-made camera moves (they write two keyframes over the clip).
enum CameraMove { zoomIn, zoomOut, driftRight, driftLeft, riseUp, tilt }

String cameraMoveLabel(CameraMove m) => switch (m) {
      CameraMove.zoomIn => 'تقريب تدريجي',
      CameraMove.zoomOut => 'ابتعاد تدريجي',
      CameraMove.driftRight => 'انجراف يمينًا',
      CameraMove.driftLeft => 'انجراف يسارًا',
      CameraMove.riseUp => 'صعود',
      CameraMove.tilt => 'ميلان خفيف',
    };

/// Start / end keyframes of a camera move. Every move keeps scale >= 1 so
/// the picture never reveals empty edges while it travels.
(VideoKey, VideoKey) cameraMoveKeys(CameraMove m, double a, double b) {
  switch (m) {
    case CameraMove.zoomIn:
      return (VideoKey(a, scale: 1.0), VideoKey(b, scale: 1.25));
    case CameraMove.zoomOut:
      return (VideoKey(a, scale: 1.25), VideoKey(b, scale: 1.0));
    case CameraMove.driftRight:
      return (VideoKey(a, scale: 1.12, x: -0.04), VideoKey(b, scale: 1.12, x: 0.04));
    case CameraMove.driftLeft:
      return (VideoKey(a, scale: 1.12, x: 0.04), VideoKey(b, scale: 1.12, x: -0.04));
    case CameraMove.riseUp:
      return (VideoKey(a, scale: 1.12, y: 0.04), VideoKey(b, scale: 1.12, y: -0.04));
    case CameraMove.tilt:
      return (VideoKey(a, scale: 1.12, rot: -2.0), VideoKey(b, scale: 1.12, rot: 2.0));
  }
}

double _clip01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Value of the transform at source-time [t].
///   no keys  -> the static values
///   one key  -> that key's values
///   2+ keys  -> interpolated (clamped before the first / after the last)
VideoXform evalVideoXform({
  required List<VideoKey> keys,
  required bool ease,
  required double scale,
  required double x,
  required double y,
  required double rot,
  required double opacity,
  required double t,
}) {
  if (keys.isEmpty) return VideoXform(scale, x, y, rot, opacity);
  if (keys.length == 1) {
    final k = keys.first;
    return VideoXform(k.scale, k.x, k.y, k.rot, opacity);
  }
  if (t <= keys.first.t) {
    final k = keys.first;
    return VideoXform(k.scale, k.x, k.y, k.rot, opacity);
  }
  if (t >= keys.last.t) {
    final k = keys.last;
    return VideoXform(k.scale, k.x, k.y, k.rot, opacity);
  }
  for (var i = 0; i < keys.length - 1; i++) {
    final a = keys[i];
    final b = keys[i + 1];
    if (t < b.t) {
      final dt = (b.t - a.t) < 0.001 ? 0.001 : (b.t - a.t);
      var p = _clip01((t - a.t) / dt);
      if (ease) p = p * p * (3 - 2 * p);
      double mix(double u, double v) => u + (v - u) * p;
      return VideoXform(mix(a.scale, b.scale), mix(a.x, b.x), mix(a.y, b.y),
          mix(a.rot, b.rot), opacity);
    }
  }
  final k = keys.last;
  return VideoXform(k.scale, k.x, k.y, k.rot, opacity);
}
