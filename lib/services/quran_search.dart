// PATCH_S123_AYAH_SEARCH: "type an ayah and find it". Runs entirely on the
// bundled corpus — no network, works on a plane.
//
// Three kinds of query are accepted without the user having to pick a mode:
//   • a reference — "2:255", "٢ ٢٥٥", "البقرة 255"
//   • a surah name — "الكهف", "Al-Kahf", "kahf"
//   • any run of ayah words — with or without tashkeel, any hamza spelling,
//     from anywhere inside the ayah
//
// The text path is a normalized substring scan over a prebuilt index. 6,236
// short strings is small enough that a linear scan is a fraction of a frame,
// and it beats a token index here because a user typing "الذين ءامنوا وعملوا"
// expects the words IN THAT ORDER, which a bag-of-words index would lose.
import '../data/mushaf_meta.dart';
import 'ayah_matcher.dart';

/// One hit, with enough context to render a result row without re-deriving
/// anything.
class AyahSearchResult {
  /// Index into the corpus list (0-based) — i.e. `ayaat[corpusIndex]`.
  final int corpusIndex;
  final Ayah ayah;

  /// Character offset of the match inside [Ayah.ar], or -1 for reference /
  /// surah-name hits where nothing inside the text matched.
  final int matchStart;
  final int matchLength;

  /// Lower is better. Used to rank exact-prefix hits above mid-ayah hits.
  final double rank;

  const AyahSearchResult({
    required this.corpusIndex,
    required this.ayah,
    required this.matchStart,
    required this.matchLength,
    required this.rank,
  });

  int get globalAyahId => corpusIndex + 1;
  int get page => pageOfAyahId(globalAyahId);
}

class QuranSearch {
  /// Normalized text of every ayah, parallel to the corpus list. Built once
  /// on first search (~6k small strings, a few ms) and reused after.
  static List<String>? _normIndex;

  /// Maps each normalized ayah's character offsets back to the original
  /// string's offsets, so a hit found in normalized space can be highlighted
  /// in the real, fully-vocalized text.
  static List<List<int>>? _offsetIndex;
  static int _indexedFor = -1;

  static void _ensureIndex(List<Ayah> ayaat) {
    if (_normIndex != null && _indexedFor == ayaat.length) return;
    final norm = <String>[];
    final offsets = <List<int>>[];
    for (final a in ayaat) {
      // normalizeArabicMapped keeps a source offset per surviving character,
      // which is what lets a hit found in normalized space be highlighted on
      // the real, fully-vocalized text.
      final (text, map) = normalizeArabicMapped(a.ar);
      norm.add(text);
      offsets.add(map);
    }
    _normIndex = norm;
    _offsetIndex = offsets;
    _indexedFor = ayaat.length;
  }

  /// Western digits for a string that may use Eastern Arabic-Indic ones.
  static String _westernDigits(String s) {
    const eastern = '٠١٢٣٤٥٦٧٨٩';
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final i = eastern.indexOf(ch);
      buf.write(i >= 0 ? '$i' : ch);
    }
    return buf.toString();
  }

  /// Parses "2:255", "2 255", "٢:٢٥٥" and returns the global ayah id, or -1.
  static int _parseReference(String query) {
    final q = _westernDigits(query).trim();
    final m = RegExp(r'^(\d{1,3})\s*[:\-/ ]\s*(\d{1,3})$').firstMatch(q);
    if (m == null) {
      // A bare surah number on its own opens that surah's first ayah.
      final single = RegExp(r'^(\d{1,3})$').firstMatch(q);
      if (single == null) return -1;
      final s = int.parse(single.group(1)!);
      return globalAyahId(s, 1);
    }
    return globalAyahId(int.parse(m.group(1)!), int.parse(m.group(2)!));
  }

  /// Surah numbers whose Arabic name, transliteration or English meaning
  /// matches [query]. Empty for a query that isn't a name.
  static List<int> matchingSurahs(String query, List<Ayah> ayaat) {
    final qNorm = normalizeArabic(query);
    final qLatin = query.trim().toLowerCase();
    if (qNorm.isEmpty && qLatin.isEmpty) return const [];
    final out = <int>[];
    // Arabic surah names come from the corpus itself (one per surah), so a
    // rename in the asset can never desync this.
    final arabicNames = <int, String>{};
    for (final a in ayaat) {
      arabicNames.putIfAbsent(a.surahNum, () => a.surah);
    }
    for (final m in kSurahMeta) {
      final ar = normalizeArabic(arabicNames[m.num] ?? '');
      final translit = m.transliteration.toLowerCase();
      // Transliterations carry hyphens/apostrophes ("Ali 'Imran", "An-Nas")
      // that nobody types — compare against a stripped form too.
      final translitBare = translit.replaceAll(RegExp(r"[^a-z]"), '');
      final qBare = qLatin.replaceAll(RegExp(r"[^a-z]"), '');
      final hit = (qNorm.isNotEmpty && ar.contains(qNorm)) ||
          (qLatin.length >= 2 && translit.contains(qLatin)) ||
          (qBare.length >= 2 && translitBare.contains(qBare)) ||
          (qLatin.length >= 3 && m.englishName.toLowerCase().contains(qLatin));
      if (hit) out.add(m.num);
    }
    return out;
  }

  /// Searches [ayaat] for [query]. Results are ranked: a reference hit
  /// first, then ayat whose text begins with the query, then the rest in
  /// mushaf order. Capped at [limit] so a one-letter query can't build a
  /// 6,000-row list.
  static List<AyahSearchResult> search(
    String query,
    List<Ayah> ayaat, {
    int limit = 80,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    _ensureIndex(ayaat);
    final norm = _normIndex!;
    final offsets = _offsetIndex!;

    final results = <AyahSearchResult>[];

    // 1. Direct reference.
    final refId = _parseReference(trimmed);
    if (refId > 0 && refId <= ayaat.length) {
      results.add(AyahSearchResult(
        corpusIndex: refId - 1,
        ayah: ayaat[refId - 1],
        matchStart: -1,
        matchLength: 0,
        rank: -1,
      ));
      return results;
    }

    // 2. Ayah text. Anything under two characters would match half the
    // mushaf, so the text scan needs a real fragment to work with.
    final q = normalizeArabic(trimmed);
    if (q.length >= 2) {
      for (var i = 0; i < norm.length && i < ayaat.length; i++) {
        final at = norm[i].indexOf(q);
        if (at < 0) continue;
        final map = offsets[i];
        final start = at < map.length ? map[at] : -1;
        final endIdx = at + q.length - 1;
        final end = endIdx < map.length ? map[endIdx] : -1;
        results.add(AyahSearchResult(
          corpusIndex: i,
          ayah: ayaat[i],
          matchStart: start,
          matchLength: (start >= 0 && end >= start) ? end - start + 1 : 0,
          // Word-boundary hits read as "the ayah starts like this" and are
          // what people usually mean; mid-word hits rank below them.
          rank: at == 0
              ? 0
              : (norm[i][at - 1] == ' ' ? 1 : 2) + at / 10000.0,
        ));
        if (results.length >= limit * 3) break;
      }
      results.sort((a, b) {
        final c = a.rank.compareTo(b.rank);
        return c != 0 ? c : a.corpusIndex.compareTo(b.corpusIndex);
      });
    }

    return results.length > limit ? results.sublist(0, limit) : results;
  }

  /// Drops the prebuilt index — only needed by tests that swap corpora.
  static void resetIndex() {
    _normIndex = null;
    _offsetIndex = null;
    _indexedFor = -1;
  }
}
