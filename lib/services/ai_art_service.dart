// PATCH_S32_AI_ART_NANO_BANANA
//
// Generates one background image per detected ayah using Pollinations'
// free, keyless image endpoint (Flux model) -- no API key, no billing.
// The faceless / no-portrait rule and the "light pillar + name medallion"
// treatment for ayat mentioning a prophet are baked directly into the
// prompt text below, never exposed as editable UI, so the house style
// (glowing monochrome line-art, see ayat_studio-22.html reference frames)
// can't drift per-ayah.
//
// Images are cached to disk forever, keyed by surah:ayah (+ a seed offset
// for manual regenerate), so the same ayah never re-hits the network and
// re-editing the same clip later reproduces the exact same art.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AiArtService {
  static const String _base = 'https://gen.pollinations.ai/image/';

  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/ai_art_cache');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _fileFor(int surahNum, int ayahNum, int seedOffset) async {
    final dir = await _cacheDir();
    final suffix = seedOffset == 0 ? '' : '_v$seedOffset';
    return File('${dir.path}/${surahNum}_$ayahNum$suffix.png');
  }

  /// Fixed house style -- matches the glowing monochrome line-art reference
  /// frames (ayat_studio-22.html). Never surfaced as editable text.
  static const String _styleBase =
      'monochrome glowing line-art illustration, deep black background, '
      'thin luminous white outline strokes, subtle starry night sky, '
      'minimal Middle-Eastern desert architecture silhouettes in the '
      'background, quiet reverent mood, high contrast, no color, '
      'digital line-art poster style';

  /// Repeated at the END of every prompt on purpose -- placing it last
  /// keeps it from being diluted/overridden by earlier scene-description
  /// tokens the way an early instruction can be.
  static const String _noFacesRule =
      'absolutely no human faces, no facial features, no eyes, no mouths -- '
      'every person shown only as a plain faceless glowing silhouette or '
      'outline with a blank featureless head where the face would be';

  /// Prophet names as they can appear in unvocalized Quranic text. If any
  /// show up in the matched ayah, the ENTIRE prompt is replaced with the
  /// light-pillar + medallion treatment instead of attempting to depict
  /// the prophet as a figure at all.
  static const Map<String, String> _prophetNames = {
    'نوح': 'نوح',
    'هود': 'هود',
    'صالح': 'صالح',
    'ابراهيم': 'إبراهيم',
    'إبراهيم': 'إبراهيم',
    'اسماعيل': 'إسماعيل',
    'إسماعيل': 'إسماعيل',
    'اسحاق': 'إسحاق',
    'إسحاق': 'إسحاق',
    'يعقوب': 'يعقوب',
    'يوسف': 'يوسف',
    'ايوب': 'أيوب',
    'أيوب': 'أيوب',
    'شعيب': 'شعيب',
    'موسي': 'موسى',
    'موسى': 'موسى',
    'هارون': 'هارون',
    'داود': 'داود',
    'سليمان': 'سليمان',
    'الياس': 'إلياس',
    'إلياس': 'إلياس',
    'اليسع': 'اليسع',
    'يونس': 'يونس',
    'ذا النون': 'يونس',
    'زكريا': 'زكريا',
    'يحيي': 'يحيى',
    'يحيى': 'يحيى',
    'عيسي': 'عيسى',
    'عيسى': 'عيسى',
    'لوط': 'لوط',
    'ادم': 'آدم',
    'آدم': 'آدم',
    'محمد': 'محمد',
  };

  static String? _matchedProphet(String ayahArabic) {
    for (final entry in _prophetNames.entries) {
      if (ayahArabic.contains(entry.key)) return entry.value;
    }
    return null;
  }

  static String _buildPrompt(String ayahArabic) {
    final prophet = _matchedProphet(ayahArabic);
    if (prophet != null) {
      return '$_styleBase, a single tall pillar of soft glowing white light '
          'standing where a person would be, no body, no figure, no face at '
          'all, a circular medallion above the light pillar containing the '
          'Arabic calligraphy name "$prophet" written in elegant thuluth '
          'script, $_noFacesRule';
    }
    return '$_styleBase, faceless glowing silhouette figures only if the '
        'scene calls for people, otherwise an empty landscape, scene '
        'inspired by the theme of this Quranic ayah, $_noFacesRule';
  }

  /// Returns a local file path to the cached (or freshly generated) art for
  /// [surahNum]:[ayahNum], or null on any failure -- caller should keep
  /// whatever background was already active if this returns null.
  static Future<String?> artFor({
    required int surahNum,
    required int ayahNum,
    required String ayahArabic,
    int seedOffset = 0,
  }) async {
    final cached = await _fileFor(surahNum, ayahNum, seedOffset);
    if (await cached.exists()) return cached.path;

    final prompt = _buildPrompt(ayahArabic);
    // Deterministic seed from surah:ayah (+ offset) -- same ayah always
    // reproduces the same art; a regenerate tap bumps the offset for a
    // genuinely different result.
    final seed = (surahNum * 1000 + ayahNum) * 97 + seedOffset;
    final url = Uri.parse('$_base${Uri.encodeComponent(prompt)}'
        '?width=1080&height=1920&seed=$seed&nologo=true&model=flux');

    try {
      final res = await http.get(url).timeout(const Duration(seconds: 45));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
      await cached.writeAsBytes(res.bodyBytes);
      return cached.path;
    } catch (_) {
      return null;
    }
  }

  // PATCH_S51_AI_ART_DELETE: removes the base cached image AND every
  // regenerate-bumped seed variant (_v1, _v2, ...) for this ayah, so
  // "delete" actually clears the disk cache instead of only detaching
  // the currently-displayed path. Silently ignores files already gone.
  static Future<void> deleteCached(int surahNum, int ayahNum) async {
    final dir = await _cacheDir();
    if (!await dir.exists()) return;
    final prefix = '${surahNum}_$ayahNum';
    await for (final entry in dir.list()) {
      if (entry is! File) continue;
      final name = entry.uri.pathSegments.last;
      if (name == '$prefix.png' || name.startsWith('${prefix}_v')) {
        try {
          await entry.delete();
        } catch (_) {
          // best-effort; a locked/already-deleted file shouldn't block the rest
        }
      }
    }
  }
}
