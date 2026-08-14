// PATCH_S123_TAFSIR: per-ayah explanation (تفسير) for every ayah in the
// mushaf, from several classical and modern works rather than one fixed
// opinion.
//
// The corpus is NOT bundled: all editions together are hundreds of
// megabytes, and the APK already carries the Whisper model download and the
// full Quran text. Instead each ayah is fetched once, on demand, and cached
// as a plain file under the app's documents directory — so a surah you have
// read once is fully readable offline afterwards, and a re-open costs no
// network at all.
//
// Source: the spa5k/tafsir_api dataset (per-ayah JSON, one file per ayah).
// jsDelivr is tried first because it is a real CDN; raw.githubusercontent.com
// is the fallback for networks where jsDelivr is blocked (the same class of
// problem that forced the Whisper model off huggingface.co — see
// whisper_service.dart).
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// One selectable tafsir book.
class TafsirEdition {
  /// Dataset slug — also the on-disk cache folder name.
  final String slug;

  /// Title in Arabic, as it is known.
  final String nameAr;

  /// Title in English/Latin script.
  final String nameEn;

  /// Language the tafsir text itself is written in ('ar', 'en', …).
  final String textLang;

  /// One line on what this book is, so the picker is a real choice and not
  /// a list of unfamiliar names.
  final String noteAr;
  final String noteEn;

  const TafsirEdition({
    required this.slug,
    required this.nameAr,
    required this.nameEn,
    required this.textLang,
    required this.noteAr,
    required this.noteEn,
  });
}

/// Curated shortlist — the widely-trusted works, not the dataset's full
/// 120-edition dump, which would be a wall of unfamiliar names.
const List<TafsirEdition> kTafsirEditions = [
  TafsirEdition(
    slug: 'ar-tafsir-muyassar',
    nameAr: 'التفسير الميسّر',
    nameEn: 'Al-Muyassar',
    textLang: 'ar',
    noteAr: 'شرح موجز بلغة سهلة — الأنسب للقراءة اليومية.',
    noteEn: 'A short, plain-language explanation — best for everyday reading.',
  ),
  TafsirEdition(
    slug: 'ar-tafsir-al-mukhtasar',
    nameAr: 'المختصر في التفسير',
    nameEn: 'Al-Mukhtasar',
    textLang: 'ar',
    noteAr: 'مختصر معاصر من مركز تفسير للدراسات القرآنية.',
    noteEn: 'A modern abridged tafsir from the Tafsir Center.',
  ),
  TafsirEdition(
    slug: 'ar-tafsir-ibn-kathir',
    nameAr: 'تفسير ابن كثير',
    nameEn: 'Ibn Kathir',
    textLang: 'ar',
    noteAr: 'التفسير بالمأثور — أشهر التفاسير وأوسعها انتشارًا.',
    noteEn: 'The classic narration-based tafsir, the most widely read of all.',
  ),
  TafsirEdition(
    slug: 'ar-tafseer-al-saddi',
    nameAr: 'تفسير السعدي',
    nameEn: 'As-Sa\'di',
    textLang: 'ar',
    noteAr: 'واضح ومترابط، يركّز على المعنى الإجمالي والفوائد.',
    noteEn: 'Clear and connected, focused on overall meaning and lessons.',
  ),
  TafsirEdition(
    slug: 'ar-tafseer-al-qurtubi',
    nameAr: 'تفسير القرطبي',
    nameEn: 'Al-Qurtubi',
    textLang: 'ar',
    noteAr: 'موسوعي، يعنى بالأحكام واللغة.',
    noteEn: 'Encyclopaedic, strong on rulings and language.',
  ),
  TafsirEdition(
    slug: 'ar-tafsir-al-tabari',
    nameAr: 'تفسير الطبري',
    nameEn: 'At-Tabari',
    textLang: 'ar',
    noteAr: 'أقدم التفاسير الجامعة، وأصل كثير مما بعده.',
    noteEn: 'The earliest comprehensive tafsir, the root of much that followed.',
  ),
  TafsirEdition(
    slug: 'ar-tafsir-al-baghawi',
    nameAr: 'تفسير البغوي',
    nameEn: 'Al-Baghawi',
    textLang: 'ar',
    noteAr: 'متوسط الطول، جامع بين الأثر والدراية.',
    noteEn: 'Mid-length, balancing narration and reasoning.',
  ),
  TafsirEdition(
    slug: 'ar-tafsir-al-jalalayn',
    nameAr: 'تفسير الجلالين',
    nameEn: 'Al-Jalalayn',
    textLang: 'ar',
    noteAr: 'مختصر جدًا، كلمة بكلمة تقريبًا.',
    noteEn: 'Extremely brief, almost word-by-word.',
  ),
  TafsirEdition(
    slug: 'en-tafsir-al-mukhtasar',
    nameAr: 'المختصر (بالإنجليزية)',
    nameEn: 'Al-Mukhtasar (English)',
    textLang: 'en',
    noteAr: 'الترجمة الإنجليزية للمختصر في التفسير.',
    noteEn: 'The English rendering of the abridged tafsir.',
  ),
  TafsirEdition(
    slug: 'en-tafisr-ibn-kathir',
    nameAr: 'ابن كثير (بالإنجليزية)',
    nameEn: 'Ibn Kathir (English)',
    textLang: 'en',
    noteAr: 'ترجمة إنجليزية لتفسير ابن كثير.',
    noteEn: 'The English translation of Ibn Kathir.',
  ),
  TafsirEdition(
    slug: 'en-tafsir-maarif-ul-quran',
    nameAr: 'معارف القرآن (بالإنجليزية)',
    nameEn: 'Maarif-ul-Quran (English)',
    textLang: 'en',
    noteAr: 'تفسير معاصر مطوّل، للمفتي محمد شفيع.',
    noteEn: 'A detailed modern tafsir by Mufti Muhammad Shafi.',
  ),
  TafsirEdition(
    slug: 'ur-tafseer-ibn-e-kaseer',
    nameAr: 'ابن كثير (بالأردية)',
    nameEn: 'Ibn Kathir (Urdu)',
    textLang: 'ur',
    noteAr: 'ترجمة أردية لتفسير ابن كثير.',
    noteEn: 'The Urdu translation of Ibn Kathir.',
  ),
  TafsirEdition(
    slug: 'indonesian-mokhtasar',
    nameAr: 'المختصر (بالإندونيسية)',
    nameEn: 'Al-Mukhtasar (Indonesian)',
    textLang: 'id',
    noteAr: 'الترجمة الإندونيسية للمختصر في التفسير.',
    noteEn: 'The Indonesian rendering of the abridged tafsir.',
  ),
  TafsirEdition(
    slug: 'french-mokhtasar',
    nameAr: 'المختصر (بالفرنسية)',
    nameEn: 'Al-Mukhtasar (French)',
    textLang: 'fr',
    noteAr: 'الترجمة الفرنسية للمختصر في التفسير.',
    noteEn: 'The French rendering of the abridged tafsir.',
  ),
];

TafsirEdition editionBySlug(String slug) => kTafsirEditions.firstWhere(
      (e) => e.slug == slug,
      orElse: () => kTafsirEditions.first,
    );

/// Thrown when an ayah's tafsir genuinely can't be produced (offline and
/// not cached, or the edition has no entry for that ayah).
class TafsirException implements Exception {
  final String messageAr;
  final String messageEn;
  TafsirException(this.messageAr, this.messageEn);
  @override
  String toString() => messageAr;
}

class TafsirResult {
  final String text;

  /// True when this came off the device instead of the network — surfaced in
  /// the UI so the user knows re-reading is free.
  final bool fromCache;
  const TafsirResult(this.text, this.fromCache);
}

class TafsirService {
  static const _cdnBase = 'https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir';
  static const _rawBase =
      'https://raw.githubusercontent.com/spa5k/tafsir_api/main/tafsir';

  /// Small in-memory cache so paging back and forth over the same few ayat
  /// doesn't even touch the filesystem.
  static final Map<String, String> _memory = {};
  static const _memoryMax = 400;

  static Directory? _cacheRoot;

  static Future<Directory> _root() async {
    final cached = _cacheRoot;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/tafsir');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cacheRoot = dir;
    return dir;
  }

  static String _key(String slug, int surah, int ayah) => '$slug/$surah/$ayah';

  static void _remember(String key, String text) {
    if (_memory.length >= _memoryMax) {
      // Cheap eviction: drop the oldest inserted key. A strict LRU would need
      // per-hit bookkeeping for no real benefit at this size.
      _memory.remove(_memory.keys.first);
    }
    _memory[key] = text;
  }

  /// True when this ayah's tafsir is already on the device (memory or disk),
  /// i.e. readable with no network at all.
  static Future<bool> isCached(String slug, int surah, int ayah) async {
    if (_memory.containsKey(_key(slug, surah, ayah))) return true;
    try {
      final root = await _root();
      return File('${root.path}/$slug/${surah}_$ayah.txt').exists();
    } catch (_) {
      return false;
    }
  }

  /// Tafsir text for one ayah. Returns from memory, then disk, then network
  /// (CDN, then raw GitHub). Throws [TafsirException] when none of those can
  /// produce it.
  static Future<TafsirResult> fetch({
    required String slug,
    required int surah,
    required int ayah,
  }) async {
    final key = _key(slug, surah, ayah);
    final hot = _memory[key];
    if (hot != null) return TafsirResult(hot, true);

    File? cacheFile;
    try {
      final root = await _root();
      cacheFile = File('${root.path}/$slug/${surah}_$ayah.txt');
      if (await cacheFile.exists()) {
        final text = await cacheFile.readAsString();
        if (text.trim().isNotEmpty) {
          _remember(key, text);
          return TafsirResult(text, true);
        }
      }
    } catch (_) {
      cacheFile = null; // caching is best-effort, never fatal
    }

    Object? lastError;
    for (final base in const [_cdnBase, _rawBase]) {
      try {
        final res = await http
            .get(Uri.parse('$base/$slug/$surah/$ayah.json'))
            .timeout(const Duration(seconds: 20));
        if (res.statusCode != 200) {
          lastError = 'HTTP ${res.statusCode}';
          continue;
        }
        final decoded = jsonDecode(utf8.decode(res.bodyBytes));
        final text = (decoded is Map ? decoded['text'] : null) as String?;
        final clean = _tidy(text ?? '');
        if (clean.isEmpty) {
          lastError = 'empty';
          continue;
        }
        _remember(key, clean);
        if (cacheFile != null) {
          // Fire-and-forget: a failed write just means we fetch again later.
          unawaitedWrite(cacheFile, clean);
        }
        return TafsirResult(clean, false);
      } catch (e) {
        lastError = e;
      }
    }
    throw TafsirException(
      'تعذّر تحميل التفسير (${lastError ?? 'خطأ غير معروف'}) — تحقّق من الاتصال بالإنترنت.',
      'Could not load the tafsir (${lastError ?? 'unknown error'}) — check your connection.',
    );
  }

  /// Writes the cache entry without making callers wait on the filesystem.
  static void unawaitedWrite(File file, String text) {
    () async {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(text, flush: false);
      } catch (_) {
        // ignored on purpose — see the comment at the call site
      }
    }();
  }

  /// The dataset carries a little HTML (mostly <br> and stray tags) inside
  /// some editions; strip it so the reader renders text, not markup.
  static String _tidy(String raw) {
    var t = raw;
    t = t.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    t = t.replaceAll(RegExp(r'</?p[^>]*>', caseSensitive: false), '\n');
    t = t.replaceAll(RegExp(r'<[^>]+>'), '');
    t = t.replaceAll('&nbsp;', ' ');
    t = t.replaceAll('&amp;', '&');
    t = t.replaceAll('&quot;', '"');
    t = t.replaceAll(RegExp(r'[ \t]+'), ' ');
    t = t.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  /// Total bytes the tafsir cache currently occupies, for the settings
  /// screen's "clear cache" row.
  static Future<int> cacheSizeBytes() async {
    try {
      final root = await _root();
      var total = 0;
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is File) total += await e.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearCache() async {
    _memory.clear();
    try {
      final root = await _root();
      if (await root.exists()) await root.delete(recursive: true);
      _cacheRoot = null;
    } catch (_) {
      // nothing to do — the cache is disposable by definition
    }
  }
}
