// PATCH_S123_MATCHER_ACCURACY: a measurable accuracy number for ayah
// detection, so "make the AI better" stops being a guess.
//
// tool/matcher_test.dart is a 13-case sanity harness — it says the matcher
// isn't broken, not how good it is. This runs the real matcher over hundreds
// of ayat sampled across the whole mushaf, feeding it text corrupted the way
// Whisper actually corrupts Arabic recitation, and reports top-1 accuracy per
// difficulty tier plus a false-positive rate on inputs that must NOT match.
//
// The corruption model is built from the failure classes already documented
// in this repo: tashkeel is always gone; consonants collapse along the
// phonetic pairs listed in ayah_matcher.dart's _phoneticFold; whole words
// drop out on fast/مجود recitation; and long ayat arrive as a window from
// somewhere in the middle rather than from the start.
//
// Usage:  dart run tool/matcher_bench.dart [samples]
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:ayat_studio_app/services/ayah_matcher.dart';

/// Consonant confusions Whisper makes on recited Arabic, in the direction it
/// tends to make them (heard → written).
const Map<String, List<String>> _confusions = {
  'ض': ['ظ', 'د'],
  'ظ': ['ض', 'ز'],
  'ذ': ['ز', 'د'],
  'ز': ['ذ'],
  'ث': ['س', 'ت'],
  'س': ['ص', 'ث'],
  'ص': ['س'],
  'ق': ['ك', 'غ'],
  'ك': ['ق'],
  'ه': ['ح'],
  'ح': ['ه', 'خ'],
  'ط': ['ت'],
  'ت': ['ط'],
  'غ': ['خ', 'ق'],
  'خ': ['غ', 'ح'],
  'ع': ['ا', 'ء'],
  'أ': ['ا'],
  'إ': ['ا'],
  'آ': ['ا'],
  'ة': ['ه'],
  'ى': ['ي'],
};

final _tashkeel = RegExp(r'[ً-ٰٟۖ-ۭـ]');

String _stripTashkeel(String s) => s.replaceAll(_tashkeel, '');

List<String> _words(String s) =>
    _stripTashkeel(s).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();

/// One difficulty tier of the corruption model.
class Tier {
  final String name;

  /// Probability each character is swapped for a confusable one.
  final double charErrorRate;

  /// Probability each word is dropped entirely.
  final double wordDropRate;

  /// When set, only this many consecutive words are kept (an ASR window from
  /// the middle of the ayah), if the ayah is long enough.
  final int? windowWords;
  const Tier(this.name, this.charErrorRate, this.wordDropRate,
      {this.windowWords});
}

const _tiers = [
  // What a clean recitation of a short ayah looks like coming out of Whisper.
  Tier('clean', 0.0, 0.0),
  // Ordinary conditions: a few consonants heard wrong.
  Tier('light noise', 0.04, 0.0),
  // Fast or heavily elongated recitation: consonants wrong AND words lost.
  Tier('heavy noise', 0.10, 0.08),
  // A 6-word analysis window landing mid-ayah, lightly corrupted — the
  // auto-sync path's normal input for anything longer than a few words.
  Tier('mid-ayah window', 0.04, 0.0, windowWords: 6),
  // The hardest realistic case: a short window that is also noisy.
  Tier('noisy window', 0.10, 0.05, windowWords: 6),
];

String _corrupt(String ayahText, Tier tier, Random rnd) {
  var words = _words(ayahText);
  final window = tier.windowWords;
  if (window != null && words.length > window + 2) {
    final start = rnd.nextInt(words.length - window);
    words = words.sublist(start, start + window);
  }
  if (tier.wordDropRate > 0 && words.length > 4) {
    words = [
      for (final w in words)
        if (rnd.nextDouble() >= tier.wordDropRate) w,
    ];
    if (words.length < 2) return '';
  }
  if (tier.charErrorRate > 0) {
    words = [
      for (final w in words)
        w.split('').map((ch) {
          final options = _confusions[ch];
          if (options == null) return ch;
          if (rnd.nextDouble() >= tier.charErrorRate) return ch;
          return options[rnd.nextInt(options.length)];
        }).join(),
    ];
  }
  return words.join(' ');
}

// Defaults mirror TimelineBuilder's shipped constants, so a plain run
// reproduces what the app actually does. They stay overridable from the
// command line (`dart run tool/matcher_bench.dart 200 <gate> <bonus>`) for
// re-tuning: `gate` is the confidence above which the sequential rescore is
// skipped (>1 means never skip, which is what ships), `bonus` is
// TimelineBuilder.contextPriorBonus. TimelineBuilder itself can't be
// imported here -- it pulls in Flutter through whisper_service.
double kGate = 1.01;
double kBonus = 0.12;

void main(List<String> args) {
  final sampleCount = args.isEmpty ? 300 : int.parse(args.first);
  if (args.length > 1) kGate = double.parse(args[1]);
  if (args.length > 2) kBonus = double.parse(args[2]);

  final raw = File('assets/quran/quran_full.json').readAsStringSync();
  final List<dynamic> data = jsonDecode(raw);
  final ayaat = <Ayah>[];
  var surahNum = 0;
  String? lastSurah;
  for (final e in data) {
    final surah = e['surah'] as String;
    if (surah != lastSurah) {
      surahNum++;
      lastSurah = surah;
    }
    ayaat.add(Ayah(
        surahNum: surahNum,
        surah: surah,
        num: e['num'] as int,
        ar: e['ar'] as String,
        en: (e['en'] ?? '') as String));
  }

  final sw = Stopwatch()..start();
  final matcher = AyahMatcher(ayaat);
  stdout.writeln('corpus ${ayaat.length} ayat · matcher built in '
      '${sw.elapsedMilliseconds}ms');
  stdout.writeln('sampling $sampleCount ayat per tier (seeded, reproducible)\n');

  // A fixed seed keeps every run comparable — this is a regression metric,
  // not a random spot check. Ayat under 3 words are excluded: no matcher can
  // or should confidently resolve "الرحمن الرحيم" on its own, and the
  // matcher deliberately refuses inputs that short.
  final eligible = [
    for (var i = 0; i < ayaat.length; i++)
      if (_words(ayaat[i].ar).length >= 4) i,
  ];

  var grandHit = 0, grandTotal = 0, duplicateResolved = 0;
  final rows = <String>[];
  final failures = <String>[];
  final latencies = <int>[];

  for (final tier in _tiers) {
    final rnd = Random(20260814);
    var hit = 0, total = 0, noMatch = 0;
    for (var n = 0; n < sampleCount; n++) {
      final idx = eligible[rnd.nextInt(eligible.length)];
      final truth = ayaat[idx];
      final input = _corrupt(truth.ar, tier, rnd);
      if (input.split(' ').length < 2) continue;
      total++;
      final t = Stopwatch()..start();
      final m = matcher.match(input, minConfidence: 0.30);
      latencies.add(t.elapsedMilliseconds);
      if (m == null) {
        noMatch++;
        if (failures.length < 12) {
          failures.add('[${tier.name}] NO MATCH  "$input"\n'
              '    truth: ${truth.surah}:${truth.num}');
        }
      } else if (m.ayah.surahNum == truth.surahNum && m.ayah.num == truth.num) {
        hit++;
      } else if (matcher
          .textIdenticalTo(truth)
          .any((a) => a.surahNum == m.ayah.surahNum && a.num == m.ayah.num)) {
        // The matched ayah is word-for-word the sampled one -- ar-Rahman's
        // refrain and friends. No text matcher can separate these, and the
        // app resolves them from reading order (AyahMatcher.resolveByOrder,
        // applied in TimelineBuilder), so scoring them as errors would be
        // measuring an impossible task rather than this component's job.
        hit++;
        duplicateResolved++;
      } else if (failures.length < 12) {
        failures.add('[${tier.name}] WRONG     "$input"\n'
            '    truth: ${truth.surah}:${truth.num}  got: '
            '${m.ayah.surah}:${m.ayah.num} (${(m.confidence * 100).round()}%)');
      }
    }
    grandHit += hit;
    grandTotal += total;
    final pct = total == 0 ? 0.0 : hit * 100 / total;
    rows.add('${tier.name.padRight(18)} ${pct.toStringAsFixed(1).padLeft(6)}%'
        '   (${hit}/$total, $noMatch refused)');
  }

  // ---- sequential pass: what the app actually runs -----------------------
  //
  // The tiers above score the matcher on ONE isolated fragment, with no idea
  // what came before it. That is not how auto-sync works: it walks a
  // recitation forward, so every window after the first has an anchor. This
  // replays that -- consecutive ayat, each arriving as a corrupted mid-ayah
  // window, resolved exactly the way TimelineBuilder resolves them
  // (corpus-wide match, duplicate settled by reading order, weak matches
  // rescored against the ayat the mushaf predicts next).
  const runLength = 5;
  const window = Tier('sequential window', 0.06, 0.04, windowWords: 6);
  final seqRnd = Random(20260814);
  var seqHit = 0, seqTotal = 0;
  var isolatedHit = 0;
  // Half the runs jump to an unrelated ayah partway through — someone
  // recording a montage, or auto-sync resuming after a gap. A sequential
  // prior that is too strong "sticks" to the old passage and never
  // recovers, so recovery after a jump is measured separately.
  var jumpHit = 0, jumpTotal = 0;
  for (var n = 0; n < sampleCount; n++) {
    var startIdx = eligible[seqRnd.nextInt(eligible.length)];
    final jumpsAt = n.isEven ? 2 : -1;
    Ayah? anchorAyah;
    for (var k = 0; k < runLength; k++) {
      if (k == jumpsAt) startIdx = eligible[seqRnd.nextInt(eligible.length)] - k;
      final idx = startIdx + k;
      if (idx < 0 || idx >= ayaat.length) break;
      final truth = ayaat[idx];
      if (_words(truth.ar).length < 4) continue;
      final input = _corrupt(truth.ar, window, seqRnd);
      if (input.split(' ').length < 3) continue;
      seqTotal++;

      var m = matcher.match(input, minConfidence: 0.30);
      if (m != null &&
          m.ayah.surahNum == truth.surahNum &&
          m.ayah.num == truth.num) {
        isolatedHit++;
      }
      if (m != null && matcher.isTextAmbiguous(m.ayah)) {
        m = AyahMatch(
            matcher.resolveByOrder(m.ayah, anchor: anchorAyah), m.confidence);
      }
      if (anchorAyah != null && (m == null || m.confidence < kGate)) {
        final i = matcher.positionOf(anchorAyah);
        final expected = i < 0
            ? <Ayah>[anchorAyah]
            : <Ayah>[
                if (i > 0) ayaat[i - 1],
                ...ayaat.sublist(i, min(ayaat.length, i + 4)),
              ];
        final ctx = matcher.matchAmong(input, expected, minConfidence: 0.22);
        if (ctx != null &&
            (m == null || ctx.confidence + kBonus >= m.confidence)) {
          m = ctx;
        }
      }
      final correct = m != null &&
          m.ayah.surahNum == truth.surahNum &&
          m.ayah.num == truth.num;
      if (correct) seqHit++;
      if (jumpsAt >= 0 && k >= jumpsAt) {
        jumpTotal++;
        if (correct) jumpHit++;
      }
      if (m != null) anchorAyah = m.ayah;
    }
  }

  // Inputs that must NOT produce a confident match. A detector that matches
  // everything scores 100% above and is useless in the app.
  const mustNotMatch = [
    'يا ايها الذين امنوا', // ambiguous opener, 100+ ayat
    'الله الله الله الله الله', // hallucination loop
    'قال قال قال قال', // hallucination loop
    'الحمد لله', // too common on its own
    'ترجمة نانسي قنقر', // Whisper's stock Arabic subtitle hallucination
    'اشترك في القناة',
    'مرحبا كيف حالك اليوم', // ordinary speech, not Quran
  ];
  var falsePositives = 0;
  for (final s in mustNotMatch) {
    final m = matcher.match(s, minConfidence: 0.30);
    if (m != null) {
      falsePositives++;
      failures.add('FALSE POSITIVE "$s" -> ${m.ayah.surah}:${m.ayah.num} '
          '(${(m.confidence * 100).round()}%)');
    }
  }

  latencies.sort();
  final p50 = latencies.isEmpty ? 0 : latencies[latencies.length ~/ 2];
  final p95 = latencies.isEmpty ? 0 : latencies[(latencies.length * 95) ~/ 100];

  stdout.writeln('tier                 top-1');
  stdout.writeln('-' * 52);
  for (final r in rows) {
    stdout.writeln(r);
  }
  stdout.writeln('-' * 52);
  final overall = grandTotal == 0 ? 0.0 : grandHit * 100 / grandTotal;
  stdout.writeln('OVERALL            ${overall.toStringAsFixed(1).padLeft(6)}%'
      '   ($grandHit/$grandTotal)');
  stdout.writeln('of which repeated  $duplicateResolved  (ayat whose text also '
      'appears elsewhere —\n                      unresolvable from audio, '
      'settled by reading order at scan time)');
  final seqPct = seqTotal == 0 ? 0.0 : seqHit * 100 / seqTotal;
  final isoPct = seqTotal == 0 ? 0.0 : isolatedHit * 100 / seqTotal;
  stdout.writeln('');
  stdout.writeln('sequential (as the app runs it, $runLength-ayah runs of '
      'noisy mid-ayah windows)');
  stdout.writeln('  no context     ${isoPct.toStringAsFixed(1).padLeft(6)}%'
      '   ($isolatedHit/$seqTotal)');
  stdout.writeln('  with context   ${seqPct.toStringAsFixed(1).padLeft(6)}%'
      '   ($seqHit/$seqTotal)');
  final jumpPct = jumpTotal == 0 ? 0.0 : jumpHit * 100 / jumpTotal;
  stdout.writeln('  after a jump   ${jumpPct.toStringAsFixed(1).padLeft(6)}%'
      '   ($jumpHit/$jumpTotal — guards against the prior sticking)');
  stdout.writeln('');
  stdout.writeln('false positives    $falsePositives/${mustNotMatch.length} '
      '(lower is better)');
  stdout.writeln('latency            p50 ${p50}ms · p95 ${p95}ms');

  if (failures.isNotEmpty) {
    stdout.writeln('\nsample failures:');
    for (final f in failures.take(14)) {
      stdout.writeln('  $f');
    }
  }

  // Non-zero exit when the detector regresses below where it shipped, so
  // this can gate a build rather than just print numbers.
  const overallFloor = 90.0;
  if (overall < overallFloor || falsePositives > 0) {
    stdout.writeln('\nFAIL: overall ${overall.toStringAsFixed(1)}% '
        '(floor ${overallFloor.toStringAsFixed(0)}%), '
        '$falsePositives false positives (max 0)');
    exit(1);
  }
  stdout.writeln('\nOK');
}
