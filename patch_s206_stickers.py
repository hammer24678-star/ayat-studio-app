#!/usr/bin/env python3
"""
patch_s206_stickers.py
======================
Ayat Studio S206 - run from the repo root (after S205):

    python3 patch_s206_stickers.py

STICKERS.

  * New tool on the main bar: «ملصقات». Opens a library of 50 stickers drawn
    on the device: glowing line-art (speech bubble, thought bubble, crescent,
    8-point star, sparkle, heart, arrow, ring, clock, forbidden cross, tick,
    dome), Arabic phrases (البسملة, ما شاء الله, سبحان الله, الحمد لله,
    الله أكبر, آمين, ﷺ, ۞) and emoji (mosque, Kaaba, moon, hands raised,
    rosary, book, rain, sun, fire, hourglass, ...).
  * One tap puts it on the video at the playhead for 3 seconds with a pop-in.
    Drag it, pinch to resize, rotate - it is a normal overlay layer, so the
    existing animation, opacity, layer order, copy, split, trim and delete
    all work, and it is burned into the export exactly as shown.
  * «ملصقاتي»: make your own from any picture - crop (free / 1:1 / 4:3 /
    3:4 / 16:9, drag the corners), REMOVE THE BACKGROUND (tap the background
    colour or leave it automatic, sensitivity + soft edge sliders, colours
    that are enclosed inside the subject are kept), flip, turn 90 degrees,
    undo. Saved stickers stay in the library; long-press one to delete it.
  * With any picture overlay selected the bottom bar now has «قلب أفقي»,
    «قلب رأسي» and «قص / خلفية» (re-opens the editor on that sticker and
    swaps the edited picture in, keeping its place and timing).

Honest limits: background removal is colour-based (works best on a plain or
studio background, like a logo or a cut-out on white). It does not
"recognise" a person against a busy photo.

New files: lib/services/sticker_ops.dart, lib/services/sticker_service.dart,
lib/widgets/sticker_editor.dart, lib/widgets/sticker_sheet.dart,
test/sticker_ops_test.dart. Edited: lib/screens/home_screen.dart.
All edits apply together or not at all. Idempotent (marker PATCH_S206).
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
MARK = 'PATCH_S206'
HS = os.path.join(ROOT, 'lib/screens/home_screen.dart')
if not os.path.exists(HS):
    sys.exit('lib/screens/home_screen.dart missing')
hs = open(HS, encoding='utf-8').read()

NEW_FILES = [
    ('lib/services/sticker_ops.dart', r'''// PATCH_S206_STICKERS
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
'''),
    ('lib/services/sticker_service.dart', r'''// PATCH_S206_STICKERS
// The sticker library: a built-in set drawn on the device (line-art shapes,
// emoji, Arabic phrases) plus the user's own stickers. Every sticker is a
// transparent PNG on disk, so the preview and the exporter treat it like any
// other picture.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' hide TextStyle;
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

import 'sticker_ops.dart';

class BuiltinSticker {
  final String key;
  final String label;
  const BuiltinSticker(this.key, this.label);
}

class StickerService {
  static const List<BuiltinSticker> builtins = [
    // line-art (white glow, like the story scenes)
    BuiltinSticker('shape:bubble', 'فقاعة'),
    BuiltinSticker('shape:bubble2', 'فكرة'),
    BuiltinSticker('shape:crescent', 'هلال'),
    BuiltinSticker('shape:star8', 'نجمة'),
    BuiltinSticker('shape:sparkle', 'لمعة'),
    BuiltinSticker('shape:heart', 'قلب'),
    BuiltinSticker('shape:arrow', 'سهم'),
    BuiltinSticker('shape:ring', 'دائرة'),
    BuiltinSticker('shape:clock', 'ساعة'),
    BuiltinSticker('shape:cross', 'ممنوع'),
    BuiltinSticker('shape:check', 'صح'),
    BuiltinSticker('shape:dome', 'قبّة'),
    // phrases
    BuiltinSticker('text:﷽', 'البسملة'),
    BuiltinSticker('text:ماشاء الله', 'ما شاء الله'),
    BuiltinSticker('text:سبحان الله', 'سبحان الله'),
    BuiltinSticker('text:الحمد لله', 'الحمد لله'),
    BuiltinSticker('text:الله أكبر', 'الله أكبر'),
    BuiltinSticker('text:آمين', 'آمين'),
    BuiltinSticker('text:ﷺ', 'صلى الله عليه وسلم'),
    BuiltinSticker('text:۞', 'علامة الحزب'),
    // emoji
    BuiltinSticker('emoji:🕌', 'مسجد'),
    BuiltinSticker('emoji:🕋', 'الكعبة'),
    BuiltinSticker('emoji:☪️', 'هلال ونجمة'),
    BuiltinSticker('emoji:🌙', 'قمر'),
    BuiltinSticker('emoji:⭐', 'نجمة'),
    BuiltinSticker('emoji:✨', 'بريق'),
    BuiltinSticker('emoji:🤲', 'دعاء'),
    BuiltinSticker('emoji:📿', 'سبحة'),
    BuiltinSticker('emoji:📖', 'كتاب'),
    BuiltinSticker('emoji:🌹', 'وردة'),
    BuiltinSticker('emoji:🌸', 'زهرة'),
    BuiltinSticker('emoji:🕯️', 'شمعة'),
    BuiltinSticker('emoji:☁️', 'سحابة'),
    BuiltinSticker('emoji:🌧️', 'مطر'),
    BuiltinSticker('emoji:☀️', 'شمس'),
    BuiltinSticker('emoji:🔥', 'نار'),
    BuiltinSticker('emoji:💧', 'قطرة'),
    BuiltinSticker('emoji:🌍', 'الأرض'),
    BuiltinSticker('emoji:⏳', 'ساعة رملية'),
    BuiltinSticker('emoji:❤️', 'حب'),
    BuiltinSticker('emoji:🤍', 'قلب أبيض'),
    BuiltinSticker('emoji:🕊️', 'حمامة'),
    BuiltinSticker('emoji:⛰️', 'جبل'),
    BuiltinSticker('emoji:🌊', 'موج'),
    BuiltinSticker('emoji:⚡', 'برق'),
    BuiltinSticker('emoji:✅', 'تم'),
    BuiltinSticker('emoji:❌', 'خطأ'),
    BuiltinSticker('emoji:❓', 'سؤال'),
    BuiltinSticker('emoji:❗', 'تنبيه'),
    BuiltinSticker('emoji:👆', 'إشارة'),
  ];

  static Directory? _root;
  static Future<Directory> _dir(String sub) async {
    _root ??= Directory(
        '${(await getApplicationDocumentsDirectory()).path}/stickers');
    final d = Directory('${_root!.path}/$sub');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  static String _safe(String key) =>
      key.runes.map((r) => r.toRadixString(16)).join('_');

  // -------------------------------------------------------------- built-in

  static final Map<String, Future<String?>> _building = {};

  /// Path of a built-in sticker's PNG, drawing it the first time.
  static Future<String?> builtinPath(String key) {
    return _building.putIfAbsent(key, () => _buildBuiltin(key));
  }

  static Future<String?> _buildBuiltin(String key) async {
    try {
      final dir = await _dir('builtin');
      final f = File('${dir.path}/v1_${_safe(key)}.png');
      if (await f.exists() && await f.length() > 200) return f.path;
      final bytes = await _render(key);
      if (bytes == null) return null;
      await f.writeAsBytes(bytes, flush: true);
      return f.path;
    } catch (_) {
      _building.remove(key);
      return null;
    }
  }

  static Future<Uint8List?> _render(String key) async {
    final i = key.indexOf(':');
    final kind = key.substring(0, i);
    final arg = key.substring(i + 1);
    const s = 512.0;
    var w = s;
    var h = s;
    if (kind == 'text') {
      w = 900;
      h = 360;
    }
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, w, h));
    switch (kind) {
      case 'emoji':
        _paintText(c, arg, w, h, size: 360, color: const Color(0xFFFFFFFF));
      case 'text':
        _paintText(c, arg, w, h,
            size: arg.length <= 2 ? 300 : 150,
            color: const Color(0xFFFFFFFF),
            glow: true);
      case 'shape':
        _paintShape(c, arg, s);
      default:
        return null;
    }
    final pic = rec.endRecording();
    final img = await pic.toImage(w.toInt(), h.toInt());
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    img.dispose();
    if (bd == null) return null;
    // trim the empty margin so the sticker's box hugs the drawing
    final raw = RgbaImage(w.toInt(), h.toInt(),
        Uint8List.fromList(bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes)));
    return encodePng(trimTransparent(raw, pad: 6));
  }

  static void _paintText(Canvas c, String text, double w, double h,
      {required double size, required Color color, bool glow = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: FontWeight.w700,
          height: 1.2,
          shadows: glow
              ? const [
                  Shadow(color: Color(0xCCECC875), blurRadius: 28),
                  Shadow(color: Color(0x99FFFFFF), blurRadius: 8),
                ]
              : null,
        ),
      ),
      textDirection: TextDirection.rtl,
      textAlign: TextAlign.center,
    )..layout(maxWidth: w);
    tp.paint(c, Offset((w - tp.width) / 2, (h - tp.height) / 2));
  }

  static void _line(Canvas c, Path p,
      {Color color = const Color(0xFFFFFFFF), double width = 12}) {
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width * 2.2
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color.withOpacity(0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    c.drawPath(
        p,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = color);
  }

  static void _paintShape(Canvas c, String name, double s) {
    final m = s / 2;
    switch (name) {
      case 'bubble':
        final p = Path()
          ..addRRect(RRect.fromRectAndRadius(
              Rect.fromLTWH(60, 70, s - 120, 270), const Radius.circular(70)))
          ..moveTo(150, 340)
          ..lineTo(120, 440)
          ..lineTo(230, 340);
        _line(c, p);
      case 'bubble2':
        final p = Path()
          ..addOval(Rect.fromLTWH(50, 40, s - 100, 280))
          ..addOval(Rect.fromCircle(center: const Offset(130, 390), radius: 30))
          ..addOval(Rect.fromCircle(center: const Offset(80, 455), radius: 16));
        _line(c, p);
      case 'crescent':
        final a = Path()..addOval(Rect.fromCircle(center: Offset(m, m), radius: 190));
        final b = Path()
          ..addOval(Rect.fromCircle(center: Offset(m + 90, m - 30), radius: 160));
        _line(c, Path.combine(PathOperation.difference, a, b));
      case 'star8':
        final p = Path();
        for (var k = 0; k < 16; k++) {
          final r = k.isEven ? 200.0 : 120.0;
          final ang = -math.pi / 2 + k * math.pi / 8;
          final pt = Offset(m + r * math.cos(ang), m + r * math.sin(ang));
          if (k == 0) {
            p.moveTo(pt.dx, pt.dy);
          } else {
            p.lineTo(pt.dx, pt.dy);
          }
        }
        p.close();
        _line(c, p);
      case 'sparkle':
        final p = Path()
          ..moveTo(m, 40)
          ..quadraticBezierTo(m, m, s - 40, m)
          ..quadraticBezierTo(m, m, m, s - 40)
          ..quadraticBezierTo(m, m, 40, m)
          ..quadraticBezierTo(m, m, m, 40)
          ..close();
        _line(c, p);
      case 'heart':
        final p = Path()
          ..moveTo(m, 440)
          ..cubicTo(40, 300, 50, 110, 190, 110)
          ..cubicTo(240, 110, m, 160, m, 200)
          ..cubicTo(m, 160, 272, 110, 322, 110)
          ..cubicTo(462, 110, 472, 300, m, 440)
          ..close();
        _line(c, p);
      case 'arrow':
        final p = Path()
          ..moveTo(60, m)
          ..lineTo(430, m)
          ..moveTo(330, m - 100)
          ..lineTo(440, m)
          ..lineTo(330, m + 100);
        _line(c, p);
      case 'ring':
        _line(c, Path()..addOval(Rect.fromCircle(center: Offset(m, m), radius: 200)));
      case 'clock':
        final p = Path()
          ..addOval(Rect.fromCircle(center: Offset(m, m), radius: 200))
          ..moveTo(m, m)
          ..lineTo(m, m - 130)
          ..moveTo(m, m)
          ..lineTo(m + 95, m + 40);
        for (var k = 0; k < 12; k++) {
          final ang = k * math.pi / 6;
          p
            ..moveTo(m + 165 * math.cos(ang), m + 165 * math.sin(ang))
            ..lineTo(m + 185 * math.cos(ang), m + 185 * math.sin(ang));
        }
        _line(c, p);
      case 'cross':
        final p = Path()
          ..moveTo(90, 90)
          ..lineTo(s - 90, s - 90)
          ..moveTo(s - 90, 90)
          ..lineTo(90, s - 90);
        _line(c, p, color: const Color(0xFFE5484D), width: 34);
      case 'check':
        final p = Path()
          ..moveTo(80, 270)
          ..lineTo(210, 400)
          ..lineTo(440, 120);
        _line(c, p, color: const Color(0xFF3DD68C), width: 34);
      case 'dome':
        final p = Path()
          ..moveTo(70, 400)
          ..lineTo(70, 290)
          ..quadraticBezierTo(70, 130, m, 110)
          ..quadraticBezierTo(s - 70, 130, s - 70, 290)
          ..lineTo(s - 70, 400)
          ..close()
          ..moveTo(m, 110)
          ..lineTo(m, 50)
          ..moveTo(m - 34, 400)
          ..lineTo(m - 34, 320)
          ..quadraticBezierTo(m, 270, m + 34, 320)
          ..lineTo(m + 34, 400);
        _line(c, p);
    }
  }

  // ---------------------------------------------------------------- custom

  /// The user's own stickers, newest first.
  static Future<List<String>> customPaths() async {
    final dir = await _dir('custom');
    final files = <File>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith('.png')) files.add(e);
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files.map((f) => f.path).toList();
  }

  static Future<String> saveCustom(Uint8List png) async {
    final dir = await _dir('custom');
    final f = File('${dir.path}/s_${DateTime.now().microsecondsSinceEpoch}.png');
    await f.writeAsBytes(png, flush: true);
    return f.path;
  }

  static Future<void> deleteCustom(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  // ----------------------------------------------------------- conversions

  /// Decodes a picture file to RGBA, scaled down so the longer side is at
  /// most [maxSide] (keeps the editor responsive on big photos).
  static Future<RgbaImage?> decodeFile(String path, {int maxSide = 1024}) async {
    try {
      final bytes = await File(path).readAsBytes();
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final big = math.max(desc.width, desc.height);
      final k = big > maxSide ? maxSide / big : 1.0;
      final codec = await desc.instantiateCodec(
        targetWidth: (desc.width * k).round().clamp(1, 100000).toInt(),
        targetHeight: (desc.height * k).round().clamp(1, 100000).toInt(),
      );
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final out = bd == null
          ? null
          : RgbaImage(img.width, img.height,
              Uint8List.fromList(bd.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes)));
      img.dispose();
      codec.dispose();
      desc.dispose();
      buf.dispose();
      return out;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image> toUiImage(RgbaImage s) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(s.px, s.w, s.h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  static Future<Uint8List> encodePng(RgbaImage s) async {
    final img = await toUiImage(s);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return Uint8List.fromList(
        bd!.buffer.asUint8List(bd.offsetInBytes, bd.lengthInBytes));
  }
}
'''),
    ('lib/widgets/sticker_editor.dart', r'''// PATCH_S206_STICKERS
// Make or fix a sticker from any picture: crop it, take the background out,
// flip / turn it, then save it to "ملصقاتي". Pops with the saved PNG's path.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sticker_ops.dart';
import '../services/sticker_service.dart';
import '../theme/ayat_theme.dart';

Uint8List _bgJob(List<Object?> a) {
  final src = RgbaImage(a[1] as int, a[2] as int, a[0] as Uint8List);
  return removeBackground(src,
      keyRgb: a[3] as int?, tolerance: a[4] as int, feather: a[5] as int).px;
}

enum _Tool { crop, bg, flip }

enum _Grab { none, move, tl, tr, bl, br, l, r, t, b }

class StickerEditorPage extends StatefulWidget {
  final String sourcePath;
  final String title;
  const StickerEditorPage(
      {super.key, required this.sourcePath, this.title = 'ملصق جديد'});

  @override
  State<StickerEditorPage> createState() => _StickerEditorPageState();
}

class _StickerEditorPageState extends State<StickerEditorPage> {
  RgbaImage? _base;
  RgbaImage? _preview; // background-removal preview, not committed yet
  ui.Image? _shown;
  final List<RgbaImage> _undo = [];
  _Tool _tool = _Tool.crop;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  int _job = 0;

  // crop (fractions of the picture)
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);
  double? _ratio; // w / h, null = free
  _Grab _grab = _Grab.none;

  // background removal
  int? _key; // 0xRRGGBB, null = the corner colour
  double _tol = 28;
  double _feather = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shown?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final im = await StickerService.decodeFile(widget.sourcePath);
    if (!mounted) return;
    if (im == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    _base = im;
    await _show(im);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _show(RgbaImage im) async {
    final ui1 = await StickerService.toUiImage(im);
    if (!mounted) {
      ui1.dispose();
      return;
    }
    final old = _shown;
    setState(() => _shown = ui1);
    old?.dispose();
  }

  RgbaImage get _current => _preview ?? _base!;

  void _commit(RgbaImage next) {
    final cur = _base;
    if (cur != null) {
      _undo.add(cur);
      if (_undo.length > 8) _undo.removeAt(0);
    }
    _base = next;
    _preview = null;
    _crop = const Rect.fromLTWH(0, 0, 1, 1);
    _ratio = null;
    _show(next);
  }

  Future<void> _undoStep() async {
    if (_undo.isEmpty) return;
    HapticFeedback.selectionClick();
    _base = _undo.removeLast();
    _preview = null;
    _crop = const Rect.fromLTWH(0, 0, 1, 1);
    await _show(_base!);
    if (_tool == _Tool.bg) _runBg();
  }

  // ------------------------------------------------------------------ crop

  void _applyCrop() {
    final b = _base;
    if (b == null) return;
    final x = (_crop.left * b.w).round();
    final y = (_crop.top * b.h).round();
    final w = (_crop.width * b.w).round();
    final h = (_crop.height * b.h).round();
    if (w < 8 || h < 8) return;
    HapticFeedback.mediumImpact();
    setState(() => _commit(cropRgba(b, x, y, w, h)));
  }

  void _setRatio(double? r) {
    final b = _base;
    if (b == null) return;
    setState(() {
      _ratio = r;
      if (r == null) return;
      final imgR = b.w / b.h;
      // largest centred rectangle of ratio r inside the picture
      double fw, fh;
      if (r >= imgR) {
        fw = 1.0;
        fh = imgR / r;
      } else {
        fh = 1.0;
        fw = r / imgR;
      }
      _crop = Rect.fromLTWH((1 - fw) / 2, (1 - fh) / 2, fw, fh);
    });
  }

  _Grab _pick(Offset p, Rect r) {
    const corner = 34.0;
    const edge = 22.0;
    bool near(Offset a) => (a - p).distance < corner;
    if (_ratio == null) {
      if (near(r.topLeft)) return _Grab.tl;
      if (near(r.topRight)) return _Grab.tr;
      if (near(r.bottomLeft)) return _Grab.bl;
      if (near(r.bottomRight)) return _Grab.br;
      final inX = p.dx > r.left && p.dx < r.right;
      final inY = p.dy > r.top && p.dy < r.bottom;
      if (inX && (p.dy - r.top).abs() < edge) return _Grab.t;
      if (inX && (p.dy - r.bottom).abs() < edge) return _Grab.b;
      if (inY && (p.dx - r.left).abs() < edge) return _Grab.l;
      if (inY && (p.dx - r.right).abs() < edge) return _Grab.r;
    }
    return r.inflate(8).contains(p) ? _Grab.move : _Grab.none;
  }

  void _dragCrop(Offset d, Rect fit) {
    if (_grab == _Grab.none) return;
    final dx = d.dx / fit.width;
    final dy = d.dy / fit.height;
    const minS = 0.04;
    var l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;
    switch (_grab) {
      case _Grab.move:
        final w = r - l, h = b - t;
        l = (l + dx).clamp(0.0, 1.0 - w).toDouble();
        t = (t + dy).clamp(0.0, 1.0 - h).toDouble();
        r = l + w;
        b = t + h;
      case _Grab.tl:
        l = (l + dx).clamp(0.0, r - minS).toDouble();
        t = (t + dy).clamp(0.0, b - minS).toDouble();
      case _Grab.tr:
        r = (r + dx).clamp(l + minS, 1.0).toDouble();
        t = (t + dy).clamp(0.0, b - minS).toDouble();
      case _Grab.bl:
        l = (l + dx).clamp(0.0, r - minS).toDouble();
        b = (b + dy).clamp(t + minS, 1.0).toDouble();
      case _Grab.br:
        r = (r + dx).clamp(l + minS, 1.0).toDouble();
        b = (b + dy).clamp(t + minS, 1.0).toDouble();
      case _Grab.l:
        l = (l + dx).clamp(0.0, r - minS).toDouble();
      case _Grab.r:
        r = (r + dx).clamp(l + minS, 1.0).toDouble();
      case _Grab.t:
        t = (t + dy).clamp(0.0, b - minS).toDouble();
      case _Grab.b:
        b = (b + dy).clamp(t + minS, 1.0).toDouble();
      case _Grab.none:
        break;
    }
    setState(() => _crop = Rect.fromLTRB(l, t, r, b));
  }

  // ------------------------------------------------------------- background

  Future<void> _runBg() async {
    final b = _base;
    if (b == null) return;
    final my = ++_job;
    setState(() => _busy = true);
    try {
      final px = await compute(_bgJob, <Object?>[
        b.px,
        b.w,
        b.h,
        _key,
        _tol.round(),
        _feather.round(),
      ]);
      if (!mounted || my != _job) return;
      final res = RgbaImage(b.w, b.h, px);
      _preview = res;
      await _show(res);
    } catch (_) {
      if (mounted) _toast('تعذّرت إزالة الخلفية');
    } finally {
      if (mounted && my == _job) setState(() => _busy = false);
    }
  }

  void _pickColor(Offset local, Rect fit) {
    final b = _base;
    if (b == null || !fit.contains(local)) return;
    final x = ((local.dx - fit.left) / fit.width * b.w).floor().clamp(0, b.w - 1).toInt();
    final y = ((local.dy - fit.top) / fit.height * b.h).floor().clamp(0, b.h - 1).toInt();
    final i = (y * b.w + x) * 4;
    HapticFeedback.selectionClick();
    _key = (b.px[i] << 16) | (b.px[i + 1] << 8) | b.px[i + 2];
    _runBg();
  }

  void _commitBg() {
    final p = _preview;
    if (p == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _commit(p));
  }

  void _selectTool(_Tool t) {
    if (t == _tool) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tool = t;
      if (t != _Tool.bg && _preview != null) {
        _job++; // drop any running preview
        _preview = null;
        _show(_base!);
      }
    });
    if (t == _Tool.bg) _runBg();
  }

  // ------------------------------------------------------------------ misc

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _save() async {
    if (_base == null || _busy) return;
    setState(() => _busy = true);
    try {
      final done = trimTransparent(_current);
      final png = await StickerService.encodePng(done);
      final path = await StickerService.saveCustom(png);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(path);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('تعذّر حفظ الملصق');
      }
    }
  }

  Rect _fitRect(Size area) {
    final b = _base!;
    const pad = 14.0;
    final aw = area.width - pad * 2;
    final ah = area.height - pad * 2;
    final k = math.min(aw / b.w, ah / b.h);
    final w = b.w * k;
    final h = b.h * k;
    return Rect.fromLTWH((area.width - w) / 2, (area.height - h) / 2, w, h);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AyatColors.ink,
      appBar: AppBar(
        backgroundColor: AyatColors.surface,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'تراجع',
            onPressed: _undo.isEmpty ? null : _undoStep,
            icon: const Icon(Icons.undo),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton.icon(
              onPressed: (_base == null || _busy) ? null : _save,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('حفظ'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? const Center(child: Text('تعذّر فتح الصورة'))
              : Column(children: [
                  Expanded(child: _stage()),
                  _panel(),
                  _toolRow(),
                ]),
    );
  }

  Widget _stage() {
    return LayoutBuilder(builder: (context, c) {
      final area = Size(c.maxWidth, c.maxHeight);
      final fit = _fitRect(area);
      final shown = _shown;
      final screenCrop = Rect.fromLTRB(
        fit.left + _crop.left * fit.width,
        fit.top + _crop.top * fit.height,
        fit.left + _crop.right * fit.width,
        fit.top + _crop.bottom * fit.height,
      );
      final cropping = _tool == _Tool.crop;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (_tool == _Tool.bg) _pickColor(d.localPosition, fit);
        },
        onPanStart: cropping
            ? (d) => _grab = _pick(d.localPosition, screenCrop)
            : null,
        onPanUpdate: cropping ? (d) => _dragCrop(d.delta, fit) : null,
        onPanEnd: cropping ? (_) => _grab = _Grab.none : null,
        child: Stack(children: [
          Positioned.fromRect(
            rect: fit,
            child: CustomPaint(
              painter: const _CheckerPainter(),
              child: shown == null
                  ? const SizedBox.expand()
                  : RawImage(image: shown, fit: BoxFit.fill),
            ),
          ),
          if (cropping)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                    painter: _CropPainter(screenCrop, fit)),
              ),
            ),
          if (_busy)
            const Positioned(
              top: 12,
              right: 12,
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
        ]),
      );
    });
  }

  Widget _panel() {
    Widget body;
    switch (_tool) {
      case _Tool.crop:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, children: [
            for (final (label, r) in <(String, double?)>[
              ('حر', null),
              ('1:1', 1.0),
              ('4:3', 4 / 3),
              ('3:4', 3 / 4),
              ('16:9', 16 / 9),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _ratio == r,
                onSelected: (_) => _setRatio(r),
              ),
          ]),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _applyCrop,
            icon: const Icon(Icons.crop, size: 18),
            label: const Text('تطبيق القص'),
          ),
        ]);
      case _Tool.bg:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            _key == null
                ? 'اضغط على لون الخلفية في الصورة لتحديده — أو اتركه تلقائيًا'
                : 'اللون محدد — اضغط على مكان آخر لتغييره',
            style: const TextStyle(fontSize: 12, color: AyatColors.parchmentDim),
          ),
          Row(children: [
            const SizedBox(width: 64, child: Text('الحساسية', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                value: _tol,
                min: 2,
                max: 80,
                onChanged: (v) => setState(() => _tol = v),
                onChangeEnd: (_) => _runBg(),
              ),
            ),
          ]),
          Row(children: [
            const SizedBox(width: 64, child: Text('نعومة الحافة', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                value: _feather,
                min: 0,
                max: 6,
                divisions: 6,
                onChanged: (v) => setState(() => _feather = v),
                onChangeEnd: (_) => _runBg(),
              ),
            ),
          ]),
          FilledButton.icon(
            onPressed: _preview == null || _busy ? null : _commitBg,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('تثبيت إزالة الخلفية'),
          ),
        ]);
      case _Tool.flip:
        body = Wrap(spacing: 10, runSpacing: 6, children: [
          OutlinedButton.icon(
            onPressed: () => setState(
                () => _commit(flipRgba(_base!, horizontal: true))),
            icon: const Icon(Icons.flip, size: 18),
            label: const Text('قلب أفقي'),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(
                () => _commit(flipRgba(_base!, vertical: true))),
            icon: const Icon(Icons.swap_vert, size: 18),
            label: const Text('قلب رأسي'),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() => _commit(rotate90(_base!))),
            icon: const Icon(Icons.rotate_90_degrees_cw, size: 18),
            label: const Text('تدوير'),
          ),
        ]);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      color: AyatColors.surface,
      child: body,
    );
  }

  Widget _toolRow() {
    Widget item(_Tool t, IconData icon, String label) {
      final on = _tool == t;
      final col = on ? AyatColors.goldBright : AyatColors.parchmentDim;
      return Expanded(
        child: InkWell(
          onTap: () => _selectTool(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: col, size: 22),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: col)),
            ]),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        color: AyatColors.ink,
        child: Row(children: [
          item(_Tool.crop, Icons.crop, 'قص'),
          item(_Tool.bg, Icons.blur_on, 'إزالة الخلفية'),
          item(_Tool.flip, Icons.flip, 'قلب وتدوير'),
        ]),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final a = Paint()..color = const Color(0xFF2A2F2D);
    final b = Paint()..color = const Color(0xFF1C201F);
    const s = 12.0;
    for (var y = 0; y * s < size.height; y++) {
      for (var x = 0; x * s < size.width; x++) {
        canvas.drawRect(Rect.fromLTWH(x * s, y * s, s, s), (x + y).isEven ? a : b);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CropPainter extends CustomPainter {
  final Rect crop;
  final Rect fit;
  _CropPainter(this.crop, this.fit);

  @override
  void paint(Canvas canvas, Size size) {
    // darken everything outside the crop
    final dim = Paint()..color = const Color(0x99000000);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(fit)
        ..addRect(crop),
      dim,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AyatColors.goldBright;
    canvas.drawRect(crop, line);
    final grid = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x55FFFFFF);
    for (var k = 1; k < 3; k++) {
      final x = crop.left + crop.width * k / 3;
      final y = crop.top + crop.height * k / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }
    final dot = Paint()..color = AyatColors.goldBright;
    for (final p in [crop.topLeft, crop.topRight, crop.bottomLeft, crop.bottomRight]) {
      canvas.drawCircle(p, 7, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.crop != crop || old.fit != fit;
}
'''),
    ('lib/widgets/sticker_sheet.dart', r'''// PATCH_S206_STICKERS
// The sticker picker: built-in library + the user's own stickers, with a
// "new sticker from a picture" door into the editor.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sticker_service.dart';
import '../theme/ayat_theme.dart';
import 'sticker_editor.dart';

Future<void> showStickerSheet(
  BuildContext context, {
  required void Function(String path) onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AyatColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _StickerSheet(onPick: onPick),
  );
}

class _StickerSheet extends StatefulWidget {
  final void Function(String path) onPick;
  const _StickerSheet({required this.onPick});

  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  int _tab = 0; // 0 library, 1 mine
  List<String> _mine = const [];
  bool _loadedMine = false;

  @override
  void initState() {
    super.initState();
    _refreshMine();
  }

  Future<void> _refreshMine() async {
    final l = await StickerService.customPaths();
    if (!mounted) return;
    setState(() {
      _mine = l;
      _loadedMine = true;
    });
  }

  void _choose(String path) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    widget.onPick(path);
  }

  Future<void> _create() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => StickerEditorPage(sourcePath: path)),
    );
    if (!mounted) return;
    await _refreshMine();
    if (saved != null && mounted) _choose(saved);
  }

  Future<void> _confirmDelete(String path) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الملصق؟'),
        content: const Text('سيُحذف من «ملصقاتي». ما أُضيف منه إلى مقاطعك يبقى كما هو.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await StickerService.deleteCustom(path);
    _refreshMine();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      child: SizedBox(
        height: h * 0.72,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: AyatColors.hairline,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ChoiceChip(
              label: const Text('المكتبة'),
              selected: _tab == 0,
              onSelected: (_) => setState(() => _tab = 0),
            ),
            const SizedBox(width: 10),
            ChoiceChip(
              label: Text(_mine.isEmpty ? 'ملصقاتي' : 'ملصقاتي (${_mine.length})'),
              selected: _tab == 1,
              onSelected: (_) => setState(() => _tab = 1),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(child: _tab == 0 ? _library() : _mineGrid()),
        ]),
      ),
    );
  }

  Widget _cell({required Widget child, VoidCallback? onTap, VoidCallback? onLong}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AyatColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AyatColors.hairline),
        ),
        child: Center(child: child),
      ),
    );
  }

  static const _grid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 4,
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
  );

  Widget _library() {
    final items = StickerService.builtins;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      gridDelegate: _grid,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        return FutureBuilder<String?>(
          future: StickerService.builtinPath(it.key),
          builder: (context, snap) {
            final p = snap.data;
            return _cell(
              onTap: p == null ? null : () => _choose(p),
              child: p == null
                  ? (snap.connectionState == ConnectionState.done
                      ? const Icon(Icons.broken_image_outlined, size: 20)
                      : const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Tooltip(
                      message: it.label,
                      child: Image.file(File(p),
                          fit: BoxFit.contain, gaplessPlayback: true),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _mineGrid() {
    if (!_loadedMine) {
      return const Center(child: CircularProgressIndicator());
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      gridDelegate: _grid,
      itemCount: _mine.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _cell(
            onTap: _create,
            child: Column(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.add_photo_alternate_outlined,
                  color: AyatColors.goldBright, size: 26),
              SizedBox(height: 4),
              Text('ملصق جديد',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: AyatColors.goldBright)),
            ]),
          );
        }
        final p = _mine[i - 1];
        return _cell(
          onTap: () => _choose(p),
          onLong: () => _confirmDelete(p),
          child: Image.file(File(p), fit: BoxFit.contain, gaplessPlayback: true),
        );
      },
    );
  }
}
'''),
    ('test/sticker_ops_test.dart', r'''// PATCH_S206_STICKERS
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
'''),
]


already = MARK in hs and all(os.path.exists(os.path.join(ROOT, p)) for p, _ in NEW_FILES)
if already:
    print('  OK      already applied (PATCH_S206)')
    sys.exit(0)
if MARK in hs:
    sys.exit('  SKIP    PATCH_S206 is only partly present - restore home_screen.dart (git checkout) and re-run.')
if 'PATCH_S188_PIP' not in hs:
    sys.exit('  SKIP    this build has no PiP layer - stickers need it.')


def apply_fix(src, label, old, new):
    n = src.count(old)
    if n != 1:
        sys.exit('  SKIP    %s: anchor found %d times (need exactly 1) - nothing written' % (label, n))
    print('  PATCHED %s' % label)
    return src.replace(old, new)


IMP_OLD = "import '../widgets/nudge_sheet.dart'; // PATCH_S190_COMFORT\n"
IMP_NEW = (IMP_OLD +
           "import '../widgets/sticker_sheet.dart'; // PATCH_S206_STICKERS\n"
           "import '../widgets/sticker_editor.dart'; // PATCH_S206_STICKERS\n")
hs = apply_fix(hs, 'home_screen.dart - imports', IMP_OLD, IMP_NEW)

BAR_OLD = "        (Icons.add_photo_alternate_outlined, 'إضافة', _addMediaSheet, false),\n"
BAR_NEW = BAR_OLD + "        (Icons.emoji_emotions_outlined, 'ملصقات', _openStickers, false), // PATCH_S206_STICKERS\n"
hs = apply_fix(hs, 'home_screen.dart - «ملصقات» on the main bar', BAR_OLD, BAR_NEW)

PIP_OLD = "      (Icons.flip_to_back, 'للخلف', () => state.movePipLayer(i, -1), false),\n"
PIP_NEW = PIP_OLD + """      // PATCH_S206_STICKERS: flip + sticker editor for the selected overlay
      if (i >= 0 && i < state.pipClips.length) ...[
        (
          Icons.flip,
          'قلب أفقي',
          () {
            final c = state.pipClips[i];
            state.update(() => c.flipH = !c.flipH);
          },
          state.pipClips[i].flipH
        ),
        (
          Icons.swap_vert,
          'قلب رأسي',
          () {
            final c = state.pipClips[i];
            state.update(() => c.flipV = !c.flipV);
          },
          state.pipClips[i].flipV
        ),
        if (state.pipClips[i].isImage)
          (Icons.crop, 'قص / خلفية', () => _editSticker(i), false),
      ],
"""
hs = apply_fix(hs, 'home_screen.dart - flip + edit on the selected overlay', PIP_OLD, PIP_NEW)

M_OLD = "  List<(IconData, String, VoidCallback, bool)> _pipItems() {\n"
M_NEW = """  // ---------------------------------------------------------------------
  // PATCH_S206_STICKERS: sticker library + editor on top of the PiP layer.
  // ---------------------------------------------------------------------
  void _openStickers() {
    if (!state.hasVideo || _video == null || !_video!.value.isInitialized) {
      _toast('ارفع فيديو أولًا');
      return;
    }
    HapticFeedback.selectionClick();
    showStickerSheet(context, onPick: _addStickerFromPath);
  }

  Future<void> _addStickerFromPath(String path) async {
    final main = _video;
    if (!state.hasVideo || main == null || !main.value.isInitialized) {
      _toast('ارفع فيديو أولًا');
      return;
    }
    var aspect = 1.0;
    try {
      final img = await decodeImageFromList(await File(path).readAsBytes());
      aspect = img.width / img.height;
      img.dispose();
    } catch (_) {
      _toast('تعذّر فتح الملصق');
      return;
    }
    if (!mounted || !aspect.isFinite || aspect <= 0.05) return;
    final total = main.value.duration.inMilliseconds / 1000.0;
    var start = _playheadSec;
    var end = start + 3.0;
    if (end > total) {
      end = total;
      start = max(0.0, total - 3.0);
    }
    if (end - start < 0.5) {
      _toast('المقطع الأساسي قصير جدًّا');
      return;
    }
    state.addPip(PipClip(
      path: path,
      isImage: true,
      aspect: aspect,
      start: start,
      end: end,
      cx: 0.5,
      cy: 0.45,
      width: aspect > 1.6 ? 0.46 : (aspect < 0.7 ? 0.2 : 0.3),
      shape: PipShape.rect,
      inAnim: PipAnim.pop,
      outAnim: PipAnim.fade,
    ));
    HapticFeedback.mediumImpact();
    _toast('أُضيف الملصق — اسحبه لتحريكه واقرص لتكبيره');
  }

  Future<void> _editSticker(int i) async {
    if (i < 0 || i >= state.pipClips.length) return;
    final c = state.pipClips[i];
    if (!c.isImage) return;
    final path = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            StickerEditorPage(sourcePath: c.path, title: 'تحرير الملصق'),
      ),
    );
    if (path == null || !mounted) return;
    var aspect = c.aspect;
    try {
      final img = await decodeImageFromList(await File(path).readAsBytes());
      aspect = img.width / img.height;
      img.dispose();
    } catch (_) {}
    if (!mounted) return;
    state.update(() {
      c.path = path;
      if (aspect.isFinite && aspect > 0.05) c.aspect = aspect;
    });
    HapticFeedback.mediumImpact();
    _toast('تم تحديث الملصق');
  }

""" + M_OLD
hs = apply_fix(hs, 'home_screen.dart - sticker methods', M_OLD, M_NEW)

# ---- write everything (new files first only if the edit succeeded)
for rel, body in NEW_FILES:
    p = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, 'w', encoding='utf-8').write(body)
    print('  CREATED %s' % rel)
open(HS, 'w', encoding='utf-8').write(hs)

ok = True
for p in [HS] + [os.path.join(ROOT, r) for r, _ in NEW_FILES]:
    t = re.sub(r"//[^\n]*", '', open(p, encoding='utf-8').read())
    ok = ok and all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))
print('  all balanced' if ok else '  !! UNBALANCED - check the files before committing')
print('Next: git add -A && git commit -m "S206: stickers - library, custom stickers, crop, background removal, flip" && git push')
