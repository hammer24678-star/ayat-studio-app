// PATCH_S35_SMARTER_DETECTION: matcher top-K / subset scoring and the
// timeline post-processing (overlap split, gap bridging).
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/models/studio_state.dart';
import 'package:ayat_studio_app/services/ayah_matcher.dart';
import 'package:ayat_studio_app/services/timeline_builder.dart';

Ayah ayah(int surahNum, int num, String ar) =>
    Ayah(surahNum: surahNum, surah: 'س$surahNum', num: num, ar: ar, en: '');

TimelineSegment seg(Ayah a, double start, double end) =>
    TimelineSegment(start: start, end: end, ayah: a, confidence: 0.8);

void main() {
  final corpus = [
    ayah(112, 1, 'قل هو الله أحد'),
    ayah(112, 2, 'الله الصمد'),
    ayah(112, 3, 'لم يلد ولم يولد'),
    ayah(112, 4, 'ولم يكن له كفوا أحد'),
    ayah(94, 6, 'إن مع العسر يسرا'),
  ];
  final matcher = AyahMatcher(corpus);

  group('AyahMatcher', () {
    test('matchTop returns ranked candidates and match() equals its head', () {
      final top = matcher.matchTop('قل هو الله احد', k: 3);
      expect(top, isNotEmpty);
      expect(top.first.ayah.num, 1);
      for (var i = 0; i + 1 < top.length; i++) {
        expect(top[i].confidence, greaterThanOrEqualTo(top[i + 1].confidence));
      }
      final single = matcher.match('قل هو الله احد');
      expect(single, isNotNull);
      expect(identical(single!.ayah, top.first.ayah), isTrue);
      expect(single.confidence, top.first.confidence);
    });

    test('matchAmong only considers the given candidates', () {
      // exact text of 112:3, but restricted to 112:4 and 94:6 candidates
      final m = matcher.matchAmong(
          'لم يلد ولم يولد', [corpus[3], corpus[4]],
          minConfidence: 0.1);
      expect(m, isNotNull);
      expect(m!.ayah.num, anyOf(4, 6));
      // and finds the right one when it IS a candidate
      final hit = matcher.matchAmong(
          'لم يلد ولم يولد', [corpus[2], corpus[4]],
          minConfidence: 0.1);
      expect(hit!.ayah.num, 3);
    });

    test('matchAmong keeps the hallucination/short-input gates', () {
      expect(matcher.matchAmong('الله', corpus), isNull);
      expect(
          matcher.matchAmong('الله الله الله الله الله', corpus), isNull);
    });
  });

  group('TimelineBuilder.normalizeTimeline', () {
    test('splits window-grid overlaps at the midpoint', () {
      final t = [seg(corpus[0], 0, 11), seg(corpus[1], 10, 16)];
      TimelineBuilder.normalizeTimeline(t, 60);
      expect(t[0].end, closeTo(10.5, 1e-9));
      expect(t[1].start, closeTo(10.5, 1e-9));
    });

    test('bridges small gaps but leaves real silence gaps alone', () {
      final t = [
        seg(corpus[0], 0, 6),
        seg(corpus[1], 9, 15), // 3s gap (≤ bridgeGapSec) — bridged
        seg(corpus[2], 30, 36), // 15s gap — real pause, untouched
      ];
      TimelineBuilder.normalizeTimeline(t, 60);
      expect(t[0].end, closeTo(7.5, 1e-9));
      expect(t[1].start, closeTo(7.5, 1e-9));
      expect(t[1].end, 15);
      expect(t[2].start, 30);
    });

    test('clamps the last segment to the clip length', () {
      final t = [seg(corpus[0], 55, 66)];
      TimelineBuilder.normalizeTimeline(t, 60);
      expect(t.single.end, 60);
    });
  });

  group('StudioState timeline editing', () {
    StudioState freshState() {
      final s = StudioState();
      s.videoDurationSec = 60;
      s.setTimeline([
        seg(corpus[0], 0, 10),
        seg(corpus[1], 10, 20),
        seg(corpus[2], 20, 30),
      ]);
      return s;
    }

    test('nudging a shared boundary drags the neighbour along', () {
      final s = freshState();
      s.nudgeTimelineSegment(1, startDelta: -2);
      expect(s.timeline[1].start, 8);
      expect(s.timeline[0].end, 8);
      s.nudgeTimelineSegment(1, endDelta: 3);
      expect(s.timeline[1].end, 23);
      expect(s.timeline[2].start, 23);
    });

    test('segments keep a minimum length and stay inside the clip', () {
      final s = freshState();
      s.nudgeTimelineSegment(0, endDelta: -100);
      expect(s.timeline[0].end, closeTo(0.3, 1e-9));
      s.nudgeTimelineSegment(2, endDelta: 100);
      expect(s.timeline[2].end, 60);
    });

    test('removing a segment resets the ayah-boundary trim', () {
      final s = freshState();
      s.trimFromIndex = 0;
      s.trimToIndex = 2;
      s.removeTimelineSegment(1);
      expect(s.timeline.length, 2);
      expect(s.trimFromIndex, -1);
      expect(s.trimToIndex, -1);
      expect(s.timelineActive, isTrue);
    });
  });
}
