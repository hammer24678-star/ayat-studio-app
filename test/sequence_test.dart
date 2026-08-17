// PATCH_S125_SEQUENCE: the filtergraph for an N-clip sequence is the kind of
// string that either works or produces a wall of ffmpeg errors, and the one
// piece of real arithmetic in it — the xfade offsets — fails in a way that
// looks almost right: each transition lands a little later than the last,
// drifting further out with every clip. That is exactly what a unit test is
// for, so the graph is built by a pure function.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/services/media_service.dart';

SequenceClip _clip(String p, double dur, {double start = 0}) =>
    SequenceClip(path: p, start: start, duration: dur);

/// Pulls every `offset=N` out of a built command, in order.
List<double> _offsets(String cmd) => RegExp(r'offset=([\d.]+)')
    .allMatches(cmd)
    .map((m) => double.parse(m.group(1)!))
    .toList();

String _build(
  List<SequenceClip> clips, {
  SequenceTransition transition = SequenceTransition.cut,
  double transitionSec = 0.5,
}) =>
    MediaService.buildSequenceCommand(
      clips,
      outPath: '/tmp/out.mp4',
      width: 1080,
      height: 1920,
      encodeParams: '-c:v libx264',
      transition: transition,
      transitionSec: transitionSec,
    );

void main() {
  group('input handling', () {
    test('a sequence needs at least two clips', () {
      expect(() => _build([_clip('/a.mp4', 5)]), throwsArgumentError);
      expect(() => _build(const []), throwsArgumentError);
    });

    test('each clip becomes its own input, trimmed at the input stage', () {
      final cmd = _build([
        _clip('/a.mp4', 5, start: 2),
        _clip('/b.mp4', 3),
      ]);
      // -ss before -i seeks rather than decoding and discarding.
      expect(cmd, contains('-ss 2.000 -t 5.000 -i "/a.mp4"'));
      // A clip starting at zero needs no seek at all.
      expect(cmd, contains('-t 3.000 -i "/b.mp4"'));
      expect(cmd, isNot(contains('-ss 0.000')));
    });

    test('every clip is normalised to the same canvas before joining', () {
      final cmd = _build([_clip('/a.mp4', 5), _clip('/b.mp4', 5)]);
      expect(RegExp(r'scale=1080:1920').allMatches(cmd).length, 2);
      expect(RegExp(r'fps=30').allMatches(cmd).length, 2);
      expect(RegExp(r'aresample=44100').allMatches(cmd).length, 2);
    });
  });

  group('hard cut', () {
    test('joins with concat and maps the result', () {
      final cmd = _build([
        _clip('/a.mp4', 5),
        _clip('/b.mp4', 3),
        _clip('/c.mp4', 2),
      ]);
      expect(cmd, contains('[v0][a0][v1][a1][v2][a2]concat=n=3:v=1:a=1'));
      expect(cmd, contains('-map "[outv]" -map "[outa]"'));
      expect(cmd, isNot(contains('xfade')));
    });

    test('length is simply the sum', () {
      expect(
        MediaService.sequenceDuration([_clip('/a', 5), _clip('/b', 3)]),
        closeTo(8, 0.001),
      );
    });
  });

  group('transitions', () {
    test('offsets account for the overlap already spent, and do not drift',
        () {
      // 5s + 4s + 3s with a 1s transition. The first join starts at 5-1=4.
      // The second must start at (5+4-1)-1 = 7 — NOT at 5+4-1=8, which is
      // the drift bug this test exists to catch.
      final cmd = _build(
        [_clip('/a', 5), _clip('/b', 4), _clip('/c', 3)],
        transition: SequenceTransition.fade,
        transitionSec: 1.0,
      );
      expect(_offsets(cmd), [4.0, 7.0]);
    });

    test('offsets stay correct over many clips', () {
      final clips = List.generate(6, (i) => _clip('/c$i', 4));
      final cmd = _build(clips,
          transition: SequenceTransition.dissolve, transitionSec: 0.5);
      // Each clip adds 4 - 0.5 = 3.5 to the running position.
      expect(_offsets(cmd), [3.5, 7.0, 10.5, 14.0, 17.5]);
    });

    test('an offset is never negative, even if a clip is shorter than the '
        'transition', () {
      final cmd = _build(
        [_clip('/a', 0.4), _clip('/b', 5)],
        transition: SequenceTransition.fade,
        transitionSec: 1.0,
      );
      expect(_offsets(cmd).first, greaterThanOrEqualTo(0));
    });

    test('video and audio are both crossfaded, and chained through', () {
      final cmd = _build(
        [_clip('/a', 5), _clip('/b', 4), _clip('/c', 3)],
        transition: SequenceTransition.wipeleft,
        transitionSec: 0.5,
      );
      expect(RegExp(r'xfade=').allMatches(cmd).length, 2);
      expect(RegExp(r'acrossfade=').allMatches(cmd).length, 2);
      // Intermediate labels feed the next join; the last one is the output.
      expect(cmd, contains('[vx1]'));
      expect(cmd, contains('[outv]'));
      expect(cmd, contains('-map "[outv]" -map "[outa]"'));
    });

    test('the transition name reaches ffmpeg verbatim', () {
      for (final t in SequenceTransition.values) {
        if (t == SequenceTransition.cut) continue;
        final cmd = _build([_clip('/a', 5), _clip('/b', 5)], transition: t);
        expect(cmd, contains('xfade=transition=${t.name}:'));
        expect(t.labelAr.trim(), isNotEmpty);
      }
    });

    test('each transition shortens the sequence by its own length', () {
      final clips = [_clip('/a', 5), _clip('/b', 4), _clip('/c', 3)];
      expect(
        MediaService.sequenceDuration(clips,
            transition: SequenceTransition.fade, transitionSec: 1.0),
        closeTo(10, 0.001), // 12 total, two joins overlapping 1s each
      );
    });

    test('duration never goes to zero or below on absurd input', () {
      expect(
        MediaService.sequenceDuration(
          [_clip('/a', 0.2), _clip('/b', 0.2)],
          transition: SequenceTransition.fade,
          transitionSec: 3.0,
        ),
        greaterThan(0),
      );
    });
  });

  test('SequenceClip.copyWith changes only what it is given', () {
    const c = SequenceClip(path: '/a.mp4', start: 1, duration: 5);
    expect(c.copyWith(duration: 9).start, 1);
    expect(c.copyWith(duration: 9).duration, 9);
    expect(c.copyWith(start: 2).path, '/a.mp4');
  });
}
