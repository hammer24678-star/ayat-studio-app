// Ayat Studio's own theme — ported 1:1 from ayat_studio-22.html's :root CSS
// variables. Ayat Studio is a distinct app/brand from Tilawa Enhancer and
// keeps its own palette and typography here rather than sharing one.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AyatColors {
  static const ink = Color(0xFF050F0D);
  static const surface = Color(0xFF0D1C18);
  static const surface2 = Color(0xFF13271F);
  static const surface3 = Color(0xFF1A3128);
  static const hairline = Color(0x29C9A24B); // rgba(201,162,75,0.16)
  static const gold = Color(0xFFC9A24B);
  static const goldBright = Color(0xFFECC875);
  static const goldDim = Color(0xFF8A7130);
  static const parchment = Color(0xFFECE2CB);
  static const parchmentDim = Color(0xFF9C9280);
  static const emerald = Color(0xFF1E4B3F);
}

// PATCH_S105_GOLD_AYAH_BADGE: shared golden ayah-number ornament -- the
// same solid AyatColors.gold filled circle with dark-ink digits already
// used by the mushaf reader's ayah-end ornament (PATCH_S74). Reused
// anywhere an ayah number should read as part of the app's gold theme
// instead of plain text.
Widget ayahNumberBadge(int num, {double size = 26, double fontSize = 11}) {
  return Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: AyatColors.gold,
      boxShadow: [
        BoxShadow(
          color: AyatColors.gold.withValues(alpha: 0.45),
          blurRadius: 6,
          spreadRadius: 0.5,
        ),
      ],
    ),
    // PATCH_S117_MULTI_DIGIT_AYAH_NUMBERS: same fixed-size assumption as
    // the mushaf rosette -- shrink 3-digit ayah numbers (100+) to fit
    // instead of letting them crowd or clip against the circle's edge.
    child: Padding(
      padding: EdgeInsets.all(size * 0.14),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          '$num',
          style: TextStyle(
            color: AyatColors.ink,
            fontSize: fontSize,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ),
  );
}

class AyatTheme {
  static TextTheme get _textTheme => TextTheme(
        // Aref Ruqaa — headings/titles, matches the browser build's h1/h2/h3
        headlineLarge: GoogleFonts.arefRuqaa(
          fontWeight: FontWeight.w700,
          fontSize: 26,
          color: AyatColors.parchment,
        ),
        headlineMedium: GoogleFonts.arefRuqaa(
          fontWeight: FontWeight.w700,
          fontSize: 19,
          color: AyatColors.parchment,
        ),
        // Amiri Quran — ayah text only
        displayLarge: GoogleFonts.amiriQuran(
          fontSize: 22,
          height: 1.8,
          color: AyatColors.parchment,
        ),
        // Tajawal — everything else (body/UI)
        bodyLarge: GoogleFonts.tajawal(fontSize: 14, color: AyatColors.parchment),
        bodyMedium: GoogleFonts.tajawal(fontSize: 13, color: AyatColors.parchmentDim),
        labelLarge: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12.5),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AyatColors.ink,
        fontFamily: GoogleFonts.tajawal().fontFamily,
        colorScheme: const ColorScheme.dark(
          surface: AyatColors.surface,
          primary: AyatColors.gold,
          secondary: AyatColors.goldBright,
          onSurface: AyatColors.parchment,
        ),
        textTheme: _textTheme,
        appBarTheme: AppBarTheme(
          backgroundColor: AyatColors.ink,
          foregroundColor: AyatColors.parchment,
          elevation: 0,
          titleTextStyle: GoogleFonts.arefRuqaa(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: AyatColors.parchment,
          ),
        ),
        cardTheme: CardThemeData(
          color: AyatColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AyatColors.hairline),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AyatColors.surface3,
            foregroundColor: AyatColors.goldBright,
            side: const BorderSide(color: AyatColors.goldDim),
            textStyle: GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12.5),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AyatColors.goldBright,
        ),
      );
}
