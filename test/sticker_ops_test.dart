// PATCH_S206_STICKERS
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ayat_studio_app/services/sticker_ops.dart';

RgbaImage _solid(int w, int h, int r, int g, int b, [int a = 255]) {
  final px = Uint8List(w * h * 4);
  for (var i = 0; i < w * h; i++) {
    px[i * 4] = r;
    px[i * 4 + 1] = g;
    px[i * 4 + 2] = b;
    px[i * 4 + 3] = a;
  }
  return RgbaImage(w, h, px);
}

void _set(RgbaImage s, int x, int y, int r, int g, int b) {
  final i = (y * s.w + x) * 4;
  s.px[i] = r;
  s.px[i + 1] = g;
  s.px[i + 2] = b;
  s.px[i + 3] = 255;
}

int _alpha(RgbaImage s, int x, int y) => s.px[(y * s.w + x) * 4 + 3];

void main() {
  test('crop keeps the right pixels', () {
    final s = _solid(10, 10, 0, 0, 0);
    _set(s, 4, 3, 200, 10, 20);
    final c = cropRgba(s, 4, 3, 3, 2);
    expect(c.w, 3);
    expect(c.h, 2);
    expect(c.px[0], 200);
  });

  test('rotate90 turns clockwise and swaps the size', () {
    final s = _solid(3, 2, 0, 0, 0);
    _set(s, 0, 0, 255, 0, 0); // top-left
    final r = rotate90(s);
    expect(r.w, 2);
    expect(r.h, 3);
    // top-left goes to top-right
    expect(r.px[(0 * r.w + 1) * 4], 255);
  });

  test('flip horizontal moves a left pixel to the right', () {
    final s = _solid(4, 1, 0, 0, 0);
    _set(s, 0, 0, 9, 9, 9);
    final f = flipRgba(s, horizontal: true);
    expect(f.px[3 * 4], 9);
    expect(f.px[0], 0);
  });

  test('background removal clears the outside but keeps an inner white spot', () {
    final s = _solid(20, 20, 255, 255, 255);
    for (var y = 5; y < 15; y++) {
      for (var x = 5; x < 15; x++) {
        _set(s, x, y, 0, 0, 0);
      }
    }
    for (var y = 8; y < 12; y++) {
      for (var x = 8; x < 12; x++) {
        _set(s, x, y, 255, 255, 255);
      }
    }
    final r = removeBackground(s, tolerance: 28, feather: 0);
    expect(_alpha(r, 0, 0), 0);
    expect(_alpha(r, 6, 6), 255);
    expect(_alpha(r, 9, 9), 255); // enclosed white stays
  });

  test('trim crops to the visible pixels', () {
    final s = _solid(10, 10, 0, 0, 0, 0);
    _set(s, 4, 5, 1, 2, 3);
    final t = trimTransparent(s, pad: 0);
    expect(t.w, 1);
    expect(t.h, 1);
  });
}
