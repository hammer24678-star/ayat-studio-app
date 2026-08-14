// PATCH_S123_AYAH_SEARCH: the reader's "type an ayah and find it" box. The
// interesting behaviour is that it works on UNVOCALIZED input against a
// FULLY vocalized corpus, and still reports offsets that point at the right
// characters of the original text for highlighting.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/data/mushaf_meta.dart';
import 'package:ayat_studio_app/services/ayah_matcher.dart';
import 'package:ayat_studio_app/services/quran_search.dart';

Ayah ayah(int surahNum, String surah, int num, String ar, [String en = '']) =>
    Ayah(surahNum: surahNum, surah: surah, num: num, ar: ar, en: en);

/// A tiny corpus with real, fully-vocalized text — the vocalization is the
/// point, since that's what the normalizer has to see through.
final _corpus = <Ayah>[
  ayah(112, 'الإخلاص', 1, 'قُلْ هُوَ ٱللَّهُ أَحَدٌ'),
  ayah(112, 'الإخلاص', 2, 'ٱللَّهُ ٱلصَّمَدُ'),
  ayah(112, 'الإخلاص', 3, 'لَمْ يَلِدْ وَلَمْ يُولَدْ'),
  ayah(94, 'الشرح', 5, 'فَإِنَّ مَعَ ٱلْعُسْرِ يُسْرًا'),
  ayah(94, 'الشرح', 6, 'إِنَّ مَعَ ٱلْعُسْرِ يُسْرًا'),
  ayah(18, 'الكهف', 1, 'ٱلْحَمْدُ لِلَّهِ ٱلَّذِىٓ أَنزَلَ عَلَىٰ عَبْدِهِ ٱلْكِتَٰبَ'),
];

void main() {
  setUp(QuranSearch.resetIndex);

  group('text search', () {
    test('finds an ayah from unvocalized input', () {
      final r = QuranSearch.search('قل هو الله احد', _corpus);
      expect(r, isNotEmpty);
      expect(r.first.ayah.num, 1);
      expect(r.first.ayah.surahNum, 112);
    });

    test('finds a fragment from the middle of an ayah', () {
      final r = QuranSearch.search('مع العسر', _corpus);
      expect(r.length, 2); // both 94:5 and 94:6 contain it
      expect(r.every((x) => x.ayah.surahNum == 94), isTrue);
    });

    test('ranks a whole-ayah prefix above a mid-ayah hit', () {
      final r = QuranSearch.search('ان مع العسر يسرا', _corpus);
      expect(r, isNotEmpty);
      // 94:6 starts with it; 94:5 only contains it after فَ.
      expect(r.first.ayah.num, 6);
    });

    test('ignores hamza spelling and alef variants', () {
      // Typed with a bare alef where the corpus has أ / ٱ.
      final r = QuranSearch.search('انزل على عبده', _corpus);
      expect(r, isNotEmpty);
      expect(r.first.ayah.surahNum, 18);
    });

    test('match offsets point at the matching characters of the real text',
        () {
      final r = QuranSearch.search('مع العسر', _corpus);
      expect(r, isNotEmpty);
      for (final hit in r) {
        final slice =
            hit.ayah.ar.substring(hit.matchStart, hit.matchStart + hit.matchLength);
        // The slice still carries its tashkeel, but normalizing it must give
        // back exactly what was searched for.
        expect(normalizeArabic(slice), 'مع العسر');
      }
    });

    test('an empty or one-character query returns nothing', () {
      expect(QuranSearch.search('', _corpus), isEmpty);
      expect(QuranSearch.search('   ', _corpus), isEmpty);
      expect(QuranSearch.search('ل', _corpus), isEmpty);
    });

    test('respects the result cap', () {
      final r = QuranSearch.search('ا', _corpus, limit: 2);
      expect(r.length, lessThanOrEqualTo(2));
    });
  });

  group('reference search', () {
    // References resolve against the real mushaf table, so they need a
    // corpus with real global positions.
    final full = [
      for (var i = 1; i <= kTotalAyat; i++)
        ayah(1, 'س', i, 'نص $i'),
    ];

    test('"2:255" lands on ayat al-kursi', () {
      final r = QuranSearch.search('2:255', full);
      expect(r.length, 1);
      expect(r.first.globalAyahId, globalAyahId(2, 255));
      expect(r.first.matchStart, -1);
    });

    test('Eastern Arabic-Indic digits and a space separator both work', () {
      expect(QuranSearch.search('٢:٢٥٥', full).first.globalAyahId,
          globalAyahId(2, 255));
      expect(QuranSearch.search('2 255', full).first.globalAyahId,
          globalAyahId(2, 255));
    });

    test('a bare surah number opens that surah', () {
      expect(QuranSearch.search('18', full).first.globalAyahId,
          globalAyahId(18, 1));
    });

    test('an out-of-range reference finds nothing', () {
      expect(QuranSearch.search('2:9999', full), isEmpty);
      expect(QuranSearch.search('200:1', full), isEmpty);
    });
  });

  group('surah name search', () {
    test('matches the Arabic name', () {
      expect(QuranSearch.matchingSurahs('الكهف', _corpus), contains(18));
    });

    test('matches a transliteration, with or without punctuation', () {
      expect(QuranSearch.matchingSurahs('Al-Kahf', _corpus), contains(18));
      expect(QuranSearch.matchingSurahs('alkahf', _corpus), contains(18));
      expect(QuranSearch.matchingSurahs('ikhlas', _corpus), contains(112));
    });

    test('matches the English meaning', () {
      expect(QuranSearch.matchingSurahs('The Cave', _corpus), contains(18));
    });

    test('nonsense matches nothing', () {
      expect(QuranSearch.matchingSurahs('zzzzq', _corpus), isEmpty);
    });
  });
}
