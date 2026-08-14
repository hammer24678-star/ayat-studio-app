// PATCH_S123_MUSHAF_FROM_WELCOME: the reader is reachable from the welcome
// screen, before any studio session exists — so it can't borrow
// StudioState.ayaat the way the in-studio entry point does. This loads the
// corpus itself (one 2.4MB asset decode, ~200ms) behind a themed spinner and
// then hands off to the real reader.
//
// The parsed list is kept in a static so a second visit in the same session
// is instant rather than re-decoding the JSON.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/quran_repository.dart';
import '../services/app_settings.dart';
import '../services/ayah_matcher.dart';
import '../theme/ayat_theme.dart';
import 'mushaf_screen.dart';

class MushafLoaderScreen extends StatefulWidget {
  /// Ayah font to read in. Defaults to the app's bundled mushaf face.
  final String fontKey;
  const MushafLoaderScreen({super.key, this.fontKey = 'digitalmadina'});

  @override
  State<MushafLoaderScreen> createState() => _MushafLoaderScreenState();
}

class _MushafLoaderScreenState extends State<MushafLoaderScreen> {
  static List<Ayah>? _cached;

  List<Ayah>? _ayaat = _cached;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_ayaat == null) _load();
  }

  Future<void> _load() async {
    try {
      final list = await QuranRepository.loadFullCorpus();
      _cached = list;
      if (mounted) setState(() => _ayaat = list);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppSettings.instance;
    final ayaat = _ayaat;
    if (ayaat != null) {
      return MushafScreen(
        ayaat: ayaat,
        fontKey: widget.fontKey,
        initialAyahId:
            settings.lastReadAyahId > 0 ? settings.lastReadAyahId : null,
      );
    }
    return Scaffold(
      backgroundColor: AyatColors.ink,
      appBar: AppBar(
        backgroundColor: AyatColors.ink,
        iconTheme: const IconThemeData(color: AyatColors.gold),
        title: Text(settings.strings.t('mushaf.title')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _error == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(
                        color: AyatColors.goldBright, strokeWidth: 2.4),
                    const SizedBox(height: 18),
                    Text(
                      settings.strings.t('common.loading'),
                      style: GoogleFonts.tajawal(
                          color: AyatColors.parchmentDim, fontSize: 13),
                    ),
                  ],
                )
              : Text(
                  '${settings.strings.t('mushaf.loadFailed')}\n$_error',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchmentDim, fontSize: 13),
                ),
        ),
      ),
    );
  }
}
