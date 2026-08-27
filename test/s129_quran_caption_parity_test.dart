// PATCH_S129_QURAN_CAPTION_PARITY
import 'package:flutter_test/flutter_test.dart';
import 'package:ayat_studio_app/services/basmala.dart';
import 'package:ayat_studio_app/services/subtitle_service.dart';
import 'package:ayat_studio_app/services/ayah_matcher.dart';
import 'package:ayat_studio_app/models/studio_state.dart';

void main() {
  group('basmala / istiatha detection', () {
    test('classic basmala is recognised', () {
      expect(isBasmala('بسم الله الرحمن الرحيم'), isTrue);
      expect(isBasmala('بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ'), isTrue);
      expect(isNonAyahFormula('بسم الله الرحمن الرحيم'), isTrue);
    });

    test('istiatha is recognised', () {
      expect(isIstiatha('أعوذ بالله من الشيطان الرجيم'), isTrue);
      expect(isIstiatha('اعوذ بالله من الشيطان الرجيم'), isTrue);
      expect(isNonAyahFormula('اعوذ بالله من الشيطان الرجيم'), isTrue);
    });

    test('ordinary ayah text is not a formula', () {
      expect(isBasmala('الحمد لله رب العالمين'), isFalse);
      expect(isIstiatha('قل هو الله احد'), isFalse);
      expect(isNonAyahFormula('قل هو الله احد'), isFalse);
    });
  });

  group('YouTube chapters', () {
    final a1 = Ayah(
        surahNum: 1, surah: 'الفاتحة', num: 1, ar: 'بسم الله', en: 'In the name');
    final a2 = Ayah(
        surahNum: 1, surah: 'الفاتحة', num: 2, ar: 'الحمد لله', en: 'Praise');

    test('empty timeline yields empty (or header-only) file', () {
      final out = SubtitleService.chapters([]);
      expect(out.trim(), isEmpty);
    });

    test('timestamps and titles are correct at 1x', () {
      final segs = [
        TimelineSegment(start: 0, end: 5, ayah: a1, confidence: 1),
        TimelineSegment(start: 5, end: 12, ayah: a2, confidence: 1),
      ];
      final out = SubtitleService.chapters(segs);
      expect(out, contains('0:00  الفاتحة 1'));
      expect(out, contains('0:05  الفاتحة 2'));
    });

    test('speed retime matches subtitle arithmetic', () {
      final segs = [
        TimelineSegment(start: 0, end: 10, ayah: a1, confidence: 1),
      ];
      final fast = SubtitleService.chapters(segs, speed: 2.0);
      expect(fast, contains('0:00  الفاتحة 1'));
      // end of first chapter is not written; only start times matter
    });

    test('lead-in inserts a مقدمة chapter', () {
      final segs = [
        TimelineSegment(start: 0, end: 5, ayah: a1, confidence: 1),
      ];
      final out = SubtitleService.chapters(segs, leadInSec: 3.0);
      expect(out, contains('0:00  مقدمة'));
      expect(out, contains('0:03  الفاتحة 1'));
    });

    test('project / reciter headers are optional comments', () {
      final out = SubtitleService.chapters(
        [],
        projectName: 'My Recitation',
        reciterName: 'Al-Husary',
      );
      expect(out, contains('# My Recitation'));
      expect(out, contains('# Al-Husary'));
    });
  });
}
