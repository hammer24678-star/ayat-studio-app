// PATCH_S123_MATCHER_ACCURACY: unit cover for the two detection changes that
// move real-world accuracy — refusing inputs too short to be evidence, and
// resolving ayat whose text repeats elsewhere in the Quran from reading
// order instead of guessing.
//
// The end-to-end accuracy number lives in tool/matcher_bench.dart
// (`dart run tool/matcher_bench.dart`); these are the invariants behind it.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/services/ayah_matcher.dart';

Ayah ayah(int surahNum, int num, String ar) =>
    Ayah(surahNum: surahNum, surah: 'س$surahNum', num: num, ar: ar, en: '');

void main() {
  // A miniature ar-Rahman: a repeated refrain between distinct ayat, which is
  // exactly the structure the duplicate handling exists for.
  const refrain = 'فبأي آلاء ربكما تكذبان';
  final corpus = [
    ayah(55, 12, 'والحب ذو العصف والريحان'),
    ayah(55, 13, refrain),
    ayah(55, 14, 'خلق الإنسان من صلصال كالفخار'),
    ayah(55, 15, 'وخلق الجان من مارج من نار'),
    ayah(55, 16, refrain),
    ayah(55, 17, 'رب المشرقين ورب المغربين'),
    ayah(55, 18, refrain),
    ayah(112, 1, 'قل هو الله أحد'),
  ];
  final matcher = AyahMatcher(corpus);

  group('short-input gate', () {
    test('refuses fewer than three tokens', () {
      expect(AyahMatcher.minInputTokens, 3);
      expect(matcher.match('قل هو'), isNull);
      expect(matcher.match('الله'), isNull);
      expect(matcher.match(''), isNull);
    });

    test('still matches a three-token input that is real evidence', () {
      final m = matcher.match('رب المشرقين ورب');
      expect(m, isNotNull);
      expect(m!.ayah.num, 17);
    });
  });

  group('repeated ayat', () {
    test('groups word-for-word identical ayat, ignoring diacritics', () {
      final group = matcher.textIdenticalTo(corpus[1]);
      expect(group.map((a) => a.num).toList(), [13, 16, 18]);
      expect(matcher.isTextAmbiguous(corpus[1]), isTrue);
      expect(matcher.isTextAmbiguous(corpus[0]), isFalse);
      expect(matcher.textIdenticalTo(corpus[0]).length, 1);
      // Written with different hamza/alef forms, it is still the same ayah.
      expect(
        matcher.textIdenticalTo(ayah(55, 99, 'فباي الاء ربكما تكذبان')).length,
        3,
      );
    });

    test('resolves to the next occurrence at or after the anchor', () {
      // Reciting forward from 55:14, the refrain being heard is 55:16.
      expect(
        matcher.resolveByOrder(corpus[1], anchor: corpus[2]).num,
        16,
      );
      // Anchored on the refrain itself, the same occurrence is still valid —
      // a window can straddle one ayah without having moved on.
      expect(
        matcher.resolveByOrder(corpus[4], anchor: corpus[4]).num,
        16,
      );
      // Past the last occurrence, it falls back to the nearest one behind.
      expect(
        matcher.resolveByOrder(corpus[1], anchor: corpus[7]).num,
        18,
      );
    });

    test('with no anchor, the first occurrence wins', () {
      expect(matcher.resolveByOrder(corpus[4]).num, 13);
    });

    test('leaves a unique ayah untouched', () {
      final unique = corpus[0];
      expect(
        identical(matcher.resolveByOrder(unique, anchor: corpus[5]), unique),
        isTrue,
      );
    });
  });

  test('positionOf gives the mushaf index, -1 for a stranger', () {
    expect(matcher.positionOf(corpus[3]), 3);
    expect(matcher.positionOf(ayah(2, 1, 'الم')), -1);
  });

  group('matchAmong still restricts to the candidates it is given', () {
    test('picks the occurrence the caller expects next, not the first one',
        () {
      // The refrain, offered only the ayat that follow 55:15 — the
      // sequential prior's job. It must land on 55:16, not on 55:13.
      final m = matcher.matchAmong(refrain, [corpus[3], corpus[4]]);
      expect(m, isNotNull);
      expect(m!.ayah.num, 16);
    });

    test('returns null when no candidate is a plausible match', () {
      expect(matcher.matchAmong(refrain, [corpus[7]]), isNull);
    });
  });
}
