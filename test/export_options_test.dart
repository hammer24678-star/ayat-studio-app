// PATCH_S123_WATERMARK + PATCH_S123_AUDIO_MIX: the new export options are
// only correct if they default to doing nothing. A watermark that ships on
// by default, or an audio mix that quietly changes what a previously-working
// export sounds like, would be a worse bug than either feature is a feature.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/data/studio_presets.dart';
import 'package:ayat_studio_app/models/studio_state.dart';

void main() {
  group('watermark defaults to absent', () {
    test('a fresh project exports with no watermark', () {
      final state = StudioState();
      expect(state.watermarkEnabled, isFalse);
      expect(state.hasWatermark, isFalse);
      expect(state.watermarkImagePath, isNull);
      expect(state.watermarkText, isEmpty);
    });

    test('the switch alone is not enough — there has to be something to draw',
        () {
      final state = StudioState()..watermarkEnabled = true;
      expect(state.hasWatermark, isFalse,
          reason: 'enabled with no text and no image draws nothing');

      state.watermarkText = '   ';
      expect(state.hasWatermark, isFalse, reason: 'whitespace is not a mark');

      state.watermarkText = 'قناة نور';
      expect(state.hasWatermark, isTrue);
    });

    test('an image counts even with no text, and wins over it', () {
      final state = StudioState()
        ..watermarkEnabled = true
        ..watermarkImagePath = '/tmp/logo.png';
      expect(state.hasWatermark, isTrue);
    });

    test('turning the switch back off disables it regardless of content', () {
      final state = StudioState()
        ..watermarkEnabled = true
        ..watermarkText = 'قناة نور'
        ..watermarkImagePath = '/tmp/logo.png';
      expect(state.hasWatermark, isTrue);
      state.watermarkEnabled = false;
      expect(state.hasWatermark, isFalse);
    });
  });

  group('audio defaults preserve the old behaviour', () {
    test('a reciter track replaces the clip audio unless asked otherwise', () {
      final state = StudioState();
      expect(state.originalAudioMix, 0.0);
      expect(state.muteAudio, isFalse);
    });
  });

  group('undo/redo covers the new options', () {
    test('restores watermark and audio settings together', () {
      final state = StudioState();
      state.update(() {
        state.watermarkEnabled = true;
        state.watermarkText = 'قناة نور';
        state.watermarkCorner = WatermarkCorner.topLeft;
        state.watermarkOpacity = 0.4;
        state.watermarkScale = 0.3;
        state.originalAudioMix = 0.35;
        state.muteAudio = true;
      });
      expect(state.canUndo, isTrue);

      state.undoStep();
      expect(state.watermarkEnabled, isFalse);
      expect(state.watermarkText, isEmpty);
      expect(state.watermarkCorner, WatermarkCorner.bottomRight);
      expect(state.originalAudioMix, 0.0);
      expect(state.muteAudio, isFalse);

      state.redoStep();
      expect(state.watermarkEnabled, isTrue);
      expect(state.watermarkText, 'قناة نور');
      expect(state.watermarkCorner, WatermarkCorner.topLeft);
      expect(state.watermarkOpacity, 0.4);
      expect(state.watermarkScale, 0.3);
      expect(state.originalAudioMix, 0.35);
      expect(state.muteAudio, isTrue);
    });
  });
}
