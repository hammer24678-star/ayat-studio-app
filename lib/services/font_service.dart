// PATCH_S39_PERSISTENT_FONTS
// Makes uploaded ayah fonts durable. The old flow registered a picked
// TTF/OTF under a throwaway session family name ("CustomAyahFont1") that
// vanished on every restart; now the file is copied into the app's own
// documents dir and re-registered under a STABLE family derived from the
// filename on every launch — so a Quran font like Elgharib-NoonHafs.ttf is
// picked from the phone once and behaves like a built-in from then on
// (including staying the selected default via the persisted fontKey).
import 'dart:io';
import 'dart:typed_data' show ByteData, Uint8List;

import 'package:flutter/services.dart' show FontLoader;
import 'package:path_provider/path_provider.dart';

import '../data/studio_presets.dart';

class FontService {
  static final RegExp _fontExt = RegExp(r'\.(ttf|otf)$', caseSensitive: false);

  static Future<Directory> _fontsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/ayat_fonts');
    await dir.create(recursive: true);
    return dir;
  }

  /// Stable family name for a font file — derived from the filename only,
  /// so the same file maps to the same family on every launch.
  static String familyOf(String fileName) {
    final stem = fileName.replaceAll(_fontExt, '');
    final safe = stem.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    return 'Ayat_$safe';
  }

  static String _labelOf(String fileName) =>
      'خط محفوظ: ${fileName.replaceAll(_fontExt, '')}';

  static Future<void> _register(String family, List<int> bytes) async {
    final data = ByteData.view(Uint8List.fromList(bytes).buffer);
    final loader = FontLoader(family)..addFont(Future.value(data));
    await loader.load(); // throws on an invalid font file
  }

  /// Imports a picked TTF/OTF: registers it for immediate use AND copies it
  /// into the persistent fonts dir so [loadSavedFonts] restores it on every
  /// future launch. Throws if the file isn't a loadable font.
  static Future<AyahFontChoice> importFont(
      String sourcePath, String fileName) async {
    final safeName = fileName.split('/').last;
    if (!_fontExt.hasMatch(safeName)) {
      throw Exception('ليس ملف خط TTF/OTF');
    }
    final bytes = await File(sourcePath).readAsBytes();
    final family = familyOf(safeName);
    await _register(family, bytes);
    final dir = await _fontsDir();
    await File('${dir.path}/$safeName').writeAsBytes(bytes);
    return AyahFontChoice(family, _labelOf(safeName));
  }

  /// Loads every previously imported font from the persistent dir and
  /// registers it under its stable family. Unloadable leftovers are skipped
  /// (and cleaned up) rather than breaking startup.
  static Future<List<AyahFontChoice>> loadSavedFonts() async {
    final out = <AyahFontChoice>[];
    try {
      final dir = await _fontsDir();
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        if (!_fontExt.hasMatch(name)) continue;
        try {
          await _register(familyOf(name), await entry.readAsBytes());
          out.add(AyahFontChoice(familyOf(name), _labelOf(name)));
        } catch (_) {
          entry.delete().ignore(); // corrupt leftover — don't retry forever
        }
      }
    } catch (_) {
      // storage hiccup — the built-in fonts still work
    }
    return out;
  }
}
