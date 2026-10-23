// PATCH_S206_STICKERS
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
