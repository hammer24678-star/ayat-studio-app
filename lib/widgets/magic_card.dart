// PATCH_S170_MAGIC_FEATURES
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
