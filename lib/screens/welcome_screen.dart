// شاشة الترحيب — shown after the splash, before the studio.
// PATCH_S123_WELCOME_POLISH: the copy is the same as it always was, but the
// screen now assembles itself instead of appearing flat, is fully localized,
// carries a settings entry, and offers the mushaf as a first-class
// destination rather than burying it three taps into the editor.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_settings.dart';
import '../theme/ayat_theme.dart';
import '../widgets/ayat_info_dialog.dart';
import '../widgets/motion.dart';
import '../widgets/quran_entry_button.dart';
import 'home_screen.dart';
import 'mushaf_loader_screen.dart';
import 'settings_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const List<(IconData, String)> _features = [
    (Icons.check_circle_outline, 'app.feature.ai'),
    (Icons.grid_view_outlined, 'app.feature.templates'),
    (Icons.graphic_eq, 'app.feature.reciters'),
    (Icons.auto_stories_outlined, 'app.feature.mushaf'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = AppSettings.instance.strings;
    return Scaffold(
      backgroundColor: AyatColors.ink,
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: IconButton(
                  tooltip: s.t('settings.title'),
                  icon: const Icon(Icons.settings_outlined,
                      color: AyatColors.gold),
                  onPressed: () => Navigator.of(context)
                      .push(AppMotion.route(const SettingsScreen())),
                ),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: staggered(
                    [
                      _Logo(),
                      const SizedBox(height: 18),
                      Text(
                        s.t('app.eyebrow'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.tajawal(
                          color: AyatColors.gold,
                          fontSize: 12,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 6),
                      GoldShimmer(
                        child: Text(
                          s.t('app.name'),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineLarge,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        s.t('app.tagline'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.tajawal(
                          color: AyatColors.parchmentDim,
                          fontSize: 13.5,
                          height: 1.9,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final f in _features) ...[
                            _FeatureRow(icon: f.$1, label: s.t(f.$2)),
                            const SizedBox(height: 11),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      _PrimaryCta(
                        label: s.t('app.start'),
                        onTap: () => Navigator.of(context)
                            .pushReplacement(AppMotion.route(const HomeScreen())),
                      ),
                      const SizedBox(height: 12),
                      // The reader is a destination in its own right — many
                      // opens of this app are "I want to read", not "I want
                      // to edit". It shouldn't be hidden inside the editor.
                      QuranEntryButton(
                        title: s.t('mushaf.open'),
                        subtitle: s.t('mushaf.openHint'),
                        onTap: () => Navigator.of(context).push(
                          AppMotion.route(const MushafLoaderScreen()),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => showAyatInfoDialog(context),
                        child: Text(
                          s.t('app.learnMore'),
                          style: GoogleFonts.tajawal(
                              color: AyatColors.parchmentDim, fontSize: 12.5),
                        ),
                      ),
                    ],
                    step: const Duration(milliseconds: 60),
                    start: const Duration(milliseconds: 80),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AyatColors.gold.withValues(alpha: 0.22),
              blurRadius: 26,
              spreadRadius: 1,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Image.asset(
            'assets/icon/app_icon.png',
            width: 76,
            height: 76,
            fit: BoxFit.cover,
          ),
        ),
      );
}

/// The main call to action — a solid gold bar with the app's press feel.
class _PrimaryCta extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PrimaryCta({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AyatColors.goldBright, AyatColors.gold],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: [
              BoxShadow(
                color: AyatColors.gold.withValues(alpha: 0.3),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Text(
            label,
            style: GoogleFonts.tajawal(
              color: AyatColors.ink,
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
            ),
          ),
        ),
      );
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
            style: GoogleFonts.tajawal(
                color: AyatColors.parchment, fontSize: 12.5, height: 1.5),
          ),
        ),
      ],
    );
  }
}
