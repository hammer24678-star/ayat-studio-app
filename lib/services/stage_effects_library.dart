// PATCH_S125_EFFECTS_LIBRARY: the app shipped 13 stage effects. This adds 61
// more, in one place, keeping stage_effects.dart's original painters exactly
// as they were.
//
// Two kinds of effect live here:
//
//   * Most are declared, not hand-written. [_Spec] describes a field of
//     particles -- how many, what shape, how they move, their colours, size
//     and blur -- and one engine draws it. 40-odd genuinely different-looking
//     effects come out of that without 40 near-identical painters to keep in
//     sync, and adding another is one line.
//   * The rest are bespoke, because an arabesque tile, a scan-line overlay
//     and a kaleidoscope have nothing in common with a particle field.
//
// EVERY effect here obeys the same contract as the originals: motion is
// periodic over [StageEffects.loopSeconds], so the frame at t = loopSeconds
// is pixel-identical to t = 0 and the exported PNG tile loops seamlessly.
// That is why every speed is expressed as a whole number of cycles per
// period, never as a free-running velocity.
import 'dart:math';

import 'package:flutter/material.dart';

import 'stage_effects.dart';

/// Grouping for the picker. Sixty-odd effects in one flat Wrap is a wall;
/// by category it is a menu.
enum EffectCategory { nature, light, ornament, particles, film, energy }

extension EffectCategoryLabel on EffectCategory {
  String get labelAr => switch (this) {
        EffectCategory.nature => 'طبيعة وطقس',
        EffectCategory.light => 'إضاءة ووهج',
        EffectCategory.ornament => 'زخرفة إسلامية',
        EffectCategory.particles => 'جسيمات وحركة',
        EffectCategory.film => 'فيلم وريترو',
        EffectCategory.energy => 'نبض وطاقة',
      };

  String get labelEn => switch (this) {
        EffectCategory.nature => 'Nature & weather',
        EffectCategory.light => 'Light & glow',
        EffectCategory.ornament => 'Islamic ornament',
        EffectCategory.particles => 'Particles & motion',
        EffectCategory.film => 'Film & retro',
        EffectCategory.energy => 'Pulse & energy',
      };

  IconData get icon => switch (this) {
        EffectCategory.nature => Icons.landscape_outlined,
        EffectCategory.light => Icons.light_mode_outlined,
        EffectCategory.ornament => Icons.mosque_outlined,
        EffectCategory.particles => Icons.blur_on_outlined,
        EffectCategory.film => Icons.movie_filter_outlined,
        EffectCategory.energy => Icons.graphic_eq,
      };
}

// ---------------------------------------------------------------------------
// The declarative engine
// ---------------------------------------------------------------------------

enum _Shape {
  dot,
  softDot,
  ring,
  line,
  streak,
  star4,
  star5,
  star6,
  star8,
  petal,
  leaf,
  square,
  diamond,
  crescent,
  triangle,
  bar,
}

enum _Motion {
  /// Wraps downward; whole traversals per loop.
  fall,

  /// Wraps upward.
  rise,

  /// Wraps sideways.
  driftLeft,
  driftRight,

  /// Circles its anchor.
  orbit,

  /// Travels outward from the centre, fading — resets each loop.
  burst,

  /// Fixed position, brightness breathes.
  twinkle,

  /// Slow lissajous around its anchor.
  wander,

  /// Fixed anchor, swings horizontally.
  sway,

  /// Grows toward the viewer and fades.
  zoom,
}

class _Spec {
  final int count;
  final _Shape shape;
  final _Motion motion;
  final Color colorA;
  final Color colorB;

  /// Size range as a fraction of frame width.
  final double sizeMin;
  final double sizeMax;

  /// Blur radius as a fraction of frame width. 0 = crisp.
  final double blur;

  /// Whole motion cycles per loop period — 1 is slow, 3 is brisk.
  final int cycles;
  final double opacity;

  /// Spin, in whole turns per loop.
  final int spin;

  /// Extra horizontal drift while falling/rising, as a fraction of width.
  final double drift;

  /// Concentrate particles near the centre instead of spreading them.
  final bool fromCentre;
  final BlendMode blend;

  const _Spec({
    required this.count,
    required this.shape,
    required this.motion,
    required this.colorA,
    Color? colorB,
    this.sizeMin = 0.004,
    this.sizeMax = 0.012,
    this.blur = 0,
    this.cycles = 1,
    this.opacity = 1,
    this.spin = 0,
    this.drift = 0,
    this.fromCentre = false,
    this.blend = BlendMode.srcOver,
  }) : colorB = colorB ?? colorA;
}

// Palette shorthands, so the specs below read as design rather than hex.
const _gold = Color(0xFFC9A24B);
const _goldBright = Color(0xFFECC875);
const _parchment = Color(0xFFECE2CB);
const _white = Color(0xFFFFFFFF);
const _emerald = Color(0xFF2E7D63);
const _sky = Color(0xFF9FD8F5);
const _ember = Color(0xFFFF8A45);
const _rose = Color(0xFFEFA9B8);
const _violet = Color(0xFFB49AE0);
const _leafGreen = Color(0xFFC8B26B);

/// Deterministic pseudo-random in [0,1) — same formula the original painters
/// use, so preview and export never disagree about where a particle is.
double _rand(int i, int salt) {
  final x = sin(i * 127.1 + salt * 311.7) * 43758.5453;
  return x - x.floorToDouble();
}

double _easeInOutSine(double x) => -(cos(pi * x) - 1) / 2;
double _eased(double raw) => raw.sign * _easeInOutSine(raw.abs());

Color _lerpC(Color a, Color b, double t) => Color.lerp(a, b, t) ?? a;

// ---------------------------------------------------------------------------
// Effect table
// ---------------------------------------------------------------------------

/// Every effect added by this library, with its spec (or null when it has a
/// bespoke painter), its label and its category.
class ExtendedEffect {
  final String labelAr;
  final String labelEn;
  final EffectCategory category;
  final IconData icon;
  final _Spec? spec;
  const ExtendedEffect({
    required this.labelAr,
    required this.labelEn,
    required this.category,
    required this.icon,
    this.spec,
  });
}

const Map<StageEffect, ExtendedEffect> kExtendedEffects = {
  // ---- nature & weather -------------------------------------------------
  StageEffect.heavyRain: ExtendedEffect(
    labelAr: 'مطر غزير',
    labelEn: 'Heavy rain',
    category: EffectCategory.nature,
    icon: Icons.thunderstorm_outlined,
    spec: _Spec(
      count: 150,
      shape: _Shape.streak,
      motion: _Motion.fall,
      colorA: Color(0xFFBBD8E8),
      sizeMin: 0.002,
      sizeMax: 0.004,
      cycles: 3,
      opacity: 0.55,
      drift: 0.05,
    ),
  ),
  StageEffect.drizzle: ExtendedEffect(
    labelAr: 'رذاذ خفيف',
    labelEn: 'Drizzle',
    category: EffectCategory.nature,
    icon: Icons.grain,
    spec: _Spec(
      count: 70,
      shape: _Shape.line,
      motion: _Motion.fall,
      colorA: Color(0xFFCFE6F2),
      sizeMin: 0.001,
      sizeMax: 0.002,
      cycles: 2,
      opacity: 0.35,
    ),
  ),
  StageEffect.blizzard: ExtendedEffect(
    labelAr: 'عاصفة ثلجية',
    labelEn: 'Blizzard',
    category: EffectCategory.nature,
    icon: Icons.severe_cold,
    spec: _Spec(
      count: 130,
      shape: _Shape.softDot,
      motion: _Motion.fall,
      colorA: _white,
      sizeMin: 0.002,
      sizeMax: 0.007,
      blur: 0.002,
      cycles: 2,
      opacity: 0.75,
      drift: 0.22,
    ),
  ),
  StageEffect.sandstorm: ExtendedEffect(
    labelAr: 'عاصفة رملية',
    labelEn: 'Sandstorm',
    category: EffectCategory.nature,
    icon: Icons.filter_drama_outlined,
    spec: _Spec(
      count: 160,
      shape: _Shape.streak,
      motion: _Motion.driftRight,
      colorA: Color(0xFFD9B98A),
      colorB: Color(0xFFB08A55),
      sizeMin: 0.002,
      sizeMax: 0.006,
      blur: 0.001,
      cycles: 2,
      opacity: 0.4,
    ),
  ),
  StageEffect.fallingLeaves: ExtendedEffect(
    labelAr: 'أوراق متساقطة',
    labelEn: 'Falling leaves',
    category: EffectCategory.nature,
    icon: Icons.eco_outlined,
    spec: _Spec(
      count: 22,
      shape: _Shape.leaf,
      motion: _Motion.fall,
      colorA: _leafGreen,
      colorB: Color(0xFFC98A4B),
      sizeMin: 0.010,
      sizeMax: 0.022,
      cycles: 1,
      opacity: 0.8,
      spin: 1,
      drift: 0.16,
    ),
  ),
  StageEffect.petals: ExtendedEffect(
    labelAr: 'بتلات متطايرة',
    labelEn: 'Drifting petals',
    category: EffectCategory.nature,
    icon: Icons.local_florist_outlined,
    spec: _Spec(
      count: 26,
      shape: _Shape.petal,
      motion: _Motion.fall,
      colorA: _rose,
      colorB: Color(0xFFF6E2E8),
      sizeMin: 0.008,
      sizeMax: 0.018,
      cycles: 1,
      opacity: 0.75,
      spin: 1,
      drift: 0.20,
    ),
  ),
  StageEffect.mist: ExtendedEffect(
    labelAr: 'ندى خفيف',
    labelEn: 'Light mist',
    category: EffectCategory.nature,
    icon: Icons.foggy,
    spec: _Spec(
      count: 40,
      shape: _Shape.softDot,
      motion: _Motion.rise,
      colorA: _white,
      sizeMin: 0.004,
      sizeMax: 0.014,
      blur: 0.006,
      cycles: 1,
      opacity: 0.16,
    ),
  ),
  StageEffect.cloudDrift: ExtendedEffect(
    labelAr: 'سحب عابرة',
    labelEn: 'Drifting cloud',
    category: EffectCategory.nature,
    icon: Icons.cloud_queue,
    spec: _Spec(
      count: 8,
      shape: _Shape.softDot,
      motion: _Motion.driftLeft,
      colorA: _white,
      sizeMin: 0.10,
      sizeMax: 0.26,
      blur: 0.05,
      cycles: 1,
      opacity: 0.10,
    ),
  ),
  StageEffect.bubbles: ExtendedEffect(
    labelAr: 'فقاعات',
    labelEn: 'Bubbles',
    category: EffectCategory.nature,
    icon: Icons.bubble_chart_outlined,
    spec: _Spec(
      count: 34,
      shape: _Shape.ring,
      motion: _Motion.rise,
      colorA: _sky,
      colorB: _white,
      sizeMin: 0.005,
      sizeMax: 0.020,
      cycles: 1,
      opacity: 0.5,
      drift: 0.08,
    ),
  ),
  StageEffect.embers: ExtendedEffect(
    labelAr: 'جمرات متطايرة',
    labelEn: 'Rising embers',
    category: EffectCategory.nature,
    icon: Icons.local_fire_department_outlined,
    spec: _Spec(
      count: 48,
      shape: _Shape.softDot,
      motion: _Motion.rise,
      colorA: _ember,
      colorB: Color(0xFFFFD79A),
      sizeMin: 0.002,
      sizeMax: 0.006,
      blur: 0.003,
      cycles: 1,
      opacity: 0.85,
      drift: 0.12,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.ashfall: ExtendedEffect(
    labelAr: 'رماد متساقط',
    labelEn: 'Falling ash',
    category: EffectCategory.nature,
    icon: Icons.grain_outlined,
    spec: _Spec(
      count: 70,
      shape: _Shape.dot,
      motion: _Motion.fall,
      colorA: Color(0xFFBDBDBD),
      sizeMin: 0.001,
      sizeMax: 0.004,
      cycles: 1,
      opacity: 0.4,
      drift: 0.10,
    ),
  ),
  StageEffect.meteorShower: ExtendedEffect(
    labelAr: 'شهب',
    labelEn: 'Meteor shower',
    category: EffectCategory.nature,
    icon: Icons.star_border_purple500_outlined,
    spec: _Spec(
      count: 14,
      shape: _Shape.streak,
      motion: _Motion.fall,
      colorA: _goldBright,
      colorB: _white,
      sizeMin: 0.010,
      sizeMax: 0.030,
      blur: 0.002,
      cycles: 2,
      opacity: 0.8,
      drift: 0.35,
      blend: BlendMode.plus,
    ),
  ),

  // ---- light & glow -----------------------------------------------------
  StageEffect.bokeh: ExtendedEffect(
    labelAr: 'بوكيه ضوئي',
    labelEn: 'Bokeh',
    category: EffectCategory.light,
    icon: Icons.blur_circular,
    spec: _Spec(
      count: 22,
      shape: _Shape.softDot,
      motion: _Motion.wander,
      colorA: _goldBright,
      colorB: _parchment,
      sizeMin: 0.02,
      sizeMax: 0.07,
      blur: 0.012,
      cycles: 1,
      opacity: 0.22,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.starfield: ExtendedEffect(
    labelAr: 'سماء نجوم',
    labelEn: 'Starfield',
    category: EffectCategory.light,
    icon: Icons.nights_stay_outlined,
    spec: _Spec(
      count: 120,
      shape: _Shape.dot,
      motion: _Motion.twinkle,
      colorA: _white,
      colorB: _sky,
      sizeMin: 0.0008,
      sizeMax: 0.0028,
      cycles: 2,
      opacity: 0.85,
    ),
  ),
  StageEffect.twinkleStars: ExtendedEffect(
    labelAr: 'نجوم متلألئة',
    labelEn: 'Twinkling stars',
    category: EffectCategory.light,
    icon: Icons.auto_awesome,
    spec: _Spec(
      count: 34,
      shape: _Shape.star4,
      motion: _Motion.twinkle,
      colorA: _goldBright,
      colorB: _white,
      sizeMin: 0.004,
      sizeMax: 0.013,
      blur: 0.001,
      cycles: 3,
      opacity: 0.9,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.glowPulse: ExtendedEffect(
    labelAr: 'نبض ضوئي',
    labelEn: 'Glow pulse',
    category: EffectCategory.light,
    icon: Icons.lens_blur,
    spec: _Spec(
      count: 7,
      shape: _Shape.softDot,
      motion: _Motion.twinkle,
      colorA: _gold,
      sizeMin: 0.06,
      sizeMax: 0.16,
      blur: 0.03,
      cycles: 1,
      opacity: 0.18,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.candleGlow: ExtendedEffect(
    labelAr: 'وهج شموع',
    labelEn: 'Candle glow',
    category: EffectCategory.light,
    icon: Icons.local_fire_department,
    spec: _Spec(
      count: 10,
      shape: _Shape.softDot,
      motion: _Motion.sway,
      colorA: Color(0xFFFFC169),
      colorB: Color(0xFFFFF0C4),
      sizeMin: 0.01,
      sizeMax: 0.03,
      blur: 0.012,
      cycles: 2,
      opacity: 0.55,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.lanternGlow: ExtendedEffect(
    labelAr: 'فوانيس',
    labelEn: 'Lanterns',
    category: EffectCategory.light,
    icon: Icons.emoji_objects_outlined,
    spec: _Spec(
      count: 12,
      shape: _Shape.diamond,
      motion: _Motion.rise,
      colorA: _goldBright,
      colorB: _ember,
      sizeMin: 0.012,
      sizeMax: 0.030,
      blur: 0.004,
      cycles: 1,
      opacity: 0.7,
      drift: 0.06,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.prismSplit: ExtendedEffect(
    labelAr: 'تشتّت ضوئي',
    labelEn: 'Prism split',
    category: EffectCategory.light,
    icon: Icons.gradient,
    spec: _Spec(
      count: 26,
      shape: _Shape.streak,
      motion: _Motion.driftRight,
      colorA: _violet,
      colorB: _sky,
      sizeMin: 0.02,
      sizeMax: 0.09,
      blur: 0.008,
      cycles: 1,
      opacity: 0.20,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.shimmerHaze: ExtendedEffect(
    labelAr: 'سراب لامع',
    labelEn: 'Shimmer haze',
    category: EffectCategory.light,
    icon: Icons.waves,
    spec: _Spec(
      count: 60,
      shape: _Shape.bar,
      motion: _Motion.sway,
      colorA: _parchment,
      sizeMin: 0.03,
      sizeMax: 0.10,
      blur: 0.006,
      cycles: 2,
      opacity: 0.10,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.warmGodRays: ExtendedEffect(
    labelAr: 'أشعة دافئة',
    labelEn: 'Warm god rays',
    category: EffectCategory.light,
    icon: Icons.wb_sunny_outlined,
  ),
  StageEffect.lightLeak: ExtendedEffect(
    labelAr: 'تسرّب ضوئي',
    labelEn: 'Light leak',
    category: EffectCategory.light,
    icon: Icons.flare_outlined,
  ),
  StageEffect.lensFlare: ExtendedEffect(
    labelAr: 'وهج العدسة',
    labelEn: 'Lens flare',
    category: EffectCategory.light,
    icon: Icons.flare,
  ),
  StageEffect.aurora: ExtendedEffect(
    labelAr: 'شفق قطبي',
    labelEn: 'Aurora',
    category: EffectCategory.light,
    icon: Icons.gradient_outlined,
  ),
  StageEffect.spotlightSweep: ExtendedEffect(
    labelAr: 'كشّاف متحرك',
    labelEn: 'Spotlight sweep',
    category: EffectCategory.light,
    icon: Icons.highlight_outlined,
  ),

  // ---- Islamic ornament -------------------------------------------------
  StageEffect.star8Grid: ExtendedEffect(
    labelAr: 'نجوم ثمانية',
    labelEn: 'Eight-point stars',
    category: EffectCategory.ornament,
    icon: Icons.star_outline,
    spec: _Spec(
      count: 26,
      shape: _Shape.star8,
      motion: _Motion.twinkle,
      colorA: _gold,
      colorB: _goldBright,
      sizeMin: 0.010,
      sizeMax: 0.026,
      cycles: 1,
      opacity: 0.45,
      spin: 1,
    ),
  ),
  StageEffect.star12Grid: ExtendedEffect(
    labelAr: 'نجوم اثنا عشرية',
    labelEn: 'Twelve-point stars',
    category: EffectCategory.ornament,
    icon: Icons.brightness_7_outlined,
    spec: _Spec(
      count: 18,
      shape: _Shape.star6,
      motion: _Motion.orbit,
      colorA: _goldBright,
      sizeMin: 0.012,
      sizeMax: 0.030,
      cycles: 1,
      opacity: 0.4,
      spin: 1,
    ),
  ),
  StageEffect.crescentDrift: ExtendedEffect(
    labelAr: 'أهلّة عائمة',
    labelEn: 'Drifting crescents',
    category: EffectCategory.ornament,
    icon: Icons.nightlight_outlined,
    spec: _Spec(
      count: 14,
      shape: _Shape.crescent,
      motion: _Motion.rise,
      colorA: _gold,
      colorB: _goldBright,
      sizeMin: 0.014,
      sizeMax: 0.034,
      cycles: 1,
      opacity: 0.5,
      spin: 1,
      drift: 0.10,
    ),
  ),
  StageEffect.goldFiligree: ExtendedEffect(
    labelAr: 'خيوط ذهبية',
    labelEn: 'Gold filigree',
    category: EffectCategory.ornament,
    icon: Icons.grain,
    spec: _Spec(
      count: 40,
      shape: _Shape.ring,
      motion: _Motion.wander,
      colorA: _gold,
      sizeMin: 0.006,
      sizeMax: 0.020,
      cycles: 1,
      opacity: 0.30,
      spin: 1,
    ),
  ),
  StageEffect.rosetteBloom: ExtendedEffect(
    labelAr: 'تفتّح الوردة',
    labelEn: 'Rosette bloom',
    category: EffectCategory.ornament,
    icon: Icons.filter_vintage_outlined,
    spec: _Spec(
      count: 9,
      shape: _Shape.star8,
      motion: _Motion.burst,
      colorA: _goldBright,
      colorB: _gold,
      sizeMin: 0.02,
      sizeMax: 0.05,
      cycles: 1,
      opacity: 0.55,
      spin: 1,
      fromCentre: true,
    ),
  ),
  StageEffect.arabesqueTile: ExtendedEffect(
    labelAr: 'زخرفة أرابيسك',
    labelEn: 'Arabesque tiling',
    category: EffectCategory.ornament,
    icon: Icons.dashboard_customize_outlined,
  ),
  StageEffect.mashrabiya: ExtendedEffect(
    labelAr: 'مشربية',
    labelEn: 'Mashrabiya screen',
    category: EffectCategory.ornament,
    icon: Icons.window_outlined,
  ),
  StageEffect.kufiGrid: ExtendedEffect(
    labelAr: 'شبكة كوفية',
    labelEn: 'Kufic grid',
    category: EffectCategory.ornament,
    icon: Icons.grid_4x4,
  ),
  StageEffect.borderOrnament: ExtendedEffect(
    labelAr: 'إطار مزخرف',
    labelEn: 'Ornamented border',
    category: EffectCategory.ornament,
    icon: Icons.crop_square,
  ),
  StageEffect.domeArch: ExtendedEffect(
    labelAr: 'قوس المحراب',
    labelEn: 'Mihrab arch',
    category: EffectCategory.ornament,
    icon: Icons.mosque_outlined,
  ),
  StageEffect.tessellation: ExtendedEffect(
    labelAr: 'تعشيق هندسي',
    labelEn: 'Tessellation',
    category: EffectCategory.ornament,
    icon: Icons.hexagon_outlined,
  ),
  StageEffect.minaretSilhouette: ExtendedEffect(
    labelAr: 'ظلال المآذن',
    labelEn: 'Minaret silhouette',
    category: EffectCategory.ornament,
    icon: Icons.location_city_outlined,
  ),

  // ---- particles & motion ----------------------------------------------
  StageEffect.orbitDots: ExtendedEffect(
    labelAr: 'نقاط مدارية',
    labelEn: 'Orbiting dots',
    category: EffectCategory.particles,
    icon: Icons.blur_on,
    spec: _Spec(
      count: 40,
      shape: _Shape.dot,
      motion: _Motion.orbit,
      colorA: _goldBright,
      sizeMin: 0.002,
      sizeMax: 0.006,
      cycles: 1,
      opacity: 0.6,
    ),
  ),
  StageEffect.spiralGalaxy: ExtendedEffect(
    labelAr: 'دوّامة نجمية',
    labelEn: 'Spiral galaxy',
    category: EffectCategory.particles,
    icon: Icons.cyclone,
  ),
  StageEffect.fireSparks: ExtendedEffect(
    labelAr: 'شرر ناري',
    labelEn: 'Fire sparks',
    category: EffectCategory.particles,
    icon: Icons.whatshot_outlined,
    spec: _Spec(
      count: 60,
      shape: _Shape.dot,
      motion: _Motion.burst,
      colorA: _ember,
      colorB: _goldBright,
      sizeMin: 0.001,
      sizeMax: 0.004,
      blur: 0.002,
      cycles: 1,
      opacity: 0.9,
      fromCentre: true,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.smokeWisp: ExtendedEffect(
    labelAr: 'خيوط دخان',
    labelEn: 'Smoke wisps',
    category: EffectCategory.particles,
    icon: Icons.air,
    spec: _Spec(
      count: 18,
      shape: _Shape.softDot,
      motion: _Motion.rise,
      colorA: Color(0xFFAFAFAF),
      sizeMin: 0.03,
      sizeMax: 0.10,
      blur: 0.03,
      cycles: 1,
      opacity: 0.12,
      drift: 0.18,
    ),
  ),
  StageEffect.dustDevil: ExtendedEffect(
    labelAr: 'زوبعة غبار',
    labelEn: 'Dust devil',
    category: EffectCategory.particles,
    icon: Icons.tornado,
    spec: _Spec(
      count: 70,
      shape: _Shape.dot,
      motion: _Motion.orbit,
      colorA: Color(0xFFD9C29A),
      sizeMin: 0.001,
      sizeMax: 0.004,
      cycles: 2,
      opacity: 0.4,
    ),
  ),
  StageEffect.cometTrail: ExtendedEffect(
    labelAr: 'مذنّب',
    labelEn: 'Comet',
    category: EffectCategory.particles,
    icon: Icons.rocket_launch_outlined,
    spec: _Spec(
      count: 3,
      shape: _Shape.streak,
      motion: _Motion.driftRight,
      colorA: _white,
      colorB: _sky,
      sizeMin: 0.05,
      sizeMax: 0.14,
      blur: 0.004,
      cycles: 1,
      opacity: 0.7,
      blend: BlendMode.plus,
    ),
  ),
  StageEffect.zoomStreaks: ExtendedEffect(
    labelAr: 'خطوط اندفاع',
    labelEn: 'Zoom streaks',
    category: EffectCategory.particles,
    icon: Icons.zoom_out_map,
    spec: _Spec(
      count: 46,
      shape: _Shape.streak,
      motion: _Motion.zoom,
      colorA: _parchment,
      sizeMin: 0.01,
      sizeMax: 0.05,
      cycles: 1,
      opacity: 0.35,
      fromCentre: true,
    ),
  ),
  StageEffect.snowGlobe: ExtendedEffect(
    labelAr: 'كرة ثلجية',
    labelEn: 'Snow globe',
    category: EffectCategory.particles,
    icon: Icons.ac_unit_outlined,
    spec: _Spec(
      count: 80,
      shape: _Shape.softDot,
      motion: _Motion.wander,
      colorA: _white,
      sizeMin: 0.002,
      sizeMax: 0.006,
      blur: 0.001,
      cycles: 1,
      opacity: 0.6,
    ),
  ),
  StageEffect.ripplesConcentric: ExtendedEffect(
    labelAr: 'دوائر متتابعة',
    labelEn: 'Concentric ripples',
    category: EffectCategory.particles,
    icon: Icons.radio_button_unchecked,
  ),
  StageEffect.plasmaWave: ExtendedEffect(
    labelAr: 'موجة بلازما',
    labelEn: 'Plasma wave',
    category: EffectCategory.particles,
    icon: Icons.waves_outlined,
  ),

  // ---- film & retro -----------------------------------------------------
  StageEffect.filmGrainFlicker: ExtendedEffect(
    labelAr: 'حبيبات فيلم',
    labelEn: 'Film grain',
    category: EffectCategory.film,
    icon: Icons.grain,
  ),
  StageEffect.scanLines: ExtendedEffect(
    labelAr: 'خطوط مسح',
    labelEn: 'Scan lines',
    category: EffectCategory.film,
    icon: Icons.horizontal_rule,
  ),
  StageEffect.vhsTracking: ExtendedEffect(
    labelAr: 'شريط قديم',
    labelEn: 'VHS tracking',
    category: EffectCategory.film,
    icon: Icons.videocam_outlined,
  ),
  StageEffect.filmScratches: ExtendedEffect(
    labelAr: 'خدوش فيلم',
    labelEn: 'Film scratches',
    category: EffectCategory.film,
    icon: Icons.content_cut,
  ),
  StageEffect.halftoneDots: ExtendedEffect(
    labelAr: 'نقاط طباعة',
    labelEn: 'Halftone dots',
    category: EffectCategory.film,
    icon: Icons.grid_on,
  ),
  StageEffect.duotoneSweep: ExtendedEffect(
    labelAr: 'مسح ثنائي اللون',
    labelEn: 'Duotone sweep',
    category: EffectCategory.film,
    icon: Icons.contrast,
  ),
  StageEffect.chromaticDrift: ExtendedEffect(
    labelAr: 'انزياح لوني',
    labelEn: 'Chromatic drift',
    category: EffectCategory.film,
    icon: Icons.blur_linear,
  ),
  StageEffect.vignettePulse: ExtendedEffect(
    labelAr: 'نبض التظليل',
    labelEn: 'Vignette pulse',
    category: EffectCategory.film,
    icon: Icons.vignette_outlined,
  ),

  // ---- pulse & energy ---------------------------------------------------
  StageEffect.pulseRings: ExtendedEffect(
    labelAr: 'حلقات نابضة',
    labelEn: 'Pulse rings',
    category: EffectCategory.energy,
    icon: Icons.track_changes,
    spec: _Spec(
      count: 6,
      shape: _Shape.ring,
      motion: _Motion.burst,
      colorA: _goldBright,
      sizeMin: 0.05,
      sizeMax: 0.09,
      cycles: 1,
      opacity: 0.5,
      fromCentre: true,
    ),
  ),
  StageEffect.breathingGlow: ExtendedEffect(
    labelAr: 'تنفّس ضوئي',
    labelEn: 'Breathing glow',
    category: EffectCategory.energy,
    icon: Icons.self_improvement_outlined,
  ),
  StageEffect.waveformBars: ExtendedEffect(
    labelAr: 'موجات صوتية',
    labelEn: 'Waveform',
    category: EffectCategory.energy,
    icon: Icons.graphic_eq,
  ),
  StageEffect.equalizerBars: ExtendedEffect(
    labelAr: 'معادل صوتي',
    labelEn: 'Equalizer',
    category: EffectCategory.energy,
    icon: Icons.equalizer,
  ),
  StageEffect.speedLines: ExtendedEffect(
    labelAr: 'خطوط سرعة',
    labelEn: 'Speed lines',
    category: EffectCategory.energy,
    icon: Icons.fast_forward_outlined,
    spec: _Spec(
      count: 30,
      shape: _Shape.bar,
      motion: _Motion.driftLeft,
      colorA: _parchment,
      sizeMin: 0.06,
      sizeMax: 0.22,
      cycles: 3,
      opacity: 0.18,
    ),
  ),
  StageEffect.kaleidoscope: ExtendedEffect(
    labelAr: 'مشكال',
    labelEn: 'Kaleidoscope',
    category: EffectCategory.energy,
    icon: Icons.auto_awesome_motion_outlined,
  ),
  StageEffect.heartbeatGlow: ExtendedEffect(
    labelAr: 'نبض القلب',
    labelEn: 'Heartbeat',
    category: EffectCategory.energy,
    icon: Icons.favorite_border,
  ),
};

// ---------------------------------------------------------------------------
// Painting
// ---------------------------------------------------------------------------

class StageEffectsLibrary {
  static double get _loop => StageEffects.loopSeconds;

  /// Draws any effect defined in this library. Unknown effects draw nothing,
  /// which is the right failure mode for a decorative layer.
  static void paint(Canvas canvas, Size size, StageEffect effect, double t,
      double intensity) {
    final def = kExtendedEffects[effect];
    if (def == null) return;
    final spec = def.spec;
    if (spec != null) {
      _paintField(canvas, size, spec, t, intensity);
      return;
    }
    switch (effect) {
      case StageEffect.warmGodRays:
        _warmGodRays(canvas, size, t, intensity);
      case StageEffect.lightLeak:
        _lightLeak(canvas, size, t, intensity);
      case StageEffect.lensFlare:
        _lensFlare(canvas, size, t, intensity);
      case StageEffect.aurora:
        _aurora(canvas, size, t, intensity);
      case StageEffect.spotlightSweep:
        _spotlightSweep(canvas, size, t, intensity);
      case StageEffect.arabesqueTile:
        _arabesqueTile(canvas, size, t, intensity);
      case StageEffect.mashrabiya:
        _mashrabiya(canvas, size, t, intensity);
      case StageEffect.kufiGrid:
        _kufiGrid(canvas, size, t, intensity);
      case StageEffect.borderOrnament:
        _borderOrnament(canvas, size, t, intensity);
      case StageEffect.domeArch:
        _domeArch(canvas, size, t, intensity);
      case StageEffect.tessellation:
        _tessellation(canvas, size, t, intensity);
      case StageEffect.minaretSilhouette:
        _minaretSilhouette(canvas, size, t, intensity);
      case StageEffect.spiralGalaxy:
        _spiralGalaxy(canvas, size, t, intensity);
      case StageEffect.ripplesConcentric:
        _ripples(canvas, size, t, intensity);
      case StageEffect.plasmaWave:
        _plasmaWave(canvas, size, t, intensity);
      case StageEffect.filmGrainFlicker:
        _filmGrain(canvas, size, t, intensity);
      case StageEffect.scanLines:
        _scanLines(canvas, size, t, intensity);
      case StageEffect.vhsTracking:
        _vhsTracking(canvas, size, t, intensity);
      case StageEffect.filmScratches:
        _filmScratches(canvas, size, t, intensity);
      case StageEffect.halftoneDots:
        _halftone(canvas, size, t, intensity);
      case StageEffect.duotoneSweep:
        _duotoneSweep(canvas, size, t, intensity);
      case StageEffect.chromaticDrift:
        _chromaticDrift(canvas, size, t, intensity);
      case StageEffect.vignettePulse:
        _vignettePulse(canvas, size, t, intensity);
      case StageEffect.breathingGlow:
        _breathingGlow(canvas, size, t, intensity);
      case StageEffect.waveformBars:
        _waveform(canvas, size, t, intensity, mirrored: true);
      case StageEffect.equalizerBars:
        _waveform(canvas, size, t, intensity, mirrored: false);
      case StageEffect.kaleidoscope:
        _kaleidoscope(canvas, size, t, intensity);
      case StageEffect.heartbeatGlow:
        _heartbeat(canvas, size, t, intensity);
      default:
        return;
    }
  }

  // ---- the declarative field engine ------------------------------------

  static void _paintField(
      Canvas canvas, Size size, _Spec s, double t, double intensity) {
    final w = size.width, h = size.height;
    final count = (s.count * intensity).round().clamp(2, s.count);
    final phase = t / _loop; // 0..1 across the loop
    final paint = Paint()..blendMode = s.blend;
    if (s.blur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, s.blur * w);
    }

    for (var i = 0; i < count; i++) {
      final rx = _rand(i, 1);
      final ry = _rand(i, 2);
      final rs = _rand(i, 3);
      final rp = _rand(i, 4);
      final size0 = (s.sizeMin + (s.sizeMax - s.sizeMin) * rs) * w;

      double x, y;
      var alpha = s.opacity;
      var scale = 1.0;

      switch (s.motion) {
        case _Motion.fall:
          final range = h + size0 * 4;
          y = ((ry * range) + s.cycles * range * phase) % range - size0 * 2;
          x = rx * w +
              _eased(sin(2 * pi * (phase + rp))) * s.drift * w;
        case _Motion.rise:
          final range = h + size0 * 4;
          y = range -
              (((ry * range) + s.cycles * range * phase) % range) -
              size0 * 2;
          x = rx * w + _eased(sin(2 * pi * (phase + rp))) * s.drift * w;
        case _Motion.driftRight:
          final range = w + size0 * 4;
          x = ((rx * range) + s.cycles * range * phase) % range - size0 * 2;
          y = ry * h + _eased(sin(2 * pi * (phase + rp))) * s.drift * h;
        case _Motion.driftLeft:
          final range = w + size0 * 4;
          x = range -
              (((rx * range) + s.cycles * range * phase) % range) -
              size0 * 2;
          y = ry * h + _eased(sin(2 * pi * (phase + rp))) * s.drift * h;
        case _Motion.orbit:
          final cx = s.fromCentre ? w / 2 : rx * w;
          final cy = s.fromCentre ? h / 2 : ry * h;
          final radius = (0.05 + 0.35 * rp) * min(w, h);
          final a = 2 * pi * (s.cycles * phase + rx);
          x = cx + cos(a) * radius;
          y = cy + sin(a) * radius * 0.65;
        case _Motion.burst:
          // Each particle has its own launch offset within the loop, so the
          // burst reads as continuous rather than as one synchronised pop.
          final local = ((phase + rp) % 1.0);
          final maxR = (0.25 + 0.35 * rs) * min(w, h);
          final cx = s.fromCentre ? w / 2 : rx * w;
          final cy = s.fromCentre ? h / 2 : ry * h;
          final a = 2 * pi * rx + local * 0.6;
          x = cx + cos(a) * maxR * local;
          y = cy + sin(a) * maxR * local;
          // fade in fast, out slow, reaching zero exactly at the wrap point
          alpha *= local < 0.12 ? local / 0.12 : (1 - (local - 0.12) / 0.88);
          scale = 0.4 + local * 0.9;
        case _Motion.twinkle:
          x = rx * w;
          y = ry * h;
          final cyc = 1 + (i % max(1, s.cycles));
          alpha *= 0.25 +
              0.75 * (0.5 + 0.5 * sin(2 * pi * cyc * phase + rp * 2 * pi));
        case _Motion.wander:
          final cyc = 1 + (i % 2);
          x = rx * w +
              _eased(sin(2 * pi * cyc * phase + rp * 2 * pi)) * w * 0.05;
          y = ry * h +
              _eased(cos(2 * pi * (cyc + 1) * phase + rp * 3)) * h * 0.04;
          alpha *= 0.6 + 0.4 * (0.5 + 0.5 * sin(2 * pi * phase + rp * 6));
        case _Motion.sway:
          x = rx * w + _eased(sin(2 * pi * s.cycles * phase + rp * 2 * pi)) * w * 0.03;
          y = ry * h;
          alpha *= 0.5 + 0.5 * (0.5 + 0.5 * sin(2 * pi * s.cycles * phase + rp * 5));
        case _Motion.zoom:
          final local = (phase + rp) % 1.0;
          final a = 2 * pi * rx;
          final dist = local * min(w, h) * 0.75;
          x = w / 2 + cos(a) * dist;
          y = h / 2 + sin(a) * dist;
          alpha *= local < 0.15 ? local / 0.15 : (1 - (local - 0.15) / 0.85);
          scale = 0.3 + local * 1.6;
      }

      if (alpha <= 0.001) continue;
      paint.color = _lerpC(s.colorA, s.colorB, _rand(i, 5))
          .withValues(alpha: (alpha * intensity).clamp(0.0, 1.0));
      final rot = s.spin == 0
          ? 0.0
          : 2 * pi * s.spin * phase + rp * 2 * pi;
      _drawShape(canvas, paint, s.shape, Offset(x, y), size0 * scale, rot, w);
    }
  }

  static void _drawShape(Canvas canvas, Paint paint, _Shape shape, Offset at,
      double r, double rot, double frameW) {
    switch (shape) {
      case _Shape.dot:
      case _Shape.softDot:
        canvas.drawCircle(at, r, paint);
      case _Shape.ring:
        canvas.drawCircle(
          at,
          r,
          Paint()
            ..color = paint.color
            ..blendMode = paint.blendMode
            ..maskFilter = paint.maskFilter
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.0, r * 0.14),
        );
      case _Shape.line:
        canvas.drawLine(at, at + Offset(0, r * 5), paint..strokeWidth = max(1.0, r * 0.7));
      case _Shape.streak:
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(rot == 0 ? 0.35 : rot);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(-r * 0.12, 0, r * 0.24, r * 4),
            Radius.circular(r * 0.12),
          ),
          paint,
        );
        canvas.restore();
      case _Shape.star4:
        _star(canvas, paint, at, r, 4, rot, 0.32);
      case _Shape.star5:
        _star(canvas, paint, at, r, 5, rot, 0.45);
      case _Shape.star6:
        _star(canvas, paint, at, r, 6, rot, 0.5);
      case _Shape.star8:
        _star(canvas, paint, at, r, 8, rot, 0.52);
      case _Shape.petal:
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(rot);
        canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: r * 1.1, height: r * 2.0),
            paint);
        canvas.restore();
      case _Shape.leaf:
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(rot);
        final p = Path()
          ..moveTo(0, -r)
          ..quadraticBezierTo(r * 0.9, 0, 0, r)
          ..quadraticBezierTo(-r * 0.9, 0, 0, -r)
          ..close();
        canvas.drawPath(p, paint);
        canvas.restore();
      case _Shape.square:
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(rot);
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: r * 1.6, height: r * 1.6),
            paint);
        canvas.restore();
      case _Shape.diamond:
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(rot + pi / 4);
        canvas.drawRect(
            Rect.fromCenter(center: Offset.zero, width: r * 1.4, height: r * 1.4),
            paint);
        canvas.restore();
      case _Shape.crescent:
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(rot);
        // A crescent is one disc minus a disc offset from it.
        final outer = Path()
          ..addOval(Rect.fromCircle(center: Offset.zero, radius: r));
        final inner = Path()
          ..addOval(
              Rect.fromCircle(center: Offset(r * 0.42, 0), radius: r * 0.86));
        canvas.drawPath(
            Path.combine(PathOperation.difference, outer, inner), paint);
        canvas.restore();
      case _Shape.triangle:
        canvas.save();
        canvas.translate(at.dx, at.dy);
        canvas.rotate(rot);
        final p = Path()
          ..moveTo(0, -r)
          ..lineTo(r * 0.87, r * 0.5)
          ..lineTo(-r * 0.87, r * 0.5)
          ..close();
        canvas.drawPath(p, paint);
        canvas.restore();
      case _Shape.bar:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: at, width: r * 4, height: max(1.0, frameW * 0.0015)),
            Radius.circular(frameW * 0.001),
          ),
          paint,
        );
    }
  }

  static void _star(Canvas canvas, Paint paint, Offset c, double r, int points,
      double rot, double innerRatio) {
    final path = Path();
    final step = pi / points;
    for (var i = 0; i < points * 2; i++) {
      final rad = i.isEven ? r : r * innerRatio;
      final a = i * step + rot - pi / 2;
      final p = c + Offset(cos(a), sin(a)) * rad;
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  // ---- bespoke painters -------------------------------------------------

  static void _warmGodRays(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final origin = Offset(w * 0.7, -h * 0.1);
    for (var i = 0; i < 7; i++) {
      final base = -0.9 + 0.28 * i;
      final sway = _eased(sin(2 * pi * (1 + i % 2) * phase + i)) * 0.05;
      final a = base + sway;
      final breath = 0.55 + 0.45 * (0.5 + 0.5 * sin(2 * pi * phase + i * 1.3));
      final width = w * (0.05 + 0.03 * _rand(i, 1));
      final far = origin + Offset(sin(a), cos(a)) * (h * 1.7);
      final path = Path()
        ..moveTo(origin.dx - width * 0.2, origin.dy)
        ..lineTo(origin.dx + width * 0.2, origin.dy)
        ..lineTo(far.dx + width, far.dy)
        ..lineTo(far.dx - width, far.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.03)
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFFFE3AE).withValues(alpha: 0.20 * breath * k),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    }
  }

  static void _lightLeak(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    // Two warm washes entering from opposite corners, crossing once per loop.
    for (var i = 0; i < 2; i++) {
      final dir = i == 0 ? 1.0 : -1.0;
      final travel = _eased(sin(2 * pi * phase + i * pi));
      final cx = w * (0.5 + dir * (0.45 + 0.12 * travel));
      final cy = h * (i == 0 ? 0.18 : 0.82);
      canvas.drawCircle(
        Offset(cx, cy),
        w * 0.55,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = RadialGradient(
            colors: [
              (i == 0 ? const Color(0xFFFF9A6B) : const Color(0xFFFFD08A))
                  .withValues(alpha: 0.22 * k),
              Colors.transparent,
            ],
          ).createShader(
              Rect.fromCircle(center: Offset(cx, cy), radius: w * 0.55)),
      );
    }
  }

  static void _lensFlare(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final src = Offset(w * (0.25 + 0.5 * (0.5 + 0.5 * sin(2 * pi * phase))),
        h * 0.28);
    final centre = Offset(w / 2, h / 2);
    canvas.drawCircle(
      src,
      w * 0.10,
      Paint()
        ..blendMode = BlendMode.plus
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.04)
        ..color = _white.withValues(alpha: 0.35 * k),
    );
    // Ghosts marching along the line from the source through the centre.
    for (var i = 1; i <= 6; i++) {
      final f = i / 3.0;
      final p = src + (centre - src) * f * 1.6;
      final r = w * (0.012 + 0.02 * _rand(i, 2));
      canvas.drawCircle(
        p,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..color = _lerpC(_goldBright, _sky, _rand(i, 3))
              .withValues(alpha: 0.16 * k),
      );
    }
  }

  static void _aurora(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    for (var band = 0; band < 3; band++) {
      final path = Path();
      final yBase = h * (0.16 + 0.12 * band);
      final amp = h * (0.05 + 0.02 * band);
      path.moveTo(0, yBase);
      for (double x = 0; x <= w; x += w / 40) {
        final y = yBase +
            sin(2 * pi * (x / w * (1 + band) + phase + band * 0.3)) * amp;
        path.lineTo(x, y);
      }
      path.lineTo(w, h * 0.72);
      path.lineTo(0, h * 0.72);
      path.close();
      canvas.drawPath(
        path,
        Paint()
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.05)
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              [_emerald, _sky, _violet][band].withValues(alpha: 0.22 * k),
              Colors.transparent,
            ],
          ).createShader(Rect.fromLTWH(0, 0, w, h)),
      );
    }
  }

  static void _spotlightSweep(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final cx = w * (0.5 + 0.42 * _eased(sin(2 * pi * phase)));
    canvas.drawCircle(
      Offset(cx, h * 0.45),
      w * 0.42,
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            _parchment.withValues(alpha: 0.20 * k),
            Colors.transparent,
          ],
        ).createShader(
            Rect.fromCircle(center: Offset(cx, h * 0.45), radius: w * 0.42)),
    );
  }

  static void _arabesqueTile(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final cell = w / 5;
    final breathe = 0.6 + 0.4 * (0.5 + 0.5 * sin(2 * pi * phase));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, w * 0.0016)
      ..color = _gold.withValues(alpha: 0.22 * breathe * k);
    for (double y = -cell; y < h + cell; y += cell) {
      for (double x = -cell; x < w + cell; x += cell) {
        final c = Offset(x + cell / 2, y + cell / 2);
        _star(canvas, paint, c, cell * 0.42, 8, phase * 2 * pi * 0.25, 0.52);
        canvas.drawCircle(c, cell * 0.17, paint);
      }
    }
  }

  static void _mashrabiya(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final cell = w / 9;
    final glow = 0.5 + 0.5 * (0.5 + 0.5 * sin(2 * pi * phase));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, w * 0.0022)
      ..color = _gold.withValues(alpha: 0.20 * glow * k);
    for (double y = 0; y < h + cell; y += cell) {
      for (double x = 0; x < w + cell; x += cell) {
        final c = Offset(x, y);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(pi / 4);
        canvas.drawRect(
          Rect.fromCenter(
              center: Offset.zero, width: cell * 0.72, height: cell * 0.72),
          paint,
        );
        canvas.restore();
      }
    }
  }

  static void _kufiGrid(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final cell = w / 12;
    for (var gy = 0; gy * cell < h + cell; gy++) {
      for (var gx = 0; gx * cell < w + cell; gx++) {
        // A deterministic on/off pattern, breathing in and out of visibility
        // in blocks — the look of square Kufic without pretending to spell
        // anything, which would be the wrong thing to fake.
        final on = _rand(gx * 31 + gy, 7) > 0.55;
        if (!on) continue;
        final localPhase = ((phase + _rand(gx + gy * 17, 9)) % 1.0);
        final a = 0.18 * (0.5 + 0.5 * sin(2 * pi * localPhase)) * k;
        canvas.drawRect(
          Rect.fromLTWH(gx * cell, gy * cell, cell * 0.9, cell * 0.9),
          Paint()..color = _gold.withValues(alpha: a),
        );
      }
    }
  }

  static void _borderOrnament(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final inset = w * 0.045;
    final glow = 0.55 + 0.45 * (0.5 + 0.5 * sin(2 * pi * phase));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, w * 0.0025)
      ..color = _gold.withValues(alpha: 0.55 * glow * k);
    final r = Rect.fromLTWH(inset, inset, w - inset * 2, h - inset * 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(r, Radius.circular(w * 0.03)), paint);
    canvas.drawRRect(
      RRect.fromRectAndRadius(r.deflate(w * 0.012), Radius.circular(w * 0.025)),
      paint..strokeWidth = max(1.0, w * 0.0012),
    );
    // Corner rosettes
    for (final c in [
      r.topLeft,
      r.topRight,
      r.bottomLeft,
      r.bottomRight,
    ]) {
      _star(canvas, paint, c, w * 0.022, 8, phase * 2 * pi, 0.5);
    }
  }

  static void _domeArch(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final glow = 0.5 + 0.5 * (0.5 + 0.5 * sin(2 * pi * phase));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, w * 0.004)
      ..color = _gold.withValues(alpha: 0.45 * glow * k);
    final cx = w / 2;
    final base = h * 0.86;
    final archW = w * 0.62;
    final springLine = h * 0.46;
    final path = Path()
      ..moveTo(cx - archW / 2, base)
      ..lineTo(cx - archW / 2, springLine)
      // pointed (two-centred) arch, not a semicircle
      ..quadraticBezierTo(cx - archW * 0.30, h * 0.16, cx, h * 0.10)
      ..quadraticBezierTo(cx + archW * 0.30, h * 0.16, cx + archW / 2, springLine)
      ..lineTo(cx + archW / 2, base);
    canvas.drawPath(path, paint);
  }

  static void _tessellation(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final r = w / 10;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.0, w * 0.0016)
      ..color = _gold.withValues(
          alpha: 0.18 * (0.6 + 0.4 * sin(2 * pi * phase)) * k);
    final dx = r * 1.5, dy = r * sqrt(3);
    for (var col = -1; col * dx < w + dx; col++) {
      for (var row = -1; row * dy < h + dy; row++) {
        final cx = col * dx;
        final cy = row * dy + (col.isOdd ? dy / 2 : 0);
        final path = Path();
        for (var i = 0; i < 6; i++) {
          final a = pi / 3 * i;
          final p = Offset(cx + cos(a) * r, cy + sin(a) * r);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  static void _minaretSilhouette(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final skyline = h * 0.92;
    final paint = Paint()
      ..color = const Color(0xFF061512)
          .withValues(alpha: (0.55 + 0.15 * sin(2 * pi * phase)) * k);
    // Dome
    canvas.drawPath(
      Path()
        ..moveTo(w * 0.30, skyline)
        ..lineTo(w * 0.30, h * 0.74)
        ..quadraticBezierTo(w * 0.44, h * 0.56, w * 0.58, h * 0.74)
        ..lineTo(w * 0.58, skyline)
        ..close(),
      paint,
    );
    // Two minarets
    for (final x in [w * 0.20, w * 0.70]) {
      canvas.drawRect(
          Rect.fromLTWH(x, h * 0.52, w * 0.035, skyline - h * 0.52), paint);
      canvas.drawPath(
        Path()
          ..moveTo(x - w * 0.012, h * 0.52)
          ..lineTo(x + w * 0.035 / 2, h * 0.44)
          ..lineTo(x + w * 0.047, h * 0.52)
          ..close(),
        paint,
      );
    }
    canvas.drawRect(Rect.fromLTWH(0, skyline, w, h - skyline), paint);
  }

  static void _spiralGalaxy(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final c = Offset(w / 2, h / 2);
    final paint = Paint()..blendMode = BlendMode.plus;
    const arms = 3, perArm = 44;
    for (var a = 0; a < arms; a++) {
      for (var i = 0; i < perArm; i++) {
        final f = i / perArm;
        final angle = 2 * pi * (a / arms) + f * 3.2 + 2 * pi * phase;
        final radius = f * min(w, h) * 0.46;
        final p = c + Offset(cos(angle), sin(angle) * 0.6) * radius;
        paint.color = _lerpC(_goldBright, _sky, f)
            .withValues(alpha: (0.55 * (1 - f) + 0.08) * k);
        canvas.drawCircle(p, w * (0.0035 * (1 - f) + 0.0008), paint);
      }
    }
  }

  static void _ripples(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final c = Offset(w / 2, h * 0.55);
    const rings = 5;
    for (var i = 0; i < rings; i++) {
      final local = ((phase + i / rings) % 1.0);
      final r = local * min(w, h) * 0.55;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.0, w * 0.003 * (1 - local))
          ..color = _goldBright.withValues(alpha: 0.45 * (1 - local) * k),
      );
    }
  }

  static void _plasmaWave(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    for (var band = 0; band < 5; band++) {
      final path = Path();
      final yBase = h * (0.15 + 0.17 * band);
      path.moveTo(0, yBase);
      for (double x = 0; x <= w; x += w / 48) {
        final y = yBase +
            sin(2 * pi * (x / w * 2 + phase * (1 + band % 2))) * h * 0.035 +
            cos(2 * pi * (x / w * 3 - phase)) * h * 0.02;
        path.lineTo(x, y);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(1.0, w * 0.0035)
          ..blendMode = BlendMode.plus
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.006)
          ..color = _lerpC(_violet, _sky, band / 4).withValues(alpha: 0.35 * k),
      );
    }
  }

  static void _filmGrain(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    // Grain must differ every frame or it reads as dirt on the lens, so the
    // salt is derived from the quantised frame index — still deterministic,
    // and identical in preview and export.
    final frame = (t * StageEffects.exportFps).round();
    final count = (2200 * k).round();
    final paint = Paint();
    for (var i = 0; i < count; i++) {
      final x = _rand(i, frame * 3 + 1) * w;
      final y = _rand(i, frame * 3 + 2) * h;
      final v = _rand(i, frame * 3 + 3);
      paint.color = (v > 0.5 ? _white : Colors.black)
          .withValues(alpha: 0.10 * k);
      canvas.drawRect(Rect.fromLTWH(x, y, w * 0.0015, w * 0.0015), paint);
    }
  }

  static void _scanLines(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final gap = h / 160;
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.20 * k);
    for (double y = 0; y < h; y += gap) {
      canvas.drawRect(Rect.fromLTWH(0, y, w, gap * 0.45), paint);
    }
    // One brighter band rolling down the frame, once per loop. Drawn twice,
    // a full frame-height apart: as the band leaves the bottom edge its copy
    // is entering from the top, so the wrap is continuous. Drawing it once
    // left a sliver at the bottom on the last frame and a sliver at the top
    // on the first, which is a visible flick at the seam.
    final bandY = phase * h;
    final band = Paint()
      ..blendMode = BlendMode.plus
      ..color = _white.withValues(alpha: 0.05 * k);
    for (final y in [bandY, bandY - h]) {
      canvas.drawRect(Rect.fromLTWH(0, y - h * 0.02, w, h * 0.04), band);
    }
  }

  static void _vhsTracking(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    _scanLines(canvas, size, t, k * 0.6);
    // Torn tracking bands that jitter horizontally.
    for (var i = 0; i < 4; i++) {
      final y = ((phase * (1 + i) + _rand(i, 1)) % 1.0) * h;
      final bh = h * (0.006 + 0.02 * _rand(i, 2));
      final dx = (_rand(i, (t * 12).round() + 3) - 0.5) * w * 0.05;
      canvas.drawRect(
        Rect.fromLTWH(dx, y, w, bh),
        Paint()
          ..blendMode = BlendMode.plus
          ..color = _white.withValues(alpha: 0.10 * k),
      );
      canvas.drawRect(
        Rect.fromLTWH(dx + w * 0.01, y, w, bh * 0.5),
        Paint()
          ..blendMode = BlendMode.plus
          ..color = const Color(0xFFFF4D6D).withValues(alpha: 0.07 * k),
      );
    }
  }

  static void _filmScratches(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final frame = (t * StageEffects.exportFps).round();
    for (var i = 0; i < 5; i++) {
      // A scratch persists for a few frames then jumps — the way real
      // emulsion damage behaves on a moving strip.
      final seed = frame ~/ 3 + i * 17;
      if (_rand(seed, 11) < 0.45) continue;
      final x = _rand(seed, 12) * w;
      canvas.drawRect(
        Rect.fromLTWH(x, 0, max(1.0, w * 0.0012), h),
        Paint()..color = _white.withValues(alpha: 0.16 * k),
      );
    }
  }

  static void _halftone(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final gap = w / 46;
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.16 * k);
    for (double y = 0; y < h + gap; y += gap) {
      for (double x = 0; x < w + gap; x += gap) {
        final d = ((x / w) + (y / h)) / 2;
        final r = gap * 0.42 * (0.35 + 0.65 * (0.5 + 0.5 * sin(2 * pi * (phase + d))));
        canvas.drawCircle(Offset(x, y), r, paint);
      }
    }
  }

  static void _duotoneSweep(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final shift = _eased(sin(2 * pi * phase));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..blendMode = BlendMode.overlay
        ..shader = LinearGradient(
          begin: Alignment(-1 + shift, -1),
          end: Alignment(1 + shift, 1),
          colors: [
            _emerald.withValues(alpha: 0.35 * k),
            _gold.withValues(alpha: 0.30 * k),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  static void _chromaticDrift(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final off = _eased(sin(2 * pi * phase)) * w * 0.006;
    canvas.drawRect(
      Rect.fromLTWH(off, 0, w, h),
      Paint()
        ..blendMode = BlendMode.plus
        ..color = const Color(0xFFFF2D55).withValues(alpha: 0.06 * k),
    );
    canvas.drawRect(
      Rect.fromLTWH(-off, 0, w, h),
      Paint()
        ..blendMode = BlendMode.plus
        ..color = const Color(0xFF2DE1FF).withValues(alpha: 0.06 * k),
    );
  }

  static void _vignettePulse(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final tightness = 0.55 + 0.12 * sin(2 * pi * phase);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = RadialGradient(
          radius: 0.95,
          colors: [Colors.transparent, Colors.black.withValues(alpha: 0.55 * k)],
          stops: [tightness, 1.0],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  static void _breathingGlow(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    // 4-count in, 4-count out — a breath, not a strobe.
    final breath = 0.5 + 0.5 * sin(2 * pi * phase - pi / 2);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          colors: [
            _gold.withValues(alpha: 0.16 * breath * k),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  static void _heartbeat(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    // Two beats per loop, the second softer — lub-dub.
    double thump(double p) => exp(-pow(p, 2) * 90).toDouble();
    final beat = thump((phase % 0.5) - 0.10) + 0.55 * thump((phase % 0.5) - 0.22);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..blendMode = BlendMode.plus
        ..shader = RadialGradient(
          radius: 0.9,
          colors: [
            Colors.transparent,
            _gold.withValues(alpha: 0.28 * beat.clamp(0.0, 1.0) * k),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
  }

  static void _waveform(Canvas canvas, Size size, double t, double k,
      {required bool mirrored}) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    const bars = 42;
    final barW = w / (bars * 1.6);
    final baseY = mirrored ? h * 0.5 : h * 0.9;
    for (var i = 0; i < bars; i++) {
      // Each bar has its own frequency and phase, so the row moves like an
      // analyser rather than a single travelling sine.
      final f = 1 + (i % 4);
      final amp = (0.25 +
              0.75 *
                  (0.5 + 0.5 * sin(2 * pi * f * phase + _rand(i, 1) * 2 * pi)))
          .clamp(0.0, 1.0);
      final barH = h * 0.16 * amp * k;
      final x = w * 0.08 + i * (w * 0.84 / bars);
      final rect = mirrored
          ? Rect.fromCenter(
              center: Offset(x, baseY), width: barW, height: barH * 2)
          : Rect.fromLTWH(x - barW / 2, baseY - barH, barW, barH);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(barW * 0.4)),
        Paint()
          ..blendMode = BlendMode.plus
          ..color = _lerpC(_gold, _goldBright, amp).withValues(alpha: 0.55 * k),
      );
    }
  }

  static void _kaleidoscope(Canvas canvas, Size size, double t, double k) {
    final w = size.width, h = size.height;
    final phase = t / _loop;
    final c = Offset(w / 2, h / 2);
    const wedges = 8;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(2 * pi * phase);
    for (var s = 0; s < wedges; s++) {
      canvas.save();
      canvas.rotate(2 * pi * s / wedges);
      if (s.isOdd) canvas.scale(1, -1); // mirror alternate wedges
      for (var i = 0; i < 9; i++) {
        final r = min(w, h) * (0.06 + 0.045 * i);
        final a = 0.35 * sin(2 * pi * (phase + i / 9));
        final p = Offset(cos(a) * r, sin(a) * r);
        canvas.drawCircle(
          p,
          w * (0.004 + 0.006 * _rand(i, 3)),
          Paint()
            ..blendMode = BlendMode.plus
            ..color = _lerpC(_goldBright, _emerald, i / 9)
                .withValues(alpha: 0.45 * k),
        );
      }
      canvas.restore();
    }
    canvas.restore();
  }
}
