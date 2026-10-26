// PATCH_S123_SETTINGS_SCREEN: the app never had a settings screen — every
// preference was buried in whichever panel happened to own it. This is the
// one place for the choices that describe the app itself: language, whether
// the interface animates at all, and how the Quran reader looks.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // PATCH_S207_WHISPER_SETTINGS: Clipboard
import 'package:google_fonts/google_fonts.dart';

import '../app_info.dart';
import '../i18n/app_strings.dart';
import '../services/app_settings.dart';
import '../services/tafsir_service.dart';
import '../services/whisper_service.dart'; // PATCH_S207_WHISPER_SETTINGS
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
                    // PATCH_S141_HOME_SEQUENCE_ABOUT_I18N: this was
                    // hardcoded ar/en-only, silently showing English
                    // to fr/id/ur users -- route through the table
                    // like every other string on this screen.
                    s.t('settings.clearCache'),
                    style: GoogleFonts.tajawal(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                      foregroundColor: AyatColors.goldBright),
                ),
              ],
            ),
          ]),
          const SizedBox(height: 14),
          _WhisperSection(s: s), // PATCH_S207_WHISPER_SETTINGS
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

// PATCH_S207_WHISPER_SETTINGS: everything about Whisper in one place. The
// "try another model size from Settings" error used to point here while
// Settings had nothing of the kind.
class _WhisperSection extends StatefulWidget {
  final AppStrings s;
  const _WhisperSection({required this.s});

  @override
  State<_WhisperSection> createState() => _WhisperSectionState();
}

class _WhisperSectionState extends State<_WhisperSection> {
  final _settings = AppSettings.instance;
  Map<WhisperModelSize, int?> _have = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final m = <WhisperModelSize, int?>{};
    for (final t in WhisperModelSize.values) {
      m[t] = await WhisperService.downloadedBytes(t);
    }
    if (mounted) setState(() => _have = m);
  }

  WhisperModelSize get _tier {
    final i = _settings.whisperTierIndex;
    if (i != null && i >= 0 && i < WhisperModelSize.values.length) {
      return WhisperModelSize.values[i];
    }
    return WhisperService.currentSize;
  }

  String _mb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.toStringAsFixed(0)} MB';
  }

  void _pickTier(WhisperModelSize t) {
    _settings.setWhisperTierIndex(t.index);
    WhisperService.setModelSize(t);
    setState(() {});
  }

  Future<void> _redownload() async {
    if (_busy) return;
    setState(() => _busy = true);
    await WhisperService.deleteModel(_tier);
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.s.t('whisper.deleted'))),
    );
  }

  void _reset() {
    _settings.setWhisperThreads(0);
    _settings.setWhisperFastShort(false);
    _settings.setWhisperVad(true);
    WhisperService.resetDiagnostics();
    setState(() {});
  }

  Widget _tierRow(WhisperModelSize t, AppStrings s) {
    final sel = _tier == t;
    final bytes = _have[t];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableScale(
        onTap: () => _pickTier(t),
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: AppMotion.d(AppMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: sel
                ? AyatColors.gold.withValues(alpha: 0.16)
                : AyatColors.surface2,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: sel ? AyatColors.gold : AyatColors.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                sel ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: sel ? AyatColors.goldBright : AyatColors.parchmentDim,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('whisper.tier.${t.name}'),
                      style: GoogleFonts.tajawal(
                        color: sel
                            ? AyatColors.goldBright
                            : AyatColors.parchment,
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bytes != null
                          ? '${s.t('whisper.downloaded')} ✓ · ${_mb(bytes)}'
                          : s.t('whisper.notDownloaded'),
                      style: GoogleFonts.tajawal(
                          color: AyatColors.parchmentDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchTile(
      String title, String hint, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      activeThumbColor: AyatColors.gold,
      title: Text(title,
          style: GoogleFonts.tajawal(
              color: AyatColors.parchment, fontSize: 13.5)),
      subtitle: Text(hint,
          style: GoogleFonts.tajawal(
              color: AyatColors.parchmentDim, fontSize: 11.5, height: 1.5)),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final err = WhisperService.lastError;
    return _Section(title: s.t('whisper.title'), children: [
      _Label(s.t('whisper.model')),
      const SizedBox(height: 8),
      for (final t in WhisperModelSize.values) _tierRow(t, s),
      const Divider(height: 26, color: AyatColors.hairline),
      _Label(s.t('whisper.threads')),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final n in const [0, 2, 3, 4, 6, 8])
            _Choice(
              label: n == 0
                  ? '${s.t('whisper.threadsAuto')} (${WhisperService.autoThreads})'
                  : '$n',
              selected: _settings.whisperThreads == n,
              onTap: () => setState(() => _settings.setWhisperThreads(n)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _Hint('${s.t('whisper.threadsHint')} ${WhisperService.cpuCores}'),
      const Divider(height: 26, color: AyatColors.hairline),
      _switchTile(
        s.t('whisper.fast'),
        s.t('whisper.fastHint'),
        _settings.whisperFastShort,
        (v) => setState(() => _settings.setWhisperFastShort(v)),
      ),
      _switchTile(
        s.t('whisper.vad'),
        s.t('whisper.vadHint'),
        _settings.whisperVad,
        (v) => setState(() => _settings.setWhisperVad(v)),
      ),
      if (err != null && err.trim().isNotEmpty) ...[
        const Divider(height: 26, color: AyatColors.hairline),
        Row(
          children: [
            _Label(s.t('whisper.lastError')),
            const Spacer(),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: err)),
              icon: const Icon(Icons.copy, size: 16),
              label: Text(s.t('whisper.copy'),
                  style: GoogleFonts.tajawal(fontSize: 12)),
              style: TextButton.styleFrom(
                  foregroundColor: AyatColors.goldBright),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AyatColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AyatColors.hairline),
          ),
          child: SelectableText(
            err,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
                color: AyatColors.parchmentDim),
          ),
        ),
      ],
      const Divider(height: 26, color: AyatColors.hairline),
      OutlinedButton.icon(
        onPressed: _busy ? null : _redownload,
        icon: const Icon(Icons.refresh, size: 18),
        label: Text(s.t('whisper.redownload')),
      ),
      const SizedBox(height: 6),
      _Hint(s.t('whisper.redownloadHint')),
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt, size: 17),
          label: Text(s.t('whisper.reset'),
              style: GoogleFonts.tajawal(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: AyatColors.goldBright),
        ),
      ),
    ]);
  }
}
