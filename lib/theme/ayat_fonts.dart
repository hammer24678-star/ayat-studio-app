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
}) {
  final base = TextStyle(
    fontSize: fontSize,
    color: color,
    height: height,
    shadows: shadows,
    fontWeight: fontWeight,
  );
  switch (fontKey) {
    case 'elgharib': // PATCH_S46_DEFAULT_FONT_AND_GLOW: bundled asset font, not google_fonts
      return base.copyWith(fontFamily: 'ElgharibNoonHafs');
    case 'amiri':
      return GoogleFonts.amiriQuran(textStyle: base);
    case 'ruqaa':
      return GoogleFonts.arefRuqaa(textStyle: base);
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
