// One place that maps a font key ('amiri' / 'ruqaa' / uploaded family name)
// to a TextStyle, used by BOTH the live stage preview and the export
// renderer so what you see is exactly what gets burned into the video.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
    case 'amiri':
      return GoogleFonts.amiriQuran(textStyle: base);
    case 'ruqaa':
      return GoogleFonts.arefRuqaa(textStyle: base);
    case 'notoNaskh':
      return GoogleFonts.notoNaskhArabic(textStyle: base);
    case 'scheherazade':
      return GoogleFonts.scheherazadeNew(textStyle: base);
    case 'lateef':
      return GoogleFonts.lateef(textStyle: base);
    case 'reemKufi':
      return GoogleFonts.reemKufi(textStyle: base);
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
