// PATCH_S195_AUDIO_TAB: the Audio tab - geometry, the timeline state, and the
// ffmpeg graph it adds to the export.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/models/audio_clip.dart';
import 'package:ayat_studio_app/models/studio_state.dart';
import 'package:ayat_studio_app/services/audio_clips_export.dart';

AudioClip _clip({
  double start = 2,
  double end = 8,
  double mediaDur = 10,
  double srcIn = 0,
  double volume = 1.0,
  double fadeIn = 0,
  double fadeOut = 0,
  bool loop = false,
}) =>
    AudioClip(
      path: '/tmp/s.mp3',
      name: 's',
      mediaDur: mediaDur,
      start: start,
      end: end,
      srcIn: srcIn,
      volume: volume,
      fadeIn: fadeIn,
      fadeOut: fadeOut,
      loop: loop,
    );

void _checkGraph(List<String> filters, Set<String> given, int nextIdx) {
  final produced = <String>{...given};
  for (final f in filters) {
    final tail = RegExp(r'\[([^\]]+)\]$').firstMatch(f);
    if (tail != null) produced.add(tail.group(1)!);
  }
  for (final f in filters) {
    final lead = RegExp(r'^((?:\[[^\]]+\])+)').firstMatch(f);
    if (lead == null) continue;
    for (final m in RegExp(r'\[([^\]]+)\]').allMatches(lead.group(1)!)) {
      final l = m.group(1)!;
      if (RegExp(r'^\d+:').hasMatch(l)) {
        expect(int.parse(l.split(':').first) < nextIdx, isTrue, reason: l);
      } else {
        expect(produced.contains(l), isTrue, reason: l);
      }
    }
  }
}

void main() {
  test('gain: silent outside, fades in and out, full in the middle', () {
    final c = _clip(volume: 0.8, fadeIn: 1, fadeOut: 2);
    expect(c.gainAt(1.9), 0);
    expect(c.gainAt(8.0), 0);
    expect(c.gainAt(2.0), 0);
    expect(c.gainAt(2.5), closeTo(0.4, 1e-9));
    expect(c.gainAt(5.0), closeTo(0.8, 1e-9));
    expect(c.gainAt(7.0), closeTo(0.4, 1e-9));
    c.muted = true;
    expect(c.gainAt(5.0), 0);
  });

  test('fades never exceed half the sound', () {
    final c = _clip(start: 0, end: 2, fadeIn: 5, fadeOut: 5);
    expect(c.fadeInLen, closeTo(1, 1e-9));
    expect(c.fadeOutLen, closeTo(1, 1e-9));
  });

  test('mediaTimeAt: offsets, loops, and stops at the end of the media', () {
    final c = _clip(mediaDur: 3, srcIn: 1, end: 12, loop: true);
    expect(c.mediaTimeAt(2.0), closeTo(1, 1e-9));
    expect(c.mediaTimeAt(4.0), closeTo(0, 1e-9));
    expect(c.playsAt(11.0), isTrue);
    final n = _clip(mediaDur: 3, end: 12);
    expect(n.playsAt(3.0), isTrue);
    expect(n.playsAt(6.0), isFalse);
  });

  test('rows: overlapping sounds stack, a free row is reused', () {
    final a = _clip(start: 0, end: 5);
    final b = _clip(start: 2, end: 6);
    final c = _clip(start: 5, end: 9);
    expect(assignAudioRows([a, b, c]), [0, 1, 0]);
  });

  test('state: add, split keeps the tail in step, remove', () {
    final st = StudioState();
    st.addAudio(_clip());
    expect(st.audioClips.length, 1);
    expect(st.hasAudioSel, isTrue);
    expect(st.splitAudioAt(0, 5), isTrue);
    expect(st.audioClips.length, 2);
    expect(st.audioClips[0].end, 5);
    expect(st.audioClips[1].start, 5);
    expect(st.audioClips[1].srcIn, closeTo(3, 1e-9));
    expect(st.splitAudioAt(0, 5.05), isFalse);
    st.removeAudioAt(0);
    expect(st.audioClips.length, 1);
    expect(st.hasAudioSel, isFalse);
  });

  test('state: trimming the start moves the media with it', () {
    final st = StudioState();
    st.addAudio(_clip());
    st.setAudioWindow(0, start: 4);
    expect(st.audioClips[0].start, 4);
    expect(st.audioClips[0].srcIn, closeTo(2, 1e-9));
    st.setAudioWindow(0, end: 4.1);
    expect(st.audioClips[0].end - st.audioClips[0].start,
        greaterThanOrEqualTo(kAudioMinLen - 1e-9));
  });

  test('state: a silent export has no sounds to mix', () {
    final st = StudioState();
    st.addAudio(_clip());
    expect(st.hasAudioClips, isTrue);
    st.muteAudio = true;
    expect(st.hasAudioClips, isFalse);
  });

  test('plan: shifted by clipStart, divided by speed, tiny ones dropped', () {
    final st = StudioState();
    st.audioClips = [
      _clip(start: 3, end: 7, mediaDur: 30),
      _clip(start: 20, end: 20.05),
      _clip(start: 1, end: 4, mediaDur: 30),
    ];
    final p = AudioClipsExport.plan(st, 2.0, 10.0, 2.0, null);
    expect(p.length, 2);
    expect(p[0].ws, closeTo(0.5, 1e-9));
    expect(p[0].we, closeTo(2.5, 1e-9));
    expect(p[0].ss, closeTo(0, 1e-9));
    expect(p[1].ws, 0);
    expect(p[1].we, closeTo(1.0, 1e-9));
    expect(p[1].ss, closeTo(1.0, 1e-9));
  });

  test('plan: a sound shorter than its window ends early', () {
    final st = StudioState();
    st.audioClips = [_clip(start: 1, end: 9, mediaDur: 3)];
    final p = AudioClipsExport.plan(st, 0, 10, 1.0, null);
    expect(p.single.we, closeTo(4, 1e-9));
  });

  test('graph: raw main stream, labels line up, volume / fades / delay', () {
    final st = StudioState();
    st.audioClips = [
      _clip(volume: 0.5, fadeIn: 0.5, fadeOut: 1),
      _clip(start: 1, end: 4, loop: true, mediaDur: 1),
    ];
    final inputs = StringBuffer('-y -i main.mp4 ');
    final filters = <String>[];
    final r = AudioClipsExport.append(
      inputs: inputs,
      filters: filters,
      idx: 1,
      st: st,
      clipStart: 0,
      duration: 10,
      outDuration: 10,
      speed: 1.0,
      aLabel: null,
      aStream: '0:a',
      aChain: <String>['volume=1.000'],
    )!;
    expect(r.label, 'aclips');
    final nInputs = RegExp(r' -i ').allMatches(' ${inputs.toString()}').length;
    expect(r.idx, nInputs);
    final all = filters.join(';');
    expect(all, contains('volume=0.500'));
    expect(all, contains('afade=t=in'));
    expect(all, contains('afade=t=out'));
    expect(all, contains('adelay=2000|2000'));
    expect(all, contains('amix=inputs=3'));
    expect(inputs.toString(), contains('-stream_loop -1'));
    _checkGraph(filters, <String>{}, r.idx);
  });

  test('graph: mixes over an existing label', () {
    final st = StudioState();
    st.audioClips = [_clip()];
    final inputs = StringBuffer('-y -i main.mp4 ');
    final filters = <String>[];
    final r = AudioClipsExport.append(
      inputs: inputs,
      filters: filters,
      idx: 1,
      st: st,
      clipStart: 0,
      duration: 10,
      outDuration: 10,
      speed: 1.0,
      aLabel: 'abedmix',
      aStream: null,
      aChain: <String>[],
    )!;
    expect(r.idx, 2);
    expect(filters.last, startsWith('[abedmix][acl0]amix=inputs=2'));
    _checkGraph(filters, <String>{'abedmix'}, r.idx);
  });

  test('append: nothing to add returns null', () {
    final st = StudioState();
    final r = AudioClipsExport.append(
      inputs: StringBuffer(),
      filters: <String>[],
      idx: 1,
      st: st,
      clipStart: 0,
      duration: 10,
      outDuration: 10,
      speed: 1.0,
      aLabel: 'x',
      aStream: null,
      aChain: <String>[],
    );
    expect(r, isNull);
  });
}
