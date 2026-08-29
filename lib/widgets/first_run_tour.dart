// PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
// FirstRunTour: three cards, shown once, answers "من أين أبدأ؟" before
// the user ever sees the advanced panels.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../i18n/app_strings.dart'; // PATCH_S139_MUSHAF_AR_EN_AND_I18N_WIDGETS
import '../services/app_settings.dart'; // PATCH_S139_MUSHAF_AR_EN_AND_I18N_WIDGETS
import '../theme/ayat_theme.dart';

class FirstRunTour {
  static const _key = 'ayat_studio.app.tourDone';
  static Future<void> maybeShow(BuildContext context) async {
    final p = await SharedPreferences.getInstance();
    if (p.getBool(_key) == true) return;
    await p.setBool(_key, true);
    if (!context.mounted) return;
    showDialog(context: context, builder: (_) => const _Tour());
  }
}

class _Tour extends StatefulWidget {
  const _Tour();
  @override
  State<_Tour> createState() => _TourState();
}

class _TourState extends State<_Tour> {
  int i = 0;
  static const steps = [
    ('١', 'ارفع تلاوة', 'فيديو أو ملف صوتي — ولو صوت فقط ضع خلفية صورة أو فيديو'),
    ('٢', 'اختر الآيات', 'بالكشف التلقائي أو يدويًا من السورة والآية — النص يأتي من المصحف دائمًا'),
    ('٣', 'صدّر', 'اضبط الشكل من تبويب النص ثم صدّر بجودة تصل إلى مصدر الفيديو'),
  ];
  @override
  Widget build(BuildContext c) {
    final s = AppStrings(AppSettings.instance.lang); // PATCH_S139_MUSHAF_AR_EN_AND_I18N_WIDGETS
    return AlertDialog(
    backgroundColor: AyatColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    title: Text(s.t('firstRunTour.title'),
      style: TextStyle(color: AyatColors.gold, fontSize: 16)),
    content: SizedBox(width: 300, height: 150, child: Column(children: [
      Text(steps[i].$1, style: TextStyle(fontSize: 40, color: AyatColors.goldBright)),
      Text(steps[i].$2, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Text(steps[i].$3, textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12, color: AyatColors.parchment.withValues(alpha: .8))),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context),
        child: Text(s.t('firstRunTour.skip'))),
      ElevatedButton(onPressed: () =>
        i == 2 ? Navigator.pop(context) : setState(() => i++),
        child: Text(i == 2 ? 'ابدأ' : 'التالي')),
    ]);
  }
}
