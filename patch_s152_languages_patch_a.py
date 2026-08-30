# patch_s152_languages_patch_a.py
#
# LANGUAGES, PART A -- every remaining hardcoded string on every page
# except the welcome/intro screen and the mushaf reader (deliberately
# excluded, per instruction -- those stay for a later pass), MINUS
# home_screen.dart's own remaining strings and studio_presets.dart, which
# are big enough on their own to be Part B.
#
# Covered here, fully:
#   - sequence_screen.dart      (all remaining strings)
#   - first_run_tour.dart       (all remaining strings)
#   - text_editor_pro.dart      (all remaining strings, including the
#                                 fonts/glow/karaoke content added since by
#                                 PATCH_S145/S148/S149/S150/S151)
#   - ayat_info_dialog.dart     (the About page -- title + full body)
#   - settings_screen.dart      (the one remaining string: Clear button)
#   - text_transitions.dart     (adds a language-aware `label` getter;
#                                 labelAr/labelEn already existed and are
#                                 both complete by hand, this just picks
#                                 between them -- wired into the 2 spots
#                                 in home_screen.dart that used labelAr
#                                 directly)
#
# Arabic and English are hand-translated throughout, including the 7 new
# calligraphy font names PATCH_S148 added (transliterated, since those
# are proper names -- e.g. "الغريب نون حفص" -> "Elgharib (Hafs)", not a literal
# translation) and the new glow-intensity/karaoke-toggle strings PATCH_S145
# (the real one, not this patch) added to the glow card. French,
# Indonesian and Urdu fall back to English for every NEW key this patch
# adds (marked in app_strings.dart) -- not translated, just kept from
# showing Arabic to someone who can't read it. A follow-up language patch
# should replace those three with real translations.
#
# A pre-existing, unrelated key -- textEditorPro.quranicFont -- is removed
# from the table: PATCH_S149 deleted the "خط قرآني" chip this key was for
# (by request; 'amiri' already covers the same font under a different
# key), so the entry was dead weight.
#
# BONUS FIX (unrelated to the above, found while verifying every key this
# patch touches actually resolves): settings_screen.dart's touch-controls
# guide button and the sheet it opens (user_guide_sheet.dart) referenced
# 9 keys -- settings.guide / settings.guideOpen / settings.guideHint and
# guide.title / guide.box / guide.drag / guide.pinch / guide.wordTap /
# guide.timeline -- that were never added to the table AT ALL, in any
# language. Not a translation gap: there was no Arabic text anywhere to
# translate from, so t() was silently returning the raw key string on
# screen. Text for those 9 is written fresh here, not translated from
# anything you wrote -- worth a read before it ships.
#
# NOT covered (left for later, on purpose):
#   - home_screen.dart's own remaining strings (~385 of them -- Part B)
#   - studio_presets.dart (~104 -- also Part B; its consumers are mostly
#     in home_screen.dart, so it travels with it)
#   - stage_effects_library.dart (~65 effect names) and the smaller
#     labelAr getters in stage_effects.dart / subtitle_service.dart /
#     media_service.dart / whisper_service.dart -- found but out of
#     scope for A or B as discussed, flagged for a later patch
#   - kReciters (20 reciter names) and kBasmala/kDefaultOutro in
#     studio_presets.dart -- proper names and verbatim Qur'anic Arabic,
#     deliberately never translated regardless of interface language
#
# Requires PATCH_S144_UNIFIED_TEXT_CARD (and everything up through
# PATCH_S151_CUSTOM_FONTS_IN_CHIP_ROW) already applied -- this patch's
# anchors are written against the project exactly as of that point.
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
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")

TEXT_TRANSITIONS = 'lib/data/text_transitions.dart'
APP_STRINGS = 'lib/i18n/app_strings.dart'
HOME = 'lib/screens/home_screen.dart'
SEQUENCE = 'lib/screens/sequence_screen.dart'
SETTINGS = 'lib/screens/settings_screen.dart'
ABOUT = 'lib/widgets/ayat_info_dialog.dart'
FIRST_RUN_TOUR = 'lib/widgets/first_run_tour.dart'
TEXT_EDITOR_PRO = 'lib/widgets/text_editor_pro.dart'

TEXT_TRANSITIONS_H1_OLD = "//   * it is continuous, with no jump between adjacent frames — a jump IS the\n//     chopping, whatever the frame rate\nimport 'dart:math' as math;\n\n/// Bounds on how long a transition may last, in milliseconds.\n///\n"
TEXT_TRANSITIONS_H1_NEW = "//   * it is continuous, with no jump between adjacent frames — a jump IS the\n//     chopping, whatever the frame rate\nimport 'dart:math' as math;\n\n// PATCH_S145_LANGUAGES_PATCH_A\nimport '../i18n/app_strings.dart';\nimport '../services/app_settings.dart';\n\n/// Bounds on how long a transition may last, in milliseconds.\n///\n"

TEXT_TRANSITIONS_H2_OLD = "        TextTransition.settleIn => 'Settle',\n      };\n\n  /// Transitions that reveal the text progressively rather than moving it as\n  /// a block. Grouped in the picker, because they read very differently and\n  /// they cost more to render.\n"
TEXT_TRANSITIONS_H2_NEW = "        TextTransition.settleIn => 'Settle',\n      };\n\n  // PATCH_S145_LANGUAGES_PATCH_A: labelAr/labelEn above are both\n  // hand-written and complete; this just picks between them by the\n  // current interface language. French/Indonesian/Urdu fall back to\n  // English until a follow-up patch adds dedicated labelFr/labelId/labelUr\n  // switches -- better than showing Arabic to someone who can't read it.\n  String get label =>\n      AppSettings.instance.lang == AppLang.ar ? labelAr : labelEn;\n\n  /// Transitions that reveal the text progressively rather than moving it as\n  /// a block. Grouped in the picker, because they read very differently and\n  /// they cost more to render.\n"

APP_STRINGS_H1_OLD = "    'Surah {} — {}',\n    'سورہ {} — {}',\n  ],\n};\n\n/// Exposed for the i18n test — every row must have one entry per [AppLang].\n"
APP_STRINGS_H1_NEW = "    'Surah {} — {}',\n    'سورہ {} — {}',\n  ],\n\n  // ---- PATCH_S145_LANGUAGES_PATCH_A: sequence_screen.dart, first_run_tour.dart\n  // and text_editor_pro.dart's remaining strings, plus one shared common.*\n  // entry. Arabic and English are hand-translated; French/Indonesian/Urdu\n  // fall back to English for now (better than showing Arabic to someone who\n  // can't read it) -- a follow-up language patch should replace these three\n  // with real translations rather than leaving them on English long-term. ----\n  'common.remove': ['إزالة', 'Remove', 'Remove', 'Remove', 'Remove'],\n  'sequence.busyRendering': ['جارٍ تركيب المقاطع… قد يستغرق هذا وقتًا حسب الطول والعدد.', 'Assembling the clips… this may take a while depending on length and count.', 'Assembling the clips… this may take a while depending on length and count.', 'Assembling the clips… this may take a while depending on length and count.', 'Assembling the clips… this may take a while depending on length and count.'],\n  'sequence.durationMinSec': ['{}د {}ث', '{}m {}s', '{}m {}s', '{}m {}s', '{}m {}s'],\n  'sequence.durationSecOnly': ['{}ث', '{}s', '{}s', '{}s', '{}s'],\n  'sequence.trimStartSec': ['بداية (ث)', 'Start (s)', 'Start (s)', 'Start (s)', 'Start (s)'],\n  'sequence.trimDurationSec': ['مدة (ث)', 'Duration (s)', 'Duration (s)', 'Duration (s)', 'Duration (s)'],\n  'firstRunTour.step1Title': ['ارفع تلاوة', 'Upload a recitation', 'Upload a recitation', 'Upload a recitation', 'Upload a recitation'],\n  'firstRunTour.step1Desc': ['فيديو أو ملف صوتي — ولو صوت فقط ضع خلفية صورة أو فيديو', 'A video or audio file — if it\\'s audio only, add an image or video background', 'A video or audio file — if it\\'s audio only, add an image or video background', 'A video or audio file — if it\\'s audio only, add an image or video background', 'A video or audio file — if it\\'s audio only, add an image or video background'],\n  'firstRunTour.step2Title': ['اختر الآيات', 'Choose the ayat', 'Choose the ayat', 'Choose the ayat', 'Choose the ayat'],\n  'firstRunTour.step2Desc': ['بالكشف التلقائي أو يدويًا من السورة والآية — النص يأتي من المصحف دائمًا', 'Automatically detected, or picked manually by surah and ayah — the text always comes from the mushaf', 'Automatically detected, or picked manually by surah and ayah — the text always comes from the mushaf', 'Automatically detected, or picked manually by surah and ayah — the text always comes from the mushaf', 'Automatically detected, or picked manually by surah and ayah — the text always comes from the mushaf'],\n  'firstRunTour.step3Title': ['صدّر', 'Export', 'Export', 'Export', 'Export'],\n  'firstRunTour.step3Desc': ['اضبط الشكل من تبويب النص ثم صدّر بجودة تصل إلى مصدر الفيديو', 'Adjust the look from the Text tab, then export at quality up to your source video', 'Adjust the look from the Text tab, then export at quality up to your source video', 'Adjust the look from the Text tab, then export at quality up to your source video', 'Adjust the look from the Text tab, then export at quality up to your source video'],\n  'firstRunTour.start': ['ابدأ', 'Start', 'Start', 'Start', 'Start'],\n  'firstRunTour.next': ['التالي', 'Next', 'Next', 'Next', 'Next'],\n  'textEditorPro.tabText': ['النص', 'Text', 'Text', 'Text', 'Text'],\n  'textEditorPro.tabBorder': ['الإطار', 'Border', 'Border', 'Border', 'Border'],\n  'textEditorPro.tabShadow': ['الظل', 'Shadow', 'Shadow', 'Shadow', 'Shadow'],\n  'textEditorPro.tabGlow': ['التوهج', 'Glow', 'Glow', 'Glow', 'Glow'],\n  'textEditorPro.tabLabel': ['اللافتة', 'Label', 'Label', 'Label', 'Label'],\n  'textEditorPro.tabOpacity': ['الشفافية', 'Opacity', 'Opacity', 'Opacity', 'Opacity'],\n  'textEditorPro.fontNaskh': ['نسخ', 'Naskh', 'Naskh', 'Naskh', 'Naskh'],\n  'textEditorPro.fontRuqaa': ['رقعة', 'Ruqaa', 'Ruqaa', 'Ruqaa', 'Ruqaa'],\n  'textEditorPro.fontAndalus': ['أندلس', 'Andalusi', 'Andalusi', 'Andalusi', 'Andalusi'],\n  'textEditorPro.fontQalam': ['القلم', 'Qalam', 'Qalam', 'Qalam', 'Qalam'],\n  'textEditorPro.fontKufi': ['الكوفي', 'Kufi', 'Kufi', 'Kufi', 'Kufi'],\n  'textEditorPro.fontElgharib': ['الغريب نون حفص', 'Elgharib (Hafs)', 'Elgharib (Hafs)', 'Elgharib (Hafs)', 'Elgharib (Hafs)'],\n  'textEditorPro.fontDigitalMadina': ['المدينة الرقمية', 'Digital Madinah', 'Digital Madinah', 'Digital Madinah', 'Digital Madinah'],\n  'textEditorPro.fontTharwatEmara': ['ثروت عمارة', 'Tharwat Emara', 'Tharwat Emara', 'Tharwat Emara', 'Tharwat Emara'],\n  'textEditorPro.fontDigitalKhatt': ['الرقمي الجديد', 'New Digital', 'New Digital', 'New Digital', 'New Digital'],\n  'textEditorPro.fontElgharibLpmq': ['الغريب اللجنة', 'Elgharib (Committee)', 'Elgharib (Committee)', 'Elgharib (Committee)', 'Elgharib (Committee)'],\n  'textEditorPro.fontElgharibEid': ['الغريب عيد الأضحى', 'Elgharib (Eid al-Adha)', 'Elgharib (Eid al-Adha)', 'Elgharib (Eid al-Adha)', 'Elgharib (Eid al-Adha)'],\n  'textEditorPro.fontPfMonumenta': ['PF مونومنتا', 'PF Monumenta', 'PF Monumenta', 'PF Monumenta', 'PF Monumenta'],\n  'textEditorPro.glowIntensity': ['شدّة التوهّج', 'Glow intensity', 'Glow intensity', 'Glow intensity', 'Glow intensity'],\n  'textEditorPro.karaokeToggleTitle': ['تظليل الكلمات مع التلاوة (كاريوكي)', 'Light up words with the recitation (karaoke)', 'Light up words with the recitation (karaoke)', 'Light up words with the recitation (karaoke)', 'Light up words with the recitation (karaoke)'],\n  'textEditorPro.karaokeToggleSubtitle': ['عند الإيقاف: تُعرض الآية كاملة دون إضاءة كل كلمة على حدة', 'When off: the whole ayah shows without lighting up word by word', 'When off: the whole ayah shows without lighting up word by word', 'When off: the whole ayah shows without lighting up word by word', 'When off: the whole ayah shows without lighting up word by word'],\n  'textEditorPro.sizeLabel': ['الحجم', 'Size', 'Size', 'Size', 'Size'],\n  'textEditorPro.letterSpacing': ['تباعد الأحرف', 'Letter spacing', 'Letter spacing', 'Letter spacing', 'Letter spacing'],\n  'textEditorPro.borderCardLabel': ['الحد', 'Border', 'Border', 'Border', 'Border'],\n  'textEditorPro.thickness': ['السمك', 'Thickness', 'Thickness', 'Thickness', 'Thickness'],\n  'textEditorPro.distance': ['المسافة', 'Distance', 'Distance', 'Distance', 'Distance'],\n  'textEditorPro.blur': ['الضبابية', 'Blur', 'Blur', 'Blur', 'Blur'],\n  'textEditorPro.sharpness': ['الحدة', 'Sharpness', 'Sharpness', 'Sharpness', 'Sharpness'],\n  'textEditorPro.backgroundLabelParen': ['الخلفية (Label)', 'Background (Label)', 'Background (Label)', 'Background (Label)', 'Background (Label)'],\n  'textEditorPro.overallOpacity': ['الشفافية العامة', 'Overall opacity', 'Overall opacity', 'Overall opacity', 'Overall opacity'],\n  'textEditorPro.unifiedHintOff': ['اجعل كل الآيات سطرًا واحدًا بنفس الحجم المشترك', 'Make every ayah a single line at the same shared size', 'Make every ayah a single line at the same shared size', 'Make every ayah a single line at the same shared size', 'Make every ayah a single line at the same shared size'],\n  'textEditorPro.unifiedHintNoAyat': ['أضف آيات أولًا ليُحسب الحجم المشترك', 'Add ayat first so the shared size can be computed', 'Add ayat first so the shared size can be computed', 'Add ayat first so the shared size can be computed', 'Add ayat first so the shared size can be computed'],\n  'textEditorPro.unifiedHintComputed': ['الحجم المشترك المحسوب: {}', 'Computed shared size: {}', 'Computed shared size: {}', 'Computed shared size: {}', 'Computed shared size: {}'],\n\n  // ---- PATCH_S145_LANGUAGES_PATCH_A bonus fix: these 9 keys were\n  // referenced by settings_screen.dart / user_guide_sheet.dart but never\n  // added to the table at all -- not a translation gap, there was no\n  // Arabic text anywhere to translate from. Written fresh here; please\n  // sanity-check the wording since it wasn't yours to begin with.\n  // French/Indonesian/Urdu fall back to English, same as the rest of\n  // this patch. ----\n  'settings.guide': ['دليل التحكم باللمس', 'Touch controls guide', 'Touch controls guide', 'Touch controls guide', 'Touch controls guide'],\n  'settings.guideOpen': ['فتح الدليل', 'Open the guide', 'Open the guide', 'Open the guide', 'Open the guide'],\n  'settings.guideHint': ['شرح سريع لكل إيماءات اللمس في الاستوديو.', 'A quick explainer for every touch gesture in the studio.', 'A quick explainer for every touch gesture in the studio.', 'A quick explainer for every touch gesture in the studio.', 'A quick explainer for every touch gesture in the studio.'],\n  'guide.title': ['دليل التحكم باللمس', 'Touch controls guide', 'Touch controls guide', 'Touch controls guide', 'Touch controls guide'],\n  'guide.box': ['اسحبي الإطار حول النص لتحريكه، واسحبي أطرافه لتغيير حجمه', 'Drag the box around the text to move it, and drag its corners to resize it', 'Drag the box around the text to move it, and drag its corners to resize it', 'Drag the box around the text to move it, and drag its corners to resize it', 'Drag the box around the text to move it, and drag its corners to resize it'],\n  'guide.drag': ['اسحبي النص مباشرة لتحريكه في أي اتجاه', 'Drag the text directly to move it in any direction', 'Drag the text directly to move it in any direction', 'Drag the text directly to move it in any direction', 'Drag the text directly to move it in any direction'],\n  'guide.pinch': ['اقرصي بإصبعين لتكبير النص أو تصغيره', 'Pinch with two fingers to make the text bigger or smaller', 'Pinch with two fingers to make the text bigger or smaller', 'Pinch with two fingers to make the text bigger or smaller', 'Pinch with two fingers to make the text bigger or smaller'],\n  'guide.wordTap': ['اضغطي على أي كلمة لتلوينها بالأحمر', 'Tap any word to color it red', 'Tap any word to color it red', 'Tap any word to color it red', 'Tap any word to color it red'],\n  'guide.timeline': ['اسحبي على الخط الزمني لتحديد وقت ظهور كل آية يدويًا', 'Drag along the timeline to manually set when each ayah appears', 'Drag along the timeline to manually set when each ayah appears', 'Drag along the timeline to manually set when each ayah appears', 'Drag along the timeline to manually set when each ayah appears'],\n};\n\n/// Exposed for the i18n test — every row must have one entry per [AppLang].\n"

HOME_H1_OLD = "\n  /// Shorthand for a localized string in this screen's chrome.\n  String _t(String key) => AppSettings.instance.strings.t(key);\n\n  // PATCH_S123_QURAN_ENTRY: an ayah chosen while reading the mushaf comes\n  // straight back here as the studio's current ayah -- same path a manual\n"
HOME_H1_NEW = "\n  /// Shorthand for a localized string in this screen's chrome.\n  String _t(String key) => AppSettings.instance.strings.t(key);\n  // PATCH_S141_HOME_SEQUENCE_ABOUT_I18N: same shorthand, with `{}` placeholders filled left\n  // to right -- see AppStrings.f.\n  String _tf(String key, List<Object> args) =>\n      AppSettings.instance.strings.f(key, args);\n\n  // PATCH_S123_QURAN_ENTRY: an ayah chosen while reading the mushaf comes\n  // straight back here as the studio's current ayah -- same path a manual\n"

HOME_H2_OLD = '            children: [\n              for (final t in plain)\n                ChoiceChip(\n                  label: Text(t.labelAr),\n                  selected: current == t,\n                  onSelected: (_) => onPick(t),\n                ),\n'
HOME_H2_NEW = '            children: [\n              for (final t in plain)\n                ChoiceChip(\n                  label: Text(t.label),\n                  selected: current == t,\n                  onSelected: (_) => onPick(t),\n                ),\n'

HOME_H3_OLD = '            children: [\n              for (final t in reveals)\n                ChoiceChip(\n                  label: Text(t.labelAr),\n                  selected: current == t,\n                  onSelected: (_) => onPick(t),\n                ),\n'
HOME_H3_NEW = '            children: [\n              for (final t in reveals)\n                ChoiceChip(\n                  label: Text(t.label),\n                  selected: current == t,\n                  onSelected: (_) => onPick(t),\n                ),\n'

SEQUENCE_H1_OLD = "  bool _busy = false;\n  String _status = '';\n\n  @override\n  void initState() {\n    super.initState();\n"
SEQUENCE_H1_NEW = "  bool _busy = false;\n  String _status = '';\n\n  // PATCH_S141_HOME_SEQUENCE_ABOUT_I18N: same shorthand home_screen.dart uses for its chrome.\n  String _t(String key) => AppSettings.instance.strings.t(key);\n  String _tf(String key, List<Object> args) =>\n      AppSettings.instance.strings.f(key, args);\n\n  @override\n  void initState() {\n    super.initState();\n"

SEQUENCE_H2_OLD = "    if (_clips.length < 2) return;\n    setState(() {\n      _busy = true;\n      _status = 'جارٍ تركيب المقاطع… قد يستغرق هذا وقتًا حسب الطول والعدد.';\n    });\n    try {\n      final out = await MediaService.renderSequence(\n"
SEQUENCE_H2_NEW = "    if (_clips.length < 2) return;\n    setState(() {\n      _busy = true;\n      _status = _t('sequence.busyRendering');\n    });\n    try {\n      final out = await MediaService.renderSequence(\n"

SEQUENCE_H3_OLD = "  String _fmt(double sec) {\n    final m = sec ~/ 60;\n    final s = (sec % 60).toStringAsFixed(1);\n    return m > 0 ? '${m}د ${s}ث' : '${s}ث';\n  }\n\n  @override\n"
SEQUENCE_H3_NEW = "  String _fmt(double sec) {\n    final m = sec ~/ 60;\n    final s = (sec % 60).toStringAsFixed(1);\n    return m > 0\n        ? _tf('sequence.durationMinSec', [m, s])\n        : _tf('sequence.durationSecOnly', [s]);\n  }\n\n  @override\n"

SEQUENCE_H4_OLD = "    return Scaffold(\n      backgroundColor: AyatColors.ink,\n      appBar: AppBar(\n        title: const Text('تركيب عدة مقاطع'),\n        iconTheme: const IconThemeData(color: AyatColors.gold),\n      ),\n      body: SafeArea(\n"
SEQUENCE_H4_NEW = "    return Scaffold(\n      backgroundColor: AyatColors.ink,\n      appBar: AppBar(\n        title: Text(_t('sequence.title')),\n        iconTheme: const IconThemeData(color: AyatColors.gold),\n      ),\n      body: SafeArea(\n"

SEQUENCE_H5_OLD = "            Padding(\n              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),\n              child: Text(\n                'أضيفي مقاطع بالترتيب الذي تريدينه، وقصّي كل واحد على حدة، '\n                'واختاري طريقة الانتقال بينها. النتيجة ملف واحد يصبح هو مقطع '\n                'الاستوديو — فتعمل عليه المزامنة التلقائية والتأثيرات والتصدير '\n                'كالمعتاد.',\n                style: GoogleFonts.tajawal(\n                    color: AyatColors.parchmentDim, fontSize: 12, height: 1.7),\n              ),\n"
SEQUENCE_H5_NEW = "            Padding(\n              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),\n              child: Text(\n                _t('sequence.subtitle'),\n                style: GoogleFonts.tajawal(\n                    color: AyatColors.parchmentDim, fontSize: 12, height: 1.7),\n              ),\n"

SEQUENCE_H6_OLD = "            Expanded(\n              child: _clips.isEmpty\n                  ? Center(\n                      child: Text('لم تتم إضافة أي مقطع بعد',\n                          style: GoogleFonts.tajawal(\n                              color: AyatColors.parchmentDim)),\n                    )\n"
SEQUENCE_H6_NEW = "            Expanded(\n              child: _clips.isEmpty\n                  ? Center(\n                      child: Text(_t('sequence.noClipsYet'),\n                          style: GoogleFonts.tajawal(\n                              color: AyatColors.parchmentDim)),\n                    )\n"

SEQUENCE_H7_OLD = "                  ),\n                ),\n                IconButton(\n                  tooltip: 'إزالة',\n                  icon: const Icon(Icons.delete_outline,\n                      color: AyatColors.parchmentDim, size: 20),\n                  onPressed: () => setState(() => _clips.removeAt(i)),\n"
SEQUENCE_H7_NEW = "                  ),\n                ),\n                IconButton(\n                  tooltip: _t('common.remove'),\n                  icon: const Icon(Icons.delete_outline,\n                      color: AyatColors.parchmentDim, size: 20),\n                  onPressed: () => setState(() => _clips.removeAt(i)),\n"

SEQUENCE_H8_OLD = "              ],\n            ),\n            const SizedBox(height: 6),\n            Text('يبدأ عند ${_fmt(c.start)} · المدة ${_fmt(c.duration)}',\n                style: GoogleFonts.tajawal(\n                    color: AyatColors.parchmentDim, fontSize: 11)),\n            Row(\n              children: [\n                Expanded(\n                  child: _trimField(\n                    label: 'بداية (ث)',\n                    value: c.start,\n                    onChanged: (v) => setState(\n                        () => _clips[i] = c.copyWith(start: v.clamp(0, 36000))),\n"
SEQUENCE_H8_NEW = "              ],\n            ),\n            const SizedBox(height: 6),\n            Text(\n                _tf('sequence.clipStartDuration',\n                    [_fmt(c.start), _fmt(c.duration)]),\n                style: GoogleFonts.tajawal(\n                    color: AyatColors.parchmentDim, fontSize: 11)),\n            Row(\n              children: [\n                Expanded(\n                  child: _trimField(\n                    label: _t('sequence.trimStartSec'),\n                    value: c.start,\n                    onChanged: (v) => setState(\n                        () => _clips[i] = c.copyWith(start: v.clamp(0, 36000))),\n"

SEQUENCE_H9_OLD = "                const SizedBox(width: 10),\n                Expanded(\n                  child: _trimField(\n                    label: 'مدة (ث)',\n                    value: c.duration,\n                    onChanged: (v) => setState(() =>\n                        _clips[i] = c.copyWith(duration: v.clamp(0.3, 3600))),\n"
SEQUENCE_H9_NEW = "                const SizedBox(width: 10),\n                Expanded(\n                  child: _trimField(\n                    label: _t('sequence.trimDurationSec'),\n                    value: c.duration,\n                    onChanged: (v) => setState(() =>\n                        _clips[i] = c.copyWith(duration: v.clamp(0.3, 3600))),\n"

SEQUENCE_H10_OLD = "        crossAxisAlignment: CrossAxisAlignment.stretch,\n        children: [\n          if (_clips.length >= 2) ...[\n            Text('الانتقال بين المقاطع',\n                style: GoogleFonts.tajawal(\n                    color: AyatColors.gold,\n                    fontSize: 12,\n"
SEQUENCE_H10_NEW = "        crossAxisAlignment: CrossAxisAlignment.stretch,\n        children: [\n          if (_clips.length >= 2) ...[\n            Text(_t('sequence.transitionBetweenClips'),\n                style: GoogleFonts.tajawal(\n                    color: AyatColors.gold,\n                    fontSize: 12,\n"

SEQUENCE_H11_OLD = "            ),\n            if (_transition != SequenceTransition.cut) ...[\n              const SizedBox(height: 4),\n              Text('مدة الانتقال: ${_transitionSec.toStringAsFixed(1)}ث',\n                  style: GoogleFonts.tajawal(\n                      color: AyatColors.parchmentDim, fontSize: 11.5)),\n              Slider(\n"
SEQUENCE_H11_NEW = "            ),\n            if (_transition != SequenceTransition.cut) ...[\n              const SizedBox(height: 4),\n              Text(\n                  _tf('sequence.transitionDuration',\n                      [_transitionSec.toStringAsFixed(1)]),\n                  style: GoogleFonts.tajawal(\n                      color: AyatColors.parchmentDim, fontSize: 11.5)),\n              Slider(\n"

SEQUENCE_H12_OLD = "            ],\n            const SizedBox(height: 6),\n            Text(\n              'الطول النهائي التقريبي: ${_fmt(total)}'\n              '${_transition != SequenceTransition.cut ? ' (كل انتقال يقصّر الناتج بمقدار مدته)' : ''}',\n              style: GoogleFonts.tajawal(\n                  color: AyatColors.parchmentDim, fontSize: 11.5),\n            ),\n"
SEQUENCE_H12_NEW = "            ],\n            const SizedBox(height: 6),\n            Text(\n              _tf('sequence.approxFinalLength', [_fmt(total)]) +\n                  (_transition != SequenceTransition.cut\n                      ? _t('sequence.transitionShortensNote')\n                      : ''),\n              style: GoogleFonts.tajawal(\n                  color: AyatColors.parchmentDim, fontSize: 11.5),\n            ),\n"

SEQUENCE_H13_OLD = "                child: OutlinedButton.icon(\n                  onPressed: _busy ? null : _pick,\n                  icon: const Icon(Icons.add, size: 18),\n                  label: const Text('إضافة مقاطع'),\n                ),\n              ),\n              const SizedBox(width: 10),\n"
SEQUENCE_H13_NEW = "                child: OutlinedButton.icon(\n                  onPressed: _busy ? null : _pick,\n                  icon: const Icon(Icons.add, size: 18),\n                  label: Text(_t('sequence.addClips')),\n                ),\n              ),\n              const SizedBox(width: 10),\n"

SEQUENCE_H14_OLD = "                                strokeWidth: 2, color: AyatColors.goldBright),\n                          )\n                        : Text(\n                            'تركيب المقاطع',\n                            style: GoogleFonts.tajawal(\n                              color: _clips.length < 2\n                                  ? AyatColors.parchmentDim\n"
SEQUENCE_H14_NEW = "                                strokeWidth: 2, color: AyatColors.goldBright),\n                          )\n                        : Text(\n                            _t('sequence.assembleClips'),\n                            style: GoogleFonts.tajawal(\n                              color: _clips.length < 2\n                                  ? AyatColors.parchmentDim\n"

SEQUENCE_H15_OLD = "          if (_clips.length < 2)\n            Padding(\n              padding: const EdgeInsets.only(top: 8),\n              child: Text('أضيفي مقطعين على الأقل للتركيب.',\n                  style: GoogleFonts.tajawal(\n                      color: AyatColors.parchmentDim, fontSize: 11.5)),\n            ),\n"
SEQUENCE_H15_NEW = "          if (_clips.length < 2)\n            Padding(\n              padding: const EdgeInsets.only(top: 8),\n              child: Text(_t('sequence.addTwoClipsMin'),\n                  style: GoogleFonts.tajawal(\n                      color: AyatColors.parchmentDim, fontSize: 11.5)),\n            ),\n"

SETTINGS_H1_OLD = "                        },\n                  icon: const Icon(Icons.delete_outline, size: 17),\n                  label: Text(\n                    _settings.lang == AppLang.ar ? 'مسح' : 'Clear',\n                    style: GoogleFonts.tajawal(fontSize: 12),\n                  ),\n                  style: TextButton.styleFrom(\n"
SETTINGS_H1_NEW = "                        },\n                  icon: const Icon(Icons.delete_outline, size: 17),\n                  label: Text(\n                    // PATCH_S141_HOME_SEQUENCE_ABOUT_I18N: this was\n                    // hardcoded ar/en-only, silently showing English\n                    // to fr/id/ur users -- route through the table\n                    // like every other string on this screen.\n                    s.t('settings.clearCache'),\n                    style: GoogleFonts.tajawal(fontSize: 12),\n                  ),\n                  style: TextButton.styleFrom(\n"

ABOUT_H1_OLD = '// Shared "about this app" dialog — shown from both the welcome screen\'s\n// «معرفة المزيد عن التطبيق» link and the studio\'s app-bar (i) button, so\n// the copy only lives in one place.\nimport \'package:flutter/material.dart\';\n\nimport \'../theme/ayat_theme.dart\';\n\nvoid showAyatInfoDialog(BuildContext context) {\n  showDialog<void>(\n    context: context,\n    builder: (context) => AlertDialog(\n'
ABOUT_H1_NEW = '// Shared "about this app" dialog — shown from both the welcome screen\'s\n// «معرفة المزيد عن التطبيق» link and the studio\'s app-bar (i) button, so\n// the copy only lives in one place.\nimport \'package:flutter/material.dart\'; // PATCH_S141_HOME_SEQUENCE_ABOUT_I18N\n\nimport \'../i18n/app_strings.dart\';\nimport \'../services/app_settings.dart\';\nimport \'../theme/ayat_theme.dart\';\n\nvoid showAyatInfoDialog(BuildContext context) {\n  final s = AppStrings(AppSettings.instance.lang);\n  showDialog<void>(\n    context: context,\n    builder: (context) => AlertDialog(\n'

ABOUT_H2_OLD = "        borderRadius: BorderRadius.circular(22),\n        side: const BorderSide(color: AyatColors.hairline),\n      ),\n      title: const Text('عن استوديو الآيات ✦'),\n      content: SingleChildScrollView(\n        child: Text(\n          'تطبيق مونتاج مخصص فقط لتصميم مقاطع الفيديو القرآنية — كل خيار فيه '\n          'مبني لخدمة الآية والتلاوة.\\n\\n'\n          '• تعرّف تلقائي بالذكاء الاصطناعي على الآية من الصوت (ميكروفون مباشر، '\n          'أو صوت فيديو مرفوع)\\n'\n          '• «المزامنة التلقائية»: تحليل الفيديو كاملاً واكتشاف كل آية والزمن الذي '\n          'قيلت فيه، ثم كتابتها بأنيميشن أثناء العرض والتصدير — تمامًا مع توقيت الشيخ\\n'\n          '• المصحف كاملاً داخل التطبيق بصفحاته الـ604 الحقيقية وأرقامها والأجزاء، '\n          'مع بحث يجد الآية من أي جزء من نصها (بتشكيل أو بدونه) أو برقمها مثل '\n          '«2:255»، وتفسير لكل آية من عدة تفاسير يُحفظ على الجهاز ليُقرأ بلا إنترنت، '\n          'ووضع فاتح للقراءة — بمعزل عن تحرير الفيديو\\n'\n          '• اختيار يدوي لأي آية من القرآن كاملاً (6,236 آية مضمّنة داخل التطبيق، '\n          'تعمل بدون إنترنت)، أو كتابة نص مخصص، مع إمكانية استخدام جزء فقط من '\n          'الآية (من كلمة إلى كلمة)\\n'\n          '• نطاق آيات متعدد لتلاوة تمر بعدة آيات، بتوقيت خاص لكل آية\\n'\n          '• توقيت يدوي اختياري لظهور نص الآية (متى يبدأ ومتى يختفي)، وتلوين أي '\n          'كلمة بالأحمر، ونص إضافي أعلى أو أسفل الفيديو (اسم الشيخ أو نطاق الآيات)\\n'\n          '• خلفيات جاهزة أو صورة خاصة أو خلفية بالذكاء الاصطناعي، وإزالة كروم '\n          'حقيقية للفيديوهات المصوّرة أمام خلفية ملوّنة (أي لون، مع تحكم بالقوة '\n          'والنعومة)\\n'\n          '• تأثيرات مشهدية اختيارية (مطر، ثلج، غبار مضيء) فوق الفيديو أو الخلفية\\n'\n          '• تلاوات مرفقة لعدد من القرّاء مع معاينة صوتية، أو تحميل تلاوة قارئ '\n          'مباشرة داخل التطبيق بلا حاجة لرفع ملف\\n'\n          '• قوالب نصية جاهزة وتحكم كامل بالخط (مع رفع خطوط مخصصة) والحجم واللون '\n          'والموضع والترجمة\\n'\n          '• بسملة افتتاحية وخاتمة كشاشتين مستقلتين قبل/بعد المقطع\\n'\n          '• قص ملتزم بحدود الآيات كما رصدها التعرّف الصوتي، أو قص يدوي حر\\n'\n          '• تحكم بجودة ودقة التصدير، ومستوى صوت التلاوة ودخول/خفوت تدريجي للصوت، '\n          'ومزج صوت المقطع الأصلي تحت التلاوة بدل استبداله\\n'\n          '• علامة مائية اختيارية تمامًا (نص أو شعارك) — التطبيق لا يضيف أي علامة '\n          'أو شعار من عنده إطلاقًا، والتصدير نظيف ما لم تفعّليها بنفسك\\n'\n          '• واجهة بخمس لغات (العربية، الإنجليزية، الفرنسية، الإندونيسية، الأردية)، '\n          'مع إمكانية إيقاف حركات الواجهة بالكامل\\n'\n          '• تصدير MP4 حقيقي بدون حد للمدة، وبدقة الفيديو المصدر نفسها (بنسبة 9:16 أو 1:1)\\n\\n'\n          'يعمل التعرّف بنموذج Whisper على جهازك (يُنزَّل مرة واحدة عند أول '\n          'استخدام)، مع محرك مطابقة عربي يقارن مع القرآن الكريم كاملاً.',\n          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.8),\n        ),\n      ),\n      actions: [\n        FilledButton(\n            onPressed: () => Navigator.pop(context),\n            child: const Text('إغلاق')),\n      ],\n    ),\n  );\n"
ABOUT_H2_NEW = "        borderRadius: BorderRadius.circular(22),\n        side: const BorderSide(color: AyatColors.hairline),\n      ),\n      title: Text(s.t('about.title')),\n      content: SingleChildScrollView(\n        child: Text(\n          s.t('about.body'),\n          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.8),\n        ),\n      ),\n      actions: [\n        FilledButton(\n            onPressed: () => Navigator.pop(context),\n            child: Text(s.t('common.close'))),\n      ],\n    ),\n  );\n"

FIRST_RUN_TOUR_H1_OLD = "\nclass _TourState extends State<_Tour> {\n  int i = 0;\n  static const steps = [\n    ('١', 'ارفع تلاوة', 'فيديو أو ملف صوتي — ولو صوت فقط ضع خلفية صورة أو فيديو'),\n    ('٢', 'اختر الآيات', 'بالكشف التلقائي أو يدويًا من السورة والآية — النص يأتي من المصحف دائمًا'),\n    ('٣', 'صدّر', 'اضبط الشكل من تبويب النص ثم صدّر بجودة تصل إلى مصدر الفيديو'),\n  ];\n  @override\n  Widget build(BuildContext c) {\n"
FIRST_RUN_TOUR_H1_NEW = "\nclass _TourState extends State<_Tour> {\n  int i = 0;\n  // PATCH_S145_LANGUAGES_PATCH_A: the numeral is decorative and stays as\n  // an Arabic-Indic digit in every language; title/desc now come from the\n  // table (keyed per step, since a `static const` list can't call `t()`).\n  static const _numerals = ['١', '٢', '٣'];\n  static const _titleKeys = [\n    'firstRunTour.step1Title',\n    'firstRunTour.step2Title',\n    'firstRunTour.step3Title',\n  ];\n  static const _descKeys = [\n    'firstRunTour.step1Desc',\n    'firstRunTour.step2Desc',\n    'firstRunTour.step3Desc',\n  ];\n  @override\n  Widget build(BuildContext c) {\n"

FIRST_RUN_TOUR_H2_OLD = "    title: Text(s.t('firstRunTour.title'),\n      style: TextStyle(color: AyatColors.gold, fontSize: 16)),\n    content: SizedBox(width: 300, height: 150, child: Column(children: [\n      Text(steps[i].$1, style: TextStyle(fontSize: 40, color: AyatColors.goldBright)),\n      Text(steps[i].$2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),\n      const SizedBox(height: 6),\n      Text(steps[i].$3, textAlign: TextAlign.center,\n        style: TextStyle(fontSize: 12, color: AyatColors.parchment.withValues(alpha: .8))),\n    ])),\n    actions: [\n"
FIRST_RUN_TOUR_H2_NEW = "    title: Text(s.t('firstRunTour.title'),\n      style: TextStyle(color: AyatColors.gold, fontSize: 16)),\n    content: SizedBox(width: 300, height: 150, child: Column(children: [\n      Text(_numerals[i], style: TextStyle(fontSize: 40, color: AyatColors.goldBright)),\n      Text(s.t(_titleKeys[i]), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),\n      const SizedBox(height: 6),\n      Text(s.t(_descKeys[i]), textAlign: TextAlign.center,\n        style: TextStyle(fontSize: 12, color: AyatColors.parchment.withValues(alpha: .8))),\n    ])),\n    actions: [\n"

FIRST_RUN_TOUR_H3_OLD = "        child: Text(s.t('firstRunTour.skip'))),\n      ElevatedButton(onPressed: () =>\n        i == 2 ? Navigator.pop(context) : setState(() => i++),\n        child: Text(i == 2 ? 'ابدأ' : 'التالي')),\n    ]);\n  }\n}\n"
FIRST_RUN_TOUR_H3_NEW = "        child: Text(s.t('firstRunTour.skip'))),\n      ElevatedButton(onPressed: () =>\n        i == 2 ? Navigator.pop(context) : setState(() => i++),\n        child: Text(s.t(i == 2 ? 'firstRunTour.start' : 'firstRunTour.next'))),\n    ]);\n  }\n}\n"

TEXT_EDITOR_PRO_H1_OLD = "// the raw Dart enum identifier, English by construction, with no\n// translation possible via a literal string replace (there was no\n// literal string to replace). Real Arabic labels instead.\nconst Map<TextEditorTab, String> _kTabLabelsAr = {\n  TextEditorTab.text: 'النص',\n  TextEditorTab.border: 'الإطار',\n  TextEditorTab.shadow: 'الظل',\n  TextEditorTab.glow: 'التوهج',\n  TextEditorTab.label: 'اللافتة',\n  TextEditorTab.opacity: 'الشفافية',\n};\n// S128LabelShape mirrors S128LabelShape on StudioState\n// PATCH_S128_FIX2_TEXT_EDITOR_PRO: enum: removed, using S128LabelShape\n"
TEXT_EDITOR_PRO_H1_NEW = "// the raw Dart enum identifier, English by construction, with no\n// translation possible via a literal string replace (there was no\n// literal string to replace). Real Arabic labels instead.\n// PATCH_S152_LANGUAGES_PATCH_A: holds i18n table KEYS now, not literal\n// text -- a `const` map can't call `t()`, so the lookup happens where\n// this is read (_tabRow(), below) instead of here.\nconst Map<TextEditorTab, String> _kTabLabelKeys = {\n  TextEditorTab.text: 'textEditorPro.tabText',\n  TextEditorTab.border: 'textEditorPro.tabBorder',\n  TextEditorTab.shadow: 'textEditorPro.tabShadow',\n  TextEditorTab.glow: 'textEditorPro.tabGlow',\n  TextEditorTab.label: 'textEditorPro.tabLabel',\n  TextEditorTab.opacity: 'textEditorPro.tabOpacity',\n};\n// S128LabelShape mirrors S128LabelShape on StudioState\n// PATCH_S128_FIX2_TEXT_EDITOR_PRO: enum: removed, using S128LabelShape\n"

TEXT_EDITOR_PRO_H2_OLD = 'class _TextEditorProState extends State<TextEditorPro> {\n  TextEditorTab _tab = TextEditorTab.text;\n  StudioState get s => widget.state;\n\n  static const _quick = [Color(0xFFF4A7B9), Color(0xFFEF5350), Color(0xFFFF9800),\n    Color(0xFFFFEB3B), Color(0xFF4CAF50), Color(0xFF26C6DA), Color(0xFF3F51B5),\n'
TEXT_EDITOR_PRO_H2_NEW = "class _TextEditorProState extends State<TextEditorPro> {\n  TextEditorTab _tab = TextEditorTab.text;\n  StudioState get s => widget.state;\n  // PATCH_S152_LANGUAGES_PATCH_A: 's' is already StudioState above, so\n  // this file's shorthand for looked-up UI text is `_t`/`_tf`, matching\n  // the pattern in home_screen.dart/sequence_screen.dart.\n  String _t(String key) => AppSettings.instance.strings.t(key);\n  String _tf(String key, List<Object> args) =>\n      AppSettings.instance.strings.f(key, args);\n\n  static const _quick = [Color(0xFFF4A7B9), Color(0xFFEF5350), Color(0xFFFF9800),\n    Color(0xFFFFEB3B), Color(0xFF4CAF50), Color(0xFF26C6DA), Color(0xFF3F51B5),\n"

TEXT_EDITOR_PRO_H3_OLD = "  // and NONE of them showed as selected -- even though a real font was\n  // applied. Every bundled asset font is listed here now, so whichever\n  // one is active always shows as selected.\n  static const _fonts = [\n    ('elgharib', 'الغريب نون حفص'), ('digitalmadina', 'المدينة الرقمية'),\n    ('tharwatemara', 'ثروت عمارة'), ('digitalkhatt', 'الرقمي الجديد'),\n    ('elgharib_lpmq', 'الغريب اللجنة'), ('elgharib_eid', 'الغريب عيد الأضحى'),\n    ('pf_monumenta', 'PF مونومنتا'),\n    ('naskh', 'نسخ'), ('ruqaa', 'رقعة'), ('andalus', 'أندلس'),\n    ('qalam', 'القلم'), ('kufi', 'الكوفي'),\n  ];\n\n  @override\n"
TEXT_EDITOR_PRO_H3_NEW = "  // and NONE of them showed as selected -- even though a real font was\n  // applied. Every bundled asset font is listed here now, so whichever\n  // one is active always shows as selected.\n  // PATCH_S152_LANGUAGES_PATCH_A: second element is an i18n key now (see\n  // _kTabLabelKeys above for why), not the literal Arabic script name.\n  static const _fonts = [\n    ('elgharib', 'textEditorPro.fontElgharib'),\n    ('digitalmadina', 'textEditorPro.fontDigitalMadina'),\n    ('tharwatemara', 'textEditorPro.fontTharwatEmara'),\n    ('digitalkhatt', 'textEditorPro.fontDigitalKhatt'),\n    ('elgharib_lpmq', 'textEditorPro.fontElgharibLpmq'),\n    ('elgharib_eid', 'textEditorPro.fontElgharibEid'),\n    ('pf_monumenta', 'textEditorPro.fontPfMonumenta'),\n    ('naskh', 'textEditorPro.fontNaskh'),\n    ('ruqaa', 'textEditorPro.fontRuqaa'),\n    ('andalus', 'textEditorPro.fontAndalus'),\n    ('qalam', 'textEditorPro.fontQalam'),\n    ('kufi', 'textEditorPro.fontKufi'),\n  ];\n\n  @override\n"

TEXT_EDITOR_PRO_H4_OLD = '              color: _tab == t ? AyatColors.gold.withValues(alpha: .18) : Colors.transparent,\n              borderRadius: BorderRadius.circular(8),\n              border: Border.all(color: _tab == t ? AyatColors.gold : Colors.transparent)),\n            child: Text(_kTabLabelsAr[t]!, style: TextStyle(\n              fontSize: 12, letterSpacing: 1,\n              color: _tab == t ? AyatColors.goldBright : AyatColors.goldDim))))]));\n\n'
TEXT_EDITOR_PRO_H4_NEW = '              color: _tab == t ? AyatColors.gold.withValues(alpha: .18) : Colors.transparent,\n              borderRadius: BorderRadius.circular(8),\n              border: Border.all(color: _tab == t ? AyatColors.gold : Colors.transparent)),\n            child: Text(_t(_kTabLabelKeys[t]!), style: TextStyle(\n              fontSize: 12, letterSpacing: 1,\n              color: _tab == t ? AyatColors.goldBright : AyatColors.goldDim))))]));\n\n'

TEXT_EDITOR_PRO_H5_OLD = "      // PATCH_S149_REMOVE_FOUR_FONT_OPTIONS: 'خط قرآني' (amiri_quran)\n      // chip removed by request. 'amiri' above already covers the same\n      // Amiri Quran Google Font under a different key.\n      for (final f in _fonts) _chip(f.$2, f.$1, s.fontKey == f.$1,\n          () => s.update(() => s.fontKey = f.$1)),\n      // PATCH_S151_CUSTOM_FONTS_IN_CHIP_ROW: uploaded fonts applied\n      // correctly the moment you picked them but had no chip here\n"
TEXT_EDITOR_PRO_H5_NEW = "      // PATCH_S149_REMOVE_FOUR_FONT_OPTIONS: 'خط قرآني' (amiri_quran)\n      // chip removed by request. 'amiri' above already covers the same\n      // Amiri Quran Google Font under a different key.\n      for (final f in _fonts) _chip(_t(f.$2), f.$1, s.fontKey == f.$1,\n          () => s.update(() => s.fontKey = f.$1)),\n      // PATCH_S151_CUSTOM_FONTS_IN_CHIP_ROW: uploaded fonts applied\n      // correctly the moment you picked them but had no chip here\n"

TEXT_EDITOR_PRO_H6_OLD = "        label: Text(AppStrings(AppSettings.instance.lang).t('textEditorPro.addFont')),\n        onPressed: widget.onPickCustomFont)]),\n\n    _slider('الحجم', s.ayahFontSize, 14, 30, 0,\n        (v) => s.update(() => s.ayahFontSize = v)),\n    _slider('تباعد الأحرف', s.letterSpacing, 0, 12, 0,\n        (v) => s.update(() => s.letterSpacing = v)),\n    SwitchListTile(\n      title: Text(AppStrings(AppSettings.instance.lang).t('textEditorPro.unifiedLineForAllAyat'),\n"
TEXT_EDITOR_PRO_H6_NEW = "        label: Text(AppStrings(AppSettings.instance.lang).t('textEditorPro.addFont')),\n        onPressed: widget.onPickCustomFont)]),\n\n    _slider(_t('textEditorPro.sizeLabel'), s.ayahFontSize, 14, 30, 0,\n        (v) => s.update(() => s.ayahFontSize = v)),\n    _slider(_t('textEditorPro.letterSpacing'), s.letterSpacing, 0, 12, 0,\n        (v) => s.update(() => s.letterSpacing = v)),\n    SwitchListTile(\n      title: Text(AppStrings(AppSettings.instance.lang).t('textEditorPro.unifiedLineForAllAyat'),\n"

TEXT_EDITOR_PRO_H7_OLD = "  ]));\n\n  String _unifiedHint() {\n    if (!s.unifiedOneLine) return 'اجعل كل الآيات سطرًا واحدًا بنفس الحجم المشترك';\n    final u = _computeUnified();\n    return u == null ? 'أضف آيات أولًا ليُحسب الحجم المشترك'\n                     : 'الحجم المشترك المحسوب: ${u.toInt()}';\n  }\n  double? _computeUnified() {\n    if (widget.segmentTexts.isEmpty) return null;\n"
TEXT_EDITOR_PRO_H7_NEW = "  ]));\n\n  String _unifiedHint() {\n    if (!s.unifiedOneLine) return _t('textEditorPro.unifiedHintOff');\n    final u = _computeUnified();\n    return u == null ? _t('textEditorPro.unifiedHintNoAyat')\n                     : _tf('textEditorPro.unifiedHintComputed', [u.toInt()]);\n  }\n  double? _computeUnified() {\n    if (widget.segmentTexts.isEmpty) return null;\n"

TEXT_EDITOR_PRO_H8_OLD = "  }\n\n  // ── BORDER / SHADOW / GLOW / LABEL / OPACITY ──\n  Widget _border() => _card('الحد', Icons.border_style, s.textBorderEnabled,\n    (v) => s.update(() => s.textBorderEnabled = v), [\n    _slider('السمك', s.textBorderWidth, 1, 20, 0, (v) => s.update(() => s.textBorderWidth = v))]);\n  Widget _shadow() => _card('الظل', Icons.filter_frames, s.shadowEnabled,\n    (v) => s.update(() => s.shadowEnabled = v), [\n    _slider('المسافة', s.shadowDistance, 0, 40, 0, (v) => s.update(() => s.shadowDistance = v)),\n    _slider('الضبابية', s.shadowBlur, 0, 60, 0, (v) => s.update(() => s.shadowBlur = v))]);\n  // PATCH_S145_GLOW_KARAOKE_SETTINGS: the on/off switch this card\n  // already had (s.glowEnabled) was real and correctly wired -- but the\n  // two sliders under it (glowSize/glowSharpness) were never read by\n"
TEXT_EDITOR_PRO_H8_NEW = "  }\n\n  // ── BORDER / SHADOW / GLOW / LABEL / OPACITY ──\n  Widget _border() => _card(_t('textEditorPro.borderCardLabel'), Icons.border_style, s.textBorderEnabled,\n    (v) => s.update(() => s.textBorderEnabled = v), [\n    _slider(_t('textEditorPro.thickness'), s.textBorderWidth, 1, 20, 0, (v) => s.update(() => s.textBorderWidth = v))]);\n  Widget _shadow() => _card(_t('textEditorPro.tabShadow'), Icons.filter_frames, s.shadowEnabled,\n    (v) => s.update(() => s.shadowEnabled = v), [\n    _slider(_t('textEditorPro.distance'), s.shadowDistance, 0, 40, 0, (v) => s.update(() => s.shadowDistance = v)),\n    _slider(_t('textEditorPro.blur'), s.shadowBlur, 0, 60, 0, (v) => s.update(() => s.shadowBlur = v))]);\n  // PATCH_S145_GLOW_KARAOKE_SETTINGS: the on/off switch this card\n  // already had (s.glowEnabled) was real and correctly wired -- but the\n  // two sliders under it (glowSize/glowSharpness) were never read by\n"

TEXT_EDITOR_PRO_H9_OLD = "  // its glow -- which used to live in the now-orphaned old _textPanel()\n  // and has had no reachable control anywhere since PATCH_S128 replaced\n  // that screen with this one.\n  Widget _glow() => _card('التوهج', Icons.wb_sunny_outlined, s.glowEnabled,\n    (v) => s.update(() => s.glowEnabled = v), [\n    _slider('شدّة التوهّج', s.glowIntensity, 0, 1.5, 2,\n        (v) => s.update(() => s.glowIntensity = v)),\n    const SizedBox(height: 6),\n    SwitchListTile(\n      contentPadding: EdgeInsets.zero,\n      title: const Text('تظليل الكلمات مع التلاوة (كاريوكي)',\n          style: TextStyle(fontSize: 13)),\n      subtitle: const Text(\n          'عند الإيقاف: تُعرض الآية كاملة دون إضاءة كل كلمة على حدة',\n          style: TextStyle(fontSize: 11)),\n      value: s.karaokeEnabled,\n      activeColor: AyatColors.gold,\n      onChanged: (v) => s.update(() => s.karaokeEnabled = v),\n    ),\n  ]);\n  Widget _label() => _card('الخلفية (Label)', Icons.label_outline, s.labelEnabled,\n    (v) => s.update(() => s.labelEnabled = v), [\n    Row(children: [for (final sh in S128LabelShape.values)\n      GestureDetector(onTap: () => s.update(() => s.labelShape = sh),\n"
TEXT_EDITOR_PRO_H9_NEW = "  // its glow -- which used to live in the now-orphaned old _textPanel()\n  // and has had no reachable control anywhere since PATCH_S128 replaced\n  // that screen with this one.\n  Widget _glow() => _card(_t('textEditorPro.tabGlow'), Icons.wb_sunny_outlined, s.glowEnabled,\n    (v) => s.update(() => s.glowEnabled = v), [\n    _slider(_t('textEditorPro.glowIntensity'), s.glowIntensity, 0, 1.5, 2,\n        (v) => s.update(() => s.glowIntensity = v)),\n    const SizedBox(height: 6),\n    SwitchListTile(\n      contentPadding: EdgeInsets.zero,\n      title: Text(_t('textEditorPro.karaokeToggleTitle'),\n          style: const TextStyle(fontSize: 13)),\n      subtitle: Text(\n          _t('textEditorPro.karaokeToggleSubtitle'),\n          style: const TextStyle(fontSize: 11)),\n      value: s.karaokeEnabled,\n      activeColor: AyatColors.gold,\n      onChanged: (v) => s.update(() => s.karaokeEnabled = v),\n    ),\n  ]);\n  Widget _label() => _card(_t('textEditorPro.backgroundLabelParen'), Icons.label_outline, s.labelEnabled,\n    (v) => s.update(() => s.labelEnabled = v), [\n    Row(children: [for (final sh in S128LabelShape.values)\n      GestureDetector(onTap: () => s.update(() => s.labelShape = sh),\n"

TEXT_EDITOR_PRO_H10_OLD = "              : sh == S128LabelShape.pill ? BorderRadius.circular(15) : BorderRadius.circular(4)),\n          alignment: Alignment.center,\n          child: Text(sh.name[0], style: const TextStyle(fontSize: 10))))]),\n    _slider('الشفافية', s.labelOpacity, 0, 100, 0,\n        (v) => s.update(() => s.labelOpacity = v / 100))]);\n  Widget _opacity() => _slider('الشفافية العامة', s.overallOpacity * 100, 10, 100, 0,\n      (v) => s.update(() => s.overallOpacity = v / 100));\n\n  Widget _card(String t, IconData ic, bool on, ValueChanged<bool> set,\n"
TEXT_EDITOR_PRO_H10_NEW = "              : sh == S128LabelShape.pill ? BorderRadius.circular(15) : BorderRadius.circular(4)),\n          alignment: Alignment.center,\n          child: Text(sh.name[0], style: const TextStyle(fontSize: 10))))]),\n    _slider(_t('textEditorPro.tabOpacity'), s.labelOpacity, 0, 100, 0,\n        (v) => s.update(() => s.labelOpacity = v / 100))]);\n  Widget _opacity() => _slider(_t('textEditorPro.overallOpacity'), s.overallOpacity * 100, 10, 100, 0,\n      (v) => s.update(() => s.overallOpacity = v / 100));\n\n  Widget _card(String t, IconData ic, bool on, ValueChanged<bool> set,\n"

def main():
    apply_literal(TEXT_TRANSITIONS, TEXT_TRANSITIONS_H1_OLD, TEXT_TRANSITIONS_H1_NEW,
                  'lib/data/text_transitions.dart: hunk 1/2', skip_if=TEXT_TRANSITIONS_H1_NEW)
    apply_literal(TEXT_TRANSITIONS, TEXT_TRANSITIONS_H2_OLD, TEXT_TRANSITIONS_H2_NEW,
                  'lib/data/text_transitions.dart: hunk 2/2', skip_if=TEXT_TRANSITIONS_H2_NEW)
    apply_literal(APP_STRINGS, APP_STRINGS_H1_OLD, APP_STRINGS_H1_NEW,
                  'lib/i18n/app_strings.dart: hunk 1/1', skip_if=APP_STRINGS_H1_NEW)
    apply_literal(HOME, HOME_H1_OLD, HOME_H1_NEW,
                  'lib/screens/home_screen.dart: hunk 1/3', skip_if=HOME_H1_NEW)
    apply_literal(HOME, HOME_H2_OLD, HOME_H2_NEW,
                  'lib/screens/home_screen.dart: hunk 2/3', skip_if=HOME_H2_NEW)
    apply_literal(HOME, HOME_H3_OLD, HOME_H3_NEW,
                  'lib/screens/home_screen.dart: hunk 3/3', skip_if=HOME_H3_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H1_OLD, SEQUENCE_H1_NEW,
                  'lib/screens/sequence_screen.dart: hunk 1/15', skip_if=SEQUENCE_H1_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H2_OLD, SEQUENCE_H2_NEW,
                  'lib/screens/sequence_screen.dart: hunk 2/15', skip_if=SEQUENCE_H2_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H3_OLD, SEQUENCE_H3_NEW,
                  'lib/screens/sequence_screen.dart: hunk 3/15', skip_if=SEQUENCE_H3_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H4_OLD, SEQUENCE_H4_NEW,
                  'lib/screens/sequence_screen.dart: hunk 4/15', skip_if=SEQUENCE_H4_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H5_OLD, SEQUENCE_H5_NEW,
                  'lib/screens/sequence_screen.dart: hunk 5/15', skip_if=SEQUENCE_H5_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H6_OLD, SEQUENCE_H6_NEW,
                  'lib/screens/sequence_screen.dart: hunk 6/15', skip_if=SEQUENCE_H6_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H7_OLD, SEQUENCE_H7_NEW,
                  'lib/screens/sequence_screen.dart: hunk 7/15', skip_if=SEQUENCE_H7_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H8_OLD, SEQUENCE_H8_NEW,
                  'lib/screens/sequence_screen.dart: hunk 8/15', skip_if=SEQUENCE_H8_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H9_OLD, SEQUENCE_H9_NEW,
                  'lib/screens/sequence_screen.dart: hunk 9/15', skip_if=SEQUENCE_H9_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H10_OLD, SEQUENCE_H10_NEW,
                  'lib/screens/sequence_screen.dart: hunk 10/15', skip_if=SEQUENCE_H10_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H11_OLD, SEQUENCE_H11_NEW,
                  'lib/screens/sequence_screen.dart: hunk 11/15', skip_if=SEQUENCE_H11_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H12_OLD, SEQUENCE_H12_NEW,
                  'lib/screens/sequence_screen.dart: hunk 12/15', skip_if=SEQUENCE_H12_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H13_OLD, SEQUENCE_H13_NEW,
                  'lib/screens/sequence_screen.dart: hunk 13/15', skip_if=SEQUENCE_H13_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H14_OLD, SEQUENCE_H14_NEW,
                  'lib/screens/sequence_screen.dart: hunk 14/15', skip_if=SEQUENCE_H14_NEW)
    apply_literal(SEQUENCE, SEQUENCE_H15_OLD, SEQUENCE_H15_NEW,
                  'lib/screens/sequence_screen.dart: hunk 15/15', skip_if=SEQUENCE_H15_NEW)
    apply_literal(SETTINGS, SETTINGS_H1_OLD, SETTINGS_H1_NEW,
                  'lib/screens/settings_screen.dart: hunk 1/1', skip_if=SETTINGS_H1_NEW)
    apply_literal(ABOUT, ABOUT_H1_OLD, ABOUT_H1_NEW,
                  'lib/widgets/ayat_info_dialog.dart: hunk 1/2', skip_if=ABOUT_H1_NEW)
    apply_literal(ABOUT, ABOUT_H2_OLD, ABOUT_H2_NEW,
                  'lib/widgets/ayat_info_dialog.dart: hunk 2/2', skip_if=ABOUT_H2_NEW)
    apply_literal(FIRST_RUN_TOUR, FIRST_RUN_TOUR_H1_OLD, FIRST_RUN_TOUR_H1_NEW,
                  'lib/widgets/first_run_tour.dart: hunk 1/3', skip_if=FIRST_RUN_TOUR_H1_NEW)
    apply_literal(FIRST_RUN_TOUR, FIRST_RUN_TOUR_H2_OLD, FIRST_RUN_TOUR_H2_NEW,
                  'lib/widgets/first_run_tour.dart: hunk 2/3', skip_if=FIRST_RUN_TOUR_H2_NEW)
    apply_literal(FIRST_RUN_TOUR, FIRST_RUN_TOUR_H3_OLD, FIRST_RUN_TOUR_H3_NEW,
                  'lib/widgets/first_run_tour.dart: hunk 3/3', skip_if=FIRST_RUN_TOUR_H3_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H1_OLD, TEXT_EDITOR_PRO_H1_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 1/10', skip_if=TEXT_EDITOR_PRO_H1_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H2_OLD, TEXT_EDITOR_PRO_H2_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 2/10', skip_if=TEXT_EDITOR_PRO_H2_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H3_OLD, TEXT_EDITOR_PRO_H3_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 3/10', skip_if=TEXT_EDITOR_PRO_H3_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H4_OLD, TEXT_EDITOR_PRO_H4_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 4/10', skip_if=TEXT_EDITOR_PRO_H4_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H5_OLD, TEXT_EDITOR_PRO_H5_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 5/10', skip_if=TEXT_EDITOR_PRO_H5_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H6_OLD, TEXT_EDITOR_PRO_H6_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 6/10', skip_if=TEXT_EDITOR_PRO_H6_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H7_OLD, TEXT_EDITOR_PRO_H7_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 7/10', skip_if=TEXT_EDITOR_PRO_H7_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H8_OLD, TEXT_EDITOR_PRO_H8_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 8/10', skip_if=TEXT_EDITOR_PRO_H8_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H9_OLD, TEXT_EDITOR_PRO_H9_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 9/10', skip_if=TEXT_EDITOR_PRO_H9_NEW)
    apply_literal(TEXT_EDITOR_PRO, TEXT_EDITOR_PRO_H10_OLD, TEXT_EDITOR_PRO_H10_NEW,
                  'lib/widgets/text_editor_pro.dart: hunk 10/10', skip_if=TEXT_EDITOR_PRO_H10_NEW)

    print("\n=== S152 languages-patch-A ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("=======================================\n")


if __name__ == "__main__":
    main()
