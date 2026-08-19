// PATCH_S126_TEXT_TRANSITIONS: the two rules that decide whether text looks
// smooth or chopped are properties of the motion curve, not of the renderer,
// and neither is visible in a still screenshot:
//
//   * at full progress the motion must be EXACTLY identity — if it isn't, the
//     text never settles where the user placed it, and every ayah sits a few
//     pixels off from where the preview showed it
//   * the curve must be continuous — a jump between adjacent frames IS the
//     chopping, no matter how high the frame rate goes
//
// So both are asserted for all 30 transitions, by sampling each curve at the
// real export frame rate.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/data/text_transitions.dart';
import 'package:ayat_studio_app/models/studio_state.dart';
import 'package:ayat_studio_app/services/export_service.dart';

/// Largest change in any motion channel between two adjacent sampled frames.
double _biggestStep(TextTransition t, int fps, double durationSec) {
  final frames = (fps * durationSec).round();
  var worst = 0.0;
  TextMotion? prev;
  for (var i = 0; i <= frames; i++) {
    final m = textMotionFor(t, i / frames);
    if (prev != null) {
      final deltas = [
        (m.opacity - prev.opacity).abs(),
        (m.dx - prev.dx).abs(),
        (m.dy - prev.dy).abs(),
        (m.scale - prev.scale).abs(),
        (m.rotation - prev.rotation).abs(),
        (m.blur - prev.blur).abs(),
        (m.reveal - prev.reveal).abs(),
      ];
      for (final d in deltas) {
        if (d > worst) worst = d;
      }
    }
    prev = m;
  }
  return worst;
}

void main() {
  final animated =
      TextTransition.values.where((t) => t != TextTransition.none).toList();

  test('there are at least 25 transitions, as asked', () {
    expect(TextTransition.values.length, greaterThanOrEqualTo(25));
    expect(animated.length, greaterThanOrEqualTo(25));
  });

  test('every transition is labelled in both languages, uniquely', () {
    final ar = <String, String>{};
    for (final t in TextTransition.values) {
      expect(t.labelAr.trim(), isNotEmpty, reason: '${t.name} has no label');
      expect(t.labelEn.trim(), isNotEmpty);
      final clash = ar[t.labelAr];
      expect(clash, isNull,
          reason: '${t.name} and $clash share the label "${t.labelAr}"');
      ar[t.labelAr] = t.name;
    }
  });

  test('text settles exactly where it belongs', () {
    for (final t in TextTransition.values) {
      final m = textMotionFor(t, 1.0);
      expect(m.isIdentity, isTrue,
          reason: '${t.name} does not settle to identity at full progress');
      expect(m.opacity, 1.0);
      expect(m.dx, 0.0);
      expect(m.dy, 0.0);
      expect(m.scale, 1.0);
    }
  });

  test('text starts genuinely absent', () {
    for (final t in animated) {
      final m = textMotionFor(t, 0.0);
      final hidden = m.opacity <= 0.02 ||
          (m.revealMode != RevealMode.none && m.reveal <= 0.02);
      expect(hidden, isTrue,
          reason: '${t.name} is already visible at zero progress '
              '(opacity ${m.opacity}, reveal ${m.reveal})');
    }
  });

  test('no transition jumps between frames at the export frame rate', () {
    // The shortest transition the UI allows, at the export frame rate — the
    // worst case the app can actually produce. Over N frames some frame must
    // carry at least 1/N of the travel, so this threshold is only meaningful
    // alongside kMinTextTransitionMs: it says the curves waste no more than
    // ~1.5x of that unavoidable floor at their steepest point.
    final shortestSec = kMinTextTransitionMs / 1000;
    for (final t in animated) {
      final step = _biggestStep(t, ExportService.overlayFps, shortestSec);
      expect(step, lessThan(0.35),
          reason: '${t.name} moves $step in one frame — that is a visible jump');
    }
  });

  test('at a comfortable duration every step is imperceptible', () {
    for (final t in animated) {
      final step = _biggestStep(t, ExportService.overlayFps, 0.55);
      expect(step, lessThan(0.16), reason: '${t.name} steps by $step');
    }
  });

  test('progress is clamped, not extrapolated', () {
    for (final t in TextTransition.values) {
      expect(textMotionFor(t, -5).opacity, lessThanOrEqualTo(1.0));
      expect(textMotionFor(t, 99).isIdentity, isTrue);
    }
  });

  test('opacity and reveal never leave 0..1', () {
    for (final t in TextTransition.values) {
      for (var i = 0; i <= 50; i++) {
        final m = textMotionFor(t, i / 50);
        expect(m.opacity, inInclusiveRange(0.0, 1.0), reason: t.name);
        expect(m.reveal, inInclusiveRange(0.0, 1.0), reason: t.name);
        expect(m.scale, greaterThan(0.0),
            reason: '${t.name} scales to zero — the text would vanish');
      }
    }
  });

  group('the export frame rate is high enough to be smooth', () {
    test('overlay frames are dense enough for the shortest transition', () {
      // A transition has to be drawn in enough distinct frames to read as
      // motion rather than as a few steps.
      final framesInShortest =
          ExportService.overlayFps * kMinTextTransitionMs / 1000;
      expect(framesInShortest, greaterThanOrEqualTo(6),
          reason: 'the shortest transition the UI offers renders in only '
              '$framesInShortest frames');
      // And at the default duration it should be genuinely fluid.
      final s = StudioState();
      final framesDefault =
          ExportService.overlayFps * s.textTransitionMs / 1000;
      expect(framesDefault, greaterThanOrEqualTo(12),
          reason: 'the default transition renders in only $framesDefault '
              'frames — that is what chopping looks like');
    });
  });

  group('defaults', () {
    test('a fresh project has a real transition, not a hard cut', () {
      final s = StudioState();
      expect(s.textInTransition, isNot(TextTransition.none));
      expect(s.hasTextTransition, isTrue);
      expect(s.textTransitionMs,
          inInclusiveRange(kMinTextTransitionMs, kMaxTextTransitionMs));
    });

    test('turning both off is respected', () {
      final s = StudioState()
        ..textInTransition = TextTransition.none
        ..textOutTransition = TextTransition.none;
      expect(s.hasTextTransition, isFalse);
    });
  });

  group('word and letter reveals', () {
    test('every unit is fully hidden at the start and fully lit at the end',
        () {
      for (final count in [1, 2, 3, 9, 27, 140]) {
        for (var i = 0; i < count; i++) {
          expect(revealUnitAlpha(index: i, count: count, progress: 0), 0.0,
              reason: 'unit $i of $count is already visible');
          expect(revealUnitAlpha(index: i, count: count, progress: 1), 1.0,
              reason: 'unit $i of $count never finishes — the last words of '
                  'a long ayah would stay dim');
        }
      }
    });

    test('units light up in order', () {
      const count = 12;
      const p = 0.5;
      var prev = 1.1;
      for (var i = 0; i < count; i++) {
        final a = revealUnitAlpha(index: i, count: count, progress: p);
        expect(a, lessThanOrEqualTo(prev),
            reason: 'unit $i is ahead of unit ${i - 1}');
        prev = a;
      }
      // And it is genuinely sequential, not a uniform fade.
      expect(revealUnitAlpha(index: 0, count: count, progress: p),
          greaterThan(revealUnitAlpha(index: count - 1, count: count, progress: p)));
    });

    test('no single word pops on in one frame', () {
      // The per-block curve being smooth is not enough: each word has its own
      // ramp, and a word that goes from invisible to lit between two frames
      // is exactly the stutter this is meant to avoid.
      for (final count in [1, 2, 5, 14, 40, 200]) {
        for (final (frames, limit) in [(6, 0.35), (13, 0.16)]) {
          for (var i = 0; i < count; i++) {
            var prev = revealUnitAlpha(index: i, count: count, progress: 0);
            for (var f = 1; f <= frames; f++) {
              final a =
                  revealUnitAlpha(index: i, count: count, progress: f / frames);
              expect((a - prev).abs(), lessThan(limit),
                  reason: 'unit $i of $count jumps ${(a - prev).abs()} in one '
                      'frame of a $frames-frame transition');
              prev = a;
            }
          }
        }
      }
    });
  });

  test('reveal transitions are flagged as such', () {
    expect(TextTransition.typewriterWords.isReveal, isTrue);
    expect(TextTransition.irisOpen.isReveal, isTrue);
    expect(TextTransition.fade.isReveal, isFalse);
    expect(TextTransition.springUp.isReveal, isFalse);
  });
}
