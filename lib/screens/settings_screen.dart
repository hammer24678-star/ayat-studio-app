// PATCH_S123_SETTINGS_SCREEN: the app never had a settings screen — every
// preference was buried in whichever panel happened to own it. This is the
// one place for the choices that describe the app itself: language, whether
// the interface animates at all, and how the Quran reader looks.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_info.dart';
import '../i18n/app_strings.dart';
import '../services/app_settings.dart';
import '../services/tafsir_service.dart';
import '../theme/ayat_theme.dart';
import '../widgets/motion.dart';
import '../widgets/user_guide_sheet.dart'; // PATCH_S128

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _settings = AppSettings.instance;
  int? _cacheBytes;

  @override
  void initState() {
    super.initState();
    _refreshCacheSize();
  }

  Future<void> _refreshCacheSize() async {
    final n = await TafsirService.cacheSizeBytes();
    if (mounted) setState(() => _cacheBytes = n);
  }

  String _humanBytes(int n) {
    if (n < 1024) return '$n B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(0)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final s = _settings.strings;
    return Scaffold(
      backgroundColor: AyatColors.ink,
      appBar: AppBar(
        title: Text(s.t('settings.title')),
        iconTheme: const IconThemeData(color: AyatColors.gold),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: staggered([
          _Section(title: s.t('settings.interface'), children: [
            _Label(s.t('settings.language')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in AppLang.values)
                  _Choice(
                    label: kLangNames[l]!,
                    selected: _settings.lang == l,
                    onTap: () => setState(() => _settings.setLang(l)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _Hint(s.t('settings.languageNote')),
            const Divider(height: 26, color: AyatColors.hairline),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _settings.animations,
              activeThumbColor: AyatColors.gold,
              title: Text(s.t('settings.animations'),
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchment, fontSize: 13.5)),
              subtitle: Text(s.t('settings.animationsHint'),
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchmentDim,
                      fontSize: 11.5,
                      height: 1.5)),
              onChanged: (v) => setState(() => _settings.setAnimations(v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _settings.classicTabs,
              activeThumbColor: AyatColors.gold,
              title: Text(s.t('settings.classicTabs'),
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchment, fontSize: 13.5)),
              subtitle: Text(s.t('settings.classicTabsHint'),
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchmentDim,
                      fontSize: 11.5,
                      height: 1.5)),
              onChanged: (v) => setState(() => _settings.setClassicTabs(v)),
            ),
          ]),
          const SizedBox(height: 14),
          _Section(title: s.t('settings.quran'), children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _settings.mushafLight,
              activeThumbColor: AyatColors.gold,
              title: Text(s.t('mushaf.lightMode'),
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchment, fontSize: 13.5)),
              subtitle: Text(s.t('mushaf.lightModeHint'),
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchmentDim,
                      fontSize: 11.5,
                      height: 1.5)),
              onChanged: (v) => setState(() => _settings.setMushafLight(v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _settings.readerTranslation,
              activeThumbColor: AyatColors.gold,
              title: Text(s.t('mushaf.showTranslation'),
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchment, fontSize: 13.5)),
              onChanged: (v) =>
                  setState(() => _settings.setReaderTranslation(v)),
            ),
            const SizedBox(height: 6),
            _Label(s.t('mushaf.viewMode')),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Choice(
                    label: s.t('mushaf.viewPage'),
                    selected: _settings.mushafView == MushafViewMode.page,
                    onTap: () => setState(
                        () => _settings.setMushafView(MushafViewMode.page)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Choice(
                    label: s.t('mushaf.viewSurah'),
                    selected: _settings.mushafView == MushafViewMode.surah,
                    onTap: () => setState(
                        () => _settings.setMushafView(MushafViewMode.surah)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _Label(s.t('mushaf.fontSize')),
                const Spacer(),
                Text('${_settings.mushafFontSize.round()}',
                    style: GoogleFonts.tajawal(
                        color: AyatColors.parchmentDim, fontSize: 12)),
              ],
            ),
            Slider(
              min: 16,
              max: 40,
              divisions: 24,
              value: _settings.mushafFontSize,
              activeColor: AyatColors.gold,
              inactiveColor: AyatColors.hairline,
              onChanged: (v) =>
                  setState(() => _settings.setMushafFontSize(v)),
            ),
            const SizedBox(height: 6),
            _Label(s.t('mushaf.tafsirEdition')),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AyatColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AyatColors.hairline),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: editionBySlug(_settings.tafsirEdition).slug,
                  dropdownColor: AyatColors.surface2,
                  iconEnabledColor: AyatColors.gold,
                  style: const TextStyle(color: AyatColors.parchment),
                  items: [
                    for (final e in kTafsirEditions)
                      DropdownMenuItem(
                        value: e.slug,
                        child: Text(
                          _settings.lang == AppLang.ar ? e.nameAr : e.nameEn,
                          style: GoogleFonts.tajawal(fontSize: 13.5),
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() {
                    if (v != null) _settings.setTafsirEdition(v);
                  }),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _Hint(s.t('mushaf.tafsirOffline')),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _cacheBytes == null
                        ? '…'
                        : '${s.t('mushaf.tafsirCached')} — ${_humanBytes(_cacheBytes!)}',
                    style: GoogleFonts.tajawal(
                        color: AyatColors.parchmentDim, fontSize: 12),
                  ),
                ),
                TextButton.icon(
                  onPressed: (_cacheBytes ?? 0) == 0
                      ? null
                      : () async {
                          await TafsirService.clearCache();
                          await _refreshCacheSize();
                        },
                  icon: const Icon(Icons.delete_outline, size: 17),
                  label: Text(
                    _settings.lang == AppLang.ar ? 'مسح' : 'Clear',
                    style: GoogleFonts.tajawal(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                      foregroundColor: AyatColors.goldBright),
                ),
              ],
            ),
          ]),
          // PATCH_S128: touch-controls guide
          const SizedBox(height: 14),
          _Section(title: s.t('settings.guide'), children: [
            OutlinedButton.icon(
              onPressed: () => showUserGuide(context, s),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: Text(s.t('settings.guideOpen')),
            ),
            const SizedBox(height: 6),
            _Hint(s.t('settings.guideHint')),
          ]),
          const SizedBox(height: 14),
          _Section(title: s.t('settings.about'), children: [
            Row(
              children: [
                _Label(s.t('settings.version')),
                const Spacer(),
                Text('$kAppVersion ($kAppBuildNumber)',
                    style: GoogleFonts.tajawal(
                        color: AyatColors.parchmentDim, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 12),
            _Hint('$kPrivacyPolicyUrl\n$kSupportTelegram · $kSupportEmail'),
          ]),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        decoration: BoxDecoration(
          color: AyatColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AyatColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: GoogleFonts.arefRuqaa(
                color: AyatColors.goldBright,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            // PATCH_S123_SETTINGS_SCREEN: the SwitchListTiles inside a section
            // paint their ink on the nearest Material ancestor, which here is
            // behind this card's coloured DecoratedBox -- Flutter asserts on
            // exactly that arrangement, and the splash would be invisible.
            // A transparent Material of their own puts the ink in front.
            Material(
              type: MaterialType.transparency,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.tajawal(
            color: AyatColors.gold, fontSize: 12, fontWeight: FontWeight.w700),
      );
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.tajawal(
            color: AyatColors.parchmentDim, fontSize: 11.5, height: 1.6),
      );
}

class _Choice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => PressableScale(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: AppMotion.d(AppMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AyatColors.gold.withValues(alpha: 0.16)
                : AyatColors.surface2,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? AyatColors.gold : AyatColors.hairline,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(
              color:
                  selected ? AyatColors.goldBright : AyatColors.parchmentDim,
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      );
}
