// Real (non-simulated) Arabic ayah matcher — ported from the browser
// version's matchAyahFromText(): normalization, IDF-weighted token overlap
// for candidate selection, then partial (substring-aware) edit distance +
// bigram overlap + phonetic-fold overlap as a blended score on the top
// candidates. See docs/ayat_studio225.html for the original JS + the
// reasoning comments behind each weight/threshold.
//
// One improvement beyond the HTML version: a coverage-based boost (see
// _overlapScores) so a short ASR window from the middle of a very long ayah
// (e.g. ayat ad-dayn, البقرة 282) can still match — plain weighted Jaccard
// structurally caps such fragments near ~0.1. Regression harness:
// `dart run tool/matcher_test.dart`.

import 'dart:math';

class Ayah {
  final int surahNum;
  final String surah;
  final int num;
  final String ar;
  final String en;
  Ayah({
    required this.surahNum,
    required this.surah,
    required this.num,
    required this.ar,
    required this.en,
  });
}

class AyahMatch {
  final Ayah ayah;
  final double confidence;
  AyahMatch(this.ayah, this.confidence);
}

class _CacheEntry {
  final Ayah ayah;
  final String norm;
  final List<String> tokens;
  final Set<String> tokenSet;
  final Set<String> bigramSet;
  final Set<String> phoneticSet;
  _CacheEntry(this.ayah, this.norm, this.tokens, this.tokenSet, this.bigramSet, this.phoneticSet);
}

const int candidatePoolSize = 20;

const Map<String, String> _phoneticFold = {
  'ث': 's', 'س': 's', 'ص': 's',
  'ظ': 'z', 'ض': 'z', 'ذ': 'z', 'ز': 'z',
  'ق': 'k', 'ك': 'k',
  'ع': 'a', 'ا': 'a',
  'غ': 'gh', 'خ': 'gh',
};

// PATCH_S35_SMARTER_DETECTION: precomputed features of one ASR input, shared
// by match / matchTop / matchAmong so they all score identically.
class _InputFeatures {
  final String norm;
  final List<String> tokens;
  final Set<String> bigrams;
  final Set<String> phonetic;
  _InputFeatures(this.norm, this.tokens, this.bigrams, this.phonetic);
}

class AyahMatcher {
  final List<Ayah> ayaat;
  final List<_CacheEntry> _cache = [];
  final Map<Ayah, _CacheEntry> _entryByAyah = {}; // PATCH_S35_SMARTER_DETECTION
  final Map<String, double> _idf = {};
  double _corpusMaxIdf = 1;

  AyahMatcher(this.ayaat) {
    _rebuildCache();
  }

  String normalize(String text) {
    var t = text;
    t = t.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), ''); // tashkeel
    t = t.replaceAll('\u0640', ''); // tatweel
    t = t.replaceAll(RegExp(r'[إأآاٱ]'), 'ا');
    t = t.replaceAll('ى', 'ي');
    t = t.replaceAll('ة', 'ه');
    t = t.replaceAll('ؤ', 'و');
    t = t.replaceAll('ئ', 'ي');
    t = t.replaceAll(RegExp(r'[^\u0600-\u06FF\s]'), '');
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  String _phoneticFoldToken(String token) {
    final buf = StringBuffer();
    for (final ch in token.split('')) {
      buf.write(_phoneticFold[ch] ?? ch);
    }
    return buf.toString();
  }

  Set<String> _bigramsOf(List<String> tokens) {
    final set = <String>{};
    for (var i = 0; i < tokens.length - 1; i++) {
      set.add('${tokens[i]}_${tokens[i + 1]}');
    }
    return set;
  }

  void _rebuildCache() {
    _cache.clear();
    _entryByAyah.clear(); // PATCH_S35_SMARTER_DETECTION
    final df = <String, int>{};
    for (final a in ayaat) {
      final norm = normalize(a.ar);
      final tokens = norm.split(' ').where((t) => t.isNotEmpty).toList();
      final tokenSet = tokens.toSet();
      final bigramSet = _bigramsOf(tokens);
      final phoneticSet = tokens.map(_phoneticFoldToken).toSet();
      final entry =
          _CacheEntry(a, norm, tokens, tokenSet, bigramSet, phoneticSet);
      _cache.add(entry);
      _entryByAyah[a] = entry; // PATCH_S35_SMARTER_DETECTION
      for (final t in tokenSet) {
        df[t] = (df[t] ?? 0) + 1;
      }
    }
    final n = _cache.isEmpty ? 1 : _cache.length;
    _idf.clear();
    _corpusMaxIdf = 1;
    df.forEach((token, count) {
      final w = log((n + 1) / (count + 1)) + 1;
      _idf[token] = w;
      if (w > _corpusMaxIdf) _corpusMaxIdf = w;
    });
  }

  double _idfOf(String token) => _idf[token] ?? _corpusMaxIdf;

  // A token rare enough (document frequency ≲ 15 across 6,236 ayat) to be
  // real evidence of a specific ayah on its own — used to gate the
  // fragment-of-a-long-ayah coverage boost below.
  static const double _distinctiveIdf = 6.0;

  /// Returns (jaccard, boosted) where `boosted` additionally considers
  /// input-coverage for the fragment-of-a-long-ayah case.
  ///
  /// Plain weighted Jaccard divides by the union of BOTH token sets, which
  /// structurally punishes long ayat: a clean 10-word ASR window from the
  /// middle of ayat ad-dayn (البقرة 282, ~130 words) can never score above
  /// ~0.1 even when every word matches. For that case we also measure
  /// *coverage* — how much of the INPUT's idf mass the ayah contains — but
  /// only when the fragment is substantial (4+ tokens), the ayah really is
  /// much longer, and at least one matched token is rare enough to be real
  /// evidence (otherwise a noise window of common words like
  /// "يا أيها الذين آمنوا" would suddenly match everything).
  (double, double) _overlapScores(
      List<String> aTokens, Set<String> bTokenSet, int bTokenCount) {
    if (aTokens.isEmpty || bTokenSet.isEmpty) return (0, 0);
    final seen = <String>{};
    double matchWeight = 0, unionWeight = 0, inputWeight = 0;
    var matchedDistinctive = false;
    for (final t in aTokens) {
      if (seen.contains(t)) continue;
      seen.add(t);
      final w = _idfOf(t);
      unionWeight += w;
      inputWeight += w;
      if (bTokenSet.contains(t)) {
        matchWeight += w;
        if (w >= _distinctiveIdf) matchedDistinctive = true;
      }
    }
    for (final t in bTokenSet) {
      if (!seen.contains(t)) unionWeight += _idfOf(t);
    }
    final jaccard = unionWeight > 0 ? matchWeight / unionWeight : 0.0;
    var boosted = jaccard;
    if (matchedDistinctive &&
        seen.length >= 4 &&
        bTokenCount > seen.length * 2 &&
        inputWeight > 0) {
      final coverage = matchWeight / inputWeight;
      boosted = max(jaccard, coverage * 0.85);
    }
    return (jaccard, boosted);
  }

  double _bigramOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    var inter = 0;
    for (final bg in a) {
      if (b.contains(bg)) inter++;
    }
    final union = a.length + b.length - inter;
    return union > 0 ? inter / union : 0;
  }

  // Substring-aware edit distance: min cost of aligning the shorter string
  // anywhere inside the longer one (free skip before/after) — see the JS
  // version's comment for why plain Levenshtein unfairly punishes a short
  // ASR fragment of a long ayah.
  int _partialEditDistance(String shortStr, String longStr) {
    final m = shortStr.length, n = longStr.length;
    if (m == 0) return 0;
    if (n == 0) return m;
    var prev = List<int>.filled(n + 1, 0);
    for (var i = 1; i <= m; i++) {
      final cur = List<int>.filled(n + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = shortStr[i - 1] == longStr[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce(min);
      }
      prev = cur;
    }
    var minEnd = prev[n];
    for (var j = 0; j <= n; j++) {
      if (prev[j] < minEnd) minEnd = prev[j];
    }
    return minEnd;
  }

  bool _looksLikeHallucination(List<String> tokens) {
    if (tokens.length < 3) return false;
    final counts = <String, int>{};
    for (final t in tokens) {
      counts[t] = (counts[t] ?? 0) + 1;
    }
    final maxCount = counts.values.fold<int>(0, max);
    return maxCount / tokens.length >= 0.6;
  }

  // PATCH_S35_SMARTER_DETECTION: shared input featurization + gates for all
  // matching entry points. Returns null when the input is unmatchable
  // (empty, single word, or a Whisper hallucination loop).
  _InputFeatures? _featuresOf(String rawText) {
    final norm = normalize(rawText);
    if (norm.isEmpty) return null;
    final inTokens = norm.split(' ').where((t) => t.isNotEmpty).toList();
    if (inTokens.length < 2) return null;
    if (_looksLikeHallucination(inTokens)) return null;
    if (_cache.length != ayaat.length) _rebuildCache();
    return _InputFeatures(norm, inTokens, _bigramsOf(inTokens),
        inTokens.map(_phoneticFoldToken).toSet());
  }

  // The blended per-candidate score used identically by match / matchTop /
  // matchAmong (formula unchanged from the original match()).
  double _blendScore(_CacheEntry entry, _InputFeatures f, double overlap) {
    final shortStr = f.norm.length <= entry.norm.length ? f.norm : entry.norm;
    final longStr = f.norm.length <= entry.norm.length ? entry.norm : f.norm;
    final dist = _partialEditDistance(shortStr, longStr);
    final distScore = 1 - dist / max(shortStr.length, 1);
    final bigramScore = _bigramOverlap(f.bigrams, entry.bigramSet);
    var phoneticInter = 0;
    for (final t in f.phonetic) {
      if (entry.phoneticSet.contains(t)) phoneticInter++;
    }
    final phoneticUnion =
        f.phonetic.length + entry.phoneticSet.length - phoneticInter;
    final phoneticScore =
        phoneticUnion > 0 ? phoneticInter / phoneticUnion : 0.0;
    return overlap * 0.5 +
        max(0.0, distScore) * 0.3 +
        bigramScore * 0.1 +
        phoneticScore * 0.1;
  }

  /// Returns the best match, or null if nothing clears [minConfidence].
  AyahMatch? match(String rawText, {double minConfidence = 0.35}) {
    final top = matchTop(rawText, k: 1, minConfidence: minConfidence);
    return top.isEmpty ? null : top.first;
  }

  /// PATCH_S35_SMARTER_DETECTION: the top [k] matches above [minConfidence],
  /// best first — lets the UI offer "did you mean…?" choices instead of
  /// silently committing to a borderline winner.
  List<AyahMatch> matchTop(String rawText,
      {int k = 3, double minConfidence = 0.2}) {
    final f = _featuresOf(rawText);
    if (f == null) return const [];

    final candidates = <MapEntry<_CacheEntry, double>>[];
    for (final entry in _cache) {
      final (_, overlap) =
          _overlapScores(f.tokens, entry.tokenSet, entry.tokens.length);
      if (overlap <= 0) continue;
      candidates.add(MapEntry(entry, overlap));
    }
    candidates.sort((a, b) => b.value.compareTo(a.value));
    final pool = candidates.take(candidatePoolSize);

    final scored = <AyahMatch>[];
    for (final c in pool) {
      final score = _blendScore(c.key, f, c.value);
      if (score >= minConfidence) {
        scored.add(AyahMatch(c.key.ayah, score.clamp(0, 1)));
      }
    }
    scored.sort((a, b) => b.confidence.compareTo(a.confidence));
    return scored.take(k).toList();
  }

  /// PATCH_S35_SMARTER_DETECTION: scores ONLY the given [candidates] (same
  /// blended formula, no candidate-pool pruning) with a caller-chosen
  /// relaxed threshold. Used by the timeline builder to test the ayat we
  /// EXPECT next during a recitation — the current ayah continuing or the
  /// following ones in mushaf order — where the sequential prior justifies
  /// accepting a weaker acoustic score than a blind corpus-wide search.
  AyahMatch? matchAmong(String rawText, Iterable<Ayah> candidates,
      {double minConfidence = 0.22}) {
    final f = _featuresOf(rawText);
    if (f == null) return null;
    AyahMatch? best;
    for (final a in candidates) {
      final entry = _entryByAyah[a];
      if (entry == null) continue;
      final (_, overlap) =
          _overlapScores(f.tokens, entry.tokenSet, entry.tokens.length);
      final score = _blendScore(entry, f, overlap);
      if (score >= minConfidence &&
          (best == null || score > best.confidence)) {
        best = AyahMatch(entry.ayah, score.clamp(0, 1));
      }
    }
    return best;
  }
}
