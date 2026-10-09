// PATCH_S188_PIP
// PATCH_S193_PIP_POWER
// Picture-in-picture clips: a small video or picture floating over the main
// clip for a stretch of the timeline (InShot "PIP").
//
// Pure Dart. The preview (PipLayer) and the exporter (PipExport) both read
// THIS geometry, so what you see on the stage is what gets burned in.
//
// Times are seconds on the main clip's own clock - the same clock the text
// blocks and the ayah blocks use.
import 'dart:math' as math;

enum PipShape { rect, rounded, circle }

String pipShapeLabel(PipShape s) => switch (s) {
      PipShape.rect => 'مستطيل',
      PipShape.rounded => 'مدوّر',
      PipShape.circle => 'دائرة',
    };

/// How a clip arrives and leaves (PATCH_S193_PIP_POWER). Every style is
/// described by [pipAnimPose] and mirrored, expression for expression, by the
/// exporter, so the preview and the exported file move the same way.
enum PipAnim {
  none,
  fade,
  zoom,
  pop,
  slideLeft,
  slideRight,
  slideUp,
  slideDown,
  spin,
}

String pipAnimLabel(PipAnim a) => switch (a) {
      PipAnim.none => 'بدون',
      PipAnim.fade => 'تلاشٍ',
      PipAnim.zoom => 'تكبير',
      PipAnim.pop => 'نبضة',
      PipAnim.slideLeft => 'من اليسار',
      PipAnim.slideRight => 'من اليمين',
      PipAnim.slideUp => 'من الأسفل',
      PipAnim.slideDown => 'من الأعلى',
      PipAnim.spin => 'دوران',
    };

/// Corner radius of the "rounded" shape, as a fraction of the shorter side.
const double kPipRounded = 0.14;

/// Default length of the soft appear / disappear (seconds).
const double kPipFade = 0.30;

const double kPipMinLen = 0.3;

/// How far a sliding clip travels, as a fraction of the frame.
const double kPipSlideX = 0.6;
const double kPipSlideY = 0.5;

/// Degrees a spinning clip turns while it arrives / leaves.
const double kPipSpinDeg = 270.0;

/// Smooth 0..1 ramp.
double pipEase(double p) {
  final x = p.clamp(0.0, 1.0).toDouble();
  return x * x * (3 - 2 * x);
}

/// Overshooting ramp used by [PipAnim.pop].
double pipBack(double p) {
  final x = p.clamp(0.0, 1.0).toDouble() - 1.0;
  return 1.0 + 2.70158 * x * x * x + 1.70158 * x * x;
}

/// Fraction of an animation during which the picture is still see-through.
/// 0 means "never fades" (the clip just appears).
double pipAnimAlphaFrac(PipAnim a) => switch (a) {
      PipAnim.none => 0.0,
      PipAnim.fade => 1.0,
      PipAnim.zoom => 1.0,
      PipAnim.pop => 0.35,
      PipAnim.slideLeft ||
      PipAnim.slideRight ||
      PipAnim.slideUp ||
      PipAnim.slideDown =>
        0.7,
      PipAnim.spin => 1.0,
    };

/// How a clip looks at one instant of its arrival or exit.
class PipPose {
  /// 0..1 multiplier on the opacity.
  final double alpha;

  /// Size multiplier around the centre.
  final double scale;

  /// Shift as a fraction of the frame width / height.
  final double dx;
  final double dy;

  /// Extra turn, degrees clockwise.
  final double rot;
  const PipPose(this.alpha, this.scale, this.dx, this.dy, this.rot);
  static const PipPose still = PipPose(1, 1, 0, 0, 0);
}

/// The pose for animation [a] when its progress is [p] (0 = hidden, 1 = fully
/// arrived). For an exit, pass the progress of the exit run backwards
/// (1 -> 0), so the same shape plays in reverse.
PipPose pipAnimPose(PipAnim a, double p) {
  final q = p.clamp(0.0, 1.0).toDouble();
  if (a == PipAnim.none || q >= 1.0) return PipPose.still;
  final frac = pipAnimAlphaFrac(a);
  final alpha = frac <= 0 ? 1.0 : pipEase(q / frac);
  final e = pipEase(q);
  switch (a) {
    case PipAnim.none:
    case PipAnim.fade:
      return PipPose(alpha, 1, 0, 0, 0);
    case PipAnim.zoom:
      return PipPose(alpha, 0.5 + 0.5 * e, 0, 0, 0);
    case PipAnim.pop:
      return PipPose(alpha, math.max(0.02, pipBack(q)), 0, 0, 0);
    case PipAnim.slideLeft:
      return PipPose(alpha, 1, -(1 - e) * kPipSlideX, 0, 0);
    case PipAnim.slideRight:
      return PipPose(alpha, 1, (1 - e) * kPipSlideX, 0, 0);
    case PipAnim.slideUp:
      return PipPose(alpha, 1, 0, (1 - e) * kPipSlideY, 0);
    case PipAnim.slideDown:
      return PipPose(alpha, 1, 0, -(1 - e) * kPipSlideY, 0);
    case PipAnim.spin:
      return PipPose(alpha, 0.3 + 0.7 * e, 0, 0, -kPipSpinDeg * (1 - e));
  }
}

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

  // ---- PATCH_S193_PIP_POWER ------------------------------------------------

  /// How it arrives / leaves, and how long each takes (seconds).
  PipAnim inAnim;
  PipAnim outAnim;
  double inDur;
  double outDur;

  /// Mirror the picture.
  bool flipH;
  bool flipV;

  /// Corner radius of the "rounded" shape, fraction of the shorter side.
  double radius;

  /// Frame around the picture: width as a fraction of the shorter side
  /// (0 = none) and its colour (ARGB).
  double borderW;
  int borderColor;

  /// Soft drop shadow under the box.
  bool shadow;

  /// Make one colour (and its near neighbours) transparent - white paper,
  /// a black screen, a green screen.
  bool keyOn;
  int keyColor; // ARGB
  double keySim; // 0.02..0.6, how far from the colour still counts
  double keyBlend; // 0..0.4, soft edge

  /// Picture adjustments of this clip only.
  double brightness; // -0.4..0.4
  double contrast; // 0.5..1.8
  double saturation; // 0..2

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
    this.inAnim = PipAnim.fade,
    this.outAnim = PipAnim.fade,
    this.inDur = kPipFade,
    this.outDur = kPipFade,
    this.flipH = false,
    this.flipV = false,
    this.radius = kPipRounded,
    this.borderW = 0,
    this.borderColor = 0xFFECC875,
    this.shadow = false,
    this.keyOn = false,
    this.keyColor = 0xFFFFFFFF,
    this.keySim = 0.30,
    this.keyBlend = 0.10,
    this.brightness = 0,
    this.contrast = 1,
    this.saturation = 1,
  }) : id = id ?? _seq++;

  PipClip _clone(int? newId) => PipClip(
        id: newId,
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
        inAnim: inAnim,
        outAnim: outAnim,
        inDur: inDur,
        outDur: outDur,
        flipH: flipH,
        flipV: flipV,
        radius: radius,
        borderW: borderW,
        borderColor: borderColor,
        shadow: shadow,
        keyOn: keyOn,
        keyColor: keyColor,
        keySim: keySim,
        keyBlend: keyBlend,
        brightness: brightness,
        contrast: contrast,
        saturation: saturation,
      );

  PipClip copy() => _clone(id);

  /// A fresh clip (new identity) with the same look and timing.
  PipClip duplicate() => _clone(null);

  /// A clip that keeps the look but starts where this one ends (used by the
  /// cut: the second half arrives without a fresh entrance).
  PipClip splitTail(double t) {
    final c = _clone(null);
    c.start = t;
    c.end = end;
    c.srcIn = isImage ? 0.0 : srcIn + (t - start);
    c.inAnim = PipAnim.none;
    return c;
  }

  double get length => end - start;

  /// The shape of the box: a circle is always square (the media is
  /// centre-cropped), everything else keeps the media's own proportions.
  double get boxAspect {
    if (shape == PipShape.circle) return 1.0;
    return aspect.isFinite && aspect > 0.05 ? aspect.clamp(0.2, 5.0).toDouble() : 1.0;
  }

  /// Corner radius of the rounded shape as a fraction of the shorter side.
  double get radiusFrac => radius.clamp(0.0, 0.5).toDouble();

  bool get hasAdjust =>
      brightness.abs() > 0.004 ||
      (contrast - 1).abs() > 0.004 ||
      (saturation - 1).abs() > 0.004;

  bool get hasBorder => borderW > 0.002;

  bool activeAt(double t) => t >= start && t < end;

  /// Effective entrance / exit lengths: never more than half the clip.
  double get inLen =>
      inAnim == PipAnim.none ? 0.0 : math.min(inDur, length / 2).toDouble();
  double get outLen =>
      outAnim == PipAnim.none ? 0.0 : math.min(outDur, length / 2).toDouble();

  /// Where the clip is in its arrival and exit at main-clock time [t].
  PipPose poseAt(double t) {
    final di = inLen;
    final dout = outLen;
    final pIn = di > 0.001 ? ((t - start) / di).clamp(0.0, 1.0).toDouble() : 1.0;
    final pOut = dout > 0.001 ? ((end - t) / dout).clamp(0.0, 1.0).toDouble() : 1.0;
    final a = pipAnimPose(inAnim, pIn);
    final b = pipAnimPose(outAnim, pOut);
    return PipPose(a.alpha * b.alpha, a.scale * b.scale, a.dx + b.dx,
        a.dy + b.dy, a.rot + b.rot);
  }

  /// 0..1 visibility at [t]: opacity times the soft ends.
  double alphaAt(double t) {
    if (!activeAt(t)) return 0;
    return opacity.clamp(0.0, 1.0).toDouble() * poseAt(t).alpha;
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
