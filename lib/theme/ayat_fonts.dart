// One place that maps a font key ('amiri' / 'ruqaa' / uploaded family name)
// to a TextStyle, used by BOTH the live stage preview and the export
// renderer so what you see is exactly what gets burned into the video.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// PATCH_S24_AUTO_SHRINK_LONG_AYAH: long ayahs (Al-Baqarah 282, Al-Ahzab 20, etc.) can run
// 4-6x longer than a typical short surah -- without this, a fixed font
// size either overflows the card or crowds the translation/label
// against the frame edge. Length-based, not real text measurement, but
// cheap and deterministic -- used identically by the live preview
// (stage_preview.dart) and the export renderer (overlay_renderer.dart)
// so what you see matches what gets burned into the video.
double ayahAutoFontScale(String text) {
  final len = text.length;
  if (len <= 60) return 1.0;
  if (len <= 100) return 0.88;
  if (len <= 150) return 0.76;
  if (len <= 220) return 0.66;
  return 0.58;
}

TextStyle ayahTextStyle(
  String fontKey, {
  double? fontSize,
  Color? color,
  double? height,
  List<Shadow>? shadows,
  FontWeight? fontWeight,
  double? letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
}) {
  final base = TextStyle(
    fontSize: fontSize,
    color: color,
    height: height,
    shadows: shadows,
    fontWeight: fontWeight,
    letterSpacing: letterSpacing,
  );
  switch (fontKey) {
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
    // PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: three more bundled fonts.
    case 'digitalkhatt':
      return base.copyWith(fontFamily: 'DigitalKhattNewV2');
    case 'elgharib_a001':
      return base.copyWith(fontFamily: 'ElgharibA001');
    case 'elgharib_lpmq':
      return base.copyWith(fontFamily: 'ElgharibLPMQMisbahTaweel');
    // PATCH_S148_REMAINING_FONTS_AND_SELECTED_CHIP_FIX: 4 more bundled fonts.
    case 'elgharib_a603':
      return base.copyWith(fontFamily: 'ElgharibA603');
    case 'elgharib_eid':
      return base.copyWith(fontFamily: 'ElgharibEidAlAdha');
    case 'elgharib_qcf4':
      return base.copyWith(fontFamily: 'ElgharibQCF4SurahNames');
    case 'pf_monumenta':
      return base.copyWith(fontFamily: 'PFMonumentaPro');
    // PATCH_S145_FONT_BUTTONS_REAL_FONTS: text_editor_pro.dart's quick
    // font row (نسخ/رقعة/أندلس/القلم/الكوفي) set fontKey to these four
    // (ruqaa/amiri_quran already worked) but nothing here ever matched
    // them -- they fell through to `default` and asked for a fontFamily
    // that was never registered anywhere, so every one of those buttons
    // silently rendered in the same fallback system font. Real,
    // visually distinct Google Fonts now -- downloaded on demand the
    // same way amiri/ruqaa above already do, no asset bundling needed.
    // Swap any of these for a different GoogleFonts.xxx() call if you'd
    // rather have a different family for that button.
    case 'naskh':
      return GoogleFonts.notoNaskhArabic(textStyle: base);
    case 'andalus':
      return GoogleFonts.markaziText(textStyle: base);
    case 'qalam':
      return GoogleFonts.qahiri(textStyle: base);
    case 'kufi':
      return GoogleFonts.reemKufi(textStyle: base);
    case 'amiri_quran':
      return GoogleFonts.amiriQuran(textStyle: base);
    default:
      // custom uploaded font, registered through FontLoader under fontKey
      return base.copyWith(fontFamily: fontKey);
  }
}

TextStyle translationTextStyle({double? fontSize, Color? color, List<Shadow>? shadows}) {
  return GoogleFonts.tajawal(
    textStyle: TextStyle(fontSize: fontSize, color: color, shadows: shadows),
  );
}
