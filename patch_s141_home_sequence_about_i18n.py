# patch_s141_home_sequence_about_i18n.py
#
# Finishes the i18n sweep S139 started and deliberately left for a
# follow-up: home_screen.dart, sequence_screen.dart and the about dialog
# still held ~100 hardcoded-Arabic strings from translations.py. This
# wires all of them, plus:
#
#   - Two keys translations.py was missing (home.surahDropdownLabel,
#     home.stageOverlaySurahNum) -- found while wiring, added here.
#   - settings_screen.dart's tafsir-cache "Clear" button, which used a
#     hand-rolled `lang == AppLang.ar ? 'مسح' : 'Clear'` ternary that
#     silently showed English to French/Indonesian/Urdu users instead of
#     going through the app's 5-language table like everything else.
#
# Rather than hand-writing ~100 separate literal patches (error-prone at
# this size, and brittle against the slightest reformatting), this patch
# ships the same small parser S141 was developed and tested against a
# full extraction of the live repo with: it walks every Text(...) call,
# and for any whose Arabic string content exactly matches a known
# translations.py template, replaces just that string argument with
# _t('key') / _tf('key', [args...]) -- args are the exact Dart
# expressions that were inside the original ${...} / bare $x
# interpolations, lifted verbatim. It also strips `const` from any
# enclosing constructor that no longer qualifies once its argument
# becomes a runtime call (Text(_t(...)) is not a compile-time constant).
#
# Every match is exact-literal (no fuzzy matching) and the patch refuses
# to run if the number of matches in home_screen.dart / sequence_screen.dart
# doesn't equal what was verified against the current repo dump, so it
# fails loudly rather than silently doing less than expected.
#
# Run from the project root.

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []
MARKER = 'PATCH_S141_HOME_SEQUENCE_ABOUT_I18N'


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


APP_STRINGS = "lib/i18n/app_strings.dart"
HOME = "lib/screens/home_screen.dart"
SEQUENCE = "lib/screens/sequence_screen.dart"
SETTINGS = "lib/screens/settings_screen.dart"
ABOUT = "lib/widgets/ayat_info_dialog.dart"

# ---------------------------------------------------------------------
# 1) Two keys translations.py didn't have -- found while wiring call
#    sites that translations.py's original scan had missed.
# ---------------------------------------------------------------------
NEW_KEYS_BLOCK = (
    "  // PATCH_S141_HOME_SEQUENCE_ABOUT_I18N: two keys translations.py\n"
    "  // (from S139) was missing -- found while wiring call sites.\n"
    "  'home.surahDropdownLabel': [\n"
    "    'سورة {}',\n"
    "    'Surah {}',\n"
    "    'Sourate {}',\n"
    "    'Surah {}',\n"
    "    'سورہ {}',\n"
    "  ],\n"
    "  'home.stageOverlaySurahNum': [\n"
    "    'سورة {} — {}',\n"
    "    'Surah {} — {}',\n"
    "    'Sourate {} — {}',\n"
    "    'Surah {} — {}',\n"
    "    'سورہ {} — {}',\n"
    "  ],\n"
)


def add_new_keys():
    apply_literal(
        APP_STRINGS,
        '\n};\n\n/// Exposed for the i18n test',
        "\n" + NEW_KEYS_BLOCK + "};\n\n/// Exposed for the i18n test",
        'app_strings.dart: add 2 keys translations.py was missing',
        skip_if="home.stageOverlaySurahNum",
    )


# ---------------------------------------------------------------------
# 2) The full translation table (ar -> key), needed to recognize which
#    Text('...') calls to wire. Mirrors translations.py plus the two
#    keys just added and the three pre-existing common.* keys.
# ---------------------------------------------------------------------
AR_TO_KEY = {
    'إلغاء': 'common.cancel',
    'إغلاق': 'common.close',
    'تم': 'common.done',
    'سورة {}': 'home.surahDropdownLabel',
    'سورة {} — {}': 'home.stageOverlaySurahNum',
    'تم تركيب المقاطع — شغّلي المزامنة التلقائية من جديد': 'home.reassembleHint',
    'هل تقصد إحدى هذه الآيات؟': 'home.matchTitle',
    'سورة {} — آية {} · {}٪': 'home.matchOption',
    'ولا واحدة — استخدم النص كما كتبته': 'home.matchNone',
    'التصدير جاهز ✓': 'home.exportReadyTitle',
    'تم حفظ المقطع بصيغة MP4:\n{}{}': 'home.exportSavedBody',
    'مشاركة الفيديو': 'home.shareVideo',
    'اختر السورة للتنزيل': 'home.pickSurahDownload',
    'انتظر تحميل بيانات القرآن ثم أعد المحاولة': 'home.waitQuranData',
    'تصدير المقطع (MP4 — بدون حد للمدة أو الدقة)': 'home.exportClipTitle',
    '{}٪': 'home.exportProgressPercent',
    'إلغاء العملية': 'home.cancelOperation',
    'رفع فيديو أو تلاوة صوتية': 'home.uploadVideoOrAudio',
    'دمج مع فيديو آخر': 'home.mergeAnotherVideo',
    'تركيب عدة مقاطع (قصّ وترتيب وانتقالات)': 'home.assembleMultipleClips',
    'تعرّف من صوت الفيديو المرفوع': 'home.detectFromUploadedAudio',
    '(المقطع كاملاً)': 'home.wholeClipParen',
    'سورة {} — آية {}': 'home.timelineSurahAyah',
    'تصدير نطاق آيات محدد (اختياري)': 'home.exportAyahRangeOptional',
    'القص يلتزم دائمًا ببداية ونهاية الآية كما رصدها التعرّف الصوتي — لا يمكن القص في منتصف آية أو كلمة.': 'home.trimAyahBoundaryNote',
    'مراجعة الآيات المرصودة ({})': 'home.reviewDetectedAyat',
    'اضغط آية للانتقال إليها، أو عدّل توقيتها أو احذفها إن كان الرصد خاطئًا.': 'home.reviewDetectedHint',
    'إضافة آية {} — {}': 'home.addAdjacentAyah',
    'إضافة آية يدويًا': 'home.addAyahManually',
    '-٠٫٥ث': 'home.minusHalfSecond',
    '+٠٫٥ث': 'home.plusHalfSecond',
    'اختر الآية': 'home.chooseAyahHint',
    'آية {}': 'home.ayahDropdownLabel',
    'مستنتجة': 'home.inferredBadge',
    '{} — {} · ثقة {}٪': 'home.segmentTimeConfidence',
    'تم حذف الآية من الخط الزمني': 'home.ayahRemovedFromTimeline',
    'من موضع التشغيل': 'home.fromPlaybackPosition',
    'توقيت آية {} — {}': 'home.ayahTimingTitle',
    'استمع من بداية الآية': 'home.listenFromAyahStart',
    'تقسيم عند موضع التشغيل': 'home.splitAtPlayhead',
    'تغيير الآية (الرصد خاطئ)': 'home.changeAyahWrongDetection',
    'التعديل يظهر فورًا في المعاينة وفي إضاءة الكلمات، ويلتزم به التصدير.': 'home.editAppliesImmediatelyNote',
    'اختر الآية الصحيحة لهذا المقطع': 'home.pickCorrectAyahForSegment',
    'التوقيت الذي ضبطته يبقى كما هو — يتغير نص الآية فقط في المعاينة والتصدير.': 'home.timingUnchangedNote',
    'لإلغاء التأثير بسرعة اضغط زر ✕ أعلى المعاينة — لمس المعاينة في أي مكان آخر يوقف/يشغّل الفيديو فقط.': 'home.effectCancelHint',
    'ضبط الصورة يدويًا': 'home.adjustImageManually',
    'إعادة الضبط': 'home.resetAdjustment',
    'يُطبَّق على الخلفية فقط (جاهزة، طبيعية، فن ذكاء اصطناعي، أو مخصّصة) — لا يُطبَّق أبدًا على فيديو التلاوة المرفوع نفسه.': 'home.backgroundOnlyNote',
    'ملاحظة: قالب «زجاج مصنفر أنيق» الجديد (تبويب قوالب) يستخدم لوحة نص زجاجية — جرّبه مع هذه التأثيرات.': 'home.glassTemplateNote',
    '«احتواء + خلفية ضبابية» يعرض الفيديو كاملًا فوق نسخة ضبابية منه تملأ الإطار (مظهر الريلز الشهير). المعاينة تعرض الاحتواء، والضبابية تُرسم في الفيديو المُصدَّر.': 'home.containBlurNote',
    'صوت التلاوة في المقطع المُصدَّر': 'home.recitationAudioInExport',
    'تُطبَّق هذه الإعدادات على المسار الصوتي المُصدَّر أيًّا كان مصدره (تلاوة مرفقة أو صوت الفيديو نفسه) — التلاوة نفسها لا تُسرَّع ولا تُبطَّأ أبدًا.': 'home.exportAudioSettingsNote',
    'كشف تدريجي': 'home.gradualReveal',
    'ظهور النص واختفاؤه': 'home.textFadeInOut',
    '{} أسلوبًا لدخول النص وخروجه. المعاينة أعلاه تعرض الأسلوب نفسه الذي سيُدمج في الفيديو تمامًا.': 'home.transitionStylesCount',
    'الأطول أهدأ وأنعم. تُرسم الحركة بـ {} إطارًا في الثانية عند التصدير، فلا يظهر أي تقطيع.': 'home.transitionSpeedNote',
    'خلفية موسيقية / أجواء': 'home.backgroundMusicAmbience',
    'مسار صوتي هادئ يُمزج تحت التلاوة وصوت المقطع. يُكرَّر تلقائيًا إذا كان أقصر من الفيديو ويُقصّ إذا كان أطول، فلا حاجة لمطابقة المدة.': 'home.bgMusicLoopNote',
    'الصوت مكتوم بالكامل حاليًا — أوقف الكتم لتسمع الخلفية.': 'home.audioMutedNote',
    'سرعة المقطع': 'home.clipSpeed',
    'أقل من ١× حركة بطيئة، وأكثر تسريع. تُطبَّق على الصورة وعلى نص الآية المتزامن معًا، فلا ينفصل أحدهما عن الآخر.': 'home.speedSyncNote',
    'ملف الترجمة (SRT / VTT)': 'home.subtitleFileLabel',
    'يُحفظ ملف ترجمة بجانب الفيديو في مجلد التنزيلات، مبنيًّا على توقيت الآيات المرصودة. مفيد ليوتيوب وللمشاهدين الذين يحتاجون نصًا يمكن إيقافه أو ترجمته — بخلاف النص المحروق في الصورة.': 'home.subtitleFileNote',
    'لا توجد آيات مرصودة بعد — شغّلي «المزامنة التلقائية» أو أضيفي آيات للخط الزمني يدويًا، وإلا فلن يحتوي الملف على شيء.': 'home.noAyatDetectedNote',
    'سيحتوي الملف على {} مقطعًا نصيًا.': 'home.subtitleCuesCount',
    'تعذّر استخدام هذه الصورة: {}': 'home.imageUseFailed',
    'متى يظهر هذا النص؟': 'home.whenTextAppears',
    '{}–{} ث': 'home.secondsRangeShort',
    'مدة الفيديو: {}': 'home.videoDuration',
    'تطبيق كنص ثابت': 'home.applyAsFixedText',
    'حفظ في الخط الزمني': 'home.saveToTimeline',
    'إضافة آية إلى خط زمني متعدد': 'home.addAyahToMultiTimeline',
    'خلفية {}': 'home.backgroundNumber',
    'اضغط على خلفيتين أو أكثر بالترتيب الذي تريد التبديل بينه؛ الرقم على كل خلفية مختارة هو ترتيبها في الدورة. يظهر التبديل في الفيديو المُصدَّر فقط — المعاينة المباشرة تعرض الخلفية المحددة أعلاه. الخلفيات المخصصة/فن الذكاء الاصطناعي تبقى خلفية واحدة.': 'home.bgCycleNote',
    'اختر خلفيتين على الأقل ليعمل التبديل.': 'home.pickTwoBgMin',
    'خيارات متقدمة': 'home.advancedOptions',
    'جارٍ توليد الفن...': 'home.generatingArt',
    'إعادة توليد فن هذه الآية': 'home.regenerateArtForAyah',
    'حذف الفن المولّد لهذه الآية': 'home.deleteGeneratedArtForAyah',
    'خلفياتك المرفوعة ({})': 'home.uploadedBackgrounds',
    'اضغط مطولًا على أي صورة لحذفها من المكتبة': 'home.longPressToDeleteFromLibrary',
    'خلفيات طبيعية جاهزة': 'home.readyNatureBackgrounds',
    'اضغط على أي صورة لاستخدامها كخلفية مباشرة': 'home.tapImageToUseAsBackground',
    'ارفع خلفية جديدة': 'home.uploadNewBackground',
    'إلغاء التفعيل والعودة للخلفيات الجاهزة': 'home.deactivateBackToDefaults',
    'اختر نفس لون الشاشة التي صوّرت أمامها': 'home.pickSameScreenColor',
    'تتم إزالة اللون فعليًا على جهازك أثناء التصدير (بمحرك ffmpeg)، ويعمل مع أي لون شاشة تختاره وليس الأخضر فقط. اضبط «القوة» إذا بقيت بقايا من لون الخلفية، و«النعومة» إذا ظهرت حواف حادة حول الشخص. الجودة النهائية تعتمد أيضًا على إضاءة التصوير الأصلية.': 'home.chromaKeyNote',
    'رفع خط مخصص (TTF/OTF)': 'home.uploadCustomFont',
    'الخطوط المرفوعة تُحفظ داخل التطبيق وتبقى متاحة ومحددة بعد إغلاقه — ارفع خط المصحف المفضل لديك (مثل الغريب نون حفص) مرة واحدة فقط.': 'home.uploadedFontsNote',
    'توهّج النص': 'home.textGlow',
    'تظليل الكلمات مع التلاوة (كاريوكي)': 'home.karaokeWordHighlight',
    'عند الإيقاف: تُعرض الآية كاملة دون إضاءة كل كلمة على حدة': 'home.karaokeOffNote',
    'إعادة موضع/حجم النص للوضع الافتراضي': 'home.resetTextPositionSize',
    'أعلى الشاشة': 'home.screenTop',
    'منتصف الشاشة': 'home.screenMiddle',
    'أسفل الشاشة': 'home.screenBottom',
    'مدة التصدير بدون فيديو (ثانية)': 'home.exportDurationNoVideo',
    'تركيب عدة مقاطع': 'sequence.title',
    'أضيفي مقاطع بالترتيب الذي تريدينه، وقصّي كل واحد على حدة، واختاري طريقة الانتقال بينها. النتيجة ملف واحد يصبح هو مقطع الاستوديو — فتعمل عليه المزامنة التلقائية والتأثيرات والتصدير كالمعتاد.': 'sequence.subtitle',
    'لم تتم إضافة أي مقطع بعد': 'sequence.noClipsYet',
    'يبدأ عند {} · المدة {}': 'sequence.clipStartDuration',
    'الانتقال بين المقاطع': 'sequence.transitionBetweenClips',
    'مدة الانتقال: {}ث': 'sequence.transitionDuration',
    'إضافة مقاطع': 'sequence.addClips',
    'تركيب المقاطع': 'sequence.assembleClips',
    'أضيفي مقطعين على الأقل للتركيب.': 'sequence.addTwoClipsMin',
}

EXPECTED_COUNTS = {HOME: 112, SEQUENCE: 9}


def parse_text_call(text, start):
    i = start
    n = len(text)
    parts = []
    placeholders = []
    found_any = False
    while True:
        while i < n and text[i] in ' \t\n':
            i += 1
        if i < n and text[i] in "'\"":
            q = text[i]
            j = i + 1
            buf = []
            while j < n:
                c = text[j]
                if c == '\\':
                    nxt = text[j + 1] if j + 1 < n else ''
                    if nxt == 'n':
                        buf.append('\n')
                    elif nxt in ("'", '"', '\\', '$'):
                        buf.append(nxt)
                    else:
                        buf.append(text[j:j + 2])
                    j += 2
                    continue
                if c == '$' and j + 1 < n and text[j + 1] == '{':
                    depth = 1
                    k = j + 2
                    while k < n and depth > 0:
                        if text[k] == '{':
                            depth += 1
                        elif text[k] == '}':
                            depth -= 1
                        k += 1
                    placeholders.append(text[j + 2:k - 1])
                    buf.append('{}')
                    j = k
                    continue
                if c == '$' and j + 1 < n and (text[j + 1].isalpha() or text[j + 1] == '_'):
                    k = j + 1
                    while k < n and (text[k].isalnum() or text[k] == '_'):
                        k += 1
                    placeholders.append(text[j + 1:k])
                    buf.append('{}')
                    j = k
                    continue
                if c == q:
                    break
                buf.append(c)
                j += 1
            parts.append(''.join(buf))
            i = j + 1
            found_any = True
        else:
            break
    if not found_any:
        return None, None, start
    return parts, placeholders, i


AR_RE = re.compile(r'[\u0600-\u06FF]')


WIRED_MARKER = MARKER + '_WIRED'


def wire_file(rel_path, expected_count):
    p = ROOT / rel_path
    text = p.read_text(encoding='utf-8')
    if WIRED_MARKER in text:
        _log(f"{rel_path}: wire hardcoded strings", "SKIPPED-ALREADY")
        return
    out = []
    pos = 0
    replaced = 0
    unmatched = []
    for m in re.finditer(r"(?<![A-Za-z_])Text\(", text):
        s = m.start()
        if s < pos:
            continue
        start = m.end()
        parts, placeholders, endpos = parse_text_call(text, start)
        if parts is None:
            continue
        joined = ''.join(parts)
        if not AR_RE.search(joined):
            continue
        key = AR_TO_KEY.get(joined)
        if key is None:
            unmatched.append(joined)
            continue
        const_start = s
        back = text[max(0, s - 6):s]
        if back.rstrip().endswith('const'):
            k = s
            while k > 0 and text[k - 1] in ' \t':
                k -= 1
            if text[max(0, k - 5):k] == 'const':
                const_start = k - 5
        if placeholders:
            repl = f"_tf('{key}', [{', '.join(placeholders)}])"
        else:
            repl = f"_t('{key}')"
        out.append(text[pos:const_start])
        out.append(text[s:start])
        out.append(repl)
        pos = endpos
        replaced += 1
    out.append(text[pos:])
    newtext = ''.join(out)

    if unmatched:
        raise SystemExit(
            f"ERROR ({rel_path}): {len(unmatched)} Arabic Text() literal(s) did not "
            f"match any known translation key -- refusing to guess:\n" +
            "\n".join(f"  {u[:90]!r}" for u in unmatched))
    if replaced != expected_count:
        raise SystemExit(
            f"ERROR ({rel_path}): expected exactly {expected_count} wirable strings, "
            f"found {replaced} -- the file has likely changed since this patch was "
            f"written; refusing to guess.")

    # Strip `const` from any constructor whose args now contain a runtime
    # _t(/_tf( call -- Text(_t(...)) is not a compile-time constant, so
    # anything that wraps it with `const` no longer compiles.
    changed = True
    removed = 0
    while changed:
        changed = False
        for cm in re.finditer(r'\bconst\s+', newtext):
            cstart = cm.end()
            idm = re.match(r'[A-Za-z_][A-Za-z0-9_.<>]*\s*\(', newtext[cstart:])
            if not idm:
                continue
            paren_open = cstart + idm.end() - 1
            depth = 1
            k = paren_open + 1
            n = len(newtext)
            while k < n and depth > 0:
                if newtext[k] == '(':
                    depth += 1
                elif newtext[k] == ')':
                    depth -= 1
                k += 1
            span = newtext[paren_open:k]
            if '_t(' in span or '_tf(' in span:
                newtext = newtext[:cm.start()] + newtext[cstart:]
                removed += 1
                changed = True
                break

    # Marker comment near the top so re-runs are a no-op (distinct from the
    # plain MARKER other apply_literal calls in this same file check for,
    # so this stamp can't short-circuit those before they've run).
    newtext = newtext.replace(
        "import 'package:flutter/material.dart';",
        f"import 'package:flutter/material.dart'; // {WIRED_MARKER}",
        1,
    )

    p.write_text(newtext, encoding='utf-8')
    _log(f"{rel_path}: wire {replaced} hardcoded strings (+{removed} const stripped)",
         "APPLIED")


def add_i18n_helpers():
    apply_literal(
        HOME,
        "  /// Shorthand for a localized string in this screen's chrome.\n"
        "  String _t(String key) => AppSettings.instance.strings.t(key);\n",
        "  /// Shorthand for a localized string in this screen's chrome.\n"
        "  String _t(String key) => AppSettings.instance.strings.t(key);\n"
        f"  // {MARKER}: same shorthand, with `{{}}` placeholders filled left\n"
        "  // to right -- see AppStrings.f.\n"
        "  String _tf(String key, List<Object> args) =>\n"
        "      AppSettings.instance.strings.f(key, args);\n",
        'home_screen.dart: add _tf helper',
        skip_if="String _tf(String key",
    )

    apply_literal(
        SEQUENCE,
        "  bool _busy = false;\n"
        "  String _status = '';\n"
        "\n"
        "  @override\n"
        "  void initState() {",
        "  bool _busy = false;\n"
        "  String _status = '';\n"
        "\n"
        f"  // {MARKER}: same shorthand home_screen.dart uses for its chrome.\n"
        "  String _t(String key) => AppSettings.instance.strings.t(key);\n"
        "  String _tf(String key, List<Object> args) =>\n"
        "      AppSettings.instance.strings.f(key, args);\n"
        "\n"
        "  @override\n"
        "  void initState() {",
        'sequence_screen.dart: add _t/_tf helpers',
        skip_if="String _t(String key) => AppSettings.instance.strings.t(key);",
    )


def fix_sequence_split_string():
    apply_literal(
        SEQUENCE,
        "              'الطول النهائي التقريبي: ${_fmt(total)}'\n"
        "              '${_transition != SequenceTransition.cut ? ' (كل انتقال يقصّر الناتج بمقدار مدته)' : ''}',\n",
        "              _tf('sequence.approxFinalLength', [_fmt(total)]) +\n"
        "                  (_transition != SequenceTransition.cut\n"
        "                      ? _t('sequence.transitionShortensNote')\n"
        "                      : ''),\n",
        'sequence_screen.dart: wire the split final-length string',
        skip_if="sequence.approxFinalLength', [_fmt(total)]",
    )


def fix_settings_clear_button():
    apply_literal(
        SETTINGS,
        "                    _settings.lang == AppLang.ar ? 'مسح' : 'Clear',\n",
        "                    // PATCH_S141_HOME_SEQUENCE_ABOUT_I18N: this was\n"
        "                    // hardcoded ar/en-only, silently showing English\n"
        "                    // to fr/id/ur users -- route through the table\n"
        "                    // like every other string on this screen.\n"
        "                    s.t('settings.clearCache'),\n",
        "settings_screen.dart: Clear button through the 5-language table",
        skip_if="s.t('settings.clearCache')",
    )


def rewrite_about_dialog():
    apply_literal(
        ABOUT,
        "import 'package:flutter/material.dart';\n"
        "\n"
        "import '../theme/ayat_theme.dart';\n"
        "\n"
        "void showAyatInfoDialog(BuildContext context) {\n"
        "  showDialog<void>(\n"
        "    context: context,\n"
        "    builder: (context) => AlertDialog(\n",
        f"import 'package:flutter/material.dart'; // {MARKER}\n"
        "\n"
        "import '../i18n/app_strings.dart';\n"
        "import '../services/app_settings.dart';\n"
        "import '../theme/ayat_theme.dart';\n"
        "\n"
        "void showAyatInfoDialog(BuildContext context) {\n"
        "  final s = AppStrings(AppSettings.instance.lang);\n"
        "  showDialog<void>(\n"
        "    context: context,\n"
        "    builder: (context) => AlertDialog(\n",
        'ayat_info_dialog.dart: imports + local AppStrings',
        skip_if=MARKER,
    )
    apply_literal(
        ABOUT,
        "      title: const Text('عن استوديو الآيات ✦'),\n",
        "      title: Text(s.t('about.title')),\n",
        'ayat_info_dialog.dart: title',
    )
    apply_literal(
        ABOUT,
        "      content: SingleChildScrollView(\n"
        "        child: Text(\n"
        "          'تطبيق مونتاج مخصص فقط لتصميم مقاطع الفيديو القرآنية — كل خيار فيه '\n"
        "          'مبني لخدمة الآية والتلاوة.\\n\\n'\n"
        "          '• تعرّف تلقائي بالذكاء الاصطناعي على الآية من الصوت (ميكروفون مباشر، '\n"
        "          'أو صوت فيديو مرفوع)\\n'\n"
        "          '• «المزامنة التلقائية»: تحليل الفيديو كاملاً واكتشاف كل آية والزمن الذي '\n"
        "          'قيلت فيه، ثم كتابتها بأنيميشن أثناء العرض والتصدير — تمامًا مع توقيت الشيخ\\n'\n"
        "          '• المصحف كاملاً داخل التطبيق بصفحاته الـ604 الحقيقية وأرقامها والأجزاء، '\n"
        "          'مع بحث يجد الآية من أي جزء من نصها (بتشكيل أو بدونه) أو برقمها مثل '\n"
        "          '«2:255»، وتفسير لكل آية من عدة تفاسير يُحفظ على الجهاز ليُقرأ بلا إنترنت، '\n"
        "          'ووضع فاتح للقراءة — بمعزل عن تحرير الفيديو\\n'\n"
        "          '• اختيار يدوي لأي آية من القرآن كاملاً (6,236 آية مضمّنة داخل التطبيق، '\n"
        "          'تعمل بدون إنترنت)، أو كتابة نص مخصص، مع إمكانية استخدام جزء فقط من '\n"
        "          'الآية (من كلمة إلى كلمة)\\n'\n"
        "          '• نطاق آيات متعدد لتلاوة تمر بعدة آيات، بتوقيت خاص لكل آية\\n'\n"
        "          '• توقيت يدوي اختياري لظهور نص الآية (متى يبدأ ومتى يختفي)، وتلوين أي '\n"
        "          'كلمة بالأحمر، ونص إضافي أعلى أو أسفل الفيديو (اسم الشيخ أو نطاق الآيات)\\n'\n"
        "          '• خلفيات جاهزة أو صورة خاصة أو خلفية بالذكاء الاصطناعي، وإزالة كروم '\n"
        "          'حقيقية للفيديوهات المصوّرة أمام خلفية ملوّنة (أي لون، مع تحكم بالقوة '\n"
        "          'والنعومة)\\n'\n"
        "          '• تأثيرات مشهدية اختيارية (مطر، ثلج، غبار مضيء) فوق الفيديو أو الخلفية\\n'\n"
        "          '• تلاوات مرفقة لعدد من القرّاء مع معاينة صوتية، أو تحميل تلاوة قارئ '\n"
        "          'مباشرة داخل التطبيق بلا حاجة لرفع ملف\\n'\n"
        "          '• قوالب نصية جاهزة وتحكم كامل بالخط (مع رفع خطوط مخصصة) والحجم واللون '\n"
        "          'والموضع والترجمة\\n'\n"
        "          '• بسملة افتتاحية وخاتمة كشاشتين مستقلتين قبل/بعد المقطع\\n'\n"
        "          '• قص ملتزم بحدود الآيات كما رصدها التعرّف الصوتي، أو قص يدوي حر\\n'\n"
        "          '• تحكم بجودة ودقة التصدير، ومستوى صوت التلاوة ودخول/خفوت تدريجي للصوت، '\n"
        "          'ومزج صوت المقطع الأصلي تحت التلاوة بدل استبداله\\n'\n"
        "          '• علامة مائية اختيارية تمامًا (نص أو شعارك) — التطبيق لا يضيف أي علامة '\n"
        "          'أو شعار من عنده إطلاقًا، والتصدير نظيف ما لم تفعّليها بنفسك\\n'\n"
        "          '• واجهة بخمس لغات (العربية، الإنجليزية، الفرنسية، الإندونيسية، الأردية)، '\n"
        "          'مع إمكانية إيقاف حركات الواجهة بالكامل\\n'\n"
        "          '• تصدير MP4 حقيقي بدون حد للمدة، وبدقة الفيديو المصدر نفسها (بنسبة 9:16 أو 1:1)\\n\\n'\n"
        "          'يعمل التعرّف بنموذج Whisper على جهازك (يُنزَّل مرة واحدة عند أول '\n"
        "          'استخدام)، مع محرك مطابقة عربي يقارن مع القرآن الكريم كاملاً.',\n"
        "          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.8),\n"
        "        ),\n"
        "      ),\n"
        "      actions: [\n"
        "        FilledButton(\n"
        "            onPressed: () => Navigator.pop(context),\n"
        "            child: const Text('إغلاق')),\n"
        "      ],\n",
        "      content: SingleChildScrollView(\n"
        "        child: Text(\n"
        "          s.t('about.body'),\n"
        "          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.8),\n"
        "        ),\n"
        "      ),\n"
        "      actions: [\n"
        "        FilledButton(\n"
        "            onPressed: () => Navigator.pop(context),\n"
        "            child: Text(s.t('common.close'))),\n"
        "      ],\n",
        'ayat_info_dialog.dart: body + close button',
    )


def main():
    add_new_keys()
    wire_file(HOME, EXPECTED_COUNTS[HOME])
    wire_file(SEQUENCE, EXPECTED_COUNTS[SEQUENCE])
    add_i18n_helpers()
    fix_sequence_split_string()
    fix_settings_clear_button()
    rewrite_about_dialog()

    print("\n=== S141 gauntlet loop ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================\n")


if __name__ == "__main__":
    main()
