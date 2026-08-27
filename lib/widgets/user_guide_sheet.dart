// PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../i18n/app_strings.dart';
import '../theme/ayat_theme.dart';

Future<bool> userGuideSeen() async =>
    (await SharedPreferences.getInstance())
        .getBool('ayat_studio.app.guideSeen') ?? false;

Future<void> showUserGuide(BuildContext context, AppStrings s) async {
  final p = await SharedPreferences.getInstance();
  await p.setBool('ayat_studio.app.guideSeen', true);
  if (!context.mounted) return;
  showModalBottomSheet(
    context: context, backgroundColor: AyatColors.surface,
    shape: const RoundedRectangleBorder(borderRadius:
        BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => SafeArea(child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment:
          CrossAxisAlignment.start, children: [
        Center(child: Container(width: 44, height: 4,
          decoration: BoxDecoration(color: AyatColors.hairline,
            borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 12),
        Text(s.t('guide.title'), style: GoogleFonts.arefRuqaa(
            color: AyatColors.gold, fontSize: 19, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        for (final e in const [
          (Icons.touch_app_outlined, 'guide.box'),
          (Icons.drag_indicator, 'guide.drag'),
          (Icons.pinch_outlined, 'guide.pinch'),
          (Icons.format_color_text, 'guide.wordTap'),
          (Icons.timeline, 'guide.timeline'),
        ]) ...[
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(e.$1, size: 19, color: AyatColors.goldBright),
            const SizedBox(width: 10),
            Expanded(child: Text(s.t(e.$2), style: GoogleFonts.tajawal(
                color: AyatColors.parchment, fontSize: 13, height: 1.7))),
          ]),
          const SizedBox(height: 10),
        ],
      ]),
    )),
  );
}
