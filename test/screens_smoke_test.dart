// PATCH_S123_SMOKE: `flutter analyze` proves the new screens compile, not
// that they build. Layout asserts, RangeErrors off the end of the corpus and
// missing-ancestor errors all only show up when something actually pumps the
// widget — which, for a repo whose CI produces an APK and never runs the app,
// nothing did.
//
// Motion is switched off for these: several widgets legitimately run
// repeating animations, and pumpAndSettle never settles against an infinite
// controller. The static path is also the one where a layout mistake is
// easiest to see.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ayat_studio_app/data/mushaf_meta.dart';
import 'package:ayat_studio_app/i18n/app_strings.dart';
import 'package:ayat_studio_app/main.dart';
import 'package:ayat_studio_app/screens/splash_screen.dart';
import 'package:ayat_studio_app/screens/mushaf_screen.dart';
import 'package:ayat_studio_app/screens/settings_screen.dart';
import 'package:ayat_studio_app/screens/welcome_screen.dart';
import 'package:ayat_studio_app/services/app_settings.dart';
import 'package:ayat_studio_app/services/ayah_matcher.dart';
import 'package:ayat_studio_app/theme/ayat_theme.dart';

/// A corpus with the real shape — every surah at its real length — so page
/// ranges, juz lookups and surah headers all resolve exactly as they will in
/// the app. The text is a placeholder; none of the layout depends on it.
List<Ayah> buildFullCorpus() {
  final out = <Ayah>[];
  for (final m in kSurahMeta) {
    for (var n = 1; n <= m.ayahCount; n++) {
      out.add(Ayah(
        surahNum: m.num,
        surah: 'سورة ${m.num}',
        num: n,
        ar: 'وَمَا خَلَقْتُ ٱلْجِنَّ وَٱلْإِنسَ إِلَّا لِيَعْبُدُونِ',
        en: 'Placeholder translation.',
      ));
    }
  }
  return out;
}

Widget host(Widget child) => MaterialApp(
      theme: AyatTheme.dark,
      home: child,
      builder: (context, c) => Directionality(
        textDirection: AppSettings.instance.textDirection,
        child: c ?? const SizedBox.shrink(),
      ),
    );

void main() {
  late List<Ayah> corpus;

  setUpAll(() {
    corpus = buildFullCorpus();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.setAnimations(false);
    AppSettings.instance.setLang(AppLang.ar);
    AppSettings.instance.setMushafLight(false);
    AppSettings.instance.setMushafView(MushafViewMode.page);
  });

  // PATCH_S124_ROOT_COVERAGE: lib/main.dart and the splash were imported by
  // no test at all, so `flutter test` never compiled them -- and CI's only
  // other Dart compile is inside `flutter build apk`, which needs the Android
  // SDK and runs after everything else. A break in either would have reached
  // a user before it reached a test. These two pump the real root widget.
  testWidgets('the app root builds and reaches the welcome screen', (t) async {
    await t.pumpWidget(const AyatStudioApp());
    // Motion is off, so the splash replaces itself on the first post-frame.
    await t.pump();
    await t.pump();
    expect(find.text(const AppStrings(AppLang.ar).t('app.start')), findsOneWidget);
    expect(tester_exception(), isNull);
  });

  testWidgets('the app root follows the chosen language and direction',
      (t) async {
    AppSettings.instance.setLang(AppLang.en);
    await t.pumpWidget(const AyatStudioApp());
    await t.pump();
    await t.pump();
    expect(find.text('Start designing'), findsOneWidget);
    expect(
      Directionality.of(t.element(find.text('Start designing'))),
      TextDirection.ltr,
    );
    expect(tester_exception(), isNull);
  });

  testWidgets('the animated splash renders without throwing', (t) async {
    AppSettings.instance.setAnimations(true);
    await t.pumpWidget(const MaterialApp(home: SplashScreen()));
    await t.pump(const Duration(milliseconds: 120));
    await t.pump(const Duration(milliseconds: 600));
    await t.pump(const Duration(milliseconds: 600));
    expect(find.byType(SplashScreen), findsOneWidget);
    expect(tester_exception(), isNull);
    // Tear the tree down explicitly: the splash and the welcome screen behind
    // it run repeating shimmer/glow tickers, which never settle on their own.
    await t.pumpWidget(const SizedBox.shrink());
    AppSettings.instance.setAnimations(false);
  });

  testWidgets('the welcome screen builds with both entry points', (t) async {
    await t.pumpWidget(host(const WelcomeScreen()));
    await t.pump();
    expect(find.text(const AppStrings(AppLang.ar).t('app.start')), findsOneWidget);
    expect(
        find.text(const AppStrings(AppLang.ar).t('mushaf.open')), findsOneWidget);
    expect(tester_exception(), isNull);
  });

  testWidgets('the settings screen builds and lists every language', (t) async {
    await t.pumpWidget(host(const SettingsScreen()));
    await t.pump();
    for (final l in AppLang.values) {
      expect(find.text(kLangNames[l]!), findsOneWidget);
    }
    expect(tester_exception(), isNull);
  });

  testWidgets('switching language re-renders the settings screen in it',
      (t) async {
    AppSettings.instance.setLang(AppLang.en);
    await t.pumpWidget(host(const SettingsScreen()));
    await t.pump();
    expect(find.text('Interface animations'), findsOneWidget);
    expect(tester_exception(), isNull);
  });

  group('mushaf reader', () {
    testWidgets('shows a loading state instead of crashing on a short corpus',
        (t) async {
      await t.pumpWidget(host(MushafScreen(ayaat: const [], fontKey: 'amiri')));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester_exception(), isNull);
    });

    testWidgets('builds the surah index over the full corpus', (t) async {
      await t.pumpWidget(host(MushafScreen(ayaat: corpus, fontKey: 'amiri')));
      await t.pump();
      expect(find.text('سورة 1'), findsWidgets);
      expect(tester_exception(), isNull);
    });

    testWidgets('renders a mushaf page, and the last page too', (t) async {
      await t.pumpWidget(host(MushafScreen(
        ayaat: corpus,
        fontKey: 'amiri',
        initialAyahId: kPageStartAyahId.last, // page 604
      )));
      await t.pump();
      // Tab 1 is the reader; the screen opens on the index.
      await t.tap(find.text(const AppStrings(AppLang.ar).t('mushaf.read')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      // The footer prints the page number the way a mushaf does — Eastern
      // Arabic-Indic digits, not '604'.
      expect(find.textContaining(easternArabicNumeral(604)), findsWidgets);
      expect(tester_exception(), isNull);
    });

    testWidgets('renders in light mode and in whole-surah mode', (t) async {
      AppSettings.instance.setMushafLight(true);
      AppSettings.instance.setMushafView(MushafViewMode.surah);
      await t.pumpWidget(host(MushafScreen(
        ayaat: corpus,
        fontKey: 'digitalmadina',
        initialSurah: 2,
      )));
      await t.pump();
      await t.tap(find.text(const AppStrings(AppLang.ar).t('mushaf.read')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(tester_exception(), isNull);
    });

    testWidgets('the tafsir tab asks for an ayah before fetching anything',
        (t) async {
      await t.pumpWidget(host(MushafScreen(ayaat: corpus, fontKey: 'amiri')));
      await t.pump();
      await t.tap(find.text(const AppStrings(AppLang.ar).t('mushaf.tafsir')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text(const AppStrings(AppLang.ar).t('mushaf.tafsirPick')),
          findsOneWidget);
      expect(tester_exception(), isNull);
    });
  });
}

/// Any exception the framework swallowed into its error reporter during the
/// last pump. `expect(..., isNull)` on this turns a red-box render error into
/// a failed test instead of a passing one.
Object? tester_exception() {
  final e = TestWidgetsFlutterBinding.instance.takeException();
  return e;
}
