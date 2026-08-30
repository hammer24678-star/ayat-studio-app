// PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS
// Shared "about this app" dialog — shown from both the welcome screen's
// «معرفة المزيد عن التطبيق» link and the studio's app-bar (i) button, so
// the copy only lives in one place.
import 'package:flutter/material.dart'; // PATCH_S141_HOME_SEQUENCE_ABOUT_I18N

import '../i18n/app_strings.dart';
import '../services/app_settings.dart';
import '../theme/ayat_theme.dart';

void showAyatInfoDialog(BuildContext context) {
  final s = AppStrings(AppSettings.instance.lang);
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AyatColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AyatColors.hairline),
      ),
      title: Text(s.t('about.title')),
      content: SingleChildScrollView(
        child: Text(
          s.t('about.body'),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.8),
        ),
      ),
      actions: [
        FilledButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.t('common.close'))),
      ],
    ),
  );
}
