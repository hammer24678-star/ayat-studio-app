// PATCH_S170_MAGIC_FEATURES
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
