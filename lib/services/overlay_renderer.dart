// Headless rendering of everything the exporter composites over (or instead
// of) the video: the ayah text overlay (with the same wrapping, shadow,
// boxed/framed panel and positions as the live preview), gradient
// backgrounds, and the bismillah/outro title cards. All drawn with Flutter's
// own text engine, so Arabic shaping and the selected fonts match the
// preview exactly — no ffmpeg drawtext (which can't shape Arabic properly).
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/studio_presets.dart';
import '../theme/ayat_fonts.dart';

class OverlayStyle {
  final String fontKey;
  final double ayahFontSize; // preview-scale px (multiplied by w/270)
  final double transFontSize;
  final Color color;
  final AyahTextPosition position;
  final FrameExtra extra;
  final bool showTranslation;
  const OverlayStyle({
    required this.fontKey,
    required this.ayahFontSize,
    required this.transFontSize,
    required this.color,
    required this.position,
    required this.extra,
    required this.showTranslation,
  });
}

class OverlayRenderer {
  /// Waits until the google_fonts families used anywhere in a render are
  /// actually loaded — a headless TextPainter won't trigger/await the lazy
  /// load the way a widget would, and painting with a font that is still
  /// downloading silently falls back to the default font.
  static Future<void> ensureFontsLoaded() async {
    GoogleFonts.amiriQuran();
    GoogleFonts.arefRuqaa();
    GoogleFonts.tajawal();
    GoogleFonts.notoNaskhArabic();
    GoogleFonts.scheherazadeNew();
    GoogleFonts.lateef();
    GoogleFonts.reemKufi();
    await GoogleFonts.pendingFonts();
  }

  /// The tazhib-style corner ornaments from the HTML prototype's ayah frame:
  /// four gold quarter-arcs with a small dot, drawn just inside the edges.
  static void paintCornerOrnaments(Canvas canvas, double w, double h,
      double scale, Color color) {
    final inset = 10.0 * scale;
    final len = 24.0 * scale;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3 * scale
      ..strokeCap = StrokeCap.round
      ..color = color;
    final dot = Paint()..color = color;

    void corner(double ox, double oy, double sx, double sy) {
      canvas.save();
      canvas.translate(ox, oy);
      canvas.scale(sx, sy);
      final p = Path()
        ..moveTo(0, len)
        ..cubicTo(0, len * 0.45, len * 0.45, 0, len, 0);
      canvas.drawPath(p, stroke);
      canvas.drawCircle(Offset(0, len), 1.6 * scale, dot);
      canvas.restore();
    }

    corner(inset, inset, 1, 1); // top-left
    corner(w - inset, inset, -1, 1); // top-right
    corner(inset, h - inset, 1, -1); // bottom-left
    corner(w - inset, h - inset, -1, -1); // bottom-right
  }

  static Future<Uint8List> _picToPng(ui.Picture pic, int w, int h) async {
    final img = await pic.toImage(w, h);
    try {
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      img.dispose();
    }
  }

  static void _paintGradient(Canvas canvas, int w, int h, BgDef def) {
    final rect = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
    canvas.drawRect(rect, Paint()..shader = def.gradient.createShader(rect));
  }

  static void _paintImageCover(Canvas canvas, int w, int h, ui.Image img) {
    final scale = [w / img.width, h / img.height].reduce((a, b) => a > b ? a : b);
    final dw = img.width * scale, dh = img.height * scale;
    final dst = Rect.fromLTWH((w - dw) / 2, (h - dh) / 2, dw, dh);
    canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.high);
  }

  static Future<ui.Image> _loadImageFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Solid background PNG: the selected gradient, or the custom image drawn
  /// cover-style — used behind chroma-keyed video and for no-video exports.
  static Future<Uint8List> renderBackgroundPng({
    required int w,
    required int h,
    required int bgIndex,
    String? customBgPath,
  }) async {
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    if (customBgPath != null) {
      final img = await _loadImageFile(customBgPath);
      _paintImageCover(canvas, w, h, img);
      img.dispose();
    } else {
      _paintGradient(canvas, w, h, kBackgrounds[bgIndex % kBackgrounds.length]);
    }
    return _picToPng(rec.endRecording(), w, h);
  }

  /// Bismillah intro / outro title card: chosen background + centered gold
  /// Amiri line, exactly like the HTML's drawTitleCard().
  static Future<Uint8List> renderTitleCardPng({
    required int w,
    required int h,
    required String text,
    required int bgIndex,
    String? customBgPath,
  }) async {
    await ensureFontsLoaded();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    if (customBgPath != null) {
      final img = await _loadImageFile(customBgPath);
      _paintImageCover(canvas, w, h, img);
      img.dispose();
    } else {
      _paintGradient(canvas, w, h, kBackgrounds[bgIndex % kBackgrounds.length]);
    }
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: ayahTextStyle(
          'amiri',
          fontSize: w * 0.075,
          color: const Color(0xFFECC875),
          shadows: [
            Shadow(color: const Color(0x80000000), blurRadius: w * 0.02),
          ],
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.rtl,
    )..layout(maxWidth: w * 0.86);
    tp.paint(canvas, Offset((w - tp.width) / 2, (h - tp.height) / 2));
    return _picToPng(rec.endRecording(), w, h);
  }

  /// Transparent text-overlay PNG: the (possibly partially typed) ayah and,
  /// once fully revealed, its translation and the surah/ayah reference line.
  /// Mirrors the live stage overlay exactly.
  static Future<Uint8List> renderTextOverlayPng({
    required int w,
    required int h,
    required String text,
    required String translation,
    required OverlayStyle style,
    String reference = '',
  }) async {
    await ensureFontsLoaded();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    if (text.isNotEmpty) {
      final scale = w / 270.0; // same preview-stage scale factor as the HTML
      final maxWidth = w * 0.86;
      final shadows = [
        Shadow(color: const Color(0xA6000000), blurRadius: 8 * scale),
      ];
      paintCornerOrnaments(canvas, w.toDouble(), h.toDouble(), scale,
          const Color(0x8CC9A24B));
      final ayahPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: ayahTextStyle(
            style.fontKey,
            fontSize: style.ayahFontSize * scale,
            color: style.color,
            height: 1.5,
            shadows: shadows,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: maxWidth);

      final showTrans = style.showTranslation && translation.isNotEmpty;
      TextPainter? transPainter;
      if (showTrans) {
        transPainter = TextPainter(
          text: TextSpan(
            text: translation,
            style: translationTextStyle(
              fontSize: style.transFontSize * scale,
              color: style.color.withValues(alpha: 0.88),
              shadows: shadows,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        )..layout(maxWidth: maxWidth);
      }

      TextPainter? refPainter;
      if (reference.isNotEmpty) {
        refPainter = TextPainter(
          text: TextSpan(
            text: reference,
            style: translationTextStyle(
              fontSize: style.transFontSize * scale * 0.82,
              color: const Color(0xFFECC875),
              shadows: shadows,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        )..layout(maxWidth: maxWidth);
      }

      final gap = showTrans ? style.transFontSize * scale * 0.6 : 0.0;
      final refGap = refPainter != null ? style.transFontSize * scale * 0.5 : 0.0;
      final totalH = ayahPainter.height +
          gap +
          (transPainter?.height ?? 0) +
          refGap +
          (refPainter?.height ?? 0);
      final centerY = switch (style.position) {
        AyahTextPosition.top => h * 0.16,
        AyahTextPosition.center => h * 0.5,
        AyahTextPosition.bottom => h * 0.78,
      };
      final top = centerY - totalH / 2;

      if (style.extra != FrameExtra.none) {
        final padX = 24 * scale, padY = 18 * scale;
        final rect = Rect.fromLTWH(
            w * 0.07 - padX * 0.2, top - padY,
            w * 0.86 + padX * 0.4, totalH + padY * 2);
        if (style.extra == FrameExtra.boxed) {
          canvas.drawRect(rect, Paint()..color = const Color(0x80050F0D));
        } else {
          canvas.drawRect(
              rect,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2 * scale
                ..color = const Color(0xE6C9A24B));
        }
      }

      ayahPainter.paint(canvas, Offset((w - ayahPainter.width) / 2, top));
      transPainter?.paint(
          canvas,
          Offset((w - transPainter.width) / 2,
              top + ayahPainter.height + gap));
      refPainter?.paint(
          canvas,
          Offset(
              (w - refPainter.width) / 2,
              top +
                  ayahPainter.height +
                  gap +
                  (transPainter?.height ?? 0) +
                  refGap));
    }
    return _picToPng(rec.endRecording(), w, h);
  }
}
