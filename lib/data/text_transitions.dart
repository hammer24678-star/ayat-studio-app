// PATCH_S126_TEXT_TRANSITIONS: how the ayah text arrives on screen and how it
// leaves.
//
// Before this there was one behaviour: a linear alpha ramp over 300ms, and
// the exported overlay was drawn at 6 frames per second — so a fade was two
// or three visible steps. That is the "chopping". The live preview didn't
// even do that; it hard-cut, then cross-faded between ayat on a different
// curve and a different duration, so preview and export never agreed.
//
// Everything here is a PURE function of progress, which is what makes that
// fixable: one motion model, evaluated per frame by the exporter and per
// frame by the preview, so both draw the same thing.
//
// Progress is always 0 = fully absent, 1 = fully present, for BOTH the
// entrance and the exit (the exit just runs its progress backwards). Every
// transition must therefore satisfy two rules, and the tests enforce them:
//   * at p = 1 the motion is exactly identity — otherwise text never settles
//     where the user placed it
//   * it is continuous, with no jump between adjacent frames — a jump IS the
//     chopping, whatever the frame rate
import 'dart:math' as math;

// PATCH_S145_LANGUAGES_PATCH_A
import '../i18n/app_strings.dart';
import '../services/app_settings.dart';

/// Bounds on how long a transition may last, in milliseconds.
///
/// The floor is not a taste call. The overlay is rendered at
/// `ExportService.overlayFps` frames per second, so a transition of length
/// `ms` gets `overlayFps * ms / 1000` frames — and whatever curve is used,
/// SOME frame has to carry at least 1/frames of the travel. At 24fps a 120ms
/// transition is three frames, i.e. a third of the fade per frame however
/// carefully it is eased; that is not a fade, it is a three-step staircase.
/// 250ms buys six frames, which is where alpha steps drop under a quarter and
/// the motion starts reading as motion. Anything faster is offered as
/// [TextTransition.none], which at least looks like a deliberate cut.
const int kMinTextTransitionMs = 250;
const int kMaxTextTransitionMs = 2500;

/// What the text looks like partway through a transition. Every field is
/// relative, so the same motion applies identically at 270px preview scale
/// and 1080px export scale.
class TextMotion {
  /// 0..1 multiplier on the text's own alpha.
  final double opacity;

  /// Translation as a fraction of the FRAME (not the text), so a slide moves
  /// the same visual distance regardless of how long the ayah is.
  final double dx;
  final double dy;

  final double scale;

  /// Radians.
  final double rotation;

  /// Gaussian blur sigma, as a fraction of frame width.
  final double blur;

  /// 0..1 of the text block that is revealed, for wipes and staggers.
  final double reveal;
  final RevealMode revealMode;

  const TextMotion({
    this.opacity = 1,
    this.dx = 0,
    this.dy = 0,
    this.scale = 1,
    this.rotation = 0,
    this.blur = 0,
    this.reveal = 1,
    this.revealMode = RevealMode.none,
  });

  /// The settled state: text exactly where it belongs, fully opaque.
  static const identity = TextMotion();

  /// True when nothing needs to be applied — lets both renderers skip the
  /// whole transform/layer path on the frames that are just "showing text".
  bool get isIdentity =>
      opacity == 1 &&
      dx == 0 &&
      dy == 0 &&
      scale == 1 &&
      rotation == 0 &&
      blur == 0 &&
      (revealMode == RevealMode.none || reveal >= 1);
}

/// How a partially-revealed block is masked.
enum RevealMode {
  none,

  /// Rectangular wipes, by the edge the text appears FROM.
  wipeUp,
  wipeDown,
  wipeStart,
  wipeEnd,

  /// Expanding circle from the centre of the text block.
  iris,

  /// Horizontal bars opening from the middle.
  curtain,

  /// Words appear one after another.
  words,

  /// Letters appear one after another.
  letters,
}

/// Alpha for unit [index] of [count] in a word- or letter-by-letter reveal,
/// at [progress].
///
/// Each unit fades in over a WINDOW of the transition, and the windows of
/// neighbouring units overlap heavily. The overlap is the whole point: give
/// each word a hard on/off and the line stutters in exactly as many steps as
/// it has words, which is the chopping this file exists to remove.
///
/// The window has a floor, and that floor is not arbitrary either. A unit
/// that fades over a window w moves at 1/w per unit of progress, so across F
/// frames it steps 1/(w*F). At the shortest transition the UI offers — six
/// frames — a window under about half the transition means individual words
/// popping on in one frame. So the floor is 0.55, and the unit start times
/// are compressed into the remaining 1 - w so the LAST unit still finishes
/// exactly at progress 1 rather than being cut off mid-fade.
///
/// Shared by the exporter and the live preview so a typewriter reveal looks
/// the same in both.
double revealUnitAlpha({
  required int index,
  required int count,
  required double progress,
}) {
  if (count <= 1) return progress.clamp(0.0, 1.0);
  final p = progress.clamp(0.0, 1.0);
  final window = (2.2 / count).clamp(0.55, 0.9);
  final startAt = index * (1 - window) / (count - 1);
  return ((p - startAt) / window).clamp(0.0, 1.0);
}

extension RevealModeKind on RevealMode {
  /// Reveals that change WHICH GLYPHS are drawn rather than which pixels
  /// survive — they have to be applied while building the text spans, not by
  /// clipping afterwards.
  bool get isPerUnit =>
      this == RevealMode.words || this == RevealMode.letters;
}

/// The available in/out transitions. Append-only: SettingsService persists
/// the index, so inserting anywhere but the end repoints saved choices.
enum TextTransition {
  none,
  fade,
  fadeSoft,
  fadeBlur,
  slideUp,
  slideDown,
  slideStart,
  slideEnd,
  riseFade,
  dropFade,
  scaleUp,
  scaleDown,
  zoomBlur,
  springUp,
  elastic,
  blurIn,
  glowBloom,
  rotateIn,
  flipIn,
  wipeUp,
  wipeDown,
  wipeStart,
  wipeEnd,
  irisOpen,
  curtain,
  typewriterWords,
  typewriterLetters,
  staggerWords,
  driftIn,
  settleIn,
}

extension TextTransitionMeta on TextTransition {
  String get labelAr => switch (this) {
        TextTransition.none => 'بدون (ظهور فوري)',
        TextTransition.fade => 'تلاشٍ',
        TextTransition.fadeSoft => 'تلاشٍ ناعم',
        TextTransition.fadeBlur => 'تلاشٍ مع ضبابية',
        TextTransition.slideUp => 'انزلاق لأعلى',
        TextTransition.slideDown => 'انزلاق لأسفل',
        TextTransition.slideStart => 'انزلاق من البداية',
        TextTransition.slideEnd => 'انزلاق من النهاية',
        TextTransition.riseFade => 'ارتفاع مع تلاشٍ',
        TextTransition.dropFade => 'هبوط مع تلاشٍ',
        TextTransition.scaleUp => 'تكبير تدريجي',
        TextTransition.scaleDown => 'تصغير تدريجي',
        TextTransition.zoomBlur => 'اندفاع ضبابي',
        TextTransition.springUp => 'وثبة لأعلى',
        TextTransition.elastic => 'ارتداد مرن',
        TextTransition.blurIn => 'من الضبابية للوضوح',
        TextTransition.glowBloom => 'تفتّح نوراني',
        TextTransition.rotateIn => 'دوران خفيف',
        TextTransition.flipIn => 'انقلاب رأسي',
        TextTransition.wipeUp => 'كشف من الأسفل',
        TextTransition.wipeDown => 'كشف من الأعلى',
        TextTransition.wipeStart => 'كشف من البداية',
        TextTransition.wipeEnd => 'كشف من النهاية',
        TextTransition.irisOpen => 'دائرة تتّسع',
        TextTransition.curtain => 'ستارة تنفتح',
        TextTransition.typewriterWords => 'كلمة كلمة',
        TextTransition.typewriterLetters => 'حرفًا حرفًا',
        TextTransition.staggerWords => 'تتابع الكلمات',
        TextTransition.driftIn => 'انسياب هادئ',
        TextTransition.settleIn => 'استقرار لطيف',
      };

  String get labelEn => switch (this) {
        TextTransition.none => 'None (instant)',
        TextTransition.fade => 'Fade',
        TextTransition.fadeSoft => 'Soft fade',
        TextTransition.fadeBlur => 'Fade with blur',
        TextTransition.slideUp => 'Slide up',
        TextTransition.slideDown => 'Slide down',
        TextTransition.slideStart => 'Slide from start',
        TextTransition.slideEnd => 'Slide from end',
        TextTransition.riseFade => 'Rise and fade',
        TextTransition.dropFade => 'Drop and fade',
        TextTransition.scaleUp => 'Scale up',
        TextTransition.scaleDown => 'Scale down',
        TextTransition.zoomBlur => 'Zoom blur',
        TextTransition.springUp => 'Spring up',
        TextTransition.elastic => 'Elastic',
        TextTransition.blurIn => 'Blur to sharp',
        TextTransition.glowBloom => 'Glow bloom',
        TextTransition.rotateIn => 'Rotate in',
        TextTransition.flipIn => 'Flip in',
        TextTransition.wipeUp => 'Wipe from below',
        TextTransition.wipeDown => 'Wipe from above',
        TextTransition.wipeStart => 'Wipe from start',
        TextTransition.wipeEnd => 'Wipe from end',
        TextTransition.irisOpen => 'Iris open',
        TextTransition.curtain => 'Curtain',
        TextTransition.typewriterWords => 'Word by word',
        TextTransition.typewriterLetters => 'Letter by letter',
        TextTransition.staggerWords => 'Staggered words',
        TextTransition.driftIn => 'Gentle drift',
        TextTransition.settleIn => 'Settle',
      };

  // PATCH_S145_LANGUAGES_PATCH_A: labelAr/labelEn above are both
  // hand-written and complete; this just picks between them by the
  // current interface language. French/Indonesian/Urdu fall back to
  // English until a follow-up patch adds dedicated labelFr/labelId/labelUr
  // switches -- better than showing Arabic to someone who can't read it.
  String get label =>
      AppSettings.instance.lang == AppLang.ar ? labelAr : labelEn;

  /// Transitions that reveal the text progressively rather than moving it as
  /// a block. Grouped in the picker, because they read very differently and
  /// they cost more to render.
  bool get isReveal => const {
        TextTransition.wipeUp,
        TextTransition.wipeDown,
        TextTransition.wipeStart,
        TextTransition.wipeEnd,
        TextTransition.irisOpen,
        TextTransition.curtain,
        TextTransition.typewriterWords,
        TextTransition.typewriterLetters,
        TextTransition.staggerWords,
      }.contains(this);
}

// Easing. Written out by hand rather than pulled from Curves, for two
// reasons: the exporter has no ticker and must evaluate exactly what the
// widget layer does, and — more importantly — the MAXIMUM SLOPE of each curve
// is what decides whether a transition looks smooth.
//
// That is worth spelling out, because it is the whole reason this file was
// rewritten. Over N frames, a channel that travels 0..1 must move on average
// 1/N per frame; a curve whose steepest point is k times the average will
// step k/N there. Flutter's `Curves.easeOutCubic` has k = 3, so a 550ms fade
// at 24fps (13 frames) lurches 0.23 in its first frame and then crawls. That
// reads as a pop followed by a drift — exactly the "chopping" being fixed.
//
// So every channel that spans the full 0..1 range (opacity, reveal) uses one
// of the bounded-slope curves below. Channels with small amplitude (a 0.1
// frame-height slide, a 0.18 scale) can afford a punchier curve, because
// their step is amplitude x k / N and the amplitude keeps it small.

/// Linear. k = 1 — the smoothest curve there is, and the right one for a
/// plain fade.
double _lin(double p) => p.clamp(0.0, 1.0);

/// Classic smoothstep, 3p^2 - 2p^3. Eased at both ends, k = 1.5.
double _smooth(double p) {
  final t = p.clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

/// Smootherstep, 6p^5 - 15p^4 + 10p^3. Flatter at both ends than [_smooth]
/// (k = 1.875), so arrivals and departures are almost imperceptible.
double _smoother(double p) {
  final t = p.clamp(0.0, 1.0);
  return t * t * t * (t * (t * 6 - 15) + 10);
}

/// A smoothstep that finishes early, for transitions whose text should be
/// fully readable before the motion settles. k = 1.5 * [rush].
double _smoothRush(double p, double rush) =>
    _smooth(math.min(1.0, p.clamp(0.0, 1.0) * rush));

/// Ease-out with k = 3. Only ever applied to small-amplitude channels.
double _easeOutCubic(double p) {
  final t = 1 - p.clamp(0.0, 1.0);
  return 1 - t * t * t;
}

double _easeOutBack(double p) {
  final t = p.clamp(0.0, 1.0);
  const c1 = 1.70158, c3 = c1 + 1;
  return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2);
}

/// A damped-cosine bounce: 0 at p = 0, one clean overshoot of about 19% of
/// the travel, settling on 1.
///
/// The textbook `easeOutElastic` was tried first and rejected. It oscillates
/// at ~21 rad per unit of progress, which puts its steepest point around
/// k = 15 — five times steeper than an ease-out cubic. At any duration a user
/// would actually pick, its first bounce crosses several frames' worth of
/// travel in one frame and visibly stutters. This runs at 2.5pi rad with
/// heavier damping (k ~ 5.7), which still reads as a spring but is drawn, not
/// jumped.
double _softElastic(double p) {
  final t = p.clamp(0.0, 1.0);
  if (t <= 0) return 0;
  if (t >= 1) return 1;
  return 1 - math.pow(2, -6 * t) * math.cos(t * 2.5 * math.pi);
}

/// The motion for [t] at [progress], where 0 is fully absent and 1 is fully
/// present. Used identically by the exporter and the live preview.
TextMotion textMotionFor(TextTransition t, double progress) {
  final p = progress.clamp(0.0, 1.0);
  // Snapping to identity at the top end guarantees the settle rule exactly,
  // without relying on every curve returning a perfect 1.0 in floating point.
  if (p >= 1) return TextMotion.identity;
  if (t == TextTransition.none) {
    // Still binary, but at least honest about it: absent until it is present.
    return p <= 0 ? const TextMotion(opacity: 0) : TextMotion.identity;
  }

  // `a` drives the full-range channels (opacity, reveal) and is deliberately
  // gentle; `e` drives the small-amplitude ones and keeps its ease-out snap.
  final a = _smooth(p);
  final e = _easeOutCubic(p);

  switch (t) {
    case TextTransition.none:
      return TextMotion.identity;
    case TextTransition.fade:
      // Linear alpha: nothing steps further than 1/frames, which is the
      // theoretical floor. A plain fade should be the smoothest thing here.
      return TextMotion(opacity: _lin(p));
    case TextTransition.fadeSoft:
      // Eased at both ends and flatter than smoothstep — the gentlest
      // possible arrival.
      return TextMotion(opacity: _smoother(p));
    case TextTransition.fadeBlur:
      return TextMotion(opacity: a, blur: 0.012 * (1 - e));
    case TextTransition.slideUp:
      return TextMotion(opacity: a, dy: 0.10 * (1 - e));
    case TextTransition.slideDown:
      return TextMotion(opacity: a, dy: -0.10 * (1 - e));
    case TextTransition.slideStart:
      return TextMotion(opacity: a, dx: 0.14 * (1 - e));
    case TextTransition.slideEnd:
      return TextMotion(opacity: a, dx: -0.14 * (1 - e));
    case TextTransition.riseFade:
      return TextMotion(opacity: a, dy: 0.045 * (1 - e), scale: 0.98 + 0.02 * e);
    case TextTransition.dropFade:
      return TextMotion(
          opacity: a, dy: -0.045 * (1 - e), scale: 0.98 + 0.02 * e);
    case TextTransition.scaleUp:
      return TextMotion(opacity: a, scale: 0.82 + 0.18 * e);
    case TextTransition.scaleDown:
      return TextMotion(opacity: a, scale: 1.18 - 0.18 * e);
    case TextTransition.zoomBlur:
      return TextMotion(
          opacity: a, scale: 1.25 - 0.25 * e, blur: 0.02 * (1 - e));
    case TextTransition.springUp:
      // Readable slightly before it stops moving, which is what makes a
      // spring feel like a spring rather than a wobble.
      final s = _easeOutBack(p);
      return TextMotion(opacity: _smoothRush(p, 1.25), dy: 0.09 * (1 - s));
    case TextTransition.elastic:
      // See [_softElastic]: the bounce is damped rather than the amplitude
      // being shrunk, so it still overshoots visibly without any frame having
      // to cover an outsized share of the travel.
      final s = _softElastic(p);
      return TextMotion(
          opacity: _smoothRush(p, 1.25), scale: 0.75 + 0.25 * s);
    case TextTransition.blurIn:
      return TextMotion(opacity: _smoothRush(p, 1.25), blur: 0.03 * (1 - e));
    case TextTransition.glowBloom:
      // Over-bright and slightly large, settling back — reads as light
      // blooming into focus rather than a plain fade.
      final bloom = math.sin(p * math.pi);
      return TextMotion(
        opacity: a,
        scale: 1 + 0.05 * bloom,
        blur: 0.016 * bloom * (1 - p),
      );
    case TextTransition.rotateIn:
      return TextMotion(
          opacity: a, rotation: -0.06 * (1 - e), scale: 0.95 + 0.05 * e);
    case TextTransition.flipIn:
      // Vertical squash standing in for a 3D flip; the reveal factor never
      // hits zero, so there is no frame where the text vanishes mid-motion.
      return TextMotion(opacity: a).withFlip(0.15 + 0.85 * a);
    case TextTransition.wipeUp:
      return TextMotion(opacity: 1, reveal: a, revealMode: RevealMode.wipeUp);
    case TextTransition.wipeDown:
      return TextMotion(opacity: 1, reveal: a, revealMode: RevealMode.wipeDown);
    case TextTransition.wipeStart:
      return TextMotion(
          opacity: 1, reveal: a, revealMode: RevealMode.wipeStart);
    case TextTransition.wipeEnd:
      return TextMotion(opacity: 1, reveal: a, revealMode: RevealMode.wipeEnd);
    case TextTransition.irisOpen:
      return TextMotion(opacity: 1, reveal: a, revealMode: RevealMode.iris);
    case TextTransition.curtain:
      return TextMotion(opacity: 1, reveal: a, revealMode: RevealMode.curtain);
    case TextTransition.typewriterWords:
      // Linear on purpose: a typewriter that accelerates stops reading as
      // typing, and linear is also the smoothest ramp available.
      return TextMotion(opacity: 1, reveal: _lin(p), revealMode: RevealMode.words);
    case TextTransition.typewriterLetters:
      return TextMotion(
          opacity: 1, reveal: _lin(p), revealMode: RevealMode.letters);
    case TextTransition.staggerWords:
      // Words fade in over a sliding window rather than popping — the whole
      // block also rises very slightly so it reads as one gesture.
      return TextMotion(
          opacity: 1,
          dy: 0.02 * (1 - e),
          reveal: a,
          revealMode: RevealMode.words);
    case TextTransition.driftIn:
      return TextMotion(
          opacity: _smoother(p),
          dx: 0.03 * (1 - a),
          dy: 0.02 * (1 - a));
    case TextTransition.settleIn:
      return TextMotion(
          opacity: a, dy: 0.025 * (1 - _easeOutBack(p)), scale: 0.99 + 0.01 * e);
  }
}

extension on TextMotion {
  /// Vertical squash, used by [TextTransition.flipIn].
  TextMotion withFlip(double factor) => TextMotion(
        opacity: opacity,
        dx: dx,
        dy: dy,
        scale: scale,
        rotation: rotation,
        blur: blur,
        reveal: factor,
        revealMode: RevealMode.curtain,
      );
}
