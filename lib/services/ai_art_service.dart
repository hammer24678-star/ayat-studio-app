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

// PATCH_S80_POLLINATIONS_KEYLESS_FLUX: gen.pollinations.ai/image/ is the
// newer unified API surface and is what actually enforces the key
// requirement S69/S69b hit. image.pollinations.ai/prompt/ is the original
// endpoint and stays free and keyless -- no signup, no billing. apiKey is
// kept as an OPTIONAL field: if the user later adds a personal key (e.g.
// for higher limits or a premium model), it's still sent, but an empty key
// is the normal, fully-supported path now, not an error case.
//
// PATCH_S84_AI_ART_MODEL_CHAIN: one hardcoded model was fragile -- providers
// add better models and retire/gate old ones without notice, which is
// exactly how the art "stopped working". Generation now walks a
// quality-ordered chain of free models and uses the first one that returns
// a real image (validated by content-type + size, since these endpoints can
// answer an error as HTTP 200 with an HTML body). The winning model is
// remembered for the session so every later ayah skips the dead ones, and
// transient failures (429/5xx/timeouts) get one retry with a short backoff
// before moving down the chain.
class AiArtException implements Exception {
  final String message;
  AiArtException(this.message);
  @override
  String toString() => message;
}

class AiArtService {
  static const String _base = 'https://image.pollinations.ai/prompt/';
  static String apiKey = '';

  // PATCH_S84_AI_ART_MODEL_CHAIN: best first. `zimage` (Z-Image Turbo) beats
  // the flux-schnell tier on detail and prompt-following and is served on
  // the free tier; `flux` is the proven previous default; `turbo` (fast
  // SDXL) is the always-alive last resort. An unknown model name simply
  // falls through to the next entry, so this list is safe to extend.
  static const List<String> kModelChain = ['zimage', 'flux', 'turbo'];
  // The model that last produced a real image this session -- tried first
  // for every following ayah so dead models are only probed once.
  static String? _workingModel;

  static Future<Directory> _cacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    // PATCH_S84_AI_ART_MODEL_CHAIN: v2 -- cache is versioned so art cached
    // from the old single-model days regenerates on the better chain
    // instead of being served forever. The old dir is cleaned up once.
    Directory('${docs.path}/ai_art_cache')
        .delete(recursive: true)
        .ignore();
    final dir = Directory('${docs.path}/ai_art_cache_v2');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<File> _fileFor(int surahNum, int ayahNum, int seedOffset) async {
    final dir = await _cacheDir();
    final suffix = seedOffset == 0 ? '' : '_v$seedOffset';
    return File('${dir.path}/${surahNum}_$ayahNum$suffix.png');
  }

  /// Fixed house STYLE -- matches the glowing monochrome line-art reference
  /// frames (ayat_studio-22.html). Never surfaced as editable text.
  // PATCH_S94_SCENE_NOT_TEMPLATE: this used to also hard-code "starry
  // night sky" and "desert architecture silhouettes" as fixed elements of
  // EVERY prompt -- so every image looked the same regardless of what the
  // ayah was about, no matter what the scene description below said. Only
  // the visual STYLE belongs here; the setting comes from the scene itself.
  static const String _styleBase =
      'monochrome glowing line-art illustration, deep black background, '
      'thin luminous white outline strokes, high contrast, no color, '
      'digital line-art poster style, quiet reverent mood';

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

  // PATCH_S94_SCENE_NOT_TEMPLATE: was ayahArabic.contains(name) -- a
  // substring match anywhere in the ayah's text, including inside a
  // completely unrelated word. A false positive here doesn't just
  // mislabel something -- it throws away the whole scene prompt and
  // replaces it with the light-pillar template instead. Whole-word match
  // only (common attached prefixes و ف ب ل ك stripped first, since
  // "وموسى"/"لعيسى" etc. are legitimate attached forms of the name).
  static String? _matchedProphet(String ayahArabic) {
    final prefixes = RegExp(r'^[وفبلك]');
    for (final w in ayahArabic.split(RegExp(r'\s+'))) {
      final stripped = w.replaceFirst(prefixes, '');
      for (final entry in _prophetNames.entries) {
        if (w == entry.key || stripped == entry.key) return entry.value;
      }
    }
    return null;
  }

  static String _buildPrompt(String ayahArabic, String ayahEnglish) {
    final prophet = _matchedProphet(ayahArabic);
    if (prophet != null) {
      return '$_styleBase, a single tall pillar of soft glowing white light '
          'standing where a person would be, no body, no figure, no face at '
          'all, a circular medallion above the light pillar containing the '
          'Arabic calligraphy name "$prophet" written in elegant thuluth '
          'script, $_noFacesRule';
    }
    // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART: the old prompt said "scene
    // inspired by the theme of this Quranic ayah" and never said what that
    // theme actually was -- the model had nothing to draw a scene from.
    // Feed it the ayah's own English meaning as the scene description.
    // PATCH_S94_SCENE_NOT_TEMPLATE: and don't cap it at "one silhouette or
    // an empty landscape" -- let it actually draw what the scene contains:
    // multiple figures, objects, architecture, setting, whatever fits.
    final scene = ayahEnglish.trim().isEmpty
        ? 'this Quranic ayah'
        : ayahEnglish.trim();
    return '$_styleBase, illustrate this scene fully and specifically: '
        '$scene -- include whatever the scene actually contains (one or '
        'several figures, objects, architecture, setting), not simplified '
        'down to a lone empty landscape, $_noFacesRule';
  }

  /// Returns a local file path to the cached (or freshly generated) art for
  /// [surahNum]:[ayahNum], or null on any failure -- caller should keep
  /// whatever background was already active if this returns null.
  /// PATCH_S84_AI_ART_MODEL_CHAIN: walks [kModelChain] (working model first)
  /// until one returns a validated image.
  static Future<String?> artFor({
    required int surahNum,
    required int ayahNum,
    required String ayahArabic,
    // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART: optional so existing call
    // sites keep compiling; empty just falls back to the old vague prompt
    // instead of crashing -- but every call site below is updated to pass
    // the real translation.
    String ayahEnglish = '',
    int seedOffset = 0,
  }) async {
    final cached = await _fileFor(surahNum, ayahNum, seedOffset);
    if (await cached.exists()) return cached.path;

    final prompt = _buildPrompt(ayahArabic, ayahEnglish);
    // Deterministic seed from surah:ayah (+ offset) -- same ayah always
    // reproduces the same art; a regenerate tap bumps the offset for a
    // genuinely different result.
    final seed = (surahNum * 1000 + ayahNum) * 97 + seedOffset;
    // PATCH_S80_POLLINATIONS_KEYLESS_FLUX: key stays optional -- omit the
    // param entirely when empty rather than sending it blank.
    final keyParam = apiKey.trim().isEmpty
        ? ''
        : '&key=${Uri.encodeComponent(apiKey.trim())}';

    final models = [
      if (_workingModel != null) _workingModel!,
      ...kModelChain.where((m) => m != _workingModel),
    ];
    AiArtException? lastError;
    for (final model in models) {
      // private=true keeps generated Quranic art off the provider's public
      // feed; safe=true forces the strictest content filter tier.
      final url = Uri.parse('$_base${Uri.encodeComponent(prompt)}'
          '?width=1080&height=1920&seed=$seed&model=$model'
          '&nologo=true&private=true&safe=true$keyParam');
      // one retry per model for transient failures, with a short backoff
      for (var attempt = 0; attempt < 2; attempt++) {
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
        http.Response res;
        try {
          res = await http.get(url).timeout(const Duration(seconds: 40));
        } on Exception {
          lastError =
              AiArtException('تعذر الاتصال بخدمة توليد الفن -- تحقق من الإنترنت');
          continue;
        }
        if (res.statusCode == 401 && apiKey.trim().isNotEmpty) {
          // only reachable with a user-typed (invalid) key -- the keyless
          // path is never authenticated
          throw AiArtException(
              'المفتاح المُدخَل في الإعدادات غير صالح -- احذفه لاستخدام التوليد المجاني بدون مفتاح، أو تحقق منه في enter.pollinations.ai');
        }
        if (res.statusCode == 402 || res.statusCode == 429) {
          lastError = AiArtException(
              'تم تجاوز الحد المسموح مؤقتًا -- حاول مرة أخرى خلال دقيقة');
          continue; // retry, then next model
        }
        if (res.statusCode >= 500) {
          lastError =
              AiArtException('فشل توليد الفن (رمز الحالة: ${res.statusCode})');
          continue;
        }
        // A gated/renamed model can answer 200 with a tiny HTML/JSON error
        // body -- only a real image counts as success.
        final contentType = res.headers['content-type'] ?? '';
        final looksLikeImage = res.statusCode == 200 &&
            res.bodyBytes.length > 5000 &&
            (contentType.startsWith('image/') || contentType.isEmpty);
        if (!looksLikeImage) {
          lastError =
              AiArtException('فشل توليد الفن (رمز الحالة: ${res.statusCode})');
          break; // hard failure for this model -- try the next one
        }
        await cached.writeAsBytes(res.bodyBytes);
        _workingModel = model;
        return cached.path;
      }
    }
    throw lastError ??
        AiArtException('فشل توليد الفن -- حاول مرة أخرى لاحقًا');
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
