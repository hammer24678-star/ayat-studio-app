// Sanity harness: runs the real AyahMatcher against the full bundled corpus
// with ASR-like inputs (fragments, misspellings, hallucination patterns).
import 'dart:convert';
import 'dart:io';
import 'package:ayat_studio_app/services/ayah_matcher.dart';

void main() {
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
  print('corpus: ${ayaat.length} ayat, ${surahNum} surahs');

  final sw = Stopwatch()..start();
  final matcher = AyahMatcher(ayaat);
  print('matcher built in ${sw.elapsedMilliseconds}ms');

  final cases = <String, String?>{
    // clean fragments (what Whisper typically emits, no tashkeel)
    'ان مع العسر يسرا': 'الشرح:6',
    'فباي الاء ربكما تكذبان': 'الرحمن',
    'قل هو الله احد': 'الإخلاص:1',
    'الحمد لله رب العالمين': 'الفاتحة:2',
    'ومن يتوكل على الله فهو حسبه': 'الطلاق:3',
    // ASR-style phonetic confusion (ق→ك, ذ→ز)
    'كل هو الله احد': 'الإخلاص:1',
    // partial window of a long ayah
    'يا ايها الذين امنوا اذا تداينتم بدين الى اجل مسمى': 'البقرة:282',
    // middle fragment of the longest ayah (coverage-boost path)
    'ولا يستطيع ان يمل هو فليملل وليه بالعدل واستشهدوا شهيدين من رجالكم': 'البقرة:282',
    // more fragments of long ayat
    'ولقد كرمنا بني ادم وحملناهم في البر والبحر': 'الإسراء:70',
    // ambiguous common opener alone must NOT confidently match
    'يا ايها الذين امنوا': null,
    // hallucination pattern must NOT match
    'الله الله الله الله الله': null,
    // single word must NOT match
    'الله': null,
  };

  var pass = 0, fail = 0;
  cases.forEach((input, expected) {
    final t = Stopwatch()..start();
    final m = matcher.match(input);
    final got = m == null ? null : '${m.ayah.surah}:${m.ayah.num}';
    final ok = expected == null ? got == null : (got != null && got.startsWith(expected));
    ok ? pass++ : fail++;
    print('${ok ? "PASS" : "FAIL"} [${t.elapsedMilliseconds}ms] "$input" -> '
        '$got (expected $expected)'
        '${m != null ? " conf=${(m.confidence * 100).round()}%" : ""}');
  });
  // --- sequential prior (auto-sync mushaf-order) checks ---
  // A short/ambiguous fragment that alone matches elsewhere or nothing
  // should resolve to the expected NEXT ayah when the prior points at the
  // previous one. الشرح:5 = "فإن مع العسر يسرا", الشرح:6 = "إن مع العسر يسرا".
  final i5 = ayaat.indexWhere((a) => a.surah == 'الشرح' && a.num == 5);
  final withPrior = matcher.match('ان مع العسر يسرا', priorIndex: i5);
  final ok1 = withPrior != null &&
      withPrior.ayah.surah == 'الشرح' &&
      withPrior.ayah.num == 6;
  print('${ok1 ? "PASS" : "FAIL"} prior(الشرح:5) + "ان مع العسر يسرا" -> '
      '${withPrior?.ayah.surah}:${withPrior?.ayah.num} (expected الشرح:6)');
  ok1 ? pass++ : fail++;

  // The identical-text ayah فبأي آلاء ربكما تكذبان must resolve to the
  // occurrence right after the prior, not an arbitrary one of the 31 copies.
  final i16 = ayaat.indexWhere((a) => a.surah == 'الرحمن' && a.num == 15);
  final m2 = matcher.match('فباي الاء ربكما تكذبان', priorIndex: i16);
  final ok2 = m2 != null && m2.ayah.surah == 'الرحمن' && m2.ayah.num == 16;
  print('${ok2 ? "PASS" : "FAIL"} prior(الرحمن:15) + التكرار -> '
      '${m2?.ayah.surah}:${m2?.ayah.num} (expected الرحمن:16)');
  ok2 ? pass++ : fail++;

  // The prior must NOT override strong contrary evidence: a clear fragment
  // of a completely different ayah still wins despite the prior.
  final m3 = matcher.match('قل هو الله احد', priorIndex: i5);
  final ok3 = m3 != null && m3.ayah.surah == 'الإخلاص';
  print('${ok3 ? "PASS" : "FAIL"} prior(الشرح:5) + "قل هو الله احد" -> '
      '${m3?.ayah.surah}:${m3?.ayah.num} (expected الإخلاص:1)');
  ok3 ? pass++ : fail++;

  print('$pass passed, $fail failed');
  exit(fail == 0 ? 0 : 1);
}
