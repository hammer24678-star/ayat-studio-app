import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'screens/welcome_screen.dart';
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
  runApp(const AyatStudioApp());
}

class AyatStudioApp extends StatelessWidget {
  const AyatStudioApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'استوديو الآيات',
      debugShowCheckedModeBanner: false,
      theme: AyatTheme.dark,
      // The whole UI is Arabic — force RTL globally like the HTML's dir="rtl".
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      home: const WelcomeScreen(),
    );
  }
}
