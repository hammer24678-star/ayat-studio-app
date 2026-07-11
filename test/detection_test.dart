// PATCH_S35_SMARTER_DETECTION: matcher top-K / subset scoring and the
// timeline post-processing (overlap split, gap bridging).
import 'dart:math';
import 'dart:typed_data';

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
        seg(corpus[1], 9, 15), // 3s gap (< step) — bridged
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

  // PATCH_S42_AUTOSYNC_MAX -----------------------------------------------

  group('TimelineBuilder.adaptiveSilenceThreshold', () {
    test('keeps the fixed gate for tiny inputs and quiet clean clips', () {
      expect(TimelineBuilder.adaptiveSilenceThreshold([]),
          TimelineBuilder.vadSilenceRms);
      expect(TimelineBuilder.adaptiveSilenceThreshold([0.001, 0.05]),
          TimelineBuilder.vadSilenceRms);
      // near-zero room tone → adaptive value would be below the fixed gate,
      // which stays as the floor
      final quiet = [
        ...List.filled(3, 0.0005),
        ...List.filled(7, 0.05),
      ];
      expect(TimelineBuilder.adaptiveSilenceThreshold(quiet),
          TimelineBuilder.vadSilenceRms);
    });

    test('rises above noisy room tone but never swallows speech', () {
      // room tone ~0.012 (louder than the fixed 0.008 gate), speech ~0.1
      final noisy = [
        ...List.filled(3, 0.012),
        ...List.filled(7, 0.1),
      ];
      final gate = TimelineBuilder.adaptiveSilenceThreshold(noisy);
      expect(gate, greaterThan(0.012)); // gates the room tone away
      expect(gate, lessThan(0.1)); // never gates the speech windows
      expect(gate, lessThanOrEqualTo(0.02)); // absolute cap
    });

    test('wall-to-wall loud speech is never gated', () {
      final loud = List.filled(20, 0.08);
      final gate = TimelineBuilder.adaptiveSilenceThreshold(loud);
      expect(gate, lessThan(0.08));
    });
  });

  group('TimelineBuilder.repairTimeline', () {
    test('merges adjacent segments of the same ayah', () {
      final t = [
        TimelineSegment(start: 0, end: 6, ayah: corpus[0], confidence: 0.5),
        TimelineSegment(start: 7, end: 12, ayah: corpus[0], confidence: 0.8),
      ];
      TimelineBuilder.repairTimeline(t);
      expect(t.length, 1);
      expect(t.single.start, 0);
      expect(t.single.end, 12);
      expect(t.single.confidence, 0.8);
    });

    test('drops a short weak mis-detection sandwiched inside one ayah', () {
      final t = [
        TimelineSegment(start: 0, end: 10, ayah: corpus[0], confidence: 0.7),
        TimelineSegment(start: 10, end: 15, ayah: corpus[4], confidence: 0.35),
        TimelineSegment(start: 15, end: 25, ayah: corpus[0], confidence: 0.75),
      ];
      TimelineBuilder.repairTimeline(t);
      expect(t.length, 1);
      expect(t.single.ayah.num, 1);
      expect(t.single.start, 0);
      expect(t.single.end, 25);
    });

    test('keeps a long or confident middle segment', () {
      final confident = [
        TimelineSegment(start: 0, end: 10, ayah: corpus[0], confidence: 0.6),
        TimelineSegment(start: 10, end: 15, ayah: corpus[4], confidence: 0.9),
        TimelineSegment(start: 15, end: 25, ayah: corpus[0], confidence: 0.6),
      ];
      TimelineBuilder.repairTimeline(confident);
      expect(confident.length, 3);
      final long = [
        TimelineSegment(start: 0, end: 10, ayah: corpus[0], confidence: 0.7),
        TimelineSegment(start: 10, end: 22, ayah: corpus[4], confidence: 0.4),
        TimelineSegment(start: 22, end: 30, ayah: corpus[0], confidence: 0.7),
      ];
      TimelineBuilder.repairTimeline(long);
      expect(long.length, 3);
    });
  });

  group('TimelineBuilder.inferSkippedAyat', () {
    test('fills a skipped ayah into a same-surah gap with enough time', () {
      // 112:1 then 112:3 with a 4s gap — 112:2 was recited but never matched
      final t = [
        TimelineSegment(start: 0, end: 6, ayah: corpus[0], confidence: 0.8),
        TimelineSegment(start: 10, end: 16, ayah: corpus[2], confidence: 0.8),
      ];
      TimelineBuilder.inferSkippedAyat(t, corpus);
      expect(t.length, 3);
      expect(t[1].ayah.num, 2);
      expect(t[1].inferred, isTrue);
      expect(t[1].start, 6);
      expect(t[1].end, 10);
      expect(t[0].inferred, isFalse);
    });

    test('splits a two-ayah gap proportionally to word counts', () {
      // 112:1 then 112:4 — 112:2 (2 words) and 112:3 (4 words) missing
      final t = [
        TimelineSegment(start: 0, end: 6, ayah: corpus[0], confidence: 0.8),
        TimelineSegment(start: 12, end: 18, ayah: corpus[3], confidence: 0.8),
      ];
      TimelineBuilder.inferSkippedAyat(t, corpus);
      expect(t.length, 4);
      expect(t[1].ayah.num, 2);
      expect(t[2].ayah.num, 3);
      expect(t[2].end, 12);
      // 6s gap split 2:4 by word count
      expect(t[1].end - t[1].start, closeTo(2.0, 1e-9));
      expect(t[2].end - t[2].start, closeTo(4.0, 1e-9));
    });

    test('leaves gaps alone when too short, cross-surah, or non-consecutive',
        () {
      final tooShort = [
        TimelineSegment(start: 0, end: 6, ayah: corpus[0], confidence: 0.8),
        TimelineSegment(start: 7, end: 13, ayah: corpus[2], confidence: 0.8),
      ];
      TimelineBuilder.inferSkippedAyat(tooShort, corpus);
      expect(tooShort.length, 2);

      final crossSurah = [
        TimelineSegment(start: 0, end: 6, ayah: corpus[3], confidence: 0.8),
        TimelineSegment(start: 12, end: 18, ayah: corpus[4], confidence: 0.8),
      ];
      TimelineBuilder.inferSkippedAyat(crossSurah, corpus);
      expect(crossSurah.length, 2);

      final consecutive = [
        TimelineSegment(start: 0, end: 6, ayah: corpus[0], confidence: 0.8),
        TimelineSegment(start: 12, end: 18, ayah: corpus[1], confidence: 0.8),
      ];
      TimelineBuilder.inferSkippedAyat(consecutive, corpus);
      expect(consecutive.length, 2);
    });
  });

  // PATCH_S43_GAP_RESCUE ----------------------------------------------------

  group('TimelineBuilder.expectedInGap', () {
    test('gap between two anchors spans them inclusively', () {
      final c = TimelineBuilder.expectedInGap(corpus[0], corpus[3], corpus);
      expect(c.map((a) => a.num), [1, 2, 3, 4]);
    });

    test('head gap looks back, tail gap looks forward', () {
      final head = TimelineBuilder.expectedInGap(null, corpus[2], corpus);
      expect(head.map((a) => a.num), [1, 2, 3]);
      final tail = TimelineBuilder.expectedInGap(corpus[2], null, corpus);
      expect(tail.map((a) => a.num), [3, 4, 6]);
    });

    test('degenerate spans fall back to the anchors, wide spans to nothing',
        () {
      // out-of-order anchors (a repeat) → just the anchors themselves
      final repeat = TimelineBuilder.expectedInGap(corpus[3], corpus[0], corpus);
      expect(repeat.length, 2);
      // no anchors at all → nothing to constrain against
      expect(TimelineBuilder.expectedInGap(null, null, corpus), isEmpty);
      // span wider than maxGapCandidates → too unconstrained to guess
      final wide = [
        for (var n = 1; n <= 12; n++) ayah(2, n, 'اية رقم $n في السورة')
      ];
      expect(TimelineBuilder.expectedInGap(wide.first, wide.last, wide),
          isEmpty);
    });
  });

  group('TimelineBuilder.snapEdgesToSpeech', () {
    // 12s of 16kHz PCM: silence, then a loud tone from 3s to 10s.
    Int16List tonePcm() {
      const rate = TimelineBuilder.sampleRate;
      final pcm = Int16List(rate * 12);
      for (var i = rate * 3; i < rate * 10; i++) {
        pcm[i] = (8000 * sin(2 * pi * 220 * i / rate)).round();
      }
      return pcm;
    }

    test('first start and last end move from the grid to the speech', () {
      final t = [
        TimelineSegment(start: 0, end: 6, ayah: corpus[0], confidence: 0.8),
        TimelineSegment(start: 6, end: 11.5, ayah: corpus[1], confidence: 0.8),
      ];
      TimelineBuilder.snapEdgesToSpeech(t, tonePcm(), 0.008);
      expect(t.first.start, closeTo(3.0, 0.35));
      expect(t.last.end, closeTo(10.0, 0.35));
      // the shared boundary is not an edge and must not move
      expect(t.first.end, 6);
      expect(t.last.start, 6);
    });

    test('edges already on speech stay put', () {
      final t = [
        TimelineSegment(start: 4, end: 9, ayah: corpus[0], confidence: 0.8),
      ];
      TimelineBuilder.snapEdgesToSpeech(t, tonePcm(), 0.008);
      expect(t.single.start, 4);
      expect(t.single.end, 9);
    });

    test('an all-silent segment is left alone', () {
      final t = [
        TimelineSegment(start: 0, end: 2.5, ayah: corpus[0], confidence: 0.8),
      ];
      TimelineBuilder.snapEdgesToSpeech(t, tonePcm(), 0.008);
      expect(t.single.start, 0);
      expect(t.single.end, 2.5);
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

    // PATCH_S42_SYNC_QOL: undo of a deletion restores the exact segment
    test('remove returns the segment and insert puts it back', () {
      final s = freshState();
      final removed = s.removeTimelineSegment(1);
      expect(removed, isNotNull);
      expect(s.timeline.length, 2);
      s.insertTimelineSegment(1, removed!);
      expect(s.timeline.length, 3);
      expect(identical(s.timeline[1], removed), isTrue);
      expect(s.removeTimelineSegment(99), isNull);
    });

    // PATCH_S42_AUTOSYNC_MAX
    test('segmentAt finds the playing segment, null in gaps', () {
      final s = freshState();
      expect(s.segmentAt(5)!.ayah.num, 1);
      expect(s.segmentAt(10)!.ayah.num, 2);
      expect(s.segmentAt(29.9)!.ayah.num, 3);
      expect(s.segmentAt(31), isNull);
    });

    test('timelineCoverageFraction reports detected share of the clip', () {
      final s = freshState(); // 3 × 10s segments over a 60s clip
      expect(s.timelineCoverageFraction(), closeTo(0.5, 1e-9));
      final empty = StudioState();
      expect(empty.timelineCoverageFraction(), 0);
    });
  });
}
