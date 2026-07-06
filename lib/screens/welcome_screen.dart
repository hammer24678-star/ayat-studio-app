// شاشة الترحيب — native port of the HTML prototype's #welcomeScreen: shown
// on cold start, before the studio. Same copy/order as the browser version
// (see docs/ayat_studio225.html's .welcome-* rules) — logo, eyebrow, title,
// subtitle, three feature bullets, a primary CTA into the studio, and a
// link that opens the same info dialog the studio's (i) button uses.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/ayat_theme.dart';
import '../widgets/ayat_info_dialog.dart';
import 'home_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const List<(IconData, String)> _features = [
    (Icons.check_circle_outline, 'تعرّف تلقائي بالذكاء الاصطناعي على الآية وترجمتها'),
    (Icons.grid_view_outlined, 'خلفيات، كروم، وقوالب نصية جاهزة'),
    (Icons.graphic_eq, 'تلاوات قرّاء جاهزة مع معاينة صوتية'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AyatColors.ink,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/icon/app_icon.png',
                    width: 72,
                    height: 72,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'تصميم مقاطع قرآنية',
                  style: GoogleFonts.tajawal(
                    color: AyatColors.gold,
                    fontSize: 12,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'استوديو الآيات',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 14),
                Text(
                  'حوّل أي فيديو إلى تصميم قرآني احترافي: الآية، ترجمة المعاني، '
                  'والقارئ — كلها في مكان واحد.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                    color: AyatColors.parchmentDim,
                    fontSize: 13.5,
                    height: 1.9,
                  ),
                ),
                const SizedBox(height: 26),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final f in _features) ...[
                      _FeatureRow(icon: f.$1, label: f.$2),
                      const SizedBox(height: 11),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AyatColors.gold,
                      foregroundColor: AyatColors.ink,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      textStyle:
                          GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const HomeScreen()),
                    ),
                    child: const Text('ابدأ التصميم'),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => showAyatInfoDialog(context),
                  child: Text(
                    'معرفة المزيد عن التطبيق',
                    style:
                        GoogleFonts.tajawal(color: AyatColors.parchmentDim, fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 19, color: AyatColors.gold),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.tajawal(color: AyatColors.parchment, fontSize: 12.5, height: 1.5),
          ),
        ),
      ],
    );
  }
}
