import 'package:flutter/material.dart';
import 'screens/home_screen.dart';
import 'theme/ayat_theme.dart';

void main() => runApp(const AyatStudioApp());

class AyatStudioApp extends StatelessWidget {
  const AyatStudioApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ayat Studio',
      debugShowCheckedModeBanner: false,
      theme: AyatTheme.dark,
      home: const HomeScreen(),
    );
  }
}
