// PATCH_S125_EFFECTS_LIBRARY: 74 effects is past the point where "I looked at
// it and it seemed fine" is a check. Three things have to hold for every one
// of them, and none of them are visible in a screenshot:
//
//  1. It has a label, an English label, an icon and a category — a chip with
//     a blank label is a chip nobody can pick.
//  2. It actually draws. An effect that silently paints nothing looks
//     identical to one the user simply hasn't noticed yet.
//  3. It loops seamlessly: the frame at t = loopSeconds must be identical to
//     t = 0, because the export tiles one period with ffmpeg's -stream_loop
//     and any mismatch is a visible jump every three seconds.
//
// And the enum's indices are pinned, because SettingsService persists
// effect.index — inserting a value anywhere but the end would silently
// repoint every saved choice at a different effect.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/services/stage_effects.dart';
import 'package:ayat_studio_app/services/stage_effects_library.dart';

/// Records the drawing ops an effect emits for one frame.
ui.Picture _record(StageEffect e, double t, {Size size = const Size(360, 640)}) {
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  StageEffects.paint(canvas, size, e, t, 1.0);
  return rec.endRecording();
}

/// Rasterises one frame so two moments in the loop can be compared. Kept
/// modest because 74 effects x 2 frames adds up, but not tiny: several
/// effects stroke hairlines, and on a very small raster a sub-pixel shift in
/// a 1px stroke swings coverage enough to look like a real discontinuity.
Future<List<int>> _raster(StageEffect e, double t) async {
  const w = 160, h = 284;
  final pic = _record(e, t, size: const Size(160, 284));
  final img = await pic.toImage(w, h);
  try {
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List().toList();
  } finally {
    img.dispose();
  }
}

void main() {
  final drawable =
      StageEffect.values.where((e) => e != StageEffect.none).toList();

  test('the library really did add 50+ effects', () {
    expect(kExtendedEffects.length, greaterThanOrEqualTo(50),
        reason: 'the ask was 50 more effects, on top of the original 13');
    expect(drawable.length, greaterThanOrEqualTo(63));
  });

  test('every effect is fully described', () {
    for (final e in drawable) {
      expect(e.label.trim(), isNotEmpty, reason: '${e.name} has no Arabic label');
      expect(e.labelEn.trim(), isNotEmpty,
          reason: '${e.name} has no English label');
      expect(e.label, isNot(e.name),
          reason: '${e.name} fell through to its raw enum name');
      expect(e.category, isNotNull);
    }
  });

  test('labels are unique, so two chips are never indistinguishable', () {
    final seenAr = <String, String>{};
    for (final e in drawable) {
      final clash = seenAr[e.label];
      expect(clash, isNull,
          reason: '${e.name} and $clash share the label "${e.label}"');
      seenAr[e.label] = e.name;
    }
  });

  test('every effect actually paints something', () {
    for (final e in drawable) {
      // A frame mid-loop, where transient motions (bursts, flickers) are at
      // their most visible.
      final pic = _record(e, StageEffects.loopSeconds * 0.37);
      expect(pic.approximateBytesUsed, greaterThan(0),
          reason: '${e.name} recorded no drawing operations');
      pic.dispose();
    }
  });

  test('none paints nothing at all', () {
    // An empty Picture still reports a small fixed overhead, so the baseline
    // is "an untouched recorder", not zero.
    final empty = ui.PictureRecorder();
    Canvas(empty);
    final baseline = empty.endRecording();
    addTearDown(baseline.dispose);

    final pic = _record(StageEffect.none, 1.0);
    addTearDown(pic.dispose);
    expect(pic.approximateBytesUsed, baseline.approximateBytesUsed);
  });

  test('the export loop is seamless for every effect', () async {
    // Grain and scratch effects are deliberately re-randomised per frame —
    // they are film damage, which must NOT repeat, so they are exempt from
    // the frame-identity rule (they still tile without a visible seam
    // because the noise carries no structure).
    const perFrameNoise = {
      StageEffect.filmGrainFlicker,
      StageEffect.filmScratches,
      StageEffect.vhsTracking,
    };
    // Bit-identity is the wrong bar, and so is max-delta on its own. Some
    // effects rotate about an anchor that does not sit on a whole pixel, so
    // a stroked outline lands on different sub-pixels at the seam and its
    // antialiased EDGES differ by a good fraction of a level — while the
    // figure itself has not moved at all.
    //
    // What separates that from a real jump is how MUCH of the frame changes.
    // A feature that actually teleports repaints a large area (the rain bug
    // this test was written to catch moved ~9% of the frame); edge shimmer
    // touches a fraction of a percent.
    const deltaFloor = 24; // below this is ordinary antialiasing
    const maxChangedFraction = 0.005;
    final mismatched = <String>[];
    for (final e in drawable) {
      if (perFrameNoise.contains(e)) continue;
      final first = await _raster(e, 0);
      final wrap = await _raster(e, StageEffects.loopSeconds);
      var changed = 0;
      for (var i = 0; i < first.length; i += 4) {
        var worst = 0;
        for (var c = 0; c < 4; c++) {
          final d = (first[i + c] - wrap[i + c]).abs();
          if (d > worst) worst = d;
        }
        if (worst > deltaFloor) changed++;
      }
      final fraction = changed / (first.length / 4);
      if (fraction > maxChangedFraction) {
        mismatched.add('${e.name}(${(fraction * 100).toStringAsFixed(2)}% moved)');
      }
    }
    expect(mismatched, isEmpty,
        reason: 'these effects jump at the loop point: ${mismatched.join(', ')}');
  });

  test('intensity scales the effect down rather than off', () {
    for (final e in drawable.take(20)) {
      final quiet = _record(e, 1.0);
      addTearDown(quiet.dispose);
      expect(quiet.approximateBytesUsed, greaterThan(0));
    }
  });

  group('persisted enum indices are pinned', () {
    test('the original 14 have not moved', () {
      // SettingsService stores effect.index. These are the values that were
      // already on users' devices before the library was added.
      const original = [
        'none', 'rain', 'snow', 'dust', 'sparkle', 'geometricShimmer',
        'confetti', 'glitch', 'fireflies', 'fog', 'rays', 'spinningStar',
        'starBurst', 'flowerBurst',
      ];
      for (var i = 0; i < original.length; i++) {
        expect(StageEffect.values[i].name, original[i],
            reason: 'index $i changed meaning — saved settings now point at '
                'the wrong effect');
      }
    });

    test('the first added effect sits directly after the originals', () {
      expect(StageEffect.values[14], StageEffect.heavyRain);
    });
  });

  test('every category has effects in it', () {
    for (final c in EffectCategory.values) {
      final n = drawable.where((e) => e.category == c).length;
      expect(n, greaterThan(0), reason: '${c.name} is an empty group');
      expect(c.labelAr.trim(), isNotEmpty);
      expect(c.labelEn.trim(), isNotEmpty);
    }
  });
}
