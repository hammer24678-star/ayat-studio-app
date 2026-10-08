// PATCH_S188_PIP
// Picture-in-picture clips: a small video or picture floating over the main
// clip for a stretch of the timeline (InShot "PIP").
//
// Pure Dart. The preview (PipLayer) and the exporter (PipExport) both read
// THIS geometry, so what you see on the stage is what gets burned in.
//
// Times are seconds on the main clip's own clock - the same clock the text
// blocks and the ayah blocks use.

enum PipShape { rect, rounded, circle }

String pipShapeLabel(PipShape s) => switch (s) {
      PipShape.rect => 'مستطيل',
      PipShape.rounded => 'مدوّر',
      PipShape.circle => 'دائرة',
    };

/// Corner radius of the "rounded" shape, as a fraction of the shorter side.
const double kPipRounded = 0.14;

/// Length of the soft appear / disappear (seconds).
const double kPipFade = 0.30;

const double kPipMinLen = 0.3;

class PipClip {
  static int _seq = 1;

  /// Stable identity (survives undo / redo copies).
  final int id;
  String path;
  bool isImage;

  /// width / height of the media as it plays (rotation already applied).
  double aspect;

  /// Length of the media in seconds (0 for a picture).
  double mediaDur;

  /// Window on the main clip's clock.
  double start;
  double end;

  /// Where inside the media the window begins (seconds).
  double srcIn;

  /// Centre of the box as a fraction of the frame (0..1).
  double cx;
  double cy;

  /// Width of the box as a fraction of the frame width.
  double width;

  /// Degrees, clockwise.
  double rot;
  double opacity;
  PipShape shape;

  /// Soft appear / disappear at the two ends of the window.
  bool fade;

  PipClip({
    int? id,
    required this.path,
    required this.isImage,
    required this.aspect,
    this.mediaDur = 0,
    required this.start,
    required this.end,
    this.srcIn = 0,
    this.cx = 0.5,
    this.cy = 0.5,
    this.width = 0.5,
    this.rot = 0,
    this.opacity = 1,
    this.shape = PipShape.rounded,
    this.fade = true,
  }) : id = id ?? _seq++;

  PipClip copy() => PipClip(
        id: id,
        path: path,
        isImage: isImage,
        aspect: aspect,
        mediaDur: mediaDur,
        start: start,
        end: end,
        srcIn: srcIn,
        cx: cx,
        cy: cy,
        width: width,
        rot: rot,
        opacity: opacity,
        shape: shape,
        fade: fade,
      );

  /// A fresh clip (new identity) with the same look and timing.
  PipClip duplicate() => PipClip(
        path: path,
        isImage: isImage,
        aspect: aspect,
        mediaDur: mediaDur,
        start: start,
        end: end,
        srcIn: srcIn,
        cx: cx,
        cy: cy,
        width: width,
        rot: rot,
        opacity: opacity,
        shape: shape,
        fade: fade,
      );

  double get length => end - start;

  /// The shape of the box: a circle is always square (the media is
  /// centre-cropped), everything else keeps the media's own proportions.
  double get boxAspect {
    if (shape == PipShape.circle) return 1.0;
    return aspect.isFinite && aspect > 0.05 ? aspect.clamp(0.2, 5.0).toDouble() : 1.0;
  }

  bool activeAt(double t) => t >= start && t < end;

  /// 0..1 visibility at [t]: opacity times the soft ends.
  double alphaAt(double t) {
    if (!activeAt(t)) return 0;
    var a = opacity.clamp(0.0, 1.0).toDouble();
    if (fade) {
      final f = (length / 2) < kPipFade ? length / 2 : kPipFade;
      if (f > 0.001) {
        final i = ((t - start) / f).clamp(0.0, 1.0).toDouble();
        final o = ((end - t) / f).clamp(0.0, 1.0).toDouble();
        final m = i < o ? i : o;
        a *= m * m * (3 - 2 * m);
      }
    }
    return a;
  }

  /// Where in the media the picture should be at main-clock time [t]
  /// (loops when the media is shorter than the window).
  double mediaTimeAt(double t) {
    final raw = srcIn + (t - start);
    if (isImage || mediaDur < 0.05) return raw < 0 ? 0 : raw;
    final m = raw % mediaDur;
    return m < 0 ? m + mediaDur : m;
  }
}
