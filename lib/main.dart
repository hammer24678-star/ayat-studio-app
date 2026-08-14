import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';

import 'i18n/app_strings.dart';
import 'screens/splash_screen.dart';
import 'services/app_settings.dart';
import 'theme/ayat_theme.dart';

// PATCH_S25_SAVE_TO_DOWNLOADS: MediaStore needs to be initialized once, and needs an
// "app folder" name set up front (it throws AppFolderNotSetException
// otherwise) -- this is the subfolder created under Download/ (and
// under any other MediaStore collection) that exported files land in.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    await MediaStore.ensureInitialized();
  }
  MediaStore.appFolder = 'AyatStudio';
  // PATCH_S123_APP_SETTINGS: language and the animations switch decide what
  // the very first frame looks like, so they have to be read before runApp —
  // otherwise the splash would play in the wrong language, or play at all for
  // someone who turned motion off.
  await AppSettings.instance.load();
  runApp(const AyatStudioApp());
}

class AyatStudioApp extends StatelessWidget {
  const AyatStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilding the whole app on a settings change is what makes switching
    // language or turning animations off take effect instantly, with no
    // restart — the tree is small above the current screen.
    return ListenableBuilder(
      listenable: AppSettings.instance,
      builder: (context, _) {
        final settings = AppSettings.instance;
        return MaterialApp(
          title: settings.strings.t('app.name'),
          debugShowCheckedModeBanner: false,
          theme: AyatTheme.dark,
          locale: Locale(kLangCodes[settings.lang]!),
          // PATCH_S123_I18N: the UI was hard-forced to RTL for the
          // Arabic-only build. It now follows the chosen language, so English
          // and French lay out left-to-right while Arabic and Urdu stay RTL.
          // The Quran text itself is always rendered RTL by the reader, in
          // every language.
          builder: (context, child) => Directionality(
            textDirection: settings.textDirection,
            child: child ?? const SizedBox.shrink(),
          ),
          home: const SplashScreen(),
        );
      },
    );
  }
}
