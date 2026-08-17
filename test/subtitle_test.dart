// PATCH_S125_SUBTITLES: the failure mode of a subtitle exporter is silent —
// the file opens, the cues are there, and every line is a second or two off.
// That comes from mixing up source time with exported time, so most of these
// are about exactly that.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/data/studio_presets.dart';
import 'package:ayat_studio_app/models/studio_state.dart';
import 'package:ayat_studio_app/services/ayah_matcher.dart';
import 'package:ayat_studio_app/services/subtitle_service.dart';

Ayah _ayah(int surah, int num, String ar, [String en = '']) => Ayah(
    surahNum: surah, surah: 'الإخلاص', num: num, ar: ar, en: en);

TimelineSegment _seg(double start, double end, Ayah a, {String? override}) =>
    TimelineSegment(
        start: start, end: end, ayah: a, confidence: 0.9, textOverride: override);

void main() {
  final a1 = _ayah(112, 1, 'قل هو الله أحد', 'Say: He is Allah, the One');
  final a2 = _ayah(112, 2, 'الله الصمد', 'Allah, the Eternal Refuge');

  group('timestamps', () {
    test('SRT uses a comma, VTT a dot, both padded to hours', () {
      expect(SubtitleService.formatTimestamp(0, SubtitleFormat.srt),
          '00:00:00,000');
      expect(SubtitleService.formatTimestamp(0, SubtitleFormat.vtt),
          '00:00:00.000');
      expect(SubtitleService.formatTimestamp(3661.5, SubtitleFormat.srt),
          '01:01:01,500');
      expect(SubtitleService.formatTimestamp(75.25, SubtitleFormat.vtt),
          '00:01:15.250');
    });

    test('a negative time never produces a malformed stamp', () {
      expect(SubtitleService.formatTimestamp(-5, SubtitleFormat.srt),
          '00:00:00,000');
    });
  });

  group('file shape', () {
    test('SRT is index / times / text / blank, in that order', () {
      final out = SubtitleService.build(
        [_seg(0, 2, a1), _seg(2, 4.5, a2)],
        format: SubtitleFormat.srt,
      );
      final lines = out.trim().split('\n');
      expect(lines[0], '1');
      expect(lines[1], '00:00:00,000 --> 00:00:02,000');
      expect(lines[2], 'قل هو الله أحد');
      expect(lines[3], '');
      expect(lines[4], '2');
      expect(lines[5], '00:00:02,000 --> 00:00:04,500');
    });

    test('VTT starts with the WEBVTT header', () {
      final out = SubtitleService.build([_seg(0, 2, a1)],
          format: SubtitleFormat.vtt);
      expect(out.startsWith('WEBVTT'), isTrue);
      expect(out, contains('00:00:00.000 --> 00:00:02.000'));
    });

    test('an empty timeline produces no cues', () {
      expect(SubtitleService.build(const [], format: SubtitleFormat.srt),
          isEmpty);
      expect(
        SubtitleService.build(const [], format: SubtitleFormat.vtt).trim(),
        'WEBVTT',
      );
    });
  });

  group('exported time vs source time', () {
    test('clipStart is subtracted, so cues are not late by the trim offset',
        () {
      // The user trimmed the first 10s away; an ayah heard at 12s in the
      // source is at 2s in the export.
      final out = SubtitleService.build(
        [_seg(12, 14, a1)],
        format: SubtitleFormat.srt,
        clipStart: 10,
      );
      expect(out, contains('00:00:02,000 --> 00:00:04,000'));
    });

    test('a lead-in card pushes every cue later by its length', () {
      final out = SubtitleService.build(
        [_seg(0, 2, a1)],
        format: SubtitleFormat.srt,
        leadInSec: 2.2,
      );
      expect(out, contains('00:00:02,200 --> 00:00:04,200'));
    });

    test('segments outside the exported window are dropped, not clamped', () {
      final out = SubtitleService.build(
        [
          _seg(0, 5, a1), // before the trim — gone entirely
          _seg(12, 14, a2), // inside
        ],
        format: SubtitleFormat.srt,
        clipStart: 10,
        clipDuration: 10,
      );
      expect(out, isNot(contains('قل هو الله أحد')));
      expect(out, contains('الله الصمد'));
      expect(out.trim().split('\n').first, '1',
          reason: 'numbering restarts at 1 for the cues that survive');
    });

    test('a segment straddling the end is cut at the end, not beyond it', () {
      final out = SubtitleService.build(
        [_seg(0, 30, a1)],
        format: SubtitleFormat.srt,
        clipDuration: 8,
      );
      expect(out, contains('00:00:00,000 --> 00:00:08,000'));
    });
  });

  group('cue text', () {
    test('translation and both modes', () {
      final tr = SubtitleService.build([_seg(0, 2, a1)],
          format: SubtitleFormat.srt, content: SubtitleContent.translation);
      expect(tr, contains('Say: He is Allah, the One'));
      expect(tr, isNot(contains('قل هو الله أحد')));

      final both = SubtitleService.build([_seg(0, 2, a1)],
          format: SubtitleFormat.srt, content: SubtitleContent.both);
      expect(both, contains('قل هو الله أحد'));
      expect(both, contains('Say: He is Allah, the One'));
    });

    test('a partial-ayah slice uses its own text, not the whole ayah', () {
      final out = SubtitleService.build(
        [_seg(0, 2, a1, override: 'قل هو')],
        format: SubtitleFormat.srt,
      );
      expect(out, contains('قل هو'));
      expect(out, isNot(contains('قل هو الله أحد')));
    });

    test('a newline inside the text cannot split one cue into two', () {
      final out = SubtitleService.build(
        [_seg(0, 2, _ayah(1, 1, 'سطر\nثانٍ'))],
        format: SubtitleFormat.srt,
      );
      expect(out, contains('سطر ثانٍ'));
    });

    test('the reference can be appended', () {
      final out = SubtitleService.build([_seg(0, 2, a1)],
          format: SubtitleFormat.srt, includeReference: true);
      expect(out, contains('[الإخلاص 1]'));
    });
  });

  test('cueCount agrees with what build actually emits', () {
    final segs = [_seg(0, 5, a1), _seg(12, 14, a2), _seg(40, 41, a1)];
    final n = SubtitleService.cueCount(segs, clipStart: 10, clipDuration: 10);
    final built = SubtitleService.build(segs,
        format: SubtitleFormat.srt, clipStart: 10, clipDuration: 10);
    final emitted =
        RegExp(r'-->').allMatches(built).length;
    expect(n, emitted);
  });

  group('custom frame size', () {
    test('presets resolve to their table dimensions', () {
      final s = StudioState()..aspectRatio = AyatAspectRatio.landscape169;
      expect(s.frameSize, (1920, 1080));
      s.aspectRatio = AyatAspectRatio.portrait45;
      expect(s.frameSize, (1080, 1350));
    });

    test('a custom size is used verbatim once made even', () {
      final s = StudioState()
        ..aspectRatio = AyatAspectRatio.custom
        ..customAspectW = 1000
        ..customAspectH = 1600;
      expect(s.frameSize, (1000, 1600));
    });

    test('odd dimensions are rounded down — libx264 cannot encode them', () {
      final s = StudioState()
        ..aspectRatio = AyatAspectRatio.custom
        ..customAspectW = 1081
        ..customAspectH = 1921;
      expect(s.frameSize, (1080, 1920));
    });

    test('absurd sizes are clamped rather than handed to the encoder', () {
      final s = StudioState()
        ..aspectRatio = AyatAspectRatio.custom
        ..customAspectW = 99999
        ..customAspectH = 1;
      final (w, h) = s.frameSize;
      expect(w, 3840);
      expect(h, 240);
    });
  });
}
