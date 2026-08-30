#!/usr/bin/env python3
"""
PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW
=======================================

Four independent fixes bundled into one patch (each guarded and
idempotent on its own, same convention as every other S-series script
in this repo):

1. SCROLL BOTTOM CROP -- the الآية tab's SingleChildScrollView used the
   same flat EdgeInsets.all(16) on every side. That gave the *last* card
   ("نطاق آيات متعدد") only 16px of clearance even at max scroll, with
   no extra room past a gesture-nav phone's own bottom inset -- so it
   sat cropped right at the bottom edge of the screen, exactly as in
   your screenshot. Bottom padding now adds real breathing room on top
   of the device's own inset instead of relying on SafeArea alone.

2. WORD COLORS, MERGED WITH TIMING -- "تلوين كلمات بالأحمر" was its own
   card, stacked right above "توقيت ظهور النص يدويًا" -- two boxes for
   one job (controlling how the on-screen ayah text behaves). They're
   now one card. Tapping a word no longer *only* means red: pick a
   color first (red is still the default, so nothing changes for you
   unless you touch it) via quick swatches or the same full color
   picker every other color control in this app already uses, then tap
   words to paint them with it. Wired through the SAME redWordIndices
   plumbing that already existed in three places (the الآية tab, the
   live stage's double-tap word editor, and the export renderer) --
   renamed wordColors and retyped from a Set<int> (could only ever mean
   "red") to a Map<int, Color>, everywhere it's read or written.

3. REAL FONTS FOR THE QUICK-FONT ROW, PLUS YOUR THREE NEW FONTS --
   نسخ/رقعة/أندلس/القلم/الكوفي/خط قرآني in the "تنسيق النص" -> النص tab
   all looked identical because none of those five keys (naskh/andalus/
   qalam/kufi -- ruqaa/amiri_quran were already fine) were ever handled
   in ayahTextStyle()'s switch; they fell through to `default`, which
   asks for a fontFamily that was never registered anywhere, so Flutter
   silently fell back to the same system font for all of them. Real,
   visually distinct Google Fonts now (no asset bundling needed -- see
   the comment at each case if you'd rather swap one for a different
   family). The button labels themselves also render in their real font
   now instead of one shared generic style, so you can actually preview
   before picking. On top of that: your three new font files are
   bundled in as proper built-in fonts, selectable from both the main
   "خط الآية" dropdown and the quick-font row, the same way
   TharwatEmara/DigitalMadina were added in PATCH_S100.

4. GLOW + KARAOKE SETTINGS, FOR REAL THIS TIME -- the "التوهج" tab's
   on/off switch (glowEnabled) was already correctly wired, but the two
   sliders under it (glowSize/glowSharpness) were never read by either
   the live stage or the export renderer -- moving them did nothing.
   Replaced with a real slider for glowIntensity (the field the
   renderers actually use). Below it, a second switch restores
   "تظليل الكلمات مع التلاوة (كاريوكي)" -- on/off for the word-by-word
   lighting itself while الشيخ recites, not just its glow -- which used
   to live in the old _textPanel() screen and has had no reachable
   control anywhere since PATCH_S128 replaced that screen with this one.

WHAT THIS PATCH TOUCHES:
    pubspec.yaml
    lib/data/studio_presets.dart
    lib/theme/ayat_fonts.dart
    lib/models/studio_state.dart
    lib/services/overlay_renderer.dart
    lib/widgets/stage_preview.dart
    lib/widgets/text_editor_pro.dart
    lib/screens/home_screen.dart

NOT covered by this patch (flagged rather than guessed at):
    - Persisting wordColors across app restarts. redWordIndices was
      never in toJson()/fromJson() either (a red-word selection didn't
      survive a save/reload before this patch, and still doesn't) --
      not a regression, just not newly fixed. Colors are Objects that
      need explicit ARGB serialization to round-trip through JSON, so
      this is flagged for a dedicated follow-up rather than bolted on
      here.
    - A karaoke-glow-specific color separate from the plain-text glow.
      Both currently share one glowEnabled/glowIntensity pair by
      design (see overlay_renderer.dart/stage_preview.dart) -- splitting
      them is a bigger change than "restore the missing toggle."
    - Multi-language strings for any of the new UI text -- same
      deliberate exclusion PATCH_S144 already flagged; languages are a
      separate pass.

Run from the project root:
    python3 patch_s145_scroll_wordcolor_fonts_glow.py [project_root]
(defaults to the directory this script lives in, same as every other
S-series script here)

Idempotent: safe to run multiple times.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
LEDGER: list[tuple[str, str]] = []

# Where your three new font files might already be sitting on the phone.
# If none of these have them, the copy step just warns you with the
# exact destination path to drop them into by hand.
FONT_SOURCE_DIRS = [
    Path("/storage/emulated/0/Download"),
    Path("/storage/emulated/0/Download/Telegram"),
    ROOT,  # in case you already copied them next to this script
]

NEW_FONTS = [
    # (source filename you sent, dest asset filename, family name, fontKey)
    ("DigitalKhatt-NewV2.otf", "DigitalKhattNewV2.otf", "DigitalKhattNewV2", "digitalkhatt"),
    ("Elgharib-A001.ttf", "ElgharibA001.ttf", "ElgharibA001", "elgharib_a001"),
    ("Elgharib-LPMQ_Misbah-Taweel.ttf", "ElgharibLPMQMisbahTaweel.ttf",
     "ElgharibLPMQMisbahTaweel", "elgharib_lpmq"),
]


def _log(label: str, status: str) -> None:
    LEDGER.append((label, status))


def apply_literal(rel_path: str, old: str, new: str, label: str,
                   skip_if: str | None = None) -> None:
    p = ROOT / rel_path
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel_path} not found under {ROOT}")
    text = p.read_text(encoding="utf-8")
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


# =====================================================================
# 0. Copy the three new font files into assets/fonts/
# =====================================================================
def copy_fonts() -> None:
    dest_dir = ROOT / "assets" / "fonts"
    dest_dir.mkdir(parents=True, exist_ok=True)
    for src_name, dest_name, family, _key in NEW_FONTS:
        dest = dest_dir / dest_name
        if dest.exists():
            _log(f"copy {dest_name}", "SKIPPED-ALREADY")
            continue
        src = next((d / src_name for d in FONT_SOURCE_DIRS if (d / src_name).exists()), None)
        if src is None:
            _log(f"copy {dest_name}", "WARN-SOURCE-NOT-FOUND")
            print(f"  WARN  (copy {dest_name}): couldn't find {src_name} in "
                  f"{[str(d) for d in FONT_SOURCE_DIRS]} -- copy it to "
                  f"{dest} yourself before building.")
            continue
        shutil.copy2(src, dest)
        _log(f"copy {dest_name}", "APPLIED")


# =====================================================================
# 1. pubspec.yaml -- register the three new font families
# =====================================================================
def patch_pubspec() -> None:
    old = """  fonts:
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
    new = """  fonts:
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
    # PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: three more bundled ayah
    # fonts, copied in from the phone's Download folder by this script.
    - family: DigitalKhattNewV2
      fonts:
        - asset: assets/fonts/DigitalKhattNewV2.otf
    - family: ElgharibA001
      fonts:
        - asset: assets/fonts/ElgharibA001.ttf
    - family: ElgharibLPMQMisbahTaweel
      fonts:
        - asset: assets/fonts/ElgharibLPMQMisbahTaweel.ttf
"""
    apply_literal("pubspec.yaml", old, new,
                  "pubspec.yaml: register 3 new font families",
                  skip_if="DigitalKhattNewV2")


# =====================================================================
# 2. lib/data/studio_presets.dart -- kBuiltInFonts list
# =====================================================================
def patch_presets() -> None:
    old = """const List<AyahFontChoice> kBuiltInFonts = [
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
  // PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: three more bundled fonts.
  AyahFontChoice('digitalkhatt', 'الخط الرقمي الجديد'),
  AyahFontChoice('elgharib_a001', 'الغريب A001'),
  AyahFontChoice('elgharib_lpmq', 'الغريب اللجنة (مصباح طويل)'),
];"""
    apply_literal("lib/data/studio_presets.dart", old, new,
                  "studio_presets.dart: add 3 new fonts to kBuiltInFonts",
                  skip_if="AyahFontChoice('digitalkhatt'")


# =====================================================================
# 3. lib/theme/ayat_fonts.dart -- ayahTextStyle() switch
# =====================================================================
def patch_ayat_fonts() -> None:
    old = """  switch (fontKey) {
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
    default:
      // custom uploaded font, registered through FontLoader under fontKey
      return base.copyWith(fontFamily: fontKey);
  }"""
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
    // PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: three more bundled fonts.
    case 'digitalkhatt':
      return base.copyWith(fontFamily: 'DigitalKhattNewV2');
    case 'elgharib_a001':
      return base.copyWith(fontFamily: 'ElgharibA001');
    case 'elgharib_lpmq':
      return base.copyWith(fontFamily: 'ElgharibLPMQMisbahTaweel');
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
  }"""
    apply_literal("lib/theme/ayat_fonts.dart", old, new,
                  "ayat_fonts.dart: real fonts for naskh/andalus/qalam/kufi/"
                  "amiri_quran + 3 new bundled fonts",
                  skip_if="case 'digitalkhatt':")


# =====================================================================
# 4. lib/models/studio_state.dart -- redWordIndices -> wordColors
# =====================================================================
def patch_studio_state() -> None:
    apply_literal(
        "lib/models/studio_state.dart",
        """  // Word indices (into state.ayahText.split(RegExp(r'\\s+'))) to render in
  // red instead of the normal text color. Cleared whenever setAyah() runs.
  Set<int> redWordIndices = {};""",
        """  // PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: word index (into
  // state.ayahText.split(RegExp(r'\\s+'))) -> the color that word is
  // drawn in instead of the normal text color. Was a Set<int> that only
  // ever meant "red"; now any color, chosen from the same picker every
  // other color field in this app already uses (showAyatColorPicker) or
  // one of the quick swatches next to the word chips. Cleared whenever
  // setAyah()/applyStageTextEdit() changes the underlying words, same
  // as redWordIndices always was.
  Map<int, Color> wordColors = {};
  // The color the next tapped word gets. Defaults to the old hardcoded
  // red so existing habits (tap a word, it turns red) keep working
  // exactly as before unless a different color is deliberately picked.
  Color activeWordColor = const Color(0xFFE53935);""",
        "studio_state.dart: redWordIndices (Set<int>) -> wordColors (Map<int, Color>)",
        skip_if="Map<int, Color> wordColors = {};",
    )
    apply_literal(
        "lib/models/studio_state.dart",
        """      // PATCH_S133_STAGE_TEXT_SELECT_EDIT: a hand correction can change the
      // word count/order -- a previous red-word selection almost never
      // still lines up (same reasoning as setAyah()).
      redWordIndices = {};""",
        """      // PATCH_S133_STAGE_TEXT_SELECT_EDIT: a hand correction can change the
      // word count/order -- a previous word-color selection almost never
      // still lines up (same reasoning as setAyah()).
      wordColors = {};""",
        "studio_state.dart: applyStageTextEdit() reset",
        skip_if="wordColors = {};\n    }\n    notifyListeners();",
    )
    apply_literal(
        "lib/models/studio_state.dart",
        """    // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: a previous ayah's red-word
    // selection almost never lines up with the new ayah's word count/order.
    redWordIndices = {};""",
        """    // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: a previous ayah's
    // word-color selection almost never lines up with the new ayah's word
    // count/order.
    wordColors = {};""",
        "studio_state.dart: setAyah() reset",
        skip_if="word-color\n    // selection almost never",
    )


# =====================================================================
# 5. lib/services/overlay_renderer.dart -- OverlayStyle + export render
# =====================================================================
def patch_overlay_renderer() -> None:
    apply_literal(
        "lib/services/overlay_renderer.dart",
        "  // ---- PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION ----\n"
        "  final Set<int> redWordIndices;",
        "  // ---- PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION / PATCH_S145 ----\n"
        "  final Map<int, Color> wordColors;",
        "overlay_renderer.dart: OverlayStyle.redWordIndices -> wordColors field",
        skip_if="final Map<int, Color> wordColors;",
    )
    apply_literal(
        "lib/services/overlay_renderer.dart",
        "    this.redWordIndices = const {},",
        "    this.wordColors = const {},",
        "overlay_renderer.dart: OverlayStyle constructor default",
        skip_if="this.wordColors = const {},",
    )
    apply_literal(
        "lib/services/overlay_renderer.dart",
        "        redWordIndices: redWordIndices,\n"
        "        captionText: captionText,\n"
        "        captionPosition: captionPosition,\n"
        "        motion: m,",
        "        wordColors: wordColors,\n"
        "        captionText: captionText,\n"
        "        captionPosition: captionPosition,\n"
        "        motion: m,",
        "overlay_renderer.dart: OverlayStyle.withMotion() copy",
        skip_if="wordColors: wordColors,",
    )
    apply_literal(
        "lib/services/overlay_renderer.dart",
        """        // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING: red-flagged words
        // must stay red in exported auto-synced/timeline clips too --
        // this branch previously only chose between lit/dim and
        // silently dropped any redWordIndices selection.
        final redColorK = const Color(0xFFE53935).withValues(alpha: opacity);
        ayahSpan = TextSpan(
          children: [
            for (var i = 0; i < karaokeWords.length; i++)
              TextSpan(
                text: i == 0 ? karaokeWords[i] : ' ${karaokeWords[i]}',
                style: ayahTextStyle(
                  style.fontKey,
                  fontSize: ayahFontSize,
                  color: style.redWordIndices.contains(i)
                      ? redColorK
                      : (i < litWords ? effColor : dimColor),
                  height: style.lineHeightMultiplier,
                  letterSpacing: style.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
                  shadows: i < litWords ? litShadows : shadows,
                ),
              ),
          ],
        );""",
        """        // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING / PATCH_S145: a
        // word with its own assigned color must keep that color in
        // exported auto-synced/timeline clips too -- this branch
        // previously only chose between lit/dim and silently dropped any
        // per-word color choice.
        ayahSpan = TextSpan(
          children: [
            for (var i = 0; i < karaokeWords.length; i++)
              TextSpan(
                text: i == 0 ? karaokeWords[i] : ' ${karaokeWords[i]}',
                style: ayahTextStyle(
                  style.fontKey,
                  fontSize: ayahFontSize,
                  color: style.wordColors.containsKey(i)
                      ? style.wordColors[i]!.withValues(alpha: opacity)
                      : (i < litWords ? effColor : dimColor),
                  height: style.lineHeightMultiplier,
                  letterSpacing: style.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
                  shadows: i < litWords ? litShadows : shadows,
                ),
              ),
          ],
        );""",
        "overlay_renderer.dart: karaoke-branch word color lookup",
        skip_if="a\n        // word with its own assigned color must keep that color in\n        // exported",
    )
    apply_literal(
        "lib/services/overlay_renderer.dart",
        """        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: render word-by-word so
        // individually-flagged words can be colored red, same as the
        // karaoke branch above builds one TextSpan per word.
        if (style.redWordIndices.isNotEmpty) {
          final redColor = const Color(0xFFE53935)
              .withValues(alpha: opacity); // fixed highlight red
          final ws = text.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
          ayahSpan = TextSpan(
            children: [
              for (var i = 0; i < ws.length; i++)
                TextSpan(
                  text: i == 0 ? ws[i] : ' ${ws[i]}',
                  style: ayahTextStyle(
                    style.fontKey,
                    fontSize: ayahFontSize,
                    color: style.redWordIndices.contains(i) ? redColor : effColor,
                    height: style.lineHeightMultiplier,
                    letterSpacing: style.letterSpacing,
                    shadows: staticShadows,
                  ),
                ),
            ],
          );
        } else {""",
        """        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION / PATCH_S145: render
        // word-by-word so individually-colored words keep their own
        // color, same as the karaoke branch above builds one TextSpan
        // per word.
        if (style.wordColors.isNotEmpty) {
          final ws = text.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
          ayahSpan = TextSpan(
            children: [
              for (var i = 0; i < ws.length; i++)
                TextSpan(
                  text: i == 0 ? ws[i] : ' ${ws[i]}',
                  style: ayahTextStyle(
                    style.fontKey,
                    fontSize: ayahFontSize,
                    color: style.wordColors.containsKey(i)
                        ? style.wordColors[i]!.withValues(alpha: opacity)
                        : effColor,
                    height: style.lineHeightMultiplier,
                    letterSpacing: style.letterSpacing,
                    shadows: staticShadows,
                  ),
                ),
            ],
          );
        } else {""",
        "overlay_renderer.dart: static-branch word color lookup",
        skip_if="individually-colored words keep their own",
    )


# =====================================================================
# 6. lib/widgets/stage_preview.dart -- live render + double-tap dialog
# =====================================================================
def patch_stage_preview() -> None:
    apply_literal(
        "lib/widgets/stage_preview.dart",
        "import 'selection_box_overlay.dart'; // PATCH_S133_STAGE_TEXT_SELECT_EDIT",
        "import 'selection_box_overlay.dart'; // PATCH_S133_STAGE_TEXT_SELECT_EDIT\n"
        "import 'color_picker_dialog.dart' show showAyatColorPicker; // PATCH_S145",
        "stage_preview.dart: import showAyatColorPicker",
        skip_if="show showAyatColorPicker; // PATCH_S145",
    )
    apply_literal(
        "lib/widgets/stage_preview.dart",
        """      final dimColor = state.textColor.withValues(alpha: 0.30);
      // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING: a red-flagged word
      // stays red regardless of karaoke lit/dim state -- previously
      // redWordIndices was ignored entirely on this branch, so any
      // red selection silently vanished once karaoke highlighting
      // kicked in.
      const redColor = Color(0xFFE53935);
      ayahWidget = Text.rich(
        TextSpan(
          children: _revealedWordSpans(
            words: karaokeWords,
            byLetter: revealByLetter,
            progress: revealProgress,
            // PATCH_S115_HOTFIX_LIVE_LITWORDS_NULL_CHECK: `live` is
            // non-null in this branch (karaokeWords came from
            // live?.karaokeWords and passed the isNotEmpty check above)
            // but the analyzer can't see that, hence the `!`.
            styleFor: (i) => ayahTextStyle(
              state.fontKey,
              fontSize: ayahFontSize,
              color: state.redWordIndices.contains(i)
                  ? redColor
                  : (i < live!.litWords ? state.textColor : dimColor),
              height: state.lineHeightMultiplier,
              letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
              shadows: i < live!.litWords ? litShadows : shadows,
            ),
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      );
    } else {""",
        """      final dimColor = state.textColor.withValues(alpha: 0.30);
      // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING / PATCH_S145: a word
      // with its own assigned color keeps that color regardless of
      // karaoke lit/dim state -- previously this map (then a red-only
      // set) was ignored entirely on this branch, so any color choice
      // silently vanished once karaoke highlighting kicked in.
      ayahWidget = Text.rich(
        TextSpan(
          children: _revealedWordSpans(
            words: karaokeWords,
            byLetter: revealByLetter,
            progress: revealProgress,
            // PATCH_S115_HOTFIX_LIVE_LITWORDS_NULL_CHECK: `live` is
            // non-null in this branch (karaokeWords came from
            // live?.karaokeWords and passed the isNotEmpty check above)
            // but the analyzer can't see that, hence the `!`.
            styleFor: (i) => ayahTextStyle(
              state.fontKey,
              fontSize: ayahFontSize,
              color: state.wordColors.containsKey(i)
                  ? state.wordColors[i]!
                  : (i < live!.litWords ? state.textColor : dimColor),
              height: state.lineHeightMultiplier,
              letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
              shadows: i < live!.litWords ? litShadows : shadows,
            ),
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      );
    } else {""",
        "stage_preview.dart: karaoke-branch word color lookup",
        skip_if="a word\n      // with its own assigned color keeps that color regardless of",
    )
    apply_literal(
        "lib/widgets/stage_preview.dart",
        """      // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING: this branch never
      // looked at state.redWordIndices before, so tapping a word chip
      // in the "تلوين كلمات بالأحمر" section had zero visible effect
      // in the live preview -- it only ever reached the exported
      // video's static-text path. Mirror that path here.
      if (state.redWordIndices.isNotEmpty || perUnitReveal) {
        const redColor = Color(0xFFE53935);
        final ws = text.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
        ayahWidget = Text.rich(
          TextSpan(
            children: _revealedWordSpans(
              words: ws,
              byLetter: revealByLetter,
              progress: revealProgress,
              styleFor: (i) => ayahTextStyle(
                state.fontKey,
                fontSize: ayahFontSize,
                color: state.redWordIndices.contains(i)
                    ? redColor
                    : state.textColor,
                height: state.lineHeightMultiplier,
                letterSpacing: state.letterSpacing,
                shadows: staticShadows,
              ),
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        );
      } else {""",
        """      // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING / PATCH_S145: this
      // branch never looked at word colors before, so tapping a word
      // chip had zero visible effect in the live preview -- it only
      // ever reached the exported video's static-text path. Mirror
      // that path here.
      if (state.wordColors.isNotEmpty || perUnitReveal) {
        final ws = text.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
        ayahWidget = Text.rich(
          TextSpan(
            children: _revealedWordSpans(
              words: ws,
              byLetter: revealByLetter,
              progress: revealProgress,
              styleFor: (i) => ayahTextStyle(
                state.fontKey,
                fontSize: ayahFontSize,
                color: state.wordColors.containsKey(i)
                    ? state.wordColors[i]!
                    : state.textColor,
                height: state.lineHeightMultiplier,
                letterSpacing: state.letterSpacing,
                shadows: staticShadows,
              ),
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        );
      } else {""",
        "stage_preview.dart: static-branch word color lookup",
        skip_if="this\n      // branch never looked at word colors before",
    )
    apply_literal(
        "lib/widgets/stage_preview.dart",
        """                Text(s.t('stage.toggleWords'),
                    style: const TextStyle(
                        color: AyatColors.goldDim, fontSize: 12)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < words.length; i++)
                      FilterChip(
                        label: Text(words[i],
                            style: ayahTextStyle(state.fontKey,
                                fontSize: 13)),
                        selected: state.redWordIndices.contains(i),
                        selectedColor: const Color(0xFFE53935)
                            .withValues(alpha: 0.35),
                        onSelected: (sel) {
                          state.update(() {
                            if (sel) {
                              state.redWordIndices.add(i);
                            } else {
                              state.redWordIndices.remove(i);
                            }
                          });
                          setDialogState(() {});
                        },
                      ),
                  ],
                ),""",
        """                Row(
                  children: [
                    Expanded(
                      child: Text(s.t('stage.toggleWords'),
                          style: const TextStyle(
                              color: AyatColors.goldDim, fontSize: 12)),
                    ),
                    // PATCH_S145: which color the next tap applies --
                    // defaults to red so nothing changes for anyone who
                    // never touches this, but any color works.
                    GestureDetector(
                      onTap: () async {
                        final c = await showAyatColorPicker(
                            context, state.activeWordColor);
                        if (c != null) {
                          state.update(() => state.activeWordColor = c);
                          setDialogState(() {});
                        }
                      },
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: state.activeWordColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: AyatColors.goldDim),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var i = 0; i < words.length; i++)
                      FilterChip(
                        label: Text(words[i],
                            style: ayahTextStyle(state.fontKey,
                                fontSize: 13)),
                        selected: state.wordColors.containsKey(i),
                        selectedColor:
                            (state.wordColors[i] ?? state.activeWordColor)
                                .withValues(alpha: 0.35),
                        onSelected: (sel) {
                          state.update(() {
                            if (sel) {
                              state.wordColors[i] = state.activeWordColor;
                            } else {
                              state.wordColors.remove(i);
                            }
                          });
                          setDialogState(() {});
                        },
                      ),
                  ],
                ),""",
        "stage_preview.dart: double-tap word editor -- any color, not just red",
        skip_if="which color the next tap applies",
    )


# =====================================================================
# 7. lib/widgets/text_editor_pro.dart -- font row, chip preview, glow tab
# =====================================================================
def patch_text_editor_pro() -> None:
    apply_literal(
        "lib/widgets/text_editor_pro.dart",
        "import '../theme/ayat_theme.dart';",
        "import '../theme/ayat_theme.dart';\n"
        "import '../theme/ayat_fonts.dart'; // PATCH_S145: ayahTextStyle for chip previews",
        "text_editor_pro.dart: import ayat_fonts.dart",
        skip_if="ayahTextStyle for chip previews",
    )
    apply_literal(
        "lib/widgets/text_editor_pro.dart",
        """  static const _fonts = [('naskh', 'نسخ'), ('ruqaa', 'رقعة'), ('andalus', 'أندلس'),
    ('qalam', 'القلم'), ('kufi', 'الكوفي')];""",
        """  // PATCH_S145: three more bundled fonts (see ayat_fonts.dart /
  // studio_presets.dart) added alongside the original five.
  static const _fonts = [('naskh', 'نسخ'), ('ruqaa', 'رقعة'), ('andalus', 'أندلس'),
    ('qalam', 'القلم'), ('kufi', 'الكوفي'), ('digitalkhatt', 'الرقمي الجديد'),
    ('elgharib_a001', 'الغريب A001'), ('elgharib_lpmq', 'الغريب اللجنة')];""",
        "text_editor_pro.dart: _fonts list + 3 new fonts",
        skip_if="('digitalkhatt', 'الرقمي الجديد')",
    )
    apply_literal(
        "lib/widgets/text_editor_pro.dart",
        """    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final f in _fonts) _chip(f.$2, s.fontKey == f.$1,
          () => s.update(() => s.fontKey = f.$1)),
      _chip('خط قرآني', s.fontKey == 'amiri_quran',
          () => s.update(() => s.fontKey = 'amiri_quran')),""",
        """    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final f in _fonts) _chip(f.$2, f.$1, s.fontKey == f.$1,
          () => s.update(() => s.fontKey = f.$1)),
      _chip('خط قرآني', 'amiri_quran', s.fontKey == 'amiri_quran',
          () => s.update(() => s.fontKey = 'amiri_quran')),""",
        "text_editor_pro.dart: pass fontKey into _chip() calls",
        skip_if="_chip(f.$2, f.$1, s.fontKey == f.$1,",
    )
    apply_literal(
        "lib/widgets/text_editor_pro.dart",
        """  Widget _chip(String t, bool sel, VoidCallback on) => ChoiceChip(
    label: Text(t, style: const TextStyle(fontSize: 12)), selected: sel, onSelected: (_) => on());""",
        """  // PATCH_S145_FONT_BUTTONS_REAL_FONTS: each button now previews its
  // own actual font (via the same ayahTextStyle() the live stage and
  // the exporter use) instead of every label rendering in one shared
  // generic style regardless of which font it names -- and a touch
  // roomier so the preview is actually legible.
  Widget _chip(String label, String fontKey, bool sel, VoidCallback on) =>
      ChoiceChip(
        label: Text(label, style: ayahTextStyle(fontKey, fontSize: 15)),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        selected: sel,
        onSelected: (_) => on(),
      );""",
        "text_editor_pro.dart: _chip() renders each button in its own font",
        skip_if="Widget _chip(String label, String fontKey, bool sel, VoidCallback on)",
    )
    apply_literal(
        "lib/widgets/text_editor_pro.dart",
        """  Widget _glow() => _card('التوهج', Icons.wb_sunny_outlined, s.glowEnabled,
    (v) => s.update(() => s.glowEnabled = v), [
    _slider('الحجم', s.glowSize, 0, 60, 0, (v) => s.update(() => s.glowSize = v)),
    _slider('الحدة', s.glowSharpness, 0, 100, 0, (v) => s.update(() => s.glowSharpness = v))]);""",
        """  // PATCH_S145_GLOW_KARAOKE_SETTINGS: the on/off switch this card
  // already had (s.glowEnabled) was real and correctly wired -- but the
  // two sliders under it (glowSize/glowSharpness) were never read by
  // either the live stage or the export renderer, so moving them did
  // nothing. The one field that actually controls how strong the glow
  // looks (glowIntensity, 0..1.5, used for both the plain-text glow and
  // the karaoke lit-word glow while الشيخ is reciting) now has the real
  // slider. The second switch below restores "تظليل الكلمات مع التلاوة
  // (كاريوكي)" -- on/off for the word-by-word lighting itself, not just
  // its glow -- which used to live in the now-orphaned old _textPanel()
  // and has had no reachable control anywhere since PATCH_S128 replaced
  // that screen with this one.
  Widget _glow() => _card('التوهج', Icons.wb_sunny_outlined, s.glowEnabled,
    (v) => s.update(() => s.glowEnabled = v), [
    _slider('شدّة التوهّج', s.glowIntensity, 0, 1.5, 2,
        (v) => s.update(() => s.glowIntensity = v)),
    const SizedBox(height: 6),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('تظليل الكلمات مع التلاوة (كاريوكي)',
          style: TextStyle(fontSize: 13)),
      subtitle: const Text(
          'عند الإيقاف: تُعرض الآية كاملة دون إضاءة كل كلمة على حدة',
          style: TextStyle(fontSize: 11)),
      value: s.karaokeEnabled,
      activeColor: AyatColors.gold,
      onChanged: (v) => s.update(() => s.karaokeEnabled = v),
    ),
  ]);""",
        "text_editor_pro.dart: real glowIntensity slider + karaoke on/off switch",
        skip_if="تظليل الكلمات مع التلاوة (كاريوكي)',\n          style: TextStyle(fontSize: 13)",
    )


# =====================================================================
# 8. lib/screens/home_screen.dart -- scroll padding, merge, OverlayStyle
# =====================================================================
def patch_home_screen() -> None:
    # 8a. bottom-crop fix
    apply_literal(
        "lib/screens/home_screen.dart",
        """          builder: (context, _) => SingleChildScrollView(
            controller: _scrollCtrl, // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX
            padding: const EdgeInsets.all(16),
            child: Column(""",
        """          builder: (context, _) => SingleChildScrollView(
            controller: _scrollCtrl, // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX
            // PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: EdgeInsets.all(16)
            // gave the same 16px at the bottom as everywhere else, which
            // was never enough clearance past the last card (usually
            // "نطاق آيات متعدد") on gesture-nav phones -- SafeArea alone
            // doesn't add scroll-content padding, so the card's own
            // bottom edge sat right against the screen edge even at max
            // scroll. Extra bottom padding on top of the device's own
            // inset now.
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom + 40),
            child: Column(""",
        "home_screen.dart: bottom scroll padding past the last card",
        skip_if="EdgeInsets.fromLTRB(\n                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom + 40)",
    )

    # 8b. OverlayStyle construction: pass wordColors instead of redWordIndices
    apply_literal(
        "lib/screens/home_screen.dart",
        "        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION\n"
        "        redWordIndices: state.redWordIndices,",
        "        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION / PATCH_S145\n"
        "        wordColors: state.wordColors,",
        "home_screen.dart: OverlayStyle(...) construction uses wordColors",
        skip_if="wordColors: state.wordColors,",
    )

    # 8c. drop the separate call to _redWordsSection()
    apply_literal(
        "lib/screens/home_screen.dart",
        "        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION\n"
        "        if (state.hasAyah) _redWordsSection(),\n"
        "        _manualTimingSection(),\n",
        "        // PATCH_S145_WORD_COLORS_TIMING_MERGE: word-coloring used to\n"
        "        // be its own card here (_redWordsSection()) -- it's now\n"
        "        // folded into _manualTimingSection() below, since both\n"
        "        // control how the same on-screen ayah text behaves.\n"
        "        _manualTimingSection(),\n",
        "home_screen.dart: build list no longer calls _redWordsSection() separately",
        skip_if="WORD_COLORS_TIMING_MERGE: word-coloring used to",
    )

    # 8d. replace both methods (_redWordsSection + _manualTimingSection)
    #     with one merged _manualTimingSection().
    old_methods = """  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: tap a word of the currently
  // displayed ayah to color just that word red in the exported video.
  Widget _redWordsSection() {
    final words = state.ayahText
        .split(RegExp(r'\\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return const SizedBox.shrink();
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'تلوين كلمات بالأحمر (اختياري)',
          'اضغطي على أي كلمة لتلوينها بالأحمر في الفيديو المُصدَّر -- مفيدة '
          'لتمييز اسم الجلالة أو كلمة محورية من الآية. يمكنك تلوين أكثر '
          'من كلمة، واضغطي عليها مجددًا لإزالة اللون.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < words.length; i++)
              FilterChip(
                label: Text(words[i],
                    style: ayahTextStyle(state.fontKey, fontSize: 14)),
                selected: state.redWordIndices.contains(i),
                selectedColor: const Color(0xFFE53935).withValues(alpha: 0.35),
                onSelected: (sel) => state.update(() {
                  if (sel) {
                    state.redWordIndices.add(i);
                  } else {
                    state.redWordIndices.remove(i);
                  }
                }),
              ),
          ],
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: optional manual override for
  // when the ayah text appears/disappears in the exported clip.
  Widget _manualTimingSection() {
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'توقيت ظهور النص يدويًا (اختياري)',
          'حدّدي بالثواني متى يظهر نص الآية ومتى يختفي من الفيديو المُصدَّر -- '
          'مفيد لو أردتِ أن يظهر النص متأخرًا عن بداية المقطع أو يختفي قبل '
          'نهايته. اتركي الحقلين فارغين ليظهر النص طوال المقطع كالمعتاد.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textStartCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'يبدأ عند (ثانية)'),
                onChanged: (v) => state.update(
                    () => state.textTimeStartOverride = double.tryParse(v)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _textEndCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ينتهي عند (ثانية)'),
                onChanged: (v) => state.update(
                    () => state.textTimeEndOverride = double.tryParse(v)),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'مسح التوقيت اليدوي',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _textStartCtrl.clear();
                _textEndCtrl.clear();
                state.update(() {
                  state.textTimeStartOverride = null;
                  state.textTimeEndOverride = null;
                });
              }),
            ),
          ],
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }"""

    new_method = """  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION / PATCH_S145_WORD_COLORS_TIMING_MERGE:
  // "تلوين كلمات بالأحمر" and "توقيت ظهور النص يدويًا" used to be two
  // separate boxes stacked back-to-back, even though both are the same
  // job -- extra control over how the on-screen ayah text stands out --
  // and coloring a word used to only ever mean red, applied instantly
  // with no other option. Now one card: pick a color (red by default,
  // same as before, or any color via the picker), tap words to
  // paint/unpaint them with it, and set when the whole ayah text
  // (colored words included) appears/disappears -- one place instead
  // of two.
  Widget _manualTimingSection() {
    final words = state.ayahText
        .split(RegExp(r'\\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'تلوين الكلمات وتوقيت ظهورها (اختياري)',
          'اختاري لونًا ثم اضغطي على أي كلمة لتلوينها به في الفيديو '
          'المُصدَّر -- مفيدة لتمييز اسم الجلالة أو كلمة محورية. اضغطي '
          'الكلمة مجددًا لإزالة لونها. حدّدي أيضًا بالثواني متى يظهر نص '
          'الآية ومتى يختفي؛ اتركي الحقلين فارغين ليظهر طوال المقطع '
          'كالمعتاد.',
        ),
        if (words.isNotEmpty) ...[
          const SizedBox(height: 10),
          // PATCH_S145: the color the next tap applies -- defaults to
          // red so tapping a word behaves exactly like before unless a
          // different color is chosen first.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final c in const [
                Color(0xFFE53935), // red -- the old, only option
                Color(0xFFECC875), // gold
                Color(0xFFFFFFFF), // white
                Color(0xFF4CAF50), // green
                Color(0xFF2A6FDB), // blue
              ])
                GestureDetector(
                  onTap: () => state.update(() => state.activeWordColor = c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: state.activeWordColor.toARGB32() ==
                                  c.toARGB32()
                              ? AyatColors.goldBright
                              : Colors.black26,
                          width: state.activeWordColor.toARGB32() ==
                                  c.toARGB32()
                              ? 2.5
                              : 1),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () async {
                  final c = await showAyatColorPicker(
                      context, state.activeWordColor);
                  if (c != null) {
                    state.update(() => state.activeWordColor = c);
                  }
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: state.activeWordColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AyatColors.goldBright),
                  ),
                  child: const Icon(Icons.colorize,
                      size: 14, color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < words.length; i++)
                FilterChip(
                  label: Text(words[i],
                      style: ayahTextStyle(state.fontKey, fontSize: 14)),
                  selected: state.wordColors.containsKey(i),
                  selectedColor:
                      (state.wordColors[i] ?? state.activeWordColor)
                          .withValues(alpha: 0.35),
                  onSelected: (sel) => state.update(() {
                    if (sel) {
                      state.wordColors[i] = state.activeWordColor;
                    } else {
                      state.wordColors.remove(i);
                    }
                  }),
                ),
            ],
          ),
        ],
        const Divider(height: 28, color: AyatColors.hairline),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textStartCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'يبدأ عند (ثانية)'),
                onChanged: (v) => state.update(
                    () => state.textTimeStartOverride = double.tryParse(v)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _textEndCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ينتهي عند (ثانية)'),
                onChanged: (v) => state.update(
                    () => state.textTimeEndOverride = double.tryParse(v)),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'مسح التوقيت اليدوي',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _textStartCtrl.clear();
                _textEndCtrl.clear();
                state.update(() {
                  state.textTimeStartOverride = null;
                  state.textTimeEndOverride = null;
                });
              }),
            ),
          ],
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }"""

    apply_literal(
        "lib/screens/home_screen.dart", old_methods, new_method,
        "home_screen.dart: merge _redWordsSection() into _manualTimingSection()",
        skip_if="Widget _manualTimingSection() {\n    final words = state.ayahText",
    )


def main() -> None:
    copy_fonts()
    patch_pubspec()
    patch_presets()
    patch_ayat_fonts()
    patch_studio_state()
    patch_overlay_renderer()
    patch_stage_preview()
    patch_text_editor_pro()
    patch_home_screen()

    print("\n=== S145 scroll/word-color/fonts/glow patch ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("========================================================\n")
    print("Next steps:")
    print("  1. flutter pub get")
    print("  2. Check any WARN-SOURCE-NOT-FOUND lines above and copy the")
    print("     matching font file into assets/fonts/ by hand if needed.")
    print("  3. flutter analyze  (word-color changes touch 4 files -- worth")
    print("     a full analyze pass before you build)")
    print("  4. flutter run")


if __name__ == "__main__":
    main()
