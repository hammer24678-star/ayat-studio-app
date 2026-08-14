// PATCH_S123_I18N: guards the string table. A half-translated key is a
// runtime index error waiting to happen (AppStrings.t indexes the row by
// AppLang.index), so it has to fail here instead of on a user's phone.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/i18n/app_strings.dart';

void main() {
  final table = debugStringTable();

  test('every key has exactly one string per language', () {
    final bad = <String>[];
    table.forEach((key, row) {
      if (row.length != AppLang.values.length) {
        bad.add('$key has ${row.length}, expected ${AppLang.values.length}');
      }
    });
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('no translation is blank', () {
    final bad = <String>[];
    table.forEach((key, row) {
      for (var i = 0; i < row.length; i++) {
        if (row[i].trim().isEmpty) bad.add('$key[${AppLang.values[i].name}]');
      }
    });
    expect(bad, isEmpty, reason: bad.join(', '));
  });

  test('placeholder counts match across a key\'s languages', () {
    final bad = <String>[];
    table.forEach((key, row) {
      final expected = '{}'.allMatches(row[0]).length;
      for (var i = 1; i < row.length; i++) {
        final got = '{}'.allMatches(row[i]).length;
        if (got != expected) {
          bad.add('$key: ar has $expected, ${AppLang.values[i].name} has $got');
        }
      }
    });
    expect(bad, isEmpty, reason: bad.join('\n'));
  });

  test('every language has a display name and a locale code', () {
    for (final l in AppLang.values) {
      expect(kLangNames[l], isNotNull, reason: 'missing name for $l');
      expect(kLangCodes[l], isNotNull, reason: 'missing code for $l');
    }
  });

  test('lookups resolve, and an unknown key returns itself', () {
    expect(const AppStrings(AppLang.ar).t('app.start'), 'ابدأ التصميم');
    expect(const AppStrings(AppLang.en).t('app.start'), 'Start designing');
    expect(const AppStrings(AppLang.en).t('no.such.key'), 'no.such.key');
  });

  test('f() fills placeholders left to right', () {
    expect(
      const AppStrings(AppLang.en).f('mushaf.pageOf', [12, 604]),
      'Page 12 of 604',
    );
  });

  test('Arabic and Urdu are the right-to-left languages', () {
    expect(isRtlLang(AppLang.ar), isTrue);
    expect(isRtlLang(AppLang.ur), isTrue);
    expect(isRtlLang(AppLang.en), isFalse);
    expect(isRtlLang(AppLang.fr), isFalse);
    expect(isRtlLang(AppLang.id), isFalse);
  });
}
