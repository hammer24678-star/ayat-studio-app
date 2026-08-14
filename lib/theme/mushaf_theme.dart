// PATCH_S123_MUSHAF_LIGHT: the studio is a video editor and stays dark —
// that's the right ground for judging a clip's exposure. Reading, though, is
// the opposite job, and a page of Quran on near-black is genuinely hard for
// some people over a long sitting. So light mode exists for the mushaf
// reader ONLY, and this is the palette that swaps under it.
//
// Both palettes are the same design: warm paper, gold rules, a single
// high-contrast ink for the ayah text. Only the values flip, so every widget
// in the reader can be written once against [MushafPalette] and look right
// in either mode.
import 'package:flutter/material.dart';

import 'ayat_theme.dart';

class MushafPalette {
  /// Page background behind everything.
  final Color background;

  /// The "sheet" the ayah text is printed on.
  final Color paper;

  /// Cards, chips, dropdowns.
  final Color surface;

  /// A slightly raised surface (selected chip, sheet header).
  final Color surfaceRaised;
  final Color hairline;

  /// Ornaments, rosettes, surah frames.
  final Color gold;
  final Color goldBright;
  final Color goldDim;

  /// The ayah text itself — the highest-contrast colour in the palette.
  final Color text;

  /// Translation, hints, page furniture.
  final Color textDim;

  /// Highlight behind a searched/selected ayah.
  final Color highlight;
  final bool isLight;

  const MushafPalette({
    required this.background,
    required this.paper,
    required this.surface,
    required this.surfaceRaised,
    required this.hairline,
    required this.gold,
    required this.goldBright,
    required this.goldDim,
    required this.text,
    required this.textDim,
    required this.highlight,
    required this.isLight,
  });

  static const dark = MushafPalette(
    background: AyatColors.ink,
    paper: Color(0xFF0A1714),
    surface: AyatColors.surface2,
    surfaceRaised: AyatColors.surface3,
    hairline: AyatColors.hairline,
    gold: AyatColors.gold,
    goldBright: AyatColors.goldBright,
    goldDim: AyatColors.goldDim,
    text: AyatColors.parchment,
    textDim: AyatColors.parchmentDim,
    highlight: Color(0x33C9A24B),
    isLight: false,
  );

  /// Warm printed-page light mode — not plain white, which glares against
  /// gold and reads as a web page rather than a mushaf.
  static const light = MushafPalette(
    background: Color(0xFFF4EDDD),
    paper: Color(0xFFFCF8EE),
    surface: Color(0xFFFBF5E7),
    surfaceRaised: Color(0xFFF1E7CE),
    hairline: Color(0x4D8A6E27),
    gold: Color(0xFF8A6E27),
    goldBright: Color(0xFFB08D34),
    goldDim: Color(0xFFB9A778),
    text: Color(0xFF231C10),
    textDim: Color(0xFF6E6350),
    highlight: Color(0x338A6E27),
    isLight: true,
  );

  static MushafPalette of(bool light) => light ? MushafPalette.light : dark;

  Brightness get brightness => isLight ? Brightness.light : Brightness.dark;

  /// A full ThemeData so Material widgets inside the reader (dropdowns,
  /// dialogs, sliders, the search field) pick the palette up automatically
  /// instead of each one needing an explicit colour.
  ThemeData toTheme(ThemeData base) => base.copyWith(
        brightness: brightness,
        scaffoldBackgroundColor: background,
        canvasColor: surface,
        dividerColor: hairline,
        colorScheme: base.colorScheme.copyWith(
          brightness: brightness,
          surface: surface,
          onSurface: text,
          primary: gold,
          onPrimary: isLight ? const Color(0xFFFCF8EE) : AyatColors.ink,
          secondary: goldBright,
        ),
        appBarTheme: base.appBarTheme.copyWith(
          backgroundColor: background,
          foregroundColor: text,
          elevation: 0,
          titleTextStyle:
              base.appBarTheme.titleTextStyle?.copyWith(color: text),
        ),
        iconTheme: IconThemeData(color: gold),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: gold,
          selectionColor: highlight,
          selectionHandleColor: gold,
        ),
        sliderTheme: base.sliderTheme.copyWith(
          activeTrackColor: gold,
          inactiveTrackColor: hairline,
          thumbColor: goldBright,
        ),
        progressIndicatorTheme: ProgressIndicatorThemeData(color: gold),
      );
}
