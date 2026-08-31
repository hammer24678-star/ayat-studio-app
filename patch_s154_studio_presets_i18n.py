# patch_s154_studio_presets_i18n.py
#
# PART B1 of the deferred i18n work noted in PATCH_S152's header
# ("home_screen.dart's own remaining strings" / "studio_presets.dart").
# This covers studio_presets.dart's *displayed* labels only.
#
# Scope note, found while auditing call sites before writing this patch:
# kAspectRatios and kCuratedBackgrounds were EXCLUDED on purpose.
#   - kAspectRatios: already fully localized via `t('aspect.${enum.name}')`
#     since PATCH_S128 -- its own tuple's Arabic-only 2nd field is dead
#     code for display purposes. This patch DOES fix one leftover bug
#     where home_screen.dart's fit-mode label still read that dead field
#     directly instead of going through the i18n key (see hunk 2 below).
#   - kCuratedBackgrounds: its `.label` field isn't rendered anywhere in
#     home_screen.dart (only `.asset` is, as an Image.asset) -- nothing to
#     localize there. Left untouched.
#   - kReciters / kBasmala / kDefaultOutro: still deliberately untouched,
#     per PATCH_S152 -- proper names / verbatim Qur'anic Arabic, never
#     translated regardless of interface language.
#
# Also NOT covered (left for a later Part B2, on purpose):
#   - home_screen.dart's own remaining ~380 hardcoded strings that don't
#     come from studio_presets.dart at all (panel titles, hints, toasts
#     unrelated to the lists below, etc).
#
# Translation note, per explicit instruction: Arabic (original) + English
# (hand-translated) only. French/Indonesian/Urdu fall back to English,
# same convention PATCH_S152 used for its own additions -- flagged in the
# table comment so a native speaker can find and fill them in later.
#
# Run from the project root.

from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []


def _log(label, status):
    LEDGER.append((label, status))


def apply_literal(rel_path, old, new, label, skip_if=None):
    p = ROOT / rel_path
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel_path} not found under {ROOT}")
    text = p.read_text(encoding="utf-8")
    if skip_if is not None and old not in text and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


APP_STRINGS = 'lib/i18n/app_strings.dart'
STUDIO_PRESETS = 'lib/data/studio_presets.dart'
HOME_SCREEN = 'lib/screens/home_screen.dart'


# -----------------------------------------------------------------------
# 1. app_strings.dart -- add every new key. en hand-translated; fr/id/ur
#    fall back to en (marked below), same as PATCH_S152's own fallback.
# -----------------------------------------------------------------------

NEW_KEYS_BLOCK = """  'textEditorPro.unifiedHintComputed': ['الحجم المشترك المحسوب: {}', 'Computed shared size: {}', 'Computed shared size: {}', 'Computed shared size: {}', 'Computed shared size: {}'],

  // ---- PATCH_S154_STUDIO_PRESETS_I18N: fr/id/ur fall back to en below,
  // not yet hand-translated. ----
  'preset.colorGrade.none': ['بدون تدرّج لوني', 'No color grade', 'No color grade', 'No color grade', 'No color grade'],
  'preset.colorGrade.warmGold': ['ذهبي دافئ', 'Warm gold', 'Warm gold', 'Warm gold', 'Warm gold'],
  'preset.colorGrade.nightTeal': ['ليلي هادئ', 'Calm night', 'Calm night', 'Calm night', 'Calm night'],
  'preset.colorGrade.sepia': ['سيبيا كلاسيكي', 'Classic sepia', 'Classic sepia', 'Classic sepia', 'Classic sepia'],
  'preset.colorGrade.softMono': ['أبيض وأسود ناعم', 'Soft black & white', 'Soft black & white', 'Soft black & white', 'Soft black & white'],
  'preset.videoFit.source': ['بحجم الفيديو الأصلي', 'Original video size', 'Original video size', 'Original video size', 'Original video size'],
  'preset.videoFit.fillCrop': ['ملء الإطار (قص)', 'Fill frame (crop)', 'Fill frame (crop)', 'Fill frame (crop)', 'Fill frame (crop)'],
  'preset.videoFit.fitBlur': ['احتواء + خلفية ضبابية', 'Fit + blurred background', 'Fit + blurred background', 'Fit + blurred background', 'Fit + blurred background'],
  'preset.exportQuality.high': ['جودة قصوى', 'Maximum quality', 'Maximum quality', 'Maximum quality', 'Maximum quality'],
  'preset.exportQuality.balanced': ['متوازن', 'Balanced', 'Balanced', 'Balanced', 'Balanced'],
  'preset.exportQuality.compact': ['حجم أصغر', 'Smaller size', 'Smaller size', 'Smaller size', 'Smaller size'],
  'preset.exportRes.source': ['دقة المصدر', 'Source resolution', 'Source resolution', 'Source resolution', 'Source resolution'],
  'preset.watermarkCorner.topLeft': ['أعلى اليسار', 'Top left', 'Top left', 'Top left', 'Top left'],
  'preset.watermarkCorner.topRight': ['أعلى اليمين', 'Top right', 'Top right', 'Top right', 'Top right'],
  'preset.watermarkCorner.bottomLeft': ['أسفل اليسار', 'Bottom left', 'Bottom left', 'Bottom left', 'Bottom left'],
  'preset.watermarkCorner.bottomRight': ['أسفل اليمين', 'Bottom right', 'Bottom right', 'Bottom right', 'Bottom right'],
  'preset.bgSwitch.ayahs': ['كل عدد آيات', 'Every N ayahs', 'Every N ayahs', 'Every N ayahs', 'Every N ayahs'],
  'preset.bgSwitch.seconds': ['كل عدد ثوانٍ', 'Every N seconds', 'Every N seconds', 'Every N seconds', 'Every N seconds'],
  'preset.bgTransition.hardCut': ['قطع مباشر', 'Hard cut', 'Hard cut', 'Hard cut', 'Hard cut'],
  'preset.bgTransition.crossfade': ['تلاشٍ متداخل', 'Crossfade', 'Crossfade', 'Crossfade', 'Crossfade'],
  'preset.bgTransition.wipeLeft': ['مسح لليسار', 'Wipe left', 'Wipe left', 'Wipe left', 'Wipe left'],
  'preset.bgTransition.wipeRight': ['مسح لليمين', 'Wipe right', 'Wipe right', 'Wipe right', 'Wipe right'],
  'preset.bgTransition.slideUp': ['انزلاق للأعلى', 'Slide up', 'Slide up', 'Slide up', 'Slide up'],
  'preset.bgTransition.slideDown': ['انزلاق للأسفل', 'Slide down', 'Slide down', 'Slide down', 'Slide down'],
  'preset.bgTransition.circleOpen': ['دائرة تتّسع', 'Circle open', 'Circle open', 'Circle open', 'Circle open'],
  'preset.bgTransition.circleClose': ['دائرة تنغلق', 'Circle close', 'Circle close', 'Circle close', 'Circle close'],
  'preset.bgTransition.dissolve': ['تلاشٍ متناثر', 'Dissolve', 'Dissolve', 'Dissolve', 'Dissolve'],
  'preset.bgTransition.pixelize': ['تبكسل', 'Pixelize', 'Pixelize', 'Pixelize', 'Pixelize'],
  'preset.bgTransition.radial': ['مسح شعاعي', 'Radial wipe', 'Radial wipe', 'Radial wipe', 'Radial wipe'],
  'preset.font.elgharib': ['الغريب نون حفص', 'Elgharib Noon Hafs', 'Elgharib Noon Hafs', 'Elgharib Noon Hafs', 'Elgharib Noon Hafs'],
  'preset.font.amiri': ['أميري قرآن (كلاسيكي)', 'Amiri Quran (classic)', 'Amiri Quran (classic)', 'Amiri Quran (classic)', 'Amiri Quran (classic)'],
  'preset.font.ruqaa': ['ريقعة (خط الرقعة)', 'Ruqaa', 'Ruqaa', 'Ruqaa', 'Ruqaa'],
  'preset.font.tharwatemara': ['ثروت عمارة', 'Tharwat Emara', 'Tharwat Emara', 'Tharwat Emara', 'Tharwat Emara'],
  'preset.font.digitalmadina': ['المدينة الرقمية (افتراضي)', 'Digital Madina (default)', 'Digital Madina (default)', 'Digital Madina (default)', 'Digital Madina (default)'],
  'preset.font.digitalkhatt': ['الخط الرقمي الجديد', 'New Digital Khatt', 'New Digital Khatt', 'New Digital Khatt', 'New Digital Khatt'],
  'preset.font.elgharib_lpmq': ['الغريب اللجنة (مصباح طويل)', 'Elgharib LPMQ (Long Lamp)', 'Elgharib LPMQ (Long Lamp)', 'Elgharib LPMQ (Long Lamp)', 'Elgharib LPMQ (Long Lamp)'],
  'preset.font.elgharib_eid': ['الغريب عيد الأضحى', 'Elgharib Eid al-Adha', 'Elgharib Eid al-Adha', 'Elgharib Eid al-Adha', 'Elgharib Eid al-Adha'],
  'preset.font.pf_monumenta': ['PF مونومنتا برو', 'PF Monumenta Pro', 'PF Monumenta Pro', 'PF Monumenta Pro', 'PF Monumenta Pro'],
  'preset.template.1.name': ['سطر سفلي كلاسيكي', 'Classic bottom line', 'Classic bottom line', 'Classic bottom line', 'Classic bottom line'],
  'preset.template.1.desc': ['الآية أسفل الشاشة، ترجمة تحتها', 'Ayah at the bottom of the screen, translation below it', 'Ayah at the bottom of the screen, translation below it', 'Ayah at the bottom of the screen, translation below it', 'Ayah at the bottom of the screen, translation below it'],
  'preset.template.2.name': ['توسّط ذهبي', 'Golden center', 'Golden center', 'Golden center', 'Golden center'],
  'preset.template.2.desc': ['الآية في المنتصف بلون ذهبي', 'Ayah centered in gold', 'Ayah centered in gold', 'Ayah centered in gold', 'Ayah centered in gold'],
  'preset.template.3.name': ['عنوان رقعة علوي', 'Top ruqaa title', 'Top ruqaa title', 'Top ruqaa title', 'Top ruqaa title'],
  'preset.template.3.desc': ['خط الرقعة أعلى الشاشة', 'Ruqaa script at the top of the screen', 'Ruqaa script at the top of the screen', 'Ruqaa script at the top of the screen', 'Ruqaa script at the top of the screen'],
  'preset.template.4.name': ['بساطة بيضاء', 'Plain white', 'Plain white', 'Plain white', 'Plain white'],
  'preset.template.4.desc': ['نص أبيض واضح للقراءة السريعة', 'Clear white text for quick reading', 'Clear white text for quick reading', 'Clear white text for quick reading', 'Clear white text for quick reading'],
  'preset.template.5.name': ['لوحة زجاجية سفلية', 'Bottom glass panel', 'Bottom glass panel', 'Bottom glass panel', 'Bottom glass panel'],
  'preset.template.5.desc': ['نص داخل لوحة شبه شفافة أسفل الشاشة', 'Text inside a translucent panel at the bottom', 'Text inside a translucent panel at the bottom', 'Text inside a translucent panel at the bottom', 'Text inside a translucent panel at the bottom'],
  'preset.template.6.name': ['إطار ذهبي متوسط', 'Center gold frame', 'Center gold frame', 'Center gold frame', 'Center gold frame'],
  'preset.template.6.desc': ['نص داخل إطار مذهّب في المنتصف', 'Text inside a gilded frame, centered', 'Text inside a gilded frame, centered', 'Text inside a gilded frame, centered', 'Text inside a gilded frame, centered'],
  'preset.template.7.name': ['زجاج مصنفر أنيق', 'Elegant frosted glass', 'Elegant frosted glass', 'Elegant frosted glass', 'Elegant frosted glass'],
  'preset.template.7.desc': ['لوحة شبه شفافة بلمسة زجاجية عصرية أسفل الشاشة', 'Translucent panel with a modern glass feel at the bottom', 'Translucent panel with a modern glass feel at the bottom', 'Translucent panel with a modern glass feel at the bottom', 'Translucent panel with a modern glass feel at the bottom'],
  'preset.template.8.name': ['عنوان ثروت علوي', 'Top Tharwat title', 'Top Tharwat title', 'Top Tharwat title', 'Top Tharwat title'],
  'preset.template.8.desc': ['خط ثروت عمارة أعلى الشاشة', 'Tharwat Emara script at the top of the screen', 'Tharwat Emara script at the top of the screen', 'Tharwat Emara script at the top of the screen', 'Tharwat Emara script at the top of the screen'],
  'preset.template.9.name': ['توسّط المدينة الرقمية', 'Digital Madina center', 'Digital Madina center', 'Digital Madina center', 'Digital Madina center'],
  'preset.template.9.desc': ['الآية بخط المدينة الرقمية في المنتصف', 'Ayah in Digital Madina script, centered', 'Ayah in Digital Madina script, centered', 'Ayah in Digital Madina script, centered', 'Ayah in Digital Madina script, centered'],
  'preset.template.10.name': ['لوحة زجاجية علوية', 'Top glass panel', 'Top glass panel', 'Top glass panel', 'Top glass panel'],
  'preset.template.10.desc': ['نص داخل لوحة شبه شفافة أعلى الشاشة', 'Text inside a translucent panel at the top', 'Text inside a translucent panel at the top', 'Text inside a translucent panel at the top', 'Text inside a translucent panel at the top'],
  'preset.template.11.name': ['إطار ذهبي سفلي', 'Bottom gold frame', 'Bottom gold frame', 'Bottom gold frame', 'Bottom gold frame'],
  'preset.template.11.desc': ['نص داخل إطار مذهّب أسفل الشاشة', 'Text inside a gilded frame at the bottom', 'Text inside a gilded frame at the bottom', 'Text inside a gilded frame at the bottom', 'Text inside a gilded frame at the bottom'],
  'preset.template.12.name': ['زجاج مصنفر علوي', 'Top frosted glass', 'Top frosted glass', 'Top frosted glass', 'Top frosted glass'],
  'preset.template.12.desc': ['لوحة زجاجية عصرية أعلى الشاشة', 'Modern glass panel at the top', 'Modern glass panel at the top', 'Modern glass panel at the top', 'Modern glass panel at the top'],
  'preset.template.13.name': ['توسّط زمردي هادئ', 'Calm emerald center', 'Calm emerald center', 'Calm emerald center', 'Calm emerald center'],
  'preset.template.13.desc': ['الآية في المنتصف بلون أخضر زمردي هادئ', 'Ayah centered in calm emerald green', 'Ayah centered in calm emerald green', 'Ayah centered in calm emerald green', 'Ayah centered in calm emerald green'],
  'preset.template.14.name': ['إطار المدينة المتوسط', 'Center Madina frame', 'Center Madina frame', 'Center Madina frame', 'Center Madina frame'],
  'preset.template.14.desc': ['نص داخل إطار مذهّب بخط المدينة الرقمية في المنتصف', 'Text inside a gilded frame in Digital Madina script, centered', 'Text inside a gilded frame in Digital Madina script, centered', 'Text inside a gilded frame in Digital Madina script, centered', 'Text inside a gilded frame in Digital Madina script, centered'],
  'preset.template.15.name': ['لوحة زجاجية متوسطة', 'Center glass panel', 'Center glass panel', 'Center glass panel', 'Center glass panel'],
  'preset.template.15.desc': ['نص داخل لوحة زجاجية شفافة في المنتصف', 'Text inside a translucent glass panel, centered', 'Text inside a translucent glass panel, centered', 'Text inside a translucent glass panel, centered', 'Text inside a translucent glass panel, centered'],
  'preset.template.16.name': ['عنوان الغريب سفلي', 'Bottom Elgharib title', 'Bottom Elgharib title', 'Bottom Elgharib title', 'Bottom Elgharib title'],
  'preset.template.16.desc': ['خط الغريب نون حفص أسفل الشاشة بوضوح', 'Elgharib Noon Hafs script clearly at the bottom', 'Elgharib Noon Hafs script clearly at the bottom', 'Elgharib Noon Hafs script clearly at the bottom', 'Elgharib Noon Hafs script clearly at the bottom'],
  'preset.template.17.name': ['صندوق كهرماني علوي', 'Top amber box', 'Top amber box', 'Top amber box', 'Top amber box'],
  'preset.template.17.desc': ['نص داخل صندوق كهرماني أعلى الشاشة', 'Text inside an amber box at the top', 'Text inside an amber box at the top', 'Text inside an amber box at the top', 'Text inside an amber box at the top'],
  'preset.template.18.name': ['توسّط سماوي', 'Calm sky center', 'Calm sky center', 'Calm sky center', 'Calm sky center'],
  'preset.template.18.desc': ['الآية في المنتصف بلون أزرق سماوي هادئ', 'Ayah centered in calm sky blue', 'Ayah centered in calm sky blue', 'Ayah centered in calm sky blue', 'Ayah centered in calm sky blue'],
  'preset.template.19.name': ['لوحة زجاجية ذهبية سفلية', 'Bottom golden glass panel', 'Bottom golden glass panel', 'Bottom golden glass panel', 'Bottom golden glass panel'],
  'preset.template.19.desc': ['لوحة زجاجية عصرية بلون ذهبي أسفل الشاشة', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom'],
};

/// Exposed for the i18n test — every row must have one entry per [AppLang].
"""

APP_STRINGS_OLD = """  'textEditorPro.unifiedHintComputed': ['الحجم المشترك المحسوب: {}', 'Computed shared size: {}', 'Computed shared size: {}', 'Computed shared size: {}', 'Computed shared size: {}'],
};

/// Exposed for the i18n test — every row must have one entry per [AppLang].
"""


def patch_app_strings():
    apply_literal(APP_STRINGS, APP_STRINGS_OLD, NEW_KEYS_BLOCK,
                  'app_strings.dart: add preset.* keys (S154)',
                  skip_if="preset.colorGrade.none")


# -----------------------------------------------------------------------
# 2. studio_presets.dart -- swap literal Arabic labels for i18n keys in
#    the const tuple/class lists. kAspectRatios and kCuratedBackgrounds
#    untouched (see header note above). kReciters/kBasmala/kDefaultOutro
#    untouched (never translated, per S152).
# -----------------------------------------------------------------------

PRESETS_HUNKS = [
    (
        "kColorGrades",
        """const List<(ColorGrade, String)> kColorGrades = [
  (ColorGrade.none, 'بدون تدرّج لوني'),
  (ColorGrade.warmGold, 'ذهبي دافئ'),
  (ColorGrade.nightTeal, 'ليلي هادئ'),
  (ColorGrade.sepia, 'سيبيا كلاسيكي'),
  (ColorGrade.softMono, 'أبيض وأسود ناعم'),
];""",
        """const List<(ColorGrade, String)> kColorGrades = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is now an app_strings.dart
  // key, not literal display text -- look it up with _t()/t() at the
  // call site instead of rendering directly.
  (ColorGrade.none, 'preset.colorGrade.none'),
  (ColorGrade.warmGold, 'preset.colorGrade.warmGold'),
  (ColorGrade.nightTeal, 'preset.colorGrade.nightTeal'),
  (ColorGrade.sepia, 'preset.colorGrade.sepia'),
  (ColorGrade.softMono, 'preset.colorGrade.softMono'),
];""",
    ),
    (
        "kVideoFitModes",
        """const List<(VideoFitMode, String)> kVideoFitModes = [
  (VideoFitMode.source, 'بحجم الفيديو الأصلي'),
  (VideoFitMode.fillCrop, 'ملء الإطار (قص)'),
  (VideoFitMode.fitBlur, 'احتواء + خلفية ضبابية'),
];""",
        """const List<(VideoFitMode, String)> kVideoFitModes = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (VideoFitMode.source, 'preset.videoFit.source'),
  (VideoFitMode.fillCrop, 'preset.videoFit.fillCrop'),
  (VideoFitMode.fitBlur, 'preset.videoFit.fitBlur'),
];""",
    ),
    (
        "kExportQualities",
        """const List<(ExportQuality, String)> kExportQualities = [
  (ExportQuality.high, 'جودة قصوى'),
  (ExportQuality.balanced, 'متوازن'),
  (ExportQuality.compact, 'حجم أصغر'),
];""",
        """const List<(ExportQuality, String)> kExportQualities = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (ExportQuality.high, 'preset.exportQuality.high'),
  (ExportQuality.balanced, 'preset.exportQuality.balanced'),
  (ExportQuality.compact, 'preset.exportQuality.compact'),
];""",
    ),
    (
        "kExportResolutions",
        """const List<(ExportResolutionCap, String)> kExportResolutions = [
  (ExportResolutionCap.source, 'دقة المصدر'),
  (ExportResolutionCap.hd1080, '1080p'),
  (ExportResolutionCap.hd720, '720p'),
];""",
        """const List<(ExportResolutionCap, String)> kExportResolutions = [
  // PATCH_S154_STUDIO_PRESETS_I18N: only 'source' had translatable text;
  // '1080p'/'720p' are units, not language, and stay literal on purpose.
  (ExportResolutionCap.source, 'preset.exportRes.source'),
  (ExportResolutionCap.hd1080, '1080p'),
  (ExportResolutionCap.hd720, '720p'),
];""",
    ),
    (
        "kWatermarkCorners",
        """const List<(WatermarkCorner, String)> kWatermarkCorners = [
  (WatermarkCorner.topLeft, 'أعلى اليسار'),
  (WatermarkCorner.topRight, 'أعلى اليمين'),
  (WatermarkCorner.bottomLeft, 'أسفل اليسار'),
  (WatermarkCorner.bottomRight, 'أسفل اليمين'),
];""",
        """const List<(WatermarkCorner, String)> kWatermarkCorners = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (WatermarkCorner.topLeft, 'preset.watermarkCorner.topLeft'),
  (WatermarkCorner.topRight, 'preset.watermarkCorner.topRight'),
  (WatermarkCorner.bottomLeft, 'preset.watermarkCorner.bottomLeft'),
  (WatermarkCorner.bottomRight, 'preset.watermarkCorner.bottomRight'),
];""",
    ),
    (
        "kBgSwitchTriggers",
        """const List<(BgSwitchTrigger, String)> kBgSwitchTriggers = [
  (BgSwitchTrigger.ayahs, 'كل عدد آيات'),
  (BgSwitchTrigger.seconds, 'كل عدد ثوانٍ'),
];""",
        """const List<(BgSwitchTrigger, String)> kBgSwitchTriggers = [
  // PATCH_S154_STUDIO_PRESETS_I18N: 2nd field is an app_strings.dart key.
  (BgSwitchTrigger.ayahs, 'preset.bgSwitch.ayahs'),
  (BgSwitchTrigger.seconds, 'preset.bgSwitch.seconds'),
];""",
    ),
    (
        "kBgTransitionStyles",
        """const List<(BgTransitionStyle, String)> kBgTransitionStyles = [
  (BgTransitionStyle.hardCut, 'قطع مباشر'),
  (BgTransitionStyle.crossfade, 'تلاشٍ متداخل'),
  // PATCH_S70_MORE_TRANSITIONS
  (BgTransitionStyle.wipeLeft, 'مسح لليسار'),
  (BgTransitionStyle.wipeRight, 'مسح لليمين'),
  (BgTransitionStyle.slideUp, 'انزلاق للأعلى'),
  (BgTransitionStyle.slideDown, 'انزلاق للأسفل'),
  (BgTransitionStyle.circleOpen, 'دائرة تتّسع'),
  (BgTransitionStyle.circleClose, 'دائرة تنغلق'),
  (BgTransitionStyle.dissolve, 'تلاشٍ متناثر'),
  (BgTransitionStyle.pixelize, 'تبكسل'),
  (BgTransitionStyle.radial, 'مسح شعاعي'),
];""",
        """const List<(BgTransitionStyle, String)> kBgTransitionStyles = [
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
];""",
    ),
    (
        "kBuiltInFonts",
        """  AyahFontChoice('elgharib', 'الغريب نون حفص'),
  AyahFontChoice('amiri', 'أميري قرآن (كلاسيكي)'),
  AyahFontChoice('ruqaa', 'ريقعة (خط الرقعة)'),
  AyahFontChoice('tharwatemara', 'ثروت عمارة'),
  AyahFontChoice('digitalmadina', 'المدينة الرقمية (افتراضي)'),
  // PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: three more bundled fonts.
  AyahFontChoice('digitalkhatt', 'الخط الرقمي الجديد'),
  AyahFontChoice('elgharib_lpmq', 'الغريب اللجنة (مصباح طويل)'),
  // PATCH_S148_REMAINING_FONTS_AND_SELECTED_CHIP_FIX: 4 more bundled fonts.
  // PATCH_S149_REMOVE_FOUR_FONT_OPTIONS: elgharib_a001, elgharib_a603,
  // elgharib_qcf4 and amiri_quran (text_editor_pro.dart) removed from
  // the pickers by request -- their pubspec/ayahTextStyle() wiring is
  // left in place, just unreachable from the UI now.
  AyahFontChoice('elgharib_eid', 'الغريب عيد الأضحى'),
  AyahFontChoice('pf_monumenta', 'PF مونومنتا برو'),
];""",
        """  // PATCH_S154_STUDIO_PRESETS_I18N: `label` is now an app_strings.dart
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
];""",
    ),
]

TEMPLATE_FIELD_HUNKS = [
    (1, 'سطر سفلي كلاسيكي', 'الآية أسفل الشاشة، ترجمة تحتها'),
    (2, 'توسّط ذهبي', 'الآية في المنتصف بلون ذهبي'),
    (3, 'عنوان رقعة علوي', 'خط الرقعة أعلى الشاشة'),
    (4, 'بساطة بيضاء', 'نص أبيض واضح للقراءة السريعة'),
    (5, 'لوحة زجاجية سفلية', 'نص داخل لوحة شبه شفافة أسفل الشاشة'),
    (6, 'إطار ذهبي متوسط', 'نص داخل إطار مذهّب في المنتصف'),
    (7, 'زجاج مصنفر أنيق', 'لوحة شبه شفافة بلمسة زجاجية عصرية أسفل الشاشة'),
    (8, 'عنوان ثروت علوي', 'خط ثروت عمارة أعلى الشاشة'),
    (9, 'توسّط المدينة الرقمية', 'الآية بخط المدينة الرقمية في المنتصف'),
    (10, 'لوحة زجاجية علوية', 'نص داخل لوحة شبه شفافة أعلى الشاشة'),
    (11, 'إطار ذهبي سفلي', 'نص داخل إطار مذهّب أسفل الشاشة'),
    (12, 'زجاج مصنفر علوي', 'لوحة زجاجية عصرية أعلى الشاشة'),
    (13, 'توسّط زمردي هادئ', 'الآية في المنتصف بلون أخضر زمردي هادئ'),
    (14, 'إطار المدينة المتوسط', 'نص داخل إطار مذهّب بخط المدينة الرقمية في المنتصف'),
    (15, 'لوحة زجاجية متوسطة', 'نص داخل لوحة زجاجية شفافة في المنتصف'),
    (16, 'عنوان الغريب سفلي', 'خط الغريب نون حفص أسفل الشاشة بوضوح'),
    (17, 'صندوق كهرماني علوي', 'نص داخل صندوق كهرماني أعلى الشاشة'),
    (18, 'توسّط سماوي', 'الآية في المنتصف بلون أزرق سماوي هادئ'),
    (19, 'لوحة زجاجية ذهبية سفلية', 'لوحة زجاجية عصرية بلون ذهبي أسفل الشاشة'),
]


def patch_studio_presets():
    for label, old, new in PRESETS_HUNKS:
        # skip_if: the first i18n key each hunk introduces -- present only
        # once this specific hunk has already been applied.
        marker = new.split("'")[1]
        apply_literal(STUDIO_PRESETS, old, new,
                      f'studio_presets.dart: {label} -> i18n keys (S154)',
                      skip_if=marker)

    for n, name_ar, desc_ar in TEMPLATE_FIELD_HUNKS:
        old = f"      name: '{name_ar}',\n      desc: '{desc_ar}',"
        new = f"      name: 'preset.template.{n}.name',\n      desc: 'preset.template.{n}.desc',"
        apply_literal(STUDIO_PRESETS, old, new,
                      f'studio_presets.dart: template {n} name/desc -> i18n keys (S154)',
                      skip_if=f'preset.template.{n}.name')


# -----------------------------------------------------------------------
# 3. home_screen.dart -- route every consumer of the fields above through
#    _t(), instead of rendering entry.$2 / f.label / t.name / t.desc
#    directly. Also fixes a leftover bug: the fit-mode fieldLabel was
#    still reading kAspectRatios' dead 2nd field instead of the i18n key
#    the chip row next to it already uses.
# -----------------------------------------------------------------------

HOME_SCREEN_HUNKS = [
    (
        "aspect-ratio interpolation bug (fitMode fieldLabel)",
        """          _fieldLabel(
              'ملاءمة الفيديو مع إطار ${kAspectRatios.firstWhere((r) => r.$1 == state.aspectRatio).$2}'),""",
        """          // PATCH_S154_STUDIO_PRESETS_I18N: was reading kAspectRatios' dead
          // Arabic-only 2nd field directly -- always showed Arabic regardless
          // of interface language, even though the chip row right below this
          // already uses the aspect.* i18n key. Now consistent with it.
          _fieldLabel(_tf('preset.fitModeFrameHint',
              [_t('aspect.${state.aspectRatio.name}')])),""",
    ),
    (
        "kColorGrades chip label",
        """            for (final entry in kColorGrades)
              ChoiceChip(
                label: Text(entry.$2),
                selected: state.colorGrade == entry.$1,""",
        """            for (final entry in kColorGrades)
              ChoiceChip(
                label: Text(_t(entry.$2)),
                selected: state.colorGrade == entry.$1,""",
    ),
    (
        "kVideoFitModes chip label",
        """              for (final entry in kVideoFitModes)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: state.videoFit == entry.$1,""",
        """              for (final entry in kVideoFitModes)
                ChoiceChip(
                  label: Text(_t(entry.$2)),
                  selected: state.videoFit == entry.$1,""",
    ),
    (
        "kExportQualities chip label",
        """            for (final entry in kExportQualities)
              ChoiceChip(
                label: Text(entry.$2),
                selected: state.exportQuality == entry.$1,""",
        """            for (final entry in kExportQualities)
              ChoiceChip(
                label: Text(_t(entry.$2)),
                selected: state.exportQuality == entry.$1,""",
    ),
    (
        "kExportResolutions chip label",
        """            for (final entry in kExportResolutions)
              ChoiceChip(
                label: Text(entry.$2),
                selected: state.exportResolution == entry.$1,""",
        """            for (final entry in kExportResolutions)
              ChoiceChip(
                // PATCH_S154_STUDIO_PRESETS_I18N: '1080p'/'720p' aren't
                // i18n keys and t() returns an unknown key unchanged, so
                // this is safe for all three entries.
                label: Text(_t(entry.$2)),
                selected: state.exportResolution == entry.$1,""",
    ),
    (
        "kWatermarkCorners chip label",
        """              for (final entry in kWatermarkCorners)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: state.watermarkCorner == entry.$1,""",
        """              for (final entry in kWatermarkCorners)
                ChoiceChip(
                  label: Text(_t(entry.$2)),
                  selected: state.watermarkCorner == entry.$1,""",
    ),
    (
        "kBgSwitchTriggers chip label",
        """              for (final entry in kBgSwitchTriggers)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: state.bgSwitchTrigger == entry.$1,""",
        """              for (final entry in kBgSwitchTriggers)
                ChoiceChip(
                  label: Text(_t(entry.$2)),
                  selected: state.bgSwitchTrigger == entry.$1,""",
    ),
    (
        "kBgTransitionStyles chip label",
        """              for (final entry in kBgTransitionStyles)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: state.bgTransitionStyle == entry.$1,""",
        """              for (final entry in kBgTransitionStyles)
                ChoiceChip(
                  label: Text(_t(entry.$2)),
                  selected: state.bgTransitionStyle == entry.$1,""",
    ),
    (
        "font dropdown item label",
        """            for (final f in state.allFonts)
              DropdownMenuItem(value: f.key, child: Text(f.label)),""",
        """            for (final f in state.allFonts)
              // PATCH_S154_STUDIO_PRESETS_I18N: built-in fonts' `.label` is
              // now an i18n key; custom/uploaded fonts keep a raw filename
              // there, which t() returns unchanged since it's not a known
              // key -- one call handles both cases correctly.
              DropdownMenuItem(value: f.key, child: Text(_t(f.label))),""",
    ),
    (
        "templates toast",
        """              state.applyTemplate(i);
              _toast('تم تطبيق قالب: ${kTemplates[i].name}');""",
        """              state.applyTemplate(i);
              _toast(_tf('preset.templateAppliedToast', [_t(kTemplates[i].name)]));""",
    ),
    (
        "templates list name/desc",
        """                        Text(kTemplates[i].name,
                            style: Theme.of(context).textTheme.bodyLarge),
                        Text(kTemplates[i].desc,
                            style: Theme.of(context).textTheme.bodyMedium),""",
        """                        Text(_t(kTemplates[i].name),
                            style: Theme.of(context).textTheme.bodyLarge),
                        Text(_t(kTemplates[i].desc),
                            style: Theme.of(context).textTheme.bodyMedium),""",
    ),
]


HOME_SCREEN_SKIP_MARKERS = [
    "_t('aspect.${state.aspectRatio.name}')",
    "Text(_t(entry.$2)),\n                selected: state.colorGrade",
    "Text(_t(entry.$2)),\n                  selected: state.videoFit",
    "Text(_t(entry.$2)),\n                selected: state.exportQuality",
    "Text(_t(entry.$2)),\n                selected: state.exportResolution",
    "Text(_t(entry.$2)),\n                  selected: state.watermarkCorner",
    "Text(_t(entry.$2)),\n                  selected: state.bgSwitchTrigger",
    "Text(_t(entry.$2)),\n                  selected: state.bgTransitionStyle",
    "DropdownMenuItem(value: f.key, child: Text(_t(f.label))),",
    "_toast(_tf('preset.templateAppliedToast'",
    "Text(_t(kTemplates[i].name),",
]


def patch_home_screen():
    for (label, old, new), marker in zip(HOME_SCREEN_HUNKS, HOME_SCREEN_SKIP_MARKERS):
        apply_literal(HOME_SCREEN, old, new,
                      f'home_screen.dart: {label} (S154)',
                      skip_if=marker)


# -----------------------------------------------------------------------
# 4. app_strings.dart -- the two new placeholder-format keys the
#    home_screen.dart hunks above reference ({} filled via _tf/f()).
# -----------------------------------------------------------------------

EXTRA_KEYS_OLD = """  'preset.template.19.desc': ['لوحة زجاجية عصرية بلون ذهبي أسفل الشاشة', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom'],
};"""

EXTRA_KEYS_NEW = """  'preset.template.19.desc': ['لوحة زجاجية عصرية بلون ذهبي أسفل الشاشة', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom', 'Modern glass panel in gold at the bottom'],
  'preset.fitModeFrameHint': ['ملاءمة الفيديو مع إطار {}', 'Fit video to the {} frame', 'Fit video to the {} frame', 'Fit video to the {} frame', 'Fit video to the {} frame'],
  'preset.templateAppliedToast': ['تم تطبيق قالب: {}', 'Applied template: {}', 'Applied template: {}', 'Applied template: {}', 'Applied template: {}'],
};"""


def patch_app_strings_extra():
    apply_literal(APP_STRINGS, EXTRA_KEYS_OLD, EXTRA_KEYS_NEW,
                  'app_strings.dart: add preset.fitModeFrameHint / preset.templateAppliedToast (S154)',
                  skip_if="preset.fitModeFrameHint")


def main():
    patch_app_strings()
    patch_app_strings_extra()
    patch_studio_presets()
    patch_home_screen()

    print("\n=== S154 studio-presets-i18n ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==========================================\n")


if __name__ == "__main__":
    main()
