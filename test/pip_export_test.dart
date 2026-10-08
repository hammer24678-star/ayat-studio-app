// PATCH_S188_PIP: the PIP geometry + the ffmpeg graph it adds.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/models/pip_clip.dart';
import 'package:ayat_studio_app/models/studio_state.dart';
import 'package:ayat_studio_app/services/pip_export.dart';

PipClip _clip({
  bool image = false,
  double start = 2,
  double end = 6,
  double mediaDur = 3,
  PipShape shape = PipShape.rect,
}) =>
    PipClip(
      path: '/tmp/x.mp4',
      isImage: image,
      aspect: 16 / 9,
      mediaDur: image ? 0 : mediaDur,
      start: start,
      end: end,
      shape: shape,
    );

void main() {
  test('alpha: 0 outside, soft at the ends, full in the middle', () {
    final c = _clip();
    expect(c.alphaAt(1.9), 0);
    expect(c.alphaAt(6.0), 0);
    expect(c.alphaAt(2.0), 0);
    expect(c.alphaAt(2.15), inInclusiveRange(0.1, 0.9));
    expect(c.alphaAt(4.0), 1);
  });

  test('mediaTimeAt loops short videos', () {
    final c = _clip(mediaDur: 3);
    expect(c.mediaTimeAt(2.0), closeTo(0, 1e-9));
    expect(c.mediaTimeAt(4.0), closeTo(2, 1e-9));
    expect(c.mediaTimeAt(5.5), closeTo(0.5, 1e-9));
  });

  test('circle is always square', () {
    expect(_clip(shape: PipShape.circle).boxAspect, 1.0);
  });

  test('plan: even sizes, window shifted by clipStart, tiny clips dropped', () {
    final st = StudioState();
    st.pipClips = [_clip(), _clip(start: 20, end: 20.05)];
    final p = PipExport.plan(st, 1080, 1920, 1.0, 10.0, null);
    expect(p.length, 1);
    expect(p.first.ws, closeTo(1.0, 1e-9));
    expect(p.first.we, closeTo(5.0, 1e-9));
    expect(p.first.pw.isEven && p.first.ph.isEven, isTrue);
  });

  test('graph: every label consumed is produced; inputs line up', () {
    final st = StudioState();
    st.pipClips = [
      _clip(shape: PipShape.circle),
      _clip(image: true, start: 1, end: 3),
    ];
    final inputs = StringBuffer('-y -i main.mp4 ');
    final filters = <String>[];
    final prep = PipExportPrep(
      masks: {st.pipClips[0].id: '/tmp/m0.png'},
    );
    final r = PipExport.append(
      inputs: inputs,
      filters: filters,
      idx: 1,
      base: 'base',
      st: st,
      w: 1080,
      h: 1920,
      clipStart: 0,
      duration: 10,
      fps: 30,
      prep: prep,
    );
    expect(r.base, 'pipo1');
    final nInputs = RegExp(r' -i ').allMatches(' ${inputs.toString()}').length;
    expect(r.idx, nInputs);
    final produced = <String>{'base'};
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
          expect(int.parse(l.split(':').first) < r.idx, isTrue, reason: l);
        } else {
          expect(produced.contains(l), isTrue, reason: l);
        }
      }
    }
  });
}
