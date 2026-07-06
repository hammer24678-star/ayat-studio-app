import 'package:flutter/material.dart';
import 'screens/welcome_screen.dart';
import 'theme/ayat_theme.dart';

void main() => runApp(const AyatStudioApp());

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
