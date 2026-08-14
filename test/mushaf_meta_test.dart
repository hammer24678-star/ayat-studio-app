// PATCH_S123_MUSHAF_REBUILD: the page/juz tables are generated data that the
// reader trusts completely — a single wrong entry silently prints the wrong
// ayat on a page of Quran. These are the invariants that catch that.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/data/mushaf_meta.dart';

void main() {
  group('page table', () {
    test('covers exactly 604 pages, strictly increasing, inside the corpus', () {
      expect(kPageStartAyahId.length, kTotalPages);
      expect(kPageStartAyahId.first, 1);
      for (var i = 1; i < kPageStartAyahId.length; i++) {
        expect(kPageStartAyahId[i], greaterThan(kPageStartAyahId[i - 1]),
            reason: 'page ${i + 1} does not start after page $i');
      }
      expect(kPageStartAyahId.last, lessThanOrEqualTo(kTotalAyat));
    });

    test('pageOfAyahId agrees with the table at every boundary', () {
      for (var p = 1; p <= kTotalPages; p++) {
        final first = kPageStartAyahId[p - 1];
        expect(pageOfAyahId(first), p, reason: 'first ayah of page $p');
        final last = p == kTotalPages ? kTotalAyat : kPageStartAyahId[p] - 1;
        expect(pageOfAyahId(last), p, reason: 'last ayah of page $p');
      }
    });

    test('ayahRangeOfPage tiles the whole mushaf with no gap or overlap', () {
      var expectedNext = 1;
      for (var p = 1; p <= kTotalPages; p++) {
        final (first, last) = ayahRangeOfPage(p);
        expect(first, expectedNext, reason: 'gap or overlap before page $p');
        expect(last, greaterThanOrEqualTo(first));
        expectedNext = last + 1;
      }
      expect(expectedNext - 1, kTotalAyat);
    });

    test('page 1 is al-Fatihah and page 2 opens al-Baqarah', () {
      expect(ayahRangeOfPage(1), (1, 7));
      expect(kPageStartAyahId[1], 8);
    });
  });

  group('surah table', () {
    test('114 surahs, contiguous, summing to the full corpus', () {
      expect(kSurahMeta.length, 114);
      var next = 1;
      for (final m in kSurahMeta) {
        expect(m.firstAyahId, next, reason: 'surah ${m.num} start');
        expect(m.ayahCount, greaterThan(0));
        next = m.lastAyahId + 1;
      }
      expect(next - 1, kTotalAyat);
    });

    test('well-known counts are right', () {
      expect(kSurahMeta[0].ayahCount, 7); // الفاتحة
      expect(kSurahMeta[1].ayahCount, 286); // البقرة
      expect(kSurahMeta[8].meccan, isFalse); // التوبة is Medinan
      expect(kSurahMeta[113].ayahCount, 6); // الناس
      expect(kSurahMeta[113].lastAyahId, kTotalAyat);
    });

    test('globalAyahId maps surah:ayah both ways, and rejects out of range',
        () {
      expect(globalAyahId(1, 1), 1);
      expect(globalAyahId(2, 1), 8);
      expect(globalAyahId(2, 255), 262); // آية الكرسي
      expect(globalAyahId(114, 6), kTotalAyat);
      expect(globalAyahId(2, 287), -1);
      expect(globalAyahId(115, 1), -1);
      expect(globalAyahId(0, 1), -1);
    });
  });

  group('juz table', () {
    test('30 ajzaa starting at ayah 1, strictly increasing', () {
      expect(kJuzStartAyahId.length, 30);
      expect(kJuzStartAyahId.first, 1);
      for (var i = 1; i < kJuzStartAyahId.length; i++) {
        expect(kJuzStartAyahId[i], greaterThan(kJuzStartAyahId[i - 1]));
      }
    });

    test('juzOfAyahId lands in range and matches known landmarks', () {
      expect(juzOfAyahId(1), 1);
      expect(juzOfAyahId(kTotalAyat), 30);
      // Juz 2 begins at البقرة:142.
      expect(kJuzStartAyahId[1], globalAyahId(2, 142));
      for (final id in [1, 500, 3000, 6000, kTotalAyat]) {
        expect(juzOfAyahId(id), inInclusiveRange(1, 30));
      }
    });
  });

  test('sajda ayat are real, in-range and unique', () {
    expect(kSajdaAyahIds, isNotEmpty);
    expect(kSajdaAyahIds.toSet().length, kSajdaAyahIds.length);
    for (final id in kSajdaAyahIds) {
      expect(id, inInclusiveRange(1, kTotalAyat));
      expect(hasSajda(id), isTrue);
    }
    expect(hasSajda(1), isFalse);
  });
}
