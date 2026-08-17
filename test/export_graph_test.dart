// PATCH_S125_GRAPH_TEST: the export filtergraph is a single string that
// ffmpeg either accepts or rejects, and it is only ever validated at runtime
// — on a phone, at the end of a long render. A typo'd label there doesn't
// degrade the output, it loses the whole export.
//
// Three features have now been layered onto that graph (an optional
// watermark, audio mixing under a reciter, and a speed change), each adding
// inputs and labels. These tests check the graph the way ffmpeg's parser
// does — structurally — without needing an encoder:
//
//   * every label that is CONSUMED is also PRODUCED, exactly once
//   * every input index referenced actually exists among the -i arguments
//   * the mapped output labels exist
//
// Those three cover essentially every way a hand-assembled filtergraph
// breaks.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/data/studio_presets.dart';
import 'package:ayat_studio_app/models/studio_state.dart';
import 'package:ayat_studio_app/services/export_service.dart';

/// The `-filter_complex "..."` payload.
String _graph(String cmd) {
  final m = RegExp(r'-filter_complex "(.*?)" ', dotAll: true).firstMatch(cmd);
  expect(m, isNotNull, reason: 'no -filter_complex in:\n$cmd');
  return m!.group(1)!;
}

/// Labels a filter chain reads, e.g. `[base]` on the left of a chain.
/// Stream references like `[0:v]` are inputs, not labels, so they're excluded.
Set<String> _consumed(String graph) {
  final out = <String>{};
  for (final chain in graph.split(';')) {
    // Leading [x][y] before the filter name.
    final lead = RegExp(r'^((?:\[[^\]]+\])+)').firstMatch(chain);
    if (lead == null) continue;
    for (final m in RegExp(r'\[([^\]]+)\]').allMatches(lead.group(1)!)) {
      final label = m.group(1)!;
      if (!RegExp(r'^\d+:').hasMatch(label)) out.add(label);
    }
  }
  return out;
}

/// Labels a chain writes, i.e. the trailing [x] of each chain.
List<String> _produced(String graph) {
  final out = <String>[];
  for (final chain in graph.split(';')) {
    final tail = RegExp(r'((?:\[[^\]]+\])+)$').firstMatch(chain.trim());
    if (tail == null) continue;
    for (final m in RegExp(r'\[([^\]]+)\]').allMatches(tail.group(1)!)) {
      final label = m.group(1)!;
      if (!RegExp(r'^\d+:').hasMatch(label)) out.add(label);
    }
  }
  return out;
}

/// Input stream indices the graph reads, e.g. 0 from `[0:v]`.
Set<int> _inputRefs(String graph) => RegExp(r'\[(\d+):[av]\]')
    .allMatches(graph)
    .map((m) => int.parse(m.group(1)!))
    .toSet();

int _inputCount(String cmd) => RegExp(r'-i ').allMatches(cmd).length;

Set<String> _mapped(String cmd) => RegExp(r'-map "\[([^\]]+)\]"')
    .allMatches(cmd)
    .map((m) => m.group(1)!)
    .toSet();

void assertGraphIsSound(String cmd, {required String what}) {
  final graph = _graph(cmd);
  final produced = _produced(graph);
  final producedSet = produced.toSet();

  // A label produced twice is ambiguous and ffmpeg rejects it.
  expect(producedSet.length, produced.length,
      reason: '$what: a label is produced more than once in:\n$graph');

  for (final label in _consumed(graph)) {
    expect(producedSet, contains(label),
        reason: '$what: chain reads [$label] but nothing produces it:\n$graph');
  }

  final inputs = _inputCount(cmd);
  for (final i in _inputRefs(graph)) {
    expect(i, lessThan(inputs),
        reason: '$what: graph reads input $i but only $inputs are declared');
  }

  for (final label in _mapped(cmd)) {
    expect(producedSet, contains(label),
        reason: '$what: -map "[$label]" but nothing produces it:\n$graph');
  }
}

String build(StudioState state, {
  String? overlayPng,
  String? overlaySeq,
  String? effectSeq,
  String? watermarkPng,
  String? reciterPath,
  bool videoHasAudio = true,
  bool videoHasVideoStream = true,
}) =>
    ExportService.buildMainCommand(
      state: state,
      w: 1080,
      h: 1920,
      duration: 30,
      clipStart: 0,
      bgPng: '/tmp/bg.png',
      bgSegments: null,
      overlaySeqPattern: overlaySeq,
      overlayPng: overlayPng,
      effectSeqPattern: effectSeq,
      watermarkPng: watermarkPng,
      reciterPath: reciterPath,
      videoHasAudio: videoHasAudio,
      videoHasVideoStream: videoHasVideoStream,
      outPath: '/tmp/out.mp4',
    );

StudioState withVideo() => StudioState()..videoPath = '/tmp/in.mp4';

void main() {
  group('the graph is structurally sound', () {
    test('a plain video export', () {
      assertGraphIsSound(build(withVideo(), overlayPng: '/tmp/ov.png'),
          what: 'plain');
    });

    test('a static (no video) export', () {
      assertGraphIsSound(
        build(StudioState(),
            overlayPng: '/tmp/ov.png',
            videoHasAudio: false,
            videoHasVideoStream: false),
        what: 'static',
      );
    });

    test('with a karaoke overlay sequence', () {
      assertGraphIsSound(build(withVideo(), overlaySeq: '/tmp/ov_%04d.png'),
          what: 'karaoke');
    });

    test('with a particle effect layer', () {
      assertGraphIsSound(
        build(withVideo(),
            overlayPng: '/tmp/ov.png', effectSeq: '/tmp/fx_%03d.png'),
        what: 'effects',
      );
    });

    test('with a watermark', () {
      assertGraphIsSound(
        build(withVideo(),
            overlayPng: '/tmp/ov.png', watermarkPng: '/tmp/wm.png'),
        what: 'watermark',
      );
    });

    test('with a reciter track', () {
      assertGraphIsSound(
        build(withVideo(),
            overlayPng: '/tmp/ov.png', reciterPath: '/tmp/rec.mp3'),
        what: 'reciter',
      );
    });

    test('with the clip audio mixed under the reciter', () {
      final s = withVideo()..originalAudioMix = 0.4;
      assertGraphIsSound(
        build(s, overlayPng: '/tmp/ov.png', reciterPath: '/tmp/rec.mp3'),
        what: 'audio mix',
      );
    });

    test('with a speed change', () {
      final s = withVideo()..playbackSpeed = 2.0;
      assertGraphIsSound(build(s, overlayPng: '/tmp/ov.png'), what: 'speed');
    });

    test('with a slow-motion speed change', () {
      final s = withVideo()..playbackSpeed = 0.5;
      assertGraphIsSound(build(s, overlayPng: '/tmp/ov.png'), what: 'slow-mo');
    });

    test('muted export', () {
      final s = withVideo()..muteAudio = true;
      assertGraphIsSound(build(s, overlayPng: '/tmp/ov.png'), what: 'muted');
    });

    test('chroma key onto a background', () {
      final s = withVideo()..chromaEnabled = true;
      assertGraphIsSound(build(s, overlayPng: '/tmp/ov.png'), what: 'chroma');
    });

    test('everything at once', () {
      final s = withVideo()
        ..chromaEnabled = true
        ..playbackSpeed = 1.5
        ..originalAudioMix = 0.3
        ..colorGrade = ColorGrade.warmGold
        ..vignetteEnabled = true
        ..grainEnabled = true
        ..showIntro = true
        ..showOutro = true
        ..softTransitions = true
        ..videoFit = VideoFitMode.fitBlur;
      assertGraphIsSound(
        build(s,
            overlaySeq: '/tmp/ov_%04d.png',
            effectSeq: '/tmp/fx_%03d.png',
            watermarkPng: '/tmp/wm.png',
            reciterPath: '/tmp/rec.mp3'),
        what: 'everything',
      );
    });
  });

  group('the features actually reach the command', () {
    test('a watermark adds an input and an overlay pass', () {
      final without = build(withVideo(), overlayPng: '/tmp/ov.png');
      final with_ = build(withVideo(),
          overlayPng: '/tmp/ov.png', watermarkPng: '/tmp/wm.png');
      expect(_inputCount(with_), _inputCount(without) + 1);
      expect(with_, contains('/tmp/wm.png'));
    });

    test('no watermark means nothing is added at all', () {
      final cmd = build(withVideo(), overlayPng: '/tmp/ov.png');
      expect(cmd, isNot(contains('wmf')));
    });

    test('speed adds setpts and shortens -t by the same factor', () {
      final s = withVideo()..playbackSpeed = 2.0;
      final cmd = build(s, overlayPng: '/tmp/ov.png');
      expect(cmd, contains('setpts=PTS/2.0000'));
      // 30s at 2x is 15s of output.
      expect(cmd, contains('-t 15.000'));
    });

    test('1x adds no setpts and leaves the duration alone', () {
      final cmd = build(withVideo(), overlayPng: '/tmp/ov.png');
      expect(cmd, isNot(contains('setpts=PTS/')));
      expect(cmd, contains('-t 30.000'));
    });

    test('a reciter track is not retimed by the speed change', () {
      final s = withVideo()..playbackSpeed = 2.0;
      final cmd =
          build(s, overlayPng: '/tmp/ov.png', reciterPath: '/tmp/rec.mp3');
      expect(cmd, contains('setpts=PTS/2.0000'),
          reason: 'the picture should still be sped up');
      expect(cmd, isNot(contains('atempo')),
          reason: 'pitching up a recitation is exactly what must not happen');
    });

    test('the clip audio IS retimed when there is no reciter', () {
      final s = withVideo()..playbackSpeed = 2.0;
      expect(build(s, overlayPng: '/tmp/ov.png'), contains('atempo'));
    });

    test('a muted export still writes a real silent track', () {
      // The intro/outro concat runs with -c copy and refuses segments whose
      // stream layouts differ, so -an would break a clip with title cards.
      final s = withVideo()..muteAudio = true;
      final cmd = build(s, overlayPng: '/tmp/ov.png');
      expect(cmd, contains('anullsrc'));
      expect(cmd, isNot(contains(' -an ')));
    });

    test('a custom frame size reaches the scaler', () {
      final s = withVideo()
        ..aspectRatio = AyatAspectRatio.custom
        ..customAspectW = 720
        ..customAspectH = 900
        ..videoFit = VideoFitMode.fillCrop;
      // buildMainCommand takes w/h from the caller, so this asserts the
      // source of those numbers rather than the command itself.
      expect(s.frameSize, (720, 900));
    });
  });
}
