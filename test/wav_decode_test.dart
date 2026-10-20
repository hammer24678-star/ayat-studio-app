// PATCH_S201_WHISPER_AUDIT: regression test for the PCM reader. It used to
// return only the first half of a clip's samples (and throw when the sample
// count was odd), so auto-sync never heard the second half of a recording.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/services/timeline_builder.dart';

/// A 16 kHz mono 16-bit WAV holding [samples]. [listBytes] > 0 puts a LIST
/// chunk of that many payload bytes before `data`, like ffmpeg's encoder tag.
Uint8List makeWav(List<int> samples, {int listBytes = 0}) {
  final pcm = Int16List.fromList(samples);
  final dataLen = pcm.lengthInBytes;
  final listPad = listBytes.isOdd ? 1 : 0;
  final listTotal = listBytes > 0 ? 8 + listBytes + listPad : 0;
  final out = BytesBuilder();
  void ascii(String s) => out.add(s.codeUnits);
  void u32(int v) =>
      out.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) =>
      out.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());

  ascii('RIFF');
  u32(4 + 24 + listTotal + 8 + dataLen);
  ascii('WAVE');
  ascii('fmt ');
  u32(16);
  u16(1); // PCM
  u16(1); // mono
  u32(16000);
  u32(32000);
  u16(2);
  u16(16);
  if (listBytes > 0) {
    ascii('LIST');
    u32(listBytes);
    out.add(List<int>.filled(listBytes + listPad, 0));
  }
  ascii('data');
  u32(dataLen);
  out.add(pcm.buffer.asUint8List(pcm.offsetInBytes, dataLen));
  return out.takeBytes();
}

List<int> ramp(int n) => List<int>.generate(n, (i) => (i * 37) % 30000 - 15000);

void main() {
  group('TimelineBuilder.decodeWavMono16', () {
    test('returns every sample of an even-length clip', () {
      final samples = ramp(1000);
      final out = TimelineBuilder.decodeWavMono16(makeWav(samples));
      expect(out.length, 1000);
      expect(out.toList(), orderedEquals(samples));
    });

    test('returns every sample of an odd-length clip (used to throw)', () {
      final samples = ramp(1001);
      final out = TimelineBuilder.decodeWavMono16(makeWav(samples));
      expect(out.length, 1001);
      expect(out.last, samples.last);
    });

    test('skips a LIST chunk (odd size, padded) before the data chunk', () {
      final samples = ramp(777);
      final out =
          TimelineBuilder.decodeWavMono16(makeWav(samples, listBytes: 13));
      expect(out.toList(), orderedEquals(samples));
    });

    test('rejects something that is not a WAV', () {
      expect(() => TimelineBuilder.decodeWavMono16(Uint8List(64)),
          throwsException);
    });
  });
}
