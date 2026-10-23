// PATCH_S206_STICKERS
// Pixel operations behind the sticker editor: crop, flip, rotate, background
// removal and trimming. Pure Dart on RGBA bytes (no Flutter), so it runs in
// an isolate and can be unit-tested.
import 'dart:typed_data';

class RgbaImage {
  final int w;
  final int h;

  /// w * h * 4 bytes, R G B A.
  final Uint8List px;
  RgbaImage(this.w, this.h, this.px);

  factory RgbaImage.blank(int w, int h) =>
      RgbaImage(w, h, Uint8List(w * h * 4));

  RgbaImage copy() => RgbaImage(w, h, Uint8List.fromList(px));
}

RgbaImage cropRgba(RgbaImage s, int x, int y, int cw, int ch) {
  final x0 = x.clamp(0, s.w - 1).toInt();
  final y0 = y.clamp(0, s.h - 1).toInt();
  final w = cw.clamp(1, s.w - x0).toInt();
  final h = ch.clamp(1, s.h - y0).toInt();
  final out = Uint8List(w * h * 4);
  for (var row = 0; row < h; row++) {
    final from = ((y0 + row) * s.w + x0) * 4;
    out.setRange(row * w * 4, (row + 1) * w * 4, s.px, from);
  }
  return RgbaImage(w, h, out);
}

RgbaImage flipRgba(RgbaImage s, {bool horizontal = false, bool vertical = false}) {
  if (!horizontal && !vertical) return s;
  final out = Uint8List(s.px.length);
  for (var y = 0; y < s.h; y++) {
    final sy = vertical ? s.h - 1 - y : y;
    for (var x = 0; x < s.w; x++) {
      final sx = horizontal ? s.w - 1 - x : x;
      final a = (sy * s.w + sx) * 4;
      final b = (y * s.w + x) * 4;
      out[b] = s.px[a];
      out[b + 1] = s.px[a + 1];
      out[b + 2] = s.px[a + 2];
      out[b + 3] = s.px[a + 3];
    }
  }
  return RgbaImage(s.w, s.h, out);
}

/// Quarter turn clockwise.
RgbaImage rotate90(RgbaImage s) {
  final nw = s.h;
  final nh = s.w;
  final out = Uint8List(s.px.length);
  for (var y = 0; y < s.h; y++) {
    for (var x = 0; x < s.w; x++) {
      // (x, y) -> (s.h - 1 - y, x)
      final a = (y * s.w + x) * 4;
      final b = (x * nw + (s.h - 1 - y)) * 4;
      out[b] = s.px[a];
      out[b + 1] = s.px[a + 1];
      out[b + 2] = s.px[a + 2];
      out[b + 3] = s.px[a + 3];
    }
  }
  return RgbaImage(nw, nh, out);
}

/// The colour that dominates the four corners: mean of a small patch in each
/// corner, then the middle one of the four by brightness. Returns 0xRRGGBB.
int guessBackground(RgbaImage s) {
  final patch = (s.w < s.h ? s.w : s.h) ~/ 40 + 1;
  final means = <List<int>>[];
  for (final cx in [0, s.w - patch]) {
    for (final cy in [0, s.h - patch]) {
      var r = 0, g = 0, b = 0, n = 0;
      for (var y = cy; y < cy + patch && y < s.h; y++) {
        for (var x = cx; x < cx + patch && x < s.w; x++) {
          final i = (y * s.w + x) * 4;
          r += s.px[i];
          g += s.px[i + 1];
          b += s.px[i + 2];
          n++;
        }
      }
      if (n > 0) means.add([r ~/ n, g ~/ n, b ~/ n]);
    }
  }
  means.sort((a, b) => (a[0] + a[1] + a[2]).compareTo(b[0] + b[1] + b[2]));
  final m = means[means.length ~/ 2];
  return (m[0] << 16) | (m[1] << 8) | m[2];
}

/// Makes the background transparent.
///
/// Starting from every edge pixel that is close to [keyRgb] (0xRRGGBB, or the
/// corner colour when null) the clear area spreads through neighbouring pixels
/// that are also close - so a colour that also appears INSIDE the subject (a
/// white eye, a white word) is left alone, because the fill cannot reach it.
/// [tolerance] 0..100 is how far a pixel's colour may differ; [feather] 0..6
/// softens that many pixels of the edge.
RgbaImage removeBackground(RgbaImage s,
    {int? keyRgb, int tolerance = 28, int feather = 1}) {
  final key = keyRgb ?? guessBackground(s);
  final kr = (key >> 16) & 0xFF;
  final kg = (key >> 8) & 0xFF;
  final kb = key & 0xFF;
  final thr = (tolerance.clamp(0, 100) * 2.55).round();
  final w = s.w;
  final h = s.h;
  final n = w * h;
  final px = s.px;

  bool near(int p) {
    final i = p * 4;
    if (px[i + 3] < 12) return true; // already see-through
    final dr = px[i] - kr;
    final dg = px[i + 1] - kg;
    final db = px[i + 2] - kb;
    final m = (dr < 0 ? -dr : dr) > (dg < 0 ? -dg : dg)
        ? (dr < 0 ? -dr : dr)
        : (dg < 0 ? -dg : dg);
    final mm = m > (db < 0 ? -db : db) ? m : (db < 0 ? -db : db);
    return mm <= thr;
  }

  final bg = Uint8List(n); // 1 = background
  final stack = Int32List(n);
  var sp = 0;
  void seed(int p) {
    if (bg[p] == 0 && near(p)) {
      bg[p] = 1;
      stack[sp++] = p;
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (sp > 0) {
    final p = stack[--sp];
    final x = p % w;
    final y = p ~/ w;
    if (x > 0) seed(p - 1);
    if (x < w - 1) seed(p + 1);
    if (y > 0) seed(p - w);
    if (y < h - 1) seed(p + w);
  }

  final out = Uint8List.fromList(px);
  for (var p = 0; p < n; p++) {
    if (bg[p] == 1) out[p * 4 + 3] = 0;
  }

  final f = feather.clamp(0, 6).toInt();
  if (f > 0) {
    // distance (in steps) of each kept pixel from the cleared area, up to f
    final dist = Int32List(n);
    for (var p = 0; p < n; p++) {
      dist[p] = bg[p] == 1 ? 0 : -1;
    }
    var frontier = <int>[];
    for (var p = 0; p < n; p++) {
      if (bg[p] == 1) frontier.add(p);
    }
    for (var d = 1; d <= f && frontier.isNotEmpty; d++) {
      final next = <int>[];
      for (final p in frontier) {
        final x = p % w;
        final y = p ~/ w;
        void visit(int q) {
          if (dist[q] == -1) {
            dist[q] = d;
            next.add(q);
          }
        }

        if (x > 0) visit(p - 1);
        if (x < w - 1) visit(p + 1);
        if (y > 0) visit(p - w);
        if (y < h - 1) visit(p + w);
      }
      frontier = next;
    }
    for (var p = 0; p < n; p++) {
      final d = dist[p];
      if (d > 0 && d <= f) {
        final a = out[p * 4 + 3];
        out[p * 4 + 3] = (a * d ~/ (f + 1)).clamp(0, 255).toInt();
      }
    }
  }
  return RgbaImage(w, h, out);
}

/// Crops to the visible pixels (alpha above [minAlpha]) plus [pad] pixels.
/// Returns [s] unchanged when nothing is visible.
RgbaImage trimTransparent(RgbaImage s, {int pad = 2, int minAlpha = 10}) {
  var minX = s.w, minY = s.h, maxX = -1, maxY = -1;
  for (var y = 0; y < s.h; y++) {
    for (var x = 0; x < s.w; x++) {
      if (s.px[(y * s.w + x) * 4 + 3] > minAlpha) {
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
  }
  if (maxX < 0) return s;
  final x0 = (minX - pad).clamp(0, s.w - 1).toInt();
  final y0 = (minY - pad).clamp(0, s.h - 1).toInt();
  final x1 = (maxX + pad).clamp(0, s.w - 1).toInt();
  final y1 = (maxY + pad).clamp(0, s.h - 1).toInt();
  if (x0 == 0 && y0 == 0 && x1 == s.w - 1 && y1 == s.h - 1) return s;
  return cropRgba(s, x0, y0, x1 - x0 + 1, y1 - y0 + 1);
}
