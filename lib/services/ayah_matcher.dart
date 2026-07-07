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

  /// Position of [ayah] in the corpus list — lets callers reason about
  /// mushaf order (e.g. the auto-sync sequential prior).
  final int index;
  AyahMatch(this.ayah, this.confidence, this.index);
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

class AyahMatcher {
  final List<Ayah> ayaat;
  final List<_CacheEntry> _cache = [];
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
    final df = <String, int>{};
    for (final a in ayaat) {
      final norm = normalize(a.ar);
      final tokens = norm.split(' ').where((t) => t.isNotEmpty).toList();
      final tokenSet = tokens.toSet();
      final bigramSet = _bigramsOf(tokens);
      final phoneticSet = tokens.map(_phoneticFoldToken).toSet();
      _cache.add(_CacheEntry(a, norm, tokens, tokenSet, bigramSet, phoneticSet));
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

  /// Returns the best match, or null if nothing clears [minConfidence].
  ///
  /// [priorIndex]: corpus index of the ayah heard in the previous window.
  /// Recitation follows mushaf order, so the same ayah continuing and the
  /// next one or two ayat get a score bonus. This is what lets auto-sync
  /// follow a recitation ayah-by-ayah instead of latching onto one ayah:
  /// the following ayah often shares little vocabulary with a noisy 6s
  /// window and would otherwise lose to word-overlap noise from anywhere
  /// in the 6,236-ayah corpus.
  AyahMatch? match(String rawText,
      {double minConfidence = 0.35, int? priorIndex}) {
    final norm = normalize(rawText);
    if (norm.isEmpty) return null;
    final inTokens = norm.split(' ').where((t) => t.isNotEmpty).toList();
    if (inTokens.length < 2) return null;
    if (_looksLikeHallucination(inTokens)) return null;
    if (_cache.length != ayaat.length) _rebuildCache();

    final inBigrams = _bigramsOf(inTokens);
    final inPhonetic = inTokens.map(_phoneticFoldToken).toSet();

    double priorBoostFor(int index) {
      if (priorIndex == null) return 0;
      if (index == priorIndex) return 0.06; // same ayah still being recited
      if (index == priorIndex + 1) return 0.15; // the expected next ayah
      if (index == priorIndex + 2) return 0.08; // one window skipped an ayah
      return 0;
    }

    // (index, raw overlap) — the prior only influences pool *selection* here
    // (so the expected-next ayah always gets a stage-2 look) and is added
    // once to the final blended score below.
    final candidates = <(int, double)>[];
    for (var i = 0; i < _cache.length; i++) {
      final entry = _cache[i];
      final (_, overlap) =
          _overlapScores(inTokens, entry.tokenSet, entry.tokens.length);
      if (overlap <= 0 && priorBoostFor(i) <= 0) continue;
      candidates.add((i, overlap));
    }
    candidates.sort((a, b) => (b.$2 + priorBoostFor(b.$1))
        .compareTo(a.$2 + priorBoostFor(a.$1)));
    final pool = candidates.take(candidatePoolSize).toList();
    if (pool.isEmpty) return null;

    Ayah? best;
    var bestScore = -1.0;
    var bestIndex = -1;
    for (final (idx, overlap) in pool) {
      final entry = _cache[idx];
      final shortStr = norm.length <= entry.norm.length ? norm : entry.norm;
      final longStr = norm.length <= entry.norm.length ? entry.norm : norm;
      final dist = _partialEditDistance(shortStr, longStr);
      final distScore = 1 - dist / max(shortStr.length, 1);
      final bigramScore = _bigramOverlap(inBigrams, entry.bigramSet);
      var phoneticInter = 0;
      for (final t in inPhonetic) {
        if (entry.phoneticSet.contains(t)) phoneticInter++;
      }
      final phoneticUnion = inPhonetic.length + entry.phoneticSet.length - phoneticInter;
      final phoneticScore = phoneticUnion > 0 ? phoneticInter / phoneticUnion : 0.0;
      final score = overlap * 0.5 +
          max(0.0, distScore) * 0.3 +
          bigramScore * 0.1 +
          phoneticScore * 0.1 +
          priorBoostFor(idx);
      if (score > bestScore) {
        bestScore = score;
        best = entry.ayah;
        bestIndex = idx;
      }
    }
    if (best == null || bestScore < minConfidence) return null;
    return AyahMatch(best, bestScore.clamp(0, 1), bestIndex);
  }
}
