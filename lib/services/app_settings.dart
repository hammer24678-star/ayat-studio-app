// PATCH_S123_APP_SETTINGS: app-wide (not project-wide) preferences that live
// outside StudioState because they survive every project and every screen:
// interface language, whether UI animations run at all, the Quran reader's
// own light/dark mode, reading position, and tafsir choice.
//
// StudioState/SettingsService stay responsible for the *editing* session
// (fonts, backgrounds, timeline…). This holds the things that describe the
// app itself, so the welcome screen and the mushaf reader can read them
// without dragging a whole StudioState around.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../i18n/app_strings.dart';

/// How the mushaf reader lays text out.
enum MushafViewMode {
  /// One printed mushaf page at a time, swipeable, with the page number.
  page,

  /// A whole surah in one continuous scroll.
  surah,
}

class AppSettings extends ChangeNotifier {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _prefix = 'ayat_studio.app.';

  // ---- interface ----
  AppLang _lang = AppLang.ar;
  AppLang get lang => _lang;
  AppStrings get strings => AppStrings(_lang);
  TextDirection get textDirection =>
      isRtlLang(_lang) ? TextDirection.rtl : TextDirection.ltr;

  /// Master switch for every decorative animation in the app (splash spin,
  /// staggered reveals, button press feedback, page transitions). Off makes
  /// the whole UI snap instantly — for low-end phones, or simply for users
  /// who find motion distracting.
  bool _animations = true;
  bool get animations => _animations;

  // ---- Quran reader ----
  /// Light mode applies to the mushaf reader ONLY — the studio stays dark,
  /// because a dark editor is what a video editor wants, while a bright page
  /// is what a reader wants.
  bool _mushafLight = false;
  bool get mushafLight => _mushafLight;

  MushafViewMode _mushafView = MushafViewMode.page;
  MushafViewMode get mushafView => _mushafView;

  /// Reader font size in logical pixels (the mushaf's own slider, separate
  /// from the video overlay's ayah size).
  double _mushafFontSize = 24;
  double get mushafFontSize => _mushafFontSize;

  /// Global ayah id (1-based, 1..6236) the reader was last looking at, so
  /// "متابعة القراءة" can jump straight back to it.
  int _lastReadAyahId = 0;
  int get lastReadAyahId => _lastReadAyahId;

  /// Slug of the tafsir edition shown first in the explanation tab.
  String _tafsirEdition = 'ar-tafsir-muyassar';
  String get tafsirEdition => _tafsirEdition;

  /// Show the English meaning under each ayah in the reader.
  bool _readerTranslation = false;
  bool get readerTranslation => _readerTranslation;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// Reads everything back from disk. Call once, before runApp — a storage
  /// failure leaves the defaults in place rather than blocking startup.
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final langIdx = p.getInt('${_prefix}lang');
    if (langIdx != null && langIdx >= 0 && langIdx < AppLang.values.length) {
      _lang = AppLang.values[langIdx];
    }
    _animations = p.getBool('${_prefix}animations') ?? _animations;
    _mushafLight = p.getBool('${_prefix}mushafLight') ?? _mushafLight;
    final viewIdx = p.getInt('${_prefix}mushafView');
    if (viewIdx != null &&
        viewIdx >= 0 &&
        viewIdx < MushafViewMode.values.length) {
      _mushafView = MushafViewMode.values[viewIdx];
    }
    _mushafFontSize =
        (p.getDouble('${_prefix}mushafFontSize') ?? _mushafFontSize)
            .clamp(16.0, 40.0);
    _lastReadAyahId =
        (p.getInt('${_prefix}lastReadAyahId') ?? _lastReadAyahId).clamp(0, 6236);
    _tafsirEdition = p.getString('${_prefix}tafsirEdition') ?? _tafsirEdition;
    _readerTranslation =
        p.getBool('${_prefix}readerTranslation') ?? _readerTranslation;
    notifyListeners();
  }

  Future<void> _write(void Function(SharedPreferences p) mutate) async {
    notifyListeners();
    try {
      mutate(await SharedPreferences.getInstance());
    } catch (_) {
      // A failed write only costs this preference on the next launch.
    }
  }

  void setLang(AppLang v) {
    if (v == _lang) return;
    _lang = v;
    _write((p) => p.setInt('${_prefix}lang', v.index));
  }

  void setAnimations(bool v) {
    if (v == _animations) return;
    _animations = v;
    _write((p) => p.setBool('${_prefix}animations', v));
  }

  void setMushafLight(bool v) {
    if (v == _mushafLight) return;
    _mushafLight = v;
    _write((p) => p.setBool('${_prefix}mushafLight', v));
  }

  void setMushafView(MushafViewMode v) {
    if (v == _mushafView) return;
    _mushafView = v;
    _write((p) => p.setInt('${_prefix}mushafView', v.index));
  }

  void setMushafFontSize(double v) {
    final c = v.clamp(16.0, 40.0);
    if (c == _mushafFontSize) return;
    _mushafFontSize = c;
    _write((p) => p.setDouble('${_prefix}mushafFontSize', c));
  }

  void setLastReadAyahId(int v) {
    final c = v.clamp(0, 6236);
    if (c == _lastReadAyahId) return;
    _lastReadAyahId = c;
    _write((p) => p.setInt('${_prefix}lastReadAyahId', c));
  }

  void setTafsirEdition(String v) {
    if (v == _tafsirEdition) return;
    _tafsirEdition = v;
    _write((p) => p.setString('${_prefix}tafsirEdition', v));
  }

  void setReaderTranslation(bool v) {
    if (v == _readerTranslation) return;
    _readerTranslation = v;
    _write((p) => p.setBool('${_prefix}readerTranslation', v));
  }
}
