// PATCH_S189_QURAN_TYPE: completing a half-typed ayah from the corpus.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/services/ayah_matcher.dart';
import 'package:ayat_studio_app/services/quran_search.dart';
import 'package:ayat_studio_app/widgets/quran_text_sheet.dart';

Ayah ayah(int s, String name, int n, String ar) =>
    Ayah(surahNum: s, surah: name, num: n, ar: ar, en: '');

void main() {
  final corpus = [
    ayah(1, 'الفاتحة', 2, 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ'),
    ayah(1, 'الفاتحة', 3, 'ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ'),
  ];

  setUp(QuranSearch.resetIndex);

  test('unvocalized fragment finds the ayah and completes from the match', () {
    final r = QuranSearch.search('الحمد لله رب', corpus);
    expect(r, isNotEmpty);
    expect(r.first.ayah.num, 2);
    final full = quranCompleteFrom(r.first.ayah.ar, r.first.matchStart);
    expect(full.endsWith('ٱلْعَـٰلَمِينَ'), isTrue);
  });

  test('mid-ayah fragment completes to the end, not from the start', () {
    final r = QuranSearch.search('رب العالمين', corpus);
    expect(r, isNotEmpty);
    final out = quranCompleteFrom(r.first.ayah.ar, r.first.matchStart);
    expect(out.length < r.first.ayah.ar.length, isTrue);
    expect(out.endsWith('ٱلْعَـٰلَمِينَ'), isTrue);
  });

  test('no match offset gives the whole ayah', () {
    expect(quranCompleteFrom('abc', -1), 'abc');
    expect(quranCompleteFrom('abc', 0), 'abc');
  });

  test('non-Quran text finds nothing', () {
    expect(QuranSearch.search('مرحبا بكم', corpus), isEmpty);
  });
}
