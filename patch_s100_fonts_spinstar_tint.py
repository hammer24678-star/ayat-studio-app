#!/usr/bin/env python3
"""
PATCH_S100_FONTS_SPINSTAR_TINT
================================

Three independent additions bundled into one patch (each guarded and
idempotent on its own, same as every other S-series script):

1. FONTS -- bundles the two .ttf files you dropped into
   /storage/emulated/0/Download/Telegram/ as built-in ayah fonts,
   alongside Elgharib/Amiri/Ruqaa, and makes "DigitalMadina" the new
   default font (kept Elgharib as a selectable option, just no longer
   the one that's pre-selected). If you actually meant TharwatEmara as
   the default instead, flip DEFAULT_FONT_KEY below and re-run -- this
   patch is idempotent either way.

2. SPINNING STAR EFFECT -- a new StageEffect, distinct from the
   existing geometricShimmer (a whole *grid* of small counter-rotating
   motifs). This is a small number of large, prominent 8-pointed
   (rub el hizb) stars that continuously spin in place with a soft
   gold glow -- reuses the existing _drawEightPointStar primitive so it
   matches the app's established Islamic-geometric look.

3. CUSTOM TINT -- a color tint on the exported video, independent of
   the existing warmGold/nightTeal color-grade presets. Ships with
   quick "Blue" and "Gold" swatches (per your request) but is backed by
   the app's existing showAyatColorPicker, so it supports ANY color,
   not just those two. Implemented as an ffmpeg colorbalance filter
   (mirrors how warmGold/nightTeal already push channel balance) so it
   slots into the existing single -vf post-filter chain with no new
   filter_complex plumbing, and a matching live-preview overlay.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s100_fonts_spinstar_tint.py <project_root>
"""
import shutil
import sys
import pathlib

MARKER = "PATCH_S100_FONTS_SPINSTAR_TINT"

# Change this if you meant the other font as the default.
DEFAULT_FONT_KEY = "digitalmadina"  # or "tharwatemara"

# Where you said the two files landed on the phone.
SOURCE_DIR = pathlib.Path("/storage/emulated/0/Download/Telegram")
SOURCE_FONTS = {
    "tharwatemara": ("TEHAFS2TharwatEmara.ttf", "TharwatEmara"),
    "digitalmadina": ("DigitalMadina-NON V1.ttf", "DigitalMadinaNON"),
}


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")

    if new.strip() in text:
        print(f"  SKIP  ({label}): already applied")
        return False

    count = text.count(old)
    if count == 0:
        raise SystemExit(
            f"ERROR ({label}): expected old text not found in {path}. "
            f"File may have drifted since this patch was written -- "
            f"aborting instead of guessing."
        )
    if count > 1:
        raise SystemExit(
            f"ERROR ({label}): old text found {count} times in {path}, "
            f"expected exactly 1 -- refusing to guess which one."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  OK    ({label}): patched")
    return True


# ---------------------------------------------------------------------
# 0. Copy the two font files onto disk, into assets/fonts/
# ---------------------------------------------------------------------
def copy_fonts(root: pathlib.Path):
    fonts_dir = root / "assets" / "fonts"
    fonts_dir.mkdir(parents=True, exist_ok=True)
    for key, (src_name, family) in SOURCE_FONTS.items():
        src = SOURCE_DIR / src_name
        dest = fonts_dir / f"{family}.ttf"
        if dest.exists():
            print(f"  SKIP  (copy {family}.ttf): already in assets/fonts/")
            continue
        if not src.exists():
            print(f"  WARN  (copy {family}.ttf): source not found at {src} -- "
                  f"copy it into {dest} yourself before building.")
            continue
        shutil.copy2(src, dest)
        print(f"  OK    (copy {family}.ttf): {src} -> {dest}")


# ---------------------------------------------------------------------
# 1. pubspec.yaml -- register both font families
# ---------------------------------------------------------------------
def patch_pubspec(root: pathlib.Path):
    path = root / "pubspec.yaml"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    old = """  # PATCH_S46_DEFAULT_FONT_AND_GLOW: bundled default ayah font (place the .ttf file at
  # assets/fonts/Elgharib-NoonHafs.ttf -- not committed by this script).
  fonts:
    - family: ElgharibNoonHafs
      fonts:
        - asset: assets/fonts/Elgharib-NoonHafs.ttf
"""

    new = """  # PATCH_S46_DEFAULT_FONT_AND_GLOW: bundled default ayah font (place the .ttf file at
  # assets/fonts/Elgharib-NoonHafs.ttf -- not committed by this script).
  fonts:
    - family: ElgharibNoonHafs
      fonts:
        - asset: assets/fonts/Elgharib-NoonHafs.ttf
    # PATCH_S100_FONTS_SPINSTAR_TINT: two more bundled ayah fonts, copied in
    # from the phone's Download/Telegram folder by this patch script.
    - family: TharwatEmara
      fonts:
        - asset: assets/fonts/TharwatEmara.ttf
    - family: DigitalMadinaNON
      fonts:
        - asset: assets/fonts/DigitalMadinaNON.ttf
"""

    replace_once(path, old, new, "pubspec.yaml: register TharwatEmara + DigitalMadinaNON fonts")


# ---------------------------------------------------------------------
# 2. lib/data/studio_presets.dart -- kBuiltInFonts list
# ---------------------------------------------------------------------
def patch_presets(root: pathlib.Path):
    path = root / "lib" / "data" / "studio_presets.dart"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    old = """const List<AyahFontChoice> kBuiltInFonts = [
  // PATCH_S46_DEFAULT_FONT_AND_GLOW: bundled Quran font, now the app default.
  AyahFontChoice('elgharib', 'الغريب نون حفص (افتراضي)'),
  AyahFontChoice('amiri', 'أميري قرآن (كلاسيكي)'),
  AyahFontChoice('ruqaa', 'ريقعة (خط الرقعة)'),
];"""

    new = """const List<AyahFontChoice> kBuiltInFonts = [
  // PATCH_S100_FONTS_SPINSTAR_TINT: DigitalMadina is now the app default;
  // Elgharib stays selectable, just no longer pre-picked. See
  // studio_state.dart's `fontKey` default and ayat_fonts.dart's
  // ayahTextStyle() for the two new bundled-asset cases.
  AyahFontChoice('elgharib', 'الغريب نون حفص'),
  AyahFontChoice('amiri', 'أميري قرآن (كلاسيكي)'),
  AyahFontChoice('ruqaa', 'ريقعة (خط الرقعة)'),
  AyahFontChoice('tharwatemara', 'ثروت عمارة'),
  AyahFontChoice('digitalmadina', 'المدينة الرقمية (افتراضي)'),
];"""

    replace_once(path, old, new, "studio_presets.dart: add TharwatEmara + DigitalMadina to kBuiltInFonts")


# ---------------------------------------------------------------------
# 3. lib/models/studio_state.dart -- default fontKey + tint fields
# ---------------------------------------------------------------------
def patch_state(root: pathlib.Path):
    path = root / "lib" / "models" / "studio_state.dart"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    # 3a. default font
    old_font = """  // PATCH_S46_DEFAULT_FONT_AND_GLOW: Elgharib-NoonHafs is now the bundled default font.
  String fontKey = 'elgharib';"""
    new_font = f"""  // PATCH_S100_FONTS_SPINSTAR_TINT: DigitalMadina is now the bundled default font
  // (Elgharib was the default from S46 through S99).
  String fontKey = '{DEFAULT_FONT_KEY}';"""
    replace_once(path, old_font, new_font, "studio_state.dart: default fontKey -> DigitalMadina")

    # 3b. tint fields, placed right alongside the existing color-grade fields
    old_tint = """  ColorGrade colorGrade = ColorGrade.none;
  bool vignetteEnabled = false;
  int vignetteIntensity = 50; // 0..100"""
    new_tint = """  ColorGrade colorGrade = ColorGrade.none;
  bool vignetteEnabled = false;
  int vignetteIntensity = 50; // 0..100
  // PATCH_S100_FONTS_SPINSTAR_TINT: a color tint independent of the
  // colorGrade presets above -- null means off. Any color is valid
  // (picked via showAyatColorPicker); blue/gold are just quick presets
  // in the UI, not the only options.
  Color? tintColor;
  int tintIntensity = 45; // 0..100"""
    replace_once(path, old_tint, new_tint, "studio_state.dart: add tintColor + tintIntensity fields")


# ---------------------------------------------------------------------
# 4. lib/theme/ayat_fonts.dart -- resolve the two new font keys
# ---------------------------------------------------------------------
def patch_ayat_fonts(root: pathlib.Path):
    path = root / "lib" / "theme" / "ayat_fonts.dart"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    old = """  switch (fontKey) {
    case 'elgharib': // PATCH_S46_DEFAULT_FONT_AND_GLOW: bundled asset font, not google_fonts
      return base.copyWith(fontFamily: 'ElgharibNoonHafs');
    case 'amiri':
      return GoogleFonts.amiriQuran(textStyle: base);
    case 'ruqaa':
      return GoogleFonts.arefRuqaa(textStyle: base);
    default:"""

    new = """  switch (fontKey) {
    case 'elgharib': // PATCH_S46_DEFAULT_FONT_AND_GLOW: bundled asset font, not google_fonts
      return base.copyWith(fontFamily: 'ElgharibNoonHafs');
    case 'amiri':
      return GoogleFonts.amiriQuran(textStyle: base);
    case 'ruqaa':
      return GoogleFonts.arefRuqaa(textStyle: base);
    // PATCH_S100_FONTS_SPINSTAR_TINT: two more bundled asset fonts.
    case 'tharwatemara':
      return base.copyWith(fontFamily: 'TharwatEmara');
    case 'digitalmadina':
      return base.copyWith(fontFamily: 'DigitalMadinaNON');
    default:"""

    replace_once(path, old, new, "ayat_fonts.dart: resolve tharwatemara/digitalmadina font keys")


# ---------------------------------------------------------------------
# 5. lib/services/stage_effects.dart -- spinningStar effect
# ---------------------------------------------------------------------
def patch_stage_effects(root: pathlib.Path):
    path = root / "lib" / "services" / "stage_effects.dart"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    old_enum = (
        "enum StageEffect { none, rain, snow, dust, sparkle, geometricShimmer, "
        "confetti, glitch, fireflies, fog, rays } // PATCH_S72_GLITCH_EFFECT"
    )
    new_enum = (
        "enum StageEffect { none, rain, snow, dust, sparkle, geometricShimmer, "
        "confetti, glitch, fireflies, fog, rays, spinningStar } "
        "// PATCH_S100_FONTS_SPINSTAR_TINT"
    )
    replace_once(path, old_enum, new_enum, "stage_effects.dart: add spinningStar to StageEffect enum")

    old_label = """        StageEffect.rays => 'أشعة نور', // PATCH_S85_MORE_EFFECTS
      };"""
    new_label = """        StageEffect.rays => 'أشعة نور', // PATCH_S85_MORE_EFFECTS
        StageEffect.spinningStar => 'نجمة إسلامية دوّارة', // PATCH_S100_FONTS_SPINSTAR_TINT
      };"""
    replace_once(path, old_label, new_label, "stage_effects.dart: spinningStar label")

    old_icon = """        StageEffect.rays => Icons.wb_twilight_outlined, // PATCH_S85_MORE_EFFECTS
      };"""
    new_icon = """        StageEffect.rays => Icons.wb_twilight_outlined, // PATCH_S85_MORE_EFFECTS
        StageEffect.spinningStar => Icons.star_rate_rounded, // PATCH_S100_FONTS_SPINSTAR_TINT
      };"""
    replace_once(path, old_icon, new_icon, "stage_effects.dart: spinningStar icon")

    old_dispatch = """      case StageEffect.rays: // PATCH_S85_MORE_EFFECTS
        _paintRays(canvas, size, timeSec, intensity);
    }
  }"""
    new_dispatch = """      case StageEffect.rays: // PATCH_S85_MORE_EFFECTS
        _paintRays(canvas, size, timeSec, intensity);
      case StageEffect.spinningStar: // PATCH_S100_FONTS_SPINSTAR_TINT
        _paintSpinningStar(canvas, size, timeSec, intensity);
    }
  }"""
    replace_once(path, old_dispatch, new_dispatch, "stage_effects.dart: dispatch spinningStar")

    # New painter, inserted right after _drawEightPointStar so it can reuse it.
    old_after_star = """    canvas.drawPath(square(pi / 4), paint);
    canvas.drawPath(square(0), paint);
  }"""
    new_after_star = """    canvas.drawPath(square(pi / 4), paint);
    canvas.drawPath(square(0), paint);
  }

  // PATCH_S100_FONTS_SPINSTAR_TINT: a handful of large, prominent 8-pointed
  // (rub el hizb) stars that continuously spin in place with a soft gold
  // glow -- unlike geometricShimmer's grid of small counter-rotating
  // motifs, this is meant to read as a few clear focal stars rather than a
  // background texture. Whole rotations per loop keep the export tile
  // seamless, same convention as every other effect here.
  static void _paintSpinningStar(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    // Anchor positions kept fixed (not random) so the composition reads as
    // deliberate corners/accents rather than scattered clutter.
    final anchors = [
      Offset(w * 0.18, h * 0.16),
      Offset(w * 0.82, h * 0.20),
      Offset(w * 0.50, h * 0.82),
    ];
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5.0 * w / 1080);
    final corePaint = Paint()..style = PaintingStyle.stroke;
    for (var i = 0; i < anchors.length; i++) {
      final phase = _rand(i, 9) * 2 * pi;
      // gentle pulse so the stars breathe rather than sit static
      final pulse = 0.6 + 0.4 * sin(2 * pi * t / loopSeconds + phase);
      final r = (i == 1 ? 0.09 : 0.065) * w;
      final angle = 2 * pi * t / loopSeconds * (i.isEven ? 1 : -1) + phase;
      final alpha = (0.55 + 0.25 * pulse) * intensity;
      glowPaint
        ..color = const Color(0xFFECC875).withValues(alpha: alpha * 0.65)
        ..strokeWidth = max(1.5, w / 260);
      corePaint
        ..color = const Color(0xFFFFF3D6).withValues(alpha: alpha)
        ..strokeWidth = max(1.0, w / 480);
      canvas.save();
      canvas.translate(anchors[i].dx, anchors[i].dy);
      canvas.rotate(angle);
      _drawEightPointStar(canvas, glowPaint, r * (0.95 + 0.1 * pulse));
      _drawEightPointStar(canvas, corePaint, r * (0.95 + 0.1 * pulse));
      canvas.restore();
    }
  }"""
    replace_once(path, old_after_star, new_after_star, "stage_effects.dart: insert _paintSpinningStar")


# ---------------------------------------------------------------------
# 6. lib/services/export_service.dart -- tint ffmpeg filter
# ---------------------------------------------------------------------
def patch_export_service(root: pathlib.Path):
    path = root / "lib" / "services" / "export_service.dart"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    old = """  static String _grainFilter(int intensity) {
    final amt = (intensity.clamp(0, 100) / 100 * 26 + 4).round();
    return 'noise=alls=$amt:allf=t+u';
  }

  // Combined color-grade + vignette + grain chain, shared by the main clip
  // and the bismillah/outro title cards so a chosen look stays consistent
  // across all exported segments. Empty string when nothing is enabled.
  static String _postFilterChain(StudioState state) {
    final parts = <String>[];
    final grade = _colorGradeFilter(state.colorGrade);
    if (grade.isNotEmpty) parts.add(grade);
    // PATCH_S85_VIDEO_ADJUST: manual sliders stack on top of the preset
    // grade, mirroring the preview's nested ColorFiltered order.
    if (state.hasManualAdjust) {
      parts.add('eq=brightness=${state.adjustBrightness.toStringAsFixed(3)}'
          ':contrast=${state.adjustContrast.toStringAsFixed(3)}'
          ':saturation=${state.adjustSaturation.toStringAsFixed(3)}');
    }
    if (state.vignetteEnabled) {
      parts.add(_vignetteFilter(state.vignetteIntensity));
    }
    if (state.grainEnabled) parts.add(_grainFilter(state.grainIntensity));
    return parts.join(',');
  }"""

    new = """  static String _grainFilter(int intensity) {
    final amt = (intensity.clamp(0, 100) / 100 * 26 + 4).round();
    return 'noise=alls=$amt:allf=t+u';
  }

  // PATCH_S100_FONTS_SPINSTAR_TINT: any-color tint, independent of the
  // colorGrade presets above. Decomposes the target color into
  // colorbalance's midtone offsets (same technique warmGold/nightTeal
  // already use for their push), scaled by intensity -- so this works for
  // literally any Color, not just the two quick blue/gold presets in the UI.
  static String _tintFilter(Color color, int intensity) {
    final strength = intensity.clamp(0, 100) / 100;
    double channel(int value) =>
        (((value - 128) / 128) * strength).clamp(-1.0, 1.0);
    final rm = channel(color.red);
    final gm = channel(color.green);
    final bm = channel(color.blue);
    return 'colorbalance=rm=${rm.toStringAsFixed(3)}'
        ':gm=${gm.toStringAsFixed(3)}'
        ':bm=${bm.toStringAsFixed(3)}';
  }

  // Combined color-grade + tint + vignette + grain chain, shared by the
  // main clip and the bismillah/outro title cards so a chosen look stays
  // consistent across all exported segments. Empty string when nothing is
  // enabled.
  static String _postFilterChain(StudioState state) {
    final parts = <String>[];
    final grade = _colorGradeFilter(state.colorGrade);
    if (grade.isNotEmpty) parts.add(grade);
    // PATCH_S85_VIDEO_ADJUST: manual sliders stack on top of the preset
    // grade, mirroring the preview's nested ColorFiltered order.
    if (state.hasManualAdjust) {
      parts.add('eq=brightness=${state.adjustBrightness.toStringAsFixed(3)}'
          ':contrast=${state.adjustContrast.toStringAsFixed(3)}'
          ':saturation=${state.adjustSaturation.toStringAsFixed(3)}');
    }
    // PATCH_S100_FONTS_SPINSTAR_TINT
    if (state.tintColor != null && state.tintIntensity > 0) {
      parts.add(_tintFilter(state.tintColor!, state.tintIntensity));
    }
    if (state.vignetteEnabled) {
      parts.add(_vignetteFilter(state.vignetteIntensity));
    }
    if (state.grainEnabled) parts.add(_grainFilter(state.grainIntensity));
    return parts.join(',');
  }"""

    replace_once(path, old, new, "export_service.dart: add _tintFilter + wire into _postFilterChain")


# ---------------------------------------------------------------------
# 7. lib/widgets/stage_preview.dart -- live-preview tint overlay
# ---------------------------------------------------------------------
def patch_stage_preview(root: pathlib.Path):
    path = root / "lib" / "widgets" / "stage_preview.dart"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    old = """                if (state.vignetteEnabled)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.9,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(
                                alpha: (state.vignetteIntensity / 100 * 0.55)
                                    .clamp(0.0, 0.55)),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),"""

    new = """                // PATCH_S100_FONTS_SPINSTAR_TINT: sits with vignette/grain in the
                // same "on top of everything, matches the export chain" layer.
                if (state.tintColor != null && state.tintIntensity > 0)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: state.tintColor!.withValues(
                            alpha: (state.tintIntensity / 100 * 0.35)
                                .clamp(0.0, 0.35)),
                        backgroundBlendMode: BlendMode.overlay,
                      ),
                    ),
                  ),
                if (state.vignetteEnabled)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.9,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(
                                alpha: (state.vignetteIntensity / 100 * 0.55)
                                    .clamp(0.0, 0.55)),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),"""

    replace_once(path, old, new, "stage_preview.dart: add live tint overlay")


# ---------------------------------------------------------------------
# 8. lib/screens/home_screen.dart -- tint UI (quick blue/gold + any color)
# ---------------------------------------------------------------------
def patch_home_screen(root: pathlib.Path):
    path = root / "lib" / "screens" / "home_screen.dart"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    old = """        const SizedBox(height: 10),
        ToggleRow(
          label: 'تظليل الحواف (فينيت)',
          value: state.vignetteEnabled,
          onChanged: (v) => state.update(() => state.vignetteEnabled = v),
        ),"""

    new = """        const SizedBox(height: 10),
        // PATCH_S100_FONTS_SPINSTAR_TINT: quick blue/gold presets plus a full
        // color picker (showAyatColorPicker), so any color works, not just
        // the two swatches.
        _fieldLabel('تدرّج بلون مخصص (أزرق / ذهبي / أي لون)'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: () => state.update(() => state.tintColor = null),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: state.tintColor == null
                          ? AyatColors.goldBright
                          : AyatColors.hairline,
                      width: state.tintColor == null ? 2.5 : 1),
                ),
                child: const Icon(Icons.block, size: 16, color: AyatColors.parchmentDim),
              ),
            ),
            for (final preset in const [
              (Color(0xFF2A6FDB), 'أزرق'),
              (Color(0xFFD4A017), 'ذهبي'),
            ])
              GestureDetector(
                onTap: () => state.update(() => state.tintColor = preset.$1),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: preset.$1,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: state.tintColor?.toARGB32() ==
                                preset.$1.toARGB32()
                            ? AyatColors.goldBright
                            : AyatColors.hairline,
                        width: state.tintColor?.toARGB32() ==
                                preset.$1.toARGB32()
                            ? 2.5
                            : 1),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () async {
                final c = await showAyatColorPicker(
                    context, state.tintColor ?? AyatColors.gold);
                if (c != null) state.update(() => state.tintColor = c);
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: state.tintColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AyatColors.goldBright),
                ),
                child: const Icon(Icons.colorize, size: 15, color: Colors.black54),
              ),
            ),
          ],
        ),
        if (state.tintColor != null)
          Slider(
            value: state.tintIntensity.toDouble(),
            min: 0,
            max: 100,
            onChanged: (v) => state.update(() => state.tintIntensity = v.round()),
          ),
        const SizedBox(height: 10),
        ToggleRow(
          label: 'تظليل الحواف (فينيت)',
          value: state.vignetteEnabled,
          onChanged: (v) => state.update(() => state.vignetteEnabled = v),
        ),"""

    replace_once(path, old, new, "home_screen.dart: add tint UI (blue/gold presets + any-color picker)")


# ---------------------------------------------------------------------
# 9. lib/services/settings_service.dart -- persist tintColor/tintIntensity
# ---------------------------------------------------------------------
def patch_settings_service(root: pathlib.Path):
    path = root / "lib" / "services" / "settings_service.dart"
    if not path.exists():
        raise SystemExit(f"ERROR: expected file not found: {path}")

    old_load = """      state.vignetteEnabled =
          read<bool>('vignetteEnabled') ?? state.vignetteEnabled;
      state.vignetteIntensity =
          (read<int>('vignetteIntensity') ?? state.vignetteIntensity)
              .clamp(0, 100);"""
    new_load = """      state.vignetteEnabled =
          read<bool>('vignetteEnabled') ?? state.vignetteEnabled;
      state.vignetteIntensity =
          (read<int>('vignetteIntensity') ?? state.vignetteIntensity)
              .clamp(0, 100);
      // PATCH_S100_FONTS_SPINSTAR_TINT
      final tint = read<int>('tintColor');
      if (tint != null) state.tintColor = Color(tint);
      state.tintIntensity =
          (read<int>('tintIntensity') ?? state.tintIntensity).clamp(0, 100);"""
    replace_once(path, old_load, new_load, "settings_service.dart: load tintColor/tintIntensity")

    old_save = """      p.setBool('${_prefix}vignetteEnabled', state.vignetteEnabled),
      p.setInt('${_prefix}vignetteIntensity', state.vignetteIntensity),"""
    new_save = """      p.setBool('${_prefix}vignetteEnabled', state.vignetteEnabled),
      p.setInt('${_prefix}vignetteIntensity', state.vignetteIntensity),
      // PATCH_S100_FONTS_SPINSTAR_TINT
      if (state.tintColor != null)
        p.setInt('${_prefix}tintColor', state.tintColor!.toARGB32()),
      p.setInt('${_prefix}tintIntensity', state.tintIntensity),"""
    replace_once(path, old_save, new_save, "settings_service.dart: save tintColor/tintIntensity")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 patch_s100_fonts_spinstar_tint.py <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    if not root.exists():
        raise SystemExit(f"ERROR: project root not found: {root}")

    print(f"Patching under: {root}\n")

    print("-- fonts --")
    copy_fonts(root)
    patch_pubspec(root)
    patch_presets(root)
    patch_state(root)
    patch_ayat_fonts(root)

    print("\n-- spinning star effect --")
    patch_stage_effects(root)

    print("\n-- custom tint --")
    patch_export_service(root)
    patch_stage_preview(root)
    patch_home_screen(root)
    patch_settings_service(root)

    print(f"\nDone. {MARKER} applied (or already present).")
    print("\nSanity-check next:")
    print("  1. flutter pub get   (registers the two new font families)")
    print("  2. dart analyze")
    print("  3. New ayah font list should show 5 entries; DigitalMadina")
    print("     pre-selected on a fresh install (existing installs keep")
    print("     whatever font they already had saved).")
    print("  4. Effects picker should show a new 'نجمة إسلامية دوّارة'")
    print("     (Spinning Islamic Star) option -- a few large rotating")
    print("     gold 8-point stars, distinct from the existing shimmer grid.")
    print("  5. Export panel should show a new tint row with a none/blue/gold")
    print("     swatch group plus a color-picker swatch for any other color;")
    print("     confirm the live preview overlay roughly matches the")
    print("     exported MP4's colorbalance tint.")
    print("  6. If DEFAULT_FONT_KEY should be 'tharwatemara' instead, flip it")
    print("     at the top of this script and re-run -- idempotent either way.")


if __name__ == "__main__":
    main()
