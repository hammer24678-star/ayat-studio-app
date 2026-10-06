#!/usr/bin/env python3
"""
patch_s170_magic_features.py
============================
Ayat Studio S170 - run from the repo root (after S169):

    python3 patch_s170_magic_features.py

THREE ORIGINAL FEATURES, one card ("سحر الآية") above the export button:

 1. AYAH MOOD (مزاج الآية)
    The app reads the verse's own words - mercy, light, majesty, patience,
    gratitude, paradise, the Reckoning, water, creation, supplication - and
    styles the whole video from its meaning in one tap: stage effect +
    intensity, text colour, colour grade and vignette. A dice button
    ("فاجئني") jumps to a different mood. With an auto-sync timeline it reads
    every detected ayah. AI-art prompts get the same mood hint, so generated
    backgrounds match the verse instead of being generic.

 2. MOMENT OF THE DAY (اقتراح اللحظة)
    With no verse chosen, the card suggests one for NOW: Al-Kahf on Friday,
    Ayat al-Kursi at dawn, "with hardship comes ease" mid-day, Al-Asr in the
    afternoon, Ad-Duha in the evening, Al-Mulk at night. One tap loads it.

 3. STUDIO LAMP (سراج الاستوديو)
    A 7-dot lamp that lights one dot per consecutive day you export. Miss a
    day and it resets. Milestones (3 / 7 / 14 / 30 / 100) get a gold burst
    and a dua-style message. Stored on-device only.

New files : lib/services/ayah_mood.dart, lib/services/lamp_streak.dart,
            lib/widgets/magic_card.dart
Edited    : home_screen.dart (card + export hook), ai_art_service.dart
Everything follows Settings > animations. Idempotent (marker PATCH_S170).
Anchor-checked: if anything is missing NOTHING is written.
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
MARK = 'PATCH_S170'


def rd(p):
    with open(os.path.join(ROOT, p), encoding='utf-8') as f:
        return f.read()


def exists(p):
    return os.path.exists(os.path.join(ROOT, p))


HOME = 'lib/screens/home_screen.dart'
ART = 'lib/services/ai_art_service.dart'
NEWF = ['lib/services/ayah_mood.dart', 'lib/services/lamp_streak.dart', 'lib/widgets/magic_card.dart']

for p in (HOME, ART):
    if not exists(p):
        sys.exit('missing ' + p)
home, art = rd(HOME), rd(ART)
if MARK in home and MARK in art and all(exists(p) for p in NEWF):
    print('  OK      already applied'); sys.exit(0)

problems = []


def need(c, m):
    if not c:
        problems.append(m)


# ============================================================ ayah_mood.dart
AYAH_MOOD = r"""// PATCH_S170_MAGIC_FEATURES
// Ayah Mood: read a verse's own vocabulary and decide how the video should
// FEEL. Pure Dart, no network, instant. Works on both plain and Uthmani text
// (marks and dagger-alef are stripped before matching, so 'ٱلرَّحْمَـٰن' and
// 'الرحمن' are the same word, and both spellings of the stems are listed).
import 'package:flutter/material.dart';

import '../data/studio_presets.dart';
import 'stage_effects.dart';

class MoodRecipe {
  final String id;
  final String labelAr;
  final String blurb;
  final String emoji;
  final StageEffect effect;
  final double intensity;
  final Color textColor;
  final ColorGrade grade;
  final int vignette; // 0 = off
  final String artHint; // appended to AI-art prompts (English, no figures)
  const MoodRecipe({
    required this.id,
    required this.labelAr,
    required this.blurb,
    required this.emoji,
    required this.effect,
    required this.intensity,
    required this.textColor,
    required this.grade,
    required this.vignette,
    required this.artHint,
  });
}

class _Lex {
  final List<String> stems; // token CONTAINS the stem (stems are >= 3 letters)
  final Set<String> exact; // token EQUALS one of these
  final double weight;
  const _Lex(this.stems, [this.exact = const {}, this.weight = 1.0]);
}

class AyahMood {
  static const List<MoodRecipe> all = [
    MoodRecipe(
      id: 'dua',
      labelAr: 'دعاء ومناجاة',
      blurb: 'ضوء شمعة في العتمة، همسٌ بين العبد وربّه',
      emoji: '🕯️',
      effect: StageEffect.candleGlow,
      intensity: 0.6,
      textColor: Color(0xFFECE2CB),
      grade: ColorGrade.warmGold,
      vignette: 45,
      artHint:
          'a single lit lantern glowing in quiet darkness, intimate supplication mood, warm candle light',
    ),
    MoodRecipe(
      id: 'mercy',
      labelAr: 'رحمة ومغفرة',
      blurb: 'أشعّة دافئة تتسلّل من بين الغيم',
      emoji: '🌤️',
      effect: StageEffect.warmGodRays,
      intensity: 0.6,
      textColor: Color(0xFFECC875),
      grade: ColorGrade.warmGold,
      vignette: 35,
      artHint:
          'warm golden light rays breaking through soft clouds, gentle and merciful mood',
    ),
    MoodRecipe(
      id: 'light',
      labelAr: 'نور وهداية',
      blurb: 'شعاعٌ نقيّ يشقّ الظلام',
      emoji: '✨',
      effect: StageEffect.rays,
      intensity: 0.7,
      textColor: Color(0xFFFFFFFF),
      grade: ColorGrade.none,
      vignette: 0,
      artHint:
          'radiant beams of pure white-gold light piercing darkness, guidance and clarity',
    ),
    MoodRecipe(
      id: 'majesty',
      labelAr: 'جلال وعظمة',
      blurb: 'سماءٌ واسعة تُشعرك بصِغرك أمام العظيم',
      emoji: '🌌',
      effect: StageEffect.starfield,
      intensity: 0.8,
      textColor: Color(0xFFC9A24B),
      grade: ColorGrade.nightTeal,
      vignette: 55,
      artHint:
          'vast cosmic scale, glowing sacred geometry above endless stars, awe and majesty',
    ),
    MoodRecipe(
      id: 'patience',
      labelAr: 'صبر وسكينة',
      blurb: 'نبضٌ هادئ كنَفَسٍ عميق',
      emoji: '🌙',
      effect: StageEffect.breathingGlow,
      intensity: 0.55,
      textColor: Color(0xFF8FBBAF),
      grade: ColorGrade.nightTeal,
      vignette: 40,
      artHint:
          'still moonlit calm water and a quiet horizon, serene patience',
    ),
    MoodRecipe(
      id: 'gratitude',
      labelAr: 'شكر ونعمة',
      blurb: 'بريقٌ ذهبيّ متناثر كالنِّعَم',
      emoji: '🌾',
      effect: StageEffect.bokeh,
      intensity: 0.65,
      textColor: Color(0xFFECC875),
      grade: ColorGrade.warmGold,
      vignette: 0,
      artHint:
          'abundant blossoms, fruit and golden bokeh light, thankful abundance',
    ),
    MoodRecipe(
      id: 'paradise',
      labelAr: 'جنّة ونعيم',
      blurb: 'بتلات تتساقط في حديقة لا تذبل',
      emoji: '🌿',
      effect: StageEffect.petals,
      intensity: 0.6,
      textColor: Color(0xFFE8D5A8),
      grade: ColorGrade.none,
      vignette: 30,
      artHint:
          'lush garden with flowing rivers, flowering trees and soft green-gold light',
    ),
    MoodRecipe(
      id: 'reckoning',
      labelAr: 'يوم الحساب',
      blurb: 'جمرٌ خافت وأفقٌ مهيب، تذكيرٌ بالمصير',
      emoji: '⚖️',
      effect: StageEffect.embers,
      intensity: 0.7,
      textColor: Color(0xFFECE2CB),
      grade: ColorGrade.sepia,
      vignette: 65,
      artHint:
          'dramatic stormy sky with ember glow on the horizon, solemn reminder',
    ),
    MoodRecipe(
      id: 'water',
      labelAr: 'ماء وحياة',
      blurb: 'رذاذٌ ناعم يُحيي الأرض بعد موتها',
      emoji: '🌧️',
      effect: StageEffect.drizzle,
      intensity: 0.6,
      textColor: Color(0xFFA8C5D6),
      grade: ColorGrade.nightTeal,
      vignette: 35,
      artHint: 'rain clouds, a flowing river and sea mist, life-giving water',
    ),
    MoodRecipe(
      id: 'creation',
      labelAr: 'آيات الكون',
      blurb: 'نجومٌ تتلألأ فوق الجبال',
      emoji: '🪐',
      effect: StageEffect.twinkleStars,
      intensity: 0.75,
      textColor: Color(0xFFA8C5D6),
      grade: ColorGrade.nightTeal,
      vignette: 45,
      artHint:
          'vast night sky with stars, mountains and deep space, wonder of creation',
    ),
    MoodRecipe(
      id: 'calm',
      labelAr: 'سكينة',
      blurb: 'وهجٌ ذهبيّ هادئ يتنفّس ببطء',
      emoji: '🤍',
      effect: StageEffect.glowPulse,
      intensity: 0.5,
      textColor: Color(0xFFECE2CB),
      grade: ColorGrade.none,
      vignette: 0,
      artHint: 'quiet golden glow, minimal and serene',
    ),
  ];

  // Order = tie-break priority: specific moods before generic ones.
  static const Map<String, _Lex> _lex = {
    'dua': _Lex(
      ['دعو', 'دعا', 'استجب', 'اجيب', 'اللهم'],
      {'ربنا', 'وربنا', 'فربنا', 'ربي', 'وربي'},
      2.0,
    ),
    'mercy': _Lex(
      ['رحم', 'غفر', 'غفور', 'عفو', 'توب', 'ودود', 'لطيف', 'رءوف', 'حليم', 'ستر'],
    ),
    'light': _Lex(
      ['نور', 'هدي', 'هدا', 'صراط', 'صرط', 'بينات', 'بينت', 'برهان', 'ضياء', 'سراج', 'منير', 'فرقان'],
      {},
      1.5,
    ),
    'majesty': _Lex(
      ['عزيز', 'جبار', 'قهار', 'عظيم', 'ملك', 'عرش', 'كرسي', 'قدير', 'شديد', 'جلال', 'متكبر', 'قيوم', 'صمد'],
      {'احد'},
    ),
    'patience': _Lex(
      ['صبر', 'صابر', 'اصطبر', 'سكين', 'اطمان', 'تطمين', 'يسر', 'فرج', 'توكل'],
      {'حسبي', 'حسبنا'},
    ),
    'gratitude': _Lex(
      ['شكر', 'نعم', 'فضل', 'رزق', 'بارك', 'برك', 'حمد', 'الاء', 'ءالاء'],
    ),
    'paradise': _Lex(
      ['جنات', 'جنت', 'جنه', 'فردوس', 'نعيم', 'انهار', 'سندس', 'استبرق', 'عدن', 'ظلال', 'اريك', 'تجري'],
    ),
    'reckoning': _Lex(
      ['قيمه', 'قيامه', 'ساعه', 'نار', 'جهنم', 'حساب', 'ميزان', 'بعث', 'جحيم', 'سعير', 'حاقه', 'واقعه', 'عذاب', 'نفخ'],
      {'الدين'},
    ),
    'water': _Lex(
      ['مطر', 'سحاب', 'غيث', 'بحر', 'نهر', 'رياح', 'ودق'],
      {'ماء', 'الماء', 'بماء', 'والماء', 'ماءا'},
    ),
    'creation': _Lex(
      ['سموت', 'سماو', 'سماء', 'ارض', 'شمس', 'قمر', 'نجوم', 'نجم', 'جبال', 'جبل', 'ليل', 'نهار', 'فلك', 'كواكب', 'خلق'],
      {},
      0.6,
    ),
  };

  static MoodRecipe byId(String id) =>
      all.firstWhere((r) => r.id == id, orElse: () => all.last);

  static String _norm(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r == 0x0640) continue; // tatweel
      if (r >= 0x064B && r <= 0x065F) continue; // harakat
      if (r == 0x0670) continue; // dagger alef
      if (r >= 0x06D6 && r <= 0x06ED) continue; // Quranic annotation marks
      switch (r) {
        case 0x0622:
        case 0x0623:
        case 0x0625:
        case 0x0671:
          b.writeCharCode(0x0627); // alef variants -> ا
        case 0x0649:
        case 0x0626:
          b.writeCharCode(0x064A); // ى ئ -> ي
        case 0x0629:
          b.writeCharCode(0x0647); // ة -> ه
        case 0x0624:
          b.writeCharCode(0x0648); // ؤ -> و
        default:
          b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  /// The mood that best fits [text]; [calm] when nothing matches.
  static MoodRecipe analyze(String text) {
    final tokens = _norm(text)
        .split(RegExp(r'[^\u0621-\u064A]+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return byId('calm');
    String? best;
    var bestScore = 0.0;
    for (final e in _lex.entries) {
      var score = 0.0;
      for (final t in tokens) {
        if (e.value.exact.contains(t) ||
            e.value.stems.any((s) => t.contains(s))) {
          score += e.value.weight;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        best = e.key;
      }
    }
    return best == null ? byId('calm') : byId(best);
  }

  static String artHint(String text) => analyze(text).artHint;
}
"""

# ============================================================ lamp_streak.dart
LAMP = r"""// PATCH_S170_MAGIC_FEATURES
// Studio Lamp: one dot lights per consecutive day with an export. Local only.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LampInfo {
  final int streak; // consecutive days, 0 when the chain is broken
  final int total; // lifetime exports
  final bool litToday;
  const LampInfo(this.streak, this.total, this.litToday);
}

class LampStreak {
  static final ValueNotifier<LampInfo?> info = ValueNotifier<LampInfo?>(null);
  static const _kLast = 'lamp_last_day';
  static const _kStreak = 'lamp_streak';
  static const _kTotal = 'lamp_total';

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
  static String _key(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime? _parse(String? s) {
    if (s == null) return null;
    final p = s.split('-');
    if (p.length != 3) return null;
    final y = int.tryParse(p[0]), m = int.tryParse(p[1]), d = int.tryParse(p[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }

  static Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final today = _day(DateTime.now());
      final last = _parse(p.getString(_kLast));
      var streak = p.getInt(_kStreak) ?? 0;
      final gap = last == null ? 999 : today.difference(last).inDays;
      if (gap > 1) streak = 0; // chain broken
      info.value = LampInfo(streak, p.getInt(_kTotal) ?? 0, gap == 0);
    } catch (_) {
      info.value ??= const LampInfo(0, 0, false);
    }
  }

  /// Call after a successful export.
  static Future<LampInfo> lightUp() async {
    try {
      final p = await SharedPreferences.getInstance();
      final today = _day(DateTime.now());
      final last = _parse(p.getString(_kLast));
      var streak = p.getInt(_kStreak) ?? 0;
      final total = (p.getInt(_kTotal) ?? 0) + 1;
      final gap = last == null ? 999 : today.difference(last).inDays;
      if (gap == 0) {
        streak = streak < 1 ? 1 : streak;
      } else if (gap == 1) {
        streak += 1;
      } else {
        streak = 1;
      }
      await p.setString(_kLast, _key(today));
      await p.setInt(_kStreak, streak);
      await p.setInt(_kTotal, total);
      final r = LampInfo(streak, total, true);
      info.value = r;
      return r;
    } catch (_) {
      return info.value ?? const LampInfo(0, 0, true);
    }
  }

  /// A message for the days worth marking, null otherwise.
  static String? milestoneMessage(int streak) => switch (streak) {
        3 => 'ثلاثة أيام متتالية — سراجك يتوهّج ✨ ثبّتك الله',
        7 => 'أسبوعٌ كامل! اكتمل سراجك 🪔 بارك الله في عملك',
        14 => 'أسبوعان من النور المتواصل — جزاك الله خيرًا',
        30 => 'شهرٌ كامل من العطاء! تقبّل الله منك 🌙',
        100 => 'مئة يوم! سراجٌ لا ينطفئ — نفع الله بك',
        _ => null,
      };
}
"""

# ============================================================ magic_card.dart
CARD = r"""// PATCH_S170_MAGIC_FEATURES
// "سحر الآية": Ayah Mood + Moment of the day + Studio Lamp, in one card.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/studio_state.dart';
import '../services/ayah_mood.dart';
import '../services/lamp_streak.dart';
import '../services/stage_effects.dart';
import '../theme/ayat_theme.dart';
import 'motion.dart';

class _Moment {
  final String title;
  final String why;
  final int surah;
  final int ayah;
  const _Moment(this.title, this.why, this.surah, this.ayah);
}

_Moment _momentNow() {
  final n = DateTime.now();
  final h = n.hour;
  if (n.weekday == DateTime.friday) {
    return const _Moment('سورة الكهف', 'نورٌ ما بين الجمعتين', 18, 1);
  }
  if (h >= 4 && h < 8) {
    return const _Moment('آية الكرسي', 'حصن الصباح', 2, 255);
  }
  if (h >= 8 && h < 15) {
    return const _Moment('إنّ مع العسر يسرًا', 'لحظة فرج في منتصف اليوم', 94, 5);
  }
  if (h >= 15 && h < 18) {
    return const _Moment('والعصر', 'اغتنم ما تبقّى من يومك', 103, 1);
  }
  if (h >= 18 && h < 22) {
    return const _Moment('والضحى', 'طمأنينة المساء', 93, 3);
  }
  return const _Moment('تبارك الذي بيده الملك', 'نورك قبل النوم', 67, 1);
}

String _arDigits(int n) {
  const d = '٠١٢٣٤٥٦٧٨٩';
  return n.toString().split('').map((c) {
    final i = int.tryParse(c);
    return i == null ? c : d[i];
  }).join();
}

class MagicCard extends StatefulWidget {
  final StudioState state;
  final void Function(String message) onToast;
  const MagicCard({super.key, required this.state, required this.onToast});

  @override
  State<MagicCard> createState() => _MagicCardState();
}

class _MagicCardState extends State<MagicCard> {
  final math.Random _rng = math.Random();
  String? _cacheText;
  MoodRecipe? _cacheMood;
  String? _lastSurprise;

  @override
  void initState() {
    super.initState();
    LampStreak.load();
  }

  String _text() {
    final s = widget.state;
    if (s.timelineActive && s.timeline.isNotEmpty) {
      return s.timeline.map((t) => t.ayah.ar).toSet().join(' ');
    }
    return s.ayahText;
  }

  MoodRecipe _moodFor(String text) {
    if (_cacheText == text && _cacheMood != null) return _cacheMood!;
    _cacheText = text;
    return _cacheMood = AyahMood.analyze(text);
  }

  bool _applied(MoodRecipe r) {
    final s = widget.state;
    return s.effect == r.effect && s.textColor == r.textColor;
  }

  void _apply(MoodRecipe r) {
    final s = widget.state;
    HapticFeedback.mediumImpact();
    s.update(() {
      s.effect = r.effect;
      s.effectIntensity = r.intensity;
      s.textColor = r.textColor;
      s.colorGrade = r.grade;
      s.vignetteEnabled = r.vignette > 0;
      if (r.vignette > 0) s.vignetteIntensity = r.vignette;
    });
    widget.onToast('طُبِّق مزاج «${r.labelAr}» ${r.emoji}');
  }

  void _surprise(MoodRecipe current) {
    final pool = AyahMood.all
        .where((r) => r.id != current.id && r.id != _lastSurprise)
        .toList();
    final r = pool[_rng.nextInt(pool.length)];
    _lastSurprise = r.id;
    _apply(r);
  }

  void _loadMoment(_Moment m) {
    final s = widget.state;
    final idx =
        s.ayaat.indexWhere((a) => a.surahNum == m.surah && a.num == m.ayah);
    if (idx < 0) {
      widget.onToast('القرآن لم يُحمَّل بعد — لحظة من فضلك');
      return;
    }
    final a = s.ayaat[idx];
    HapticFeedback.selectionClick();
    s.setAyah(a.ar, a.en, 'اقتراح اللحظة: سورة ${a.surah} — آية ${a.num}',
        surahNum: a.surahNum, ayahNum: a.num);
  }

  // ------------------------------------------------------------------ UI

  Widget _pill(Widget lead, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AyatColors.surface3,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AyatColors.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          lead,
          const SizedBox(width: 6),
          Text(text,
              style: const TextStyle(
                  fontSize: 11.5, color: AyatColors.parchmentDim)),
        ]),
      );

  Widget _goldButton(String label, IconData icon, VoidCallback? onTap) {
    final on = onTap != null;
    return PressableScale(
      borderRadius: BorderRadius.circular(14),
      pressedScale: 0.96,
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppMotion.d(AppMotion.fast),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: on
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AyatColors.goldBright, AyatColors.gold])
              : null,
          color: on ? null : AyatColors.surface3,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 18, color: on ? AyatColors.ink : AyatColors.goldDim),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: on ? AyatColors.ink : AyatColors.goldDim)),
        ]),
      ),
    );
  }

  Widget _ghostButton(String label, IconData icon, VoidCallback onTap) =>
      PressableScale(
        borderRadius: BorderRadius.circular(14),
        pressedScale: 0.96,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AyatColors.goldDim),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 18, color: AyatColors.goldBright),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AyatColors.goldBright)),
          ]),
        ),
      );

  Widget _moodBody(MoodRecipe r) {
    final applied = _applied(r);
    return AnimatedSwitcher(
      duration: AppMotion.d(AppMotion.medium),
      transitionBuilder: (c, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
              .animate(a),
          child: c,
        ),
      ),
      child: Column(
        key: ValueKey(r.id),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(r.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('مزاج الآية: ${r.labelAr}',
                      style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AyatColors.goldBright)),
                  const SizedBox(height: 2),
                  Text(r.blurb,
                      style: const TextStyle(
                          fontSize: 12, color: AyatColors.parchmentDim)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _pill(
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                      color: r.textColor,
                      shape: BoxShape.circle,
                      border: Border.all(color: AyatColors.hairline)),
                ),
                'لون النص'),
            _pill(const Icon(Icons.auto_awesome, size: 13, color: AyatColors.gold),
                r.effect.label),
            if (r.vignette > 0)
              _pill(const Icon(Icons.vignette_outlined,
                      size: 13, color: AyatColors.gold),
                  'تعتيم الأطراف'),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _goldButton(applied ? 'مُطبَّق ✓' : 'طبّق المزاج',
                applied ? Icons.check_rounded : Icons.auto_fix_high_rounded,
                applied ? null : () => _apply(r)),
            _ghostButton('فاجئني', Icons.casino_outlined, () => _surprise(r)),
          ]),
        ],
      ),
    );
  }

  Widget _momentBody() {
    final m = _momentNow();
    final ready = widget.state.ayaat.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.schedule_rounded, color: AyatColors.goldBright, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('اقتراح اللحظة',
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: AyatColors.goldBright)),
                const SizedBox(height: 2),
                Text('${m.title} — ${m.why}',
                    style: const TextStyle(
                        fontSize: 12.5, color: AyatColors.parchmentDim)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 14),
        _goldButton(ready ? 'ابدأ بها' : 'جارٍ تحميل القرآن…',
            Icons.play_circle_outline_rounded, ready ? () => _loadMoment(m) : null),
      ],
    );
  }

  Widget _lamp() {
    return ValueListenableBuilder<LampInfo?>(
      valueListenable: LampStreak.info,
      builder: (context, i, _) {
        final streak = i?.streak ?? 0;
        final lit = streak == 0 ? 0 : ((streak - 1) % 7) + 1;
        return Row(children: [
          Icon(Icons.local_fire_department_rounded,
              size: 18,
              color: streak > 0 ? AyatColors.goldBright : AyatColors.goldDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              streak == 0
                  ? 'أشعل سراج الاستوديو بأول تصدير اليوم'
                  : 'سراج الاستوديو · ${_arDigits(streak)} ${streak == 1 ? 'يوم' : 'أيام'} متتالية',
              style: const TextStyle(fontSize: 12, color: AyatColors.parchmentDim),
            ),
          ),
          for (var d = 0; d < 7; d++)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: AnimatedContainer(
                duration: AppMotion.d(AppMotion.medium),
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: d < lit ? AyatColors.goldBright : AyatColors.surface3,
                  boxShadow: d < lit
                      ? [
                          BoxShadow(
                              color: AyatColors.gold.withValues(alpha: 0.5),
                              blurRadius: 6)
                        ]
                      : const [],
                  border: Border.all(color: AyatColors.hairline),
                ),
              ),
            ),
        ]);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        final text = _text();
        final hasText = text.trim().isNotEmpty;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF16291F), AyatColors.surface],
            ),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AyatColors.goldDim.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.auto_awesome_rounded,
                    size: 15, color: AyatColors.gold),
                const SizedBox(width: 6),
                const Text('سحر الآية',
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w700,
                        color: AyatColors.gold)),
              ]),
              const SizedBox(height: 12),
              hasText ? _moodBody(_moodFor(text)) : _momentBody(),
              const SizedBox(height: 14),
              const Divider(height: 1, color: AyatColors.hairline),
              const SizedBox(height: 12),
              _lamp(),
            ],
          ),
        );
      },
    );
  }
}
"""

# ============================================================ hooks
new_home, new_art = home, art

if MARK not in home:
    a = "import '../widgets/motion.dart'; // PATCH_S123_MOTION\n"
    need(a in home, 'home_screen.dart: motion import not found')
    b = ("                const SizedBox(height: 18),\n"
         "                if (!state.hasVideo) _staticDurationRow(),")
    need(home.count(b) == 1, 'home_screen.dart: card anchor (before _staticDurationRow) not found/unique')
    c = "    showGoldBurst(context); // PATCH_S169_MOTION_FEEL\n"
    need(c in home, 'home_screen.dart: export-done burst line not found (apply S169 first)')
    if not problems:
        new_home = home.replace(
            a, a + "import '../widgets/magic_card.dart'; // PATCH_S170\n"
                   "import '../services/lamp_streak.dart'; // PATCH_S170\n", 1)
        new_home = new_home.replace(
            b,
            "                const SizedBox(height: 18),\n"
            "                // PATCH_S170_MAGIC_FEATURES: mood / moment / lamp\n"
            "                FadeSlideIn(\n"
            "                    delay: const Duration(milliseconds: 200),\n"
            "                    child: MagicCard(state: state, onToast: _toast)),\n"
            "                const SizedBox(height: 14),\n"
            "                if (!state.hasVideo) _staticDurationRow(),", 1)
        new_home = new_home.replace(
            c,
            c + "    LampStreak.lightUp().then((info) {\n"
                "      // PATCH_S170: light the studio lamp, mark milestones\n"
                "      final msg = LampStreak.milestoneMessage(info.streak);\n"
                "      if (msg != null && mounted) _toast(msg);\n"
                "    });\n", 1)

if MARK not in art:
    d = "import 'package:http/http.dart' as http;"
    e = "        'down to a lone empty landscape, $_noFacesRule';"
    need(d in art, 'ai_art_service.dart: http import not found')
    need(e in art, 'ai_art_service.dart: scene prompt tail not found')
    if not problems:
        new_art = art.replace(d, d + "\nimport 'ayah_mood.dart'; // PATCH_S170", 1)
        new_art = new_art.replace(
            e,
            "        'down to a lone empty landscape, '\n"
            "        '${AyahMood.artHint(ayahArabic)}, ' // PATCH_S170: mood-matched look\n"
            "        '$_noFacesRule';", 1)

if problems:
    print('  NOTHING WRITTEN. Missing anchors:')
    for p in problems:
        print('   -', p)
    sys.exit(1)

# balance check on everything we will write
bad = 0
for name, txt in [(HOME, new_home), (ART, new_art), (NEWF[0], AYAH_MOOD),
                  (NEWF[1], LAMP), (NEWF[2], CARD)]:
    s = re.sub(r"//[^\n]*", '', txt)
    s = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", s)
    s = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', s)
    for x, y in ('{}', '()', '[]'):
        if s.count(x) != s.count(y):
            bad += 1
            print('  UNBALANCED', name, x, s.count(x), y, s.count(y))
if bad:
    sys.exit('  NOTHING WRITTEN (brackets unbalanced).')

for path, txt in zip(NEWF, (AYAH_MOOD, LAMP, CARD)):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, 'w', encoding='utf-8') as f:
        f.write(txt)
    print('  CREATED', path)
for path, old, newt in ((HOME, home, new_home), (ART, art, new_art)):
    if newt != old:
        with open(os.path.join(ROOT, path), 'w', encoding='utf-8') as f:
            f.write(newt)
        print('  PATCHED', path)
print('Done. Next: git add -A && git commit -m "S170: Ayah Mood, Moment, Studio Lamp" && git push')
