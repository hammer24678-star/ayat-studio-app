// PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS
// Preset data ported 1:1 from the HTML prototype (ayat_studio225.html):
// canvas background gradients (BG_CANVAS_DEFS), text templates (TEMPLATES),
// text color dots (COLORS) and reciter slot names (RECITERS).
import 'package:flutter/material.dart';

enum AyahTextPosition { top, center, bottom }

// PATCH_S53_LANDSCAPE_EXPORT: the three export/preview canvas shapes. Width/height here
// are the audio-only/static-export canvas AND the source of truth for
// the live-preview frame's AspectRatio -- see export_service.dart and
// stage_preview.dart.
// PATCH_S125_CUSTOM_ASPECT: `custom` appended last -- SettingsService stores
// aspectRatio.index, so it has to go on the end. Its dimensions come from
// StudioState.customAspectW/H rather than from this table.
enum AyatAspectRatio { story916, square11, landscape169, portrait45, custom }

const List<(AyatAspectRatio, String, int, int)> kAspectRatios = [
  (AyatAspectRatio.story916, '9:16 قصة', 1080, 1920),
  (AyatAspectRatio.square11, '1:1 مربع', 1080, 1080),
  (AyatAspectRatio.landscape169, '16:9 عريض', 1920, 1080), // PATCH_S53_LANDSCAPE_EXPORT
  // PATCH_S125_CUSTOM_ASPECT: 4:5 is the tallest frame Instagram's feed
  // shows without cropping -- the single most-requested shape after 9:16.
  (AyatAspectRatio.portrait45, '4:5 منشور', 1080, 1350),
  (AyatAspectRatio.custom, 'مخصص', 1080, 1920),
];

enum FrameExtra { none, boxed, framed, glass } // PATCH_S38_VIDEO_EFFECTS: glass = frosted-panel look

// PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: where the optional custom
// caption line (reciter name, ayah-range label, ...) sits on the frame.
enum CaptionPosition { top, bottom }

// PATCH_S123_WATERMARK: which corner an (entirely optional) watermark sits
// in. Named by real screen corners rather than start/end -- the exported MP4
// has no text direction, and "start" would mean opposite things to an Arabic
// and an English user looking at the same file.
enum WatermarkCorner { topLeft, topRight, bottomLeft, bottomRight }

const List<(WatermarkCorner, String)> kWatermarkCorners = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (WatermarkCorner.topLeft, 'preset.watermarkCorner.topLeft'),
  (WatermarkCorner.topRight, 'preset.watermarkCorner.topRight'),
  (WatermarkCorner.bottomLeft, 'preset.watermarkCorner.bottomLeft'),
  (WatermarkCorner.bottomRight, 'preset.watermarkCorner.bottomRight'),
];

// PATCH_S38_VIDEO_EFFECTS: export-time color grading presets — see
// ExportService._colorGradeFilter for the ffmpeg filter each one maps to.
// Purely visual, never touches audio.
enum ColorGrade { none, warmGold, nightTeal, sepia, softMono }

const List<(ColorGrade, String)> kColorGrades = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is now an app_strings.dart
  // key, not literal display text -- look it up with _t()/t() at the
  // call site instead of rendering directly.
  (ColorGrade.none, 'preset.colorGrade.none'),
  (ColorGrade.warmGold, 'preset.colorGrade.warmGold'),
  (ColorGrade.nightTeal, 'preset.colorGrade.nightTeal'),
  (ColorGrade.sepia, 'preset.colorGrade.sepia'),
  (ColorGrade.softMono, 'preset.colorGrade.softMono'),
];

// PATCH_S40_MULTI_BG_CYCLE: user-editable auto-switching multi-background
// export. Purely export-time, exactly like the S38 effects above — see
// ExportService for the ffmpeg concat/xfade chain this drives.
enum BgSwitchTrigger { ayahs, seconds }

// PATCH_S70_MORE_TRANSITIONS: 7 more xfade-backed styles alongside the original 2.
enum BgTransitionStyle {
  hardCut,
  crossfade,
  wipeLeft,
  wipeRight,
  slideUp,
  slideDown,
  circleOpen,
  circleClose,
  dissolve,
  pixelize,
  radial,
}

// PATCH_S70_MORE_TRANSITIONS: ffmpeg xfade filter name for every non-hardCut style --
// hardCut takes the concat path instead (see export_service.dart) so its
// entry here is unused, just present for switch exhaustiveness.
extension BgTransitionStyleXfade on BgTransitionStyle {
  String get ffmpegXfadeName => switch (this) {
        BgTransitionStyle.hardCut => 'fade',
        BgTransitionStyle.crossfade => 'fade',
        BgTransitionStyle.wipeLeft => 'wipeleft',
        BgTransitionStyle.wipeRight => 'wiperight',
        BgTransitionStyle.slideUp => 'slideup',
        BgTransitionStyle.slideDown => 'slidedown',
        BgTransitionStyle.circleOpen => 'circleopen',
        BgTransitionStyle.circleClose => 'circleclose',
        BgTransitionStyle.dissolve => 'dissolve',
        BgTransitionStyle.pixelize => 'pixelize',
        BgTransitionStyle.radial => 'radial',
      };
}

const List<(BgSwitchTrigger, String)> kBgSwitchTriggers = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (BgSwitchTrigger.ayahs, 'preset.bgSwitch.ayahs'),
  (BgSwitchTrigger.seconds, 'preset.bgSwitch.seconds'),
];

const List<(BgTransitionStyle, String)> kBgTransitionStyles = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (BgTransitionStyle.hardCut, 'preset.bgTransition.hardCut'),
  (BgTransitionStyle.crossfade, 'preset.bgTransition.crossfade'),
  // PATCH_S70_MORE_TRANSITIONS
  (BgTransitionStyle.wipeLeft, 'preset.bgTransition.wipeLeft'),
  (BgTransitionStyle.wipeRight, 'preset.bgTransition.wipeRight'),
  (BgTransitionStyle.slideUp, 'preset.bgTransition.slideUp'),
  (BgTransitionStyle.slideDown, 'preset.bgTransition.slideDown'),
  (BgTransitionStyle.circleOpen, 'preset.bgTransition.circleOpen'),
  (BgTransitionStyle.circleClose, 'preset.bgTransition.circleClose'),
  (BgTransitionStyle.dissolve, 'preset.bgTransition.dissolve'),
  (BgTransitionStyle.pixelize, 'preset.bgTransition.pixelize'),
  (BgTransitionStyle.radial, 'preset.bgTransition.radial'),
];

// PATCH_S54_PRO_EXPORT_CONTROLS: how an uploaded video maps onto the chosen
// aspect-ratio canvas. `source` keeps the old behaviour (export at the
// video's own size); the other two export at the ratio picker's canvas —
// fillCrop center-crops to fill it, fitBlur letterboxes the whole frame
// over a blurred, darkened copy of itself (the classic reels look).
enum VideoFitMode { source, fillCrop, fitBlur }

const List<(VideoFitMode, String)> kVideoFitModes = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (VideoFitMode.source, 'preset.videoFit.source'),
  (VideoFitMode.fillCrop, 'preset.videoFit.fillCrop'),
  (VideoFitMode.fitBlur, 'preset.videoFit.fitBlur'),
];

// PATCH_S54_PRO_EXPORT_CONTROLS: encoder quality tiers (x264 CRF + AAC
// bitrate) and an optional output resolution cap.
enum ExportQuality { high, balanced, compact }

const List<(ExportQuality, String)> kExportQualities = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (ExportQuality.high, 'preset.exportQuality.high'),
  (ExportQuality.balanced, 'preset.exportQuality.balanced'),
  (ExportQuality.compact, 'preset.exportQuality.compact'),
];

enum ExportResolutionCap { source, hd1080, hd720 }

const List<(ExportResolutionCap, String)> kExportResolutions = [
  // PATCH_S154_STUDIO_PRESETS_I18N: only 'source' had translatable text;
  // '1080p'/'720p' are units, not language, and stay literal on purpose.
  (ExportResolutionCap.source, 'preset.exportRes.source'),
  (ExportResolutionCap.hd1080, '1080p'),
  (ExportResolutionCap.hd720, '720p'),
];

class BgDef {
  final bool radial;
  final List<Color> stops;
  const BgDef({this.radial = false, required this.stops});

  Gradient get gradient => radial
      ? RadialGradient(
          center: const Alignment(-0.4, -0.6),
          radius: 1.2,
          colors: stops,
        )
      : LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: stops,
        );
}

const List<BgDef> kBackgrounds = [
  BgDef(stops: [Color(0xFF0F2B26), Color(0xFF1E4B3F), Color(0xFF173A30)]),
  BgDef(stops: [Color(0xFF241407), Color(0xFF5C2430), Color(0xFF3A1A20)]),
  BgDef(stops: [Color(0xFF0B1424), Color(0xFF1B3A63), Color(0xFF152D4D)]),
  BgDef(stops: [Color(0xFF180F1C), Color(0xFF3B2140), Color(0xFF2A1830)]),
  BgDef(stops: [Color(0xFF161005), Color(0xFF4A3A10), Color(0xFF332809)]),
  BgDef(radial: true, stops: [Color(0xFF233A34), Color(0xFF050F0D)]),
  BgDef(stops: [Color(0xFF1C1C1C), Color(0xFF050505), Color(0xFF111111)]),
  BgDef(stops: [Color(0xFF0E1E1A), Color(0xFF1E4B3F), Color(0xFF1B3A63)]),
  // PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS: nature-themed additions -- kept dark/jewel-toned like the
  // set above so gold/white ayah text stays readable; automatically get
  // the S28/S29 animated sheen since that applies to any kBackgrounds entry.
  BgDef(stops: [Color(0xFF0A2818), Color(0xFF1F4D2E), Color(0xFF0D3320)]), // forest canopy
  BgDef(radial: true, stops: [Color(0xFF16324F), Color(0xFF0A1A2C)]), // night sky & clouds
  BgDef(stops: [Color(0xFF3A1D0E), Color(0xFF7A3A1D), Color(0xFF4A1F12)]), // desert sunset
  BgDef(stops: [Color(0xFF072421), Color(0xFF0E4A44), Color(0xFF0A3733)]), // ocean teal
  BgDef(stops: [Color(0xFF33260A), Color(0xFF6B4E14), Color(0xFF40300C)]), // wheat field gold
  BgDef(radial: true, stops: [Color(0xFF2A2438), Color(0xFF120F1C)]), // mountain dusk
  // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS: sky/clouds, forest/trees, and space/planets
  // themed additions -- same gradient-only system as every background
  // above, kept dark/jewel-toned so gold/white ayah text stays readable.
  BgDef(radial: true, stops: [Color(0xFF274461), Color(0xFF0C1B2E)]), // dawn clouds
  BgDef(stops: [Color(0xFF1A3350), Color(0xFF3E6488), Color(0xFF23415F)]), // pale blue sky
  BgDef(radial: true, stops: [Color(0xFF0E2B3D), Color(0xFF040E16)]), // overcast sky & mist
  BgDef(stops: [Color(0xFF0B2A1C), Color(0xFF184A2E), Color(0xFF0E3320)]), // pine forest
  BgDef(radial: true, stops: [Color(0xFF15311F), Color(0xFF081A10)]), // misty woodland
  BgDef(stops: [Color(0xFF203218), Color(0xFF4A6B2C), Color(0xFF2B4519)]), // sunlit tree canopy
  BgDef(radial: true, stops: [Color(0xFF060A1E), Color(0xFF01020A)]), // deep space starfield
  BgDef(stops: [Color(0xFF1B0F3A), Color(0xFF4A1E63), Color(0xFF250F42)]), // cosmic nebula
  BgDef(radial: true, stops: [Color(0xFF2E1A4D), Color(0xFF0A0616)]), // violet galaxy
  BgDef(stops: [Color(0xFF3A2410), Color(0xFF8A5A22), Color(0xFF4E3212)]), // ringed planet gold
  BgDef(radial: true, stops: [Color(0xFF102A3E), Color(0xFF041019)]), // blue planet horizon
  BgDef(stops: [Color(0xFF14202E), Color(0xFF33507A), Color(0xFF1D2E46)]), // aurora night sky
];

/// Registered font choices for the ayah text. `family` is what actually gets
/// handed to TextStyle.fontFamily; the two built-ins resolve through
/// google_fonts, uploaded fonts through FontLoader (see StudioState).
class AyahFontChoice {
  final String label;
  final String key; // 'amiri' | 'ruqaa' | custom family name
  const AyahFontChoice(this.key, this.label);
}

const List<AyahFontChoice> kBuiltInFonts = [
  // PATCH_S100_FONTS_SPINSTAR_TINT: DigitalMadina is now the app default;
  // Elgharib stays selectable, just no longer pre-picked. See
  // studio_state.dart's `fontKey` default and ayat_fonts.dart's
  // ayahTextStyle() for the two new bundled-asset cases.
  // PATCH_S154_STUDIO_PRESETS_I18N: `label` is now an app_strings.dart
  // key, not literal display text. Custom, user-uploaded fonts (see
  // `customFonts` / `allFonts` in studio_state.dart) keep their raw
  // filename in this same field on purpose -- t() returns an unknown key
  // unchanged, so a filename just displays as-is instead of resolving.
  AyahFontChoice('elgharib', 'preset.font.elgharib'),
  AyahFontChoice('amiri', 'preset.font.amiri'),
  AyahFontChoice('ruqaa', 'preset.font.ruqaa'),
  AyahFontChoice('tharwatemara', 'preset.font.tharwatemara'),
  AyahFontChoice('digitalmadina', 'preset.font.digitalmadina'),
  // PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: three more bundled fonts.
  AyahFontChoice('digitalkhatt', 'preset.font.digitalkhatt'),
  AyahFontChoice('elgharib_lpmq', 'preset.font.elgharib_lpmq'),
  // PATCH_S148_REMAINING_FONTS_AND_SELECTED_CHIP_FIX: 4 more bundled fonts.
  // PATCH_S149_REMOVE_FOUR_FONT_OPTIONS: elgharib_a001, elgharib_a603,
  // elgharib_qcf4 and amiri_quran (text_editor_pro.dart) removed from
  // the pickers by request -- their pubspec/ayahTextStyle() wiring is
  // left in place, just unreachable from the UI now.
  AyahFontChoice('elgharib_eid', 'preset.font.elgharib_eid'),
  AyahFontChoice('pf_monumenta', 'preset.font.pf_monumenta'),
];

class AyahTemplate {
  final String name;
  final String desc;
  final AyahTextPosition pos;
  final FrameExtra extra;
  final String fontKey;
  final Color color;
  const AyahTemplate({
    required this.name,
    required this.desc,
    required this.pos,
    required this.extra,
    required this.fontKey,
    required this.color,
  });
}

const List<AyahTemplate> kTemplates = [
  AyahTemplate(
      name: 'preset.template.1.name',
      desc: 'preset.template.1.desc',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.none,
      fontKey: 'amiri',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'preset.template.2.name',
      desc: 'preset.template.2.desc',
      pos: AyahTextPosition.center,
      extra: FrameExtra.none,
      fontKey: 'amiri',
      color: Color(0xFFECC875)),
  AyahTemplate(
      name: 'preset.template.3.name',
      desc: 'preset.template.3.desc',
      pos: AyahTextPosition.top,
      extra: FrameExtra.none,
      fontKey: 'ruqaa',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'preset.template.4.name',
      desc: 'preset.template.4.desc',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.none,
      fontKey: 'amiri',
      color: Color(0xFFFFFFFF)),
  AyahTemplate(
      name: 'preset.template.5.name',
      desc: 'preset.template.5.desc',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.boxed,
      fontKey: 'amiri',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'preset.template.6.name',
      desc: 'preset.template.6.desc',
      pos: AyahTextPosition.center,
      extra: FrameExtra.framed,
      fontKey: 'ruqaa',
      color: Color(0xFFECC875)),
  // PATCH_S38_VIDEO_EFFECTS
  AyahTemplate(
      name: 'preset.template.7.name',
      desc: 'preset.template.7.desc',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.glass,
      fontKey: 'amiri',
      color: Color(0xFFFFFFFF)),
  // PATCH_S103_MORE_TEMPLATES: 12 more -- spread across all 5 fonts (including
  // the S100 tharwatemara/digitalmadina, unused by any template until
  // now), all 3 positions, and every FrameExtra style.
  AyahTemplate(
      name: 'preset.template.8.name',
      desc: 'preset.template.8.desc',
      pos: AyahTextPosition.top,
      extra: FrameExtra.none,
      fontKey: 'tharwatemara',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'preset.template.9.name',
      desc: 'preset.template.9.desc',
      pos: AyahTextPosition.center,
      extra: FrameExtra.none,
      fontKey: 'digitalmadina',
      color: Color(0xFFFFFFFF)),
  AyahTemplate(
      name: 'preset.template.10.name',
      desc: 'preset.template.10.desc',
      pos: AyahTextPosition.top,
      extra: FrameExtra.glass,
      fontKey: 'amiri',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'preset.template.11.name',
      desc: 'preset.template.11.desc',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.framed,
      fontKey: 'ruqaa',
      color: Color(0xFFECC875)),
  AyahTemplate(
      name: 'preset.template.12.name',
      desc: 'preset.template.12.desc',
      pos: AyahTextPosition.top,
      extra: FrameExtra.glass,
      fontKey: 'tharwatemara',
      color: Color(0xFFFFFFFF)),
  AyahTemplate(
      name: 'preset.template.13.name',
      desc: 'preset.template.13.desc',
      pos: AyahTextPosition.center,
      extra: FrameExtra.none,
      fontKey: 'amiri',
      color: Color(0xFF8FBBAF)),
  AyahTemplate(
      name: 'preset.template.14.name',
      desc: 'preset.template.14.desc',
      pos: AyahTextPosition.center,
      extra: FrameExtra.framed,
      fontKey: 'digitalmadina',
      color: Color(0xFFECC875)),
  AyahTemplate(
      name: 'preset.template.15.name',
      desc: 'preset.template.15.desc',
      pos: AyahTextPosition.center,
      extra: FrameExtra.glass,
      fontKey: 'elgharib',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'preset.template.16.name',
      desc: 'preset.template.16.desc',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.none,
      fontKey: 'elgharib',
      color: Color(0xFFFFFFFF)),
  AyahTemplate(
      name: 'preset.template.17.name',
      desc: 'preset.template.17.desc',
      pos: AyahTextPosition.top,
      extra: FrameExtra.boxed,
      fontKey: 'ruqaa',
      color: Color(0xFFC9A24B)),
  AyahTemplate(
      name: 'preset.template.18.name',
      desc: 'preset.template.18.desc',
      pos: AyahTextPosition.center,
      extra: FrameExtra.none,
      fontKey: 'tharwatemara',
      color: Color(0xFFA8C5D6)),
  AyahTemplate(
      name: 'preset.template.19.name',
      desc: 'preset.template.19.desc',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.glass,
      fontKey: 'digitalmadina',
      color: Color(0xFFECC875)),
];

const List<Color> kTextColors = [
  Color(0xFFECE2CB),
  Color(0xFFECC875),
  Color(0xFFFFFFFF),
  Color(0xFF8FBBAF),
  Color(0xFFC9A24B),
  Color(0xFFE8D5A8),
  Color(0xFF7FA88F),
  Color(0xFFA8C5D6),
  Color(0xFFD9A5B0),
  Color(0xFFF2F2F2),
];

const List<String> kReciters = [
  // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: grew from 6 to 20. Every name
  // below is matched at runtime against mp3quran.net's live reciter
  // catalog (see ReciterAudioService) for the "تنزيل من الإنترنت" button --
  // no per-reciter server URL is hardcoded here.
  'الشيخ الدوسري',
  'مشاري العفاسي',
  'عبدالباسط عبدالصمد',
  'ماهر المعيقلي',
  'ياسر الدوسري',
  'سعود الشريم',
  'عبدالرحمن السديس',
  'سعد الغامدي',
  'أحمد العجمي',
  'محمود خليل الحصري',
  'محمد صديق المنشاوي',
  'علي الحذيفي',
  'محمد أيوب',
  'ناصر القطامي',
  'هاني الرفاعي',
  'أبو بكر الشاطري',
  'خالد الجليل',
  'فارس عباد',
  'بندر بليلة',
  'صلاح البدير',
];

const String kBasmala = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ';
const String kDefaultOutro = 'صدق الله العظيم';

// PATCH_S107_CURATED_NATURE_BACKGROUNDS: bundled nature/space photo
// backgrounds, selectable with one tap alongside the gradient presets
// and your own uploaded backgrounds.
class CuratedBg {
  final String asset;
  final String label;
  const CuratedBg(this.asset, this.label);
}

const List<CuratedBg> kCuratedBackgrounds = [
  CuratedBg('assets/backgrounds/curated/moon_earth.jpg', 'الأرض من فوق سطح القمر'),
  CuratedBg('assets/backgrounds/curated/clouds_sunburst_trees.jpg', 'أشعة الشمس بين الغيوم والأشجار'),
  CuratedBg('assets/backgrounds/curated/blue_sky_clouds.jpg', 'سماء زرقاء صافية وغيوم'),
  CuratedBg('assets/backgrounds/curated/waterfall_moss.jpg', 'شلال بين صخور مغطاة بالطحالب'),
  CuratedBg('assets/backgrounds/curated/waterfall_aerial.jpg', 'شلال ونهر من الأعلى'),
];
