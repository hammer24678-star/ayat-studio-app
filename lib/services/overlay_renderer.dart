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
import '../data/text_transitions.dart'; // PATCH_S126_TEXT_TRANSITIONS
import '../models/studio_state.dart'; // PATCH_S143_TEXT_LAYERS: TextLayer
import '../theme/ayat_fonts.dart';

class OverlayStyle {
  final String fontKey;
  final double ayahFontSize; // preview-scale px (multiplied by w/270)
  final double transFontSize;
  final Color color;
  final AyahTextPosition position;
  final FrameExtra extra;
  final bool showTranslation;
  final bool glowEnabled; // PATCH_S46_DEFAULT_FONT_AND_GLOW
  final double glowIntensity;
  final double letterSpacing; // PATCH_S48_TEXT_SPACING_TOGGLES
  final double lineHeightMultiplier;
  final Offset offset; // PATCH_S50_DRAGGABLE_TEXT: matches StudioState.textOffset
  final double userScale; // matches StudioState.textUserScale
  // ---- PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION / PATCH_S145 ----
  final Map<int, Color> wordColors;
  final String captionText;
  final CaptionPosition captionPosition;
  // PATCH_S143_TEXT_LAYERS: independent stacked fixed-text boxes,
  // drawn on top of the ayah and the caption, never replacing either.
  final List<TextLayer> textLayers;
  // PATCH_S126_TEXT_TRANSITIONS: where the text is in its entrance/exit.
  // Identity on every frame that is simply "showing text", so the whole
  // transform path is skipped for the vast majority of frames.
  final TextMotion motion;
  const OverlayStyle({
    required this.fontKey,
    required this.ayahFontSize,
    required this.transFontSize,
    required this.color,
    required this.position,
    required this.extra,
    required this.showTranslation,
    this.glowEnabled = true,
    this.glowIntensity = 1.0,
    this.letterSpacing = 0,
    this.lineHeightMultiplier = 1.5,
    this.offset = Offset.zero,
    this.userScale = 1.0,
    this.wordColors = const {},
    this.captionText = '',
    this.captionPosition = CaptionPosition.bottom,
    this.motion = TextMotion.identity,
    this.textLayers = const [], // PATCH_S143_TEXT_LAYERS
  });

  /// PATCH_S126_TEXT_TRANSITIONS: the same style at a different point in its
  /// transition. Every other field is shared across a whole sequence, so
  /// rebuilding the lot per frame would be wasteful and easy to get subtly
  /// wrong.
  OverlayStyle withMotion(TextMotion m) => OverlayStyle(
        fontKey: fontKey,
        ayahFontSize: ayahFontSize,
        transFontSize: transFontSize,
        color: color,
        position: position,
        extra: extra,
        showTranslation: showTranslation,
        glowEnabled: glowEnabled,
        glowIntensity: glowIntensity,
        letterSpacing: letterSpacing,
        lineHeightMultiplier: lineHeightMultiplier,
        offset: offset,
        userScale: userScale,
        wordColors: wordColors,
        captionText: captionText,
        captionPosition: captionPosition,
        motion: m,
        textLayers: textLayers, // PATCH_S143_TEXT_LAYERS
      );
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
    await GoogleFonts.pendingFonts();
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

  // PATCH_S123_WATERMARK: rendered as its own transparent full-frame PNG and
  // composited by ffmpeg as one extra overlay input, rather than being drawn
  // into the ayah overlay. The ayah overlay is re-rendered per karaoke frame
  // and can be gated to a time window, and a watermark must do neither -- it
  // is one still image for the whole clip, so it costs one render and one
  // overlay pass no matter how long the video is.
  //
  // Drawn with Flutter's text engine like everything else here, so an Arabic
  // watermark shapes correctly (ffmpeg's drawtext cannot shape Arabic).
  static Future<Uint8List> renderWatermarkPng({
    required int w,
    required int h,
    required String text,
    String? imagePath,
    required WatermarkCorner corner,
    required double opacity,
    required double scale,
  }) async {
    await ensureFontsLoaded();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    // Margin scales with the frame so the mark sits the same distance from
    // the edge at 720p and 1080p.
    final margin = w * 0.04;
    final alpha = opacity.clamp(0.0, 1.0);
    final targetW = w * scale.clamp(0.05, 0.6);

    double left(double markW) =>
        (corner == WatermarkCorner.topLeft || corner == WatermarkCorner.bottomLeft)
            ? margin
            : w - margin - markW;
    double top(double markH) =>
        (corner == WatermarkCorner.topLeft || corner == WatermarkCorner.topRight)
            ? margin
            : h - margin - markH;

    if (imagePath != null && imagePath.isNotEmpty) {
      final img = await _loadImageFile(imagePath);
      try {
        final markW = targetW;
        final markH = markW * img.height / img.width;
        canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
          Rect.fromLTWH(left(markW), top(markH), markW, markH),
          Paint()
            ..filterQuality = FilterQuality.high
            ..color = Color.fromRGBO(255, 255, 255, alpha),
        );
      } finally {
        img.dispose();
      }
    } else if (text.trim().isNotEmpty) {
      // Font size follows the same fraction-of-width rule as the image
      // branch, so the two sizing sliders feel like one control.
      final fontSize = targetW * 0.20;
      final painter = TextPainter(
        text: TextSpan(
          text: text.trim(),
          style: GoogleFonts.tajawal(
            textStyle: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: Color.fromRGBO(236, 200, 117, alpha),
              shadows: [
                Shadow(
                  color: Color.fromRGBO(0, 0, 0, 0.55 * alpha),
                  blurRadius: fontSize * 0.35,
                ),
              ],
            ),
          ),
        ),
        textAlign: TextAlign.start,
        textDirection: TextDirection.rtl,
        maxLines: 2,
      )..layout(maxWidth: w - margin * 2);
      painter.paint(
          canvas, Offset(left(painter.width), top(painter.height)));
    }
    return _picToPng(rec.endRecording(), w, h);
  }

  // PATCH_S126_TEXT_TRANSITIONS: rebuilds a span so its words (or letters)
  // arrive one after another instead of all at once.
  //
  // Each item gets its own slice of the progress bar and fades across a
  // window WIDER than that slice, so neighbouring items overlap. That
  // overlap is the whole point: give each word a hard on/off and the line
  // stutters in exactly as many steps as it has words, which is the chopping
  // this patch exists to remove.
  static InlineSpan _revealedSpan(
      InlineSpan original, OverlayStyle style, Color baseColor, double opacity) {
    final text = original.toPlainText();
    if (text.trim().isEmpty) return original;
    final byLetter = style.motion.revealMode == RevealMode.letters;
    final units = byLetter
        ? text.split('')
        : text.split(' ').where((w) => w.isNotEmpty).toList();
    if (units.isEmpty) return original;

    final p = style.motion.reveal.clamp(0.0, 1.0);
    final style0 = ayahTextStyle(
      style.fontKey,
      fontSize: null,
      color: baseColor,
      height: style.lineHeightMultiplier,
      letterSpacing: style.letterSpacing,
    );

    final children = <InlineSpan>[];
    for (var i = 0; i < units.length; i++) {
      // Same ramp the live preview uses — see revealUnitAlpha.
      final a = revealUnitAlpha(index: i, count: units.length, progress: p);
      children.add(TextSpan(
        text: byLetter ? units[i] : (i == 0 ? units[i] : ' ${units[i]}'),
        style: style0.copyWith(
          color: baseColor.withValues(alpha: baseColor.a * a * opacity),
        ),
      ));
    }
    // Keep the original's font size/shadows by inheriting from it.
    final rootStyle = original is TextSpan ? original.style : null;
    return TextSpan(style: rootStyle, children: children);
  }

  // PATCH_S126_TEXT_TRANSITIONS: clips the canvas to the revealed portion of
  // the text block. Word/letter reveals are NOT handled here -- those change
  // which glyphs are drawn, not which pixels survive, and are applied while
  // building the span.
  static void _applyReveal(Canvas canvas, Rect block, TextMotion m) {
    final r = m.reveal.clamp(0.0, 1.0);
    if (m.revealMode == RevealMode.none || r >= 1) return;
    // Generous vertical padding: glyph ascenders and shadows draw outside the
    // laid-out block, and clipping them mid-transition looks like a bug.
    final pad = block.height * 0.6;
    switch (m.revealMode) {
      case RevealMode.wipeUp:
        canvas.clipRect(Rect.fromLTRB(block.left - pad,
            block.bottom - block.height * r, block.right + pad, block.bottom));
      case RevealMode.wipeDown:
        canvas.clipRect(Rect.fromLTRB(block.left - pad, block.top,
            block.right + pad, block.top + block.height * r));
      case RevealMode.wipeStart:
        canvas.clipRect(Rect.fromLTRB(block.right - block.width * r,
            block.top - pad, block.right, block.bottom + pad));
      case RevealMode.wipeEnd:
        canvas.clipRect(Rect.fromLTRB(block.left, block.top - pad,
            block.left + block.width * r, block.bottom + pad));
      case RevealMode.iris:
        final maxR = block.longestSide * 0.75;
        canvas.clipPath(Path()
          ..addOval(Rect.fromCircle(center: block.center, radius: maxR * r)));
      case RevealMode.curtain:
        final half = block.height * r / 2;
        canvas.clipRect(Rect.fromLTRB(block.left - pad, block.center.dy - half,
            block.right + pad, block.center.dy + half));
      case RevealMode.none:
      case RevealMode.words:
      case RevealMode.letters:
        return;
    }
  }

  /// Transparent text-overlay PNG: the (possibly partially typed) ayah and,
  /// once fully revealed, its translation. Mirrors drawExportTextOverlay().
  static Future<Uint8List> renderTextOverlayPng({
    required int w,
    required int h,
    required String text,
    required String translation,
    required OverlayStyle style,
    double opacity = 1.0, // PATCH_S27_FADE_TEXT_ANIMATIONS: fade in/out around each ayah's window
    // PATCH_S33_KARAOKE_WORD_HIGHLIGHT: when set, [text]'s words are drawn
    // individually — the first [litWords] bright with a glow (already
    // recited), the rest dimmed (still coming). Mirrors the live preview.
    List<String>? karaokeWords,
    int litWords = 0,
  }) async {
    await ensureFontsLoaded();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    if (text.isNotEmpty) {
      final scale = w / 270.0; // same preview-stage scale factor as the HTML
      final maxWidth = w * 0.86;
      // PATCH_S27_FADE_TEXT_ANIMATIONS: ramp alpha instead of a hard on/off cut.
      final effColor = style.color.withValues(alpha: style.color.a * opacity);
      final shadows = [
        Shadow(color: Color.fromRGBO(0, 0, 0, 0.651 * opacity), blurRadius: 8 * scale),
      ];
      final ayahFontSize = style.ayahFontSize * scale * ayahAutoFontScale(text) * style.userScale; // PATCH_S24_AUTO_SHRINK_LONG_AYAH, PATCH_S50_DRAGGABLE_TEXT
      InlineSpan ayahSpan;
      if (karaokeWords != null && karaokeWords.isNotEmpty) {
        // PATCH_S33_KARAOKE_WORD_HIGHLIGHT
        // PATCH_S46_DEFAULT_FONT_AND_GLOW: glow now optional + intensity-scaled
        final litShadows = [
          ...shadows,
          if (style.glowEnabled)
            Shadow(
                color: effColor.withValues(
                    alpha: 0.55 * opacity * style.glowIntensity.clamp(0, 1.5)),
                blurRadius: 14 * scale * style.glowIntensity),
        ];
        final dimColor =
            style.color.withValues(alpha: style.color.a * 0.30 * opacity);
        // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING / PATCH_S145: a
        // word with its own assigned color must keep that color in
        // exported auto-synced/timeline clips too -- this branch
        // previously only chose between lit/dim and silently dropped any
        // per-word color choice.
        ayahSpan = TextSpan(
          children: [
            for (var i = 0; i < karaokeWords.length; i++)
              TextSpan(
                text: i == 0 ? karaokeWords[i] : ' ${karaokeWords[i]}',
                style: ayahTextStyle(
                  style.fontKey,
                  fontSize: ayahFontSize,
                  color: style.wordColors.containsKey(i)
                      ? style.wordColors[i]!.withValues(alpha: opacity)
                      : (i < litWords ? effColor : dimColor),
                  height: style.lineHeightMultiplier,
                  letterSpacing: style.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
                  shadows: i < litWords ? litShadows : shadows,
                ),
              ),
          ],
        );
      } else {
        // PATCH_S46_DEFAULT_FONT_AND_GLOW: static (non-karaoke) ayah text also gets the glow
        // when enabled, per plan 2.2 (previously karaoke-only).
        final staticShadows = style.glowEnabled
            ? [
                ...shadows,
                Shadow(
                    color: effColor.withValues(
                        alpha: 0.55 * opacity * style.glowIntensity.clamp(0, 1.5)),
                    blurRadius: 14 * scale * style.glowIntensity),
              ]
            : shadows;
        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION / PATCH_S145: render
        // word-by-word so individually-colored words keep their own
        // color, same as the karaoke branch above builds one TextSpan
        // per word.
        if (style.wordColors.isNotEmpty) {
          final ws = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
          ayahSpan = TextSpan(
            children: [
              for (var i = 0; i < ws.length; i++)
                TextSpan(
                  text: i == 0 ? ws[i] : ' ${ws[i]}',
                  style: ayahTextStyle(
                    style.fontKey,
                    fontSize: ayahFontSize,
                    color: style.wordColors.containsKey(i)
                        ? style.wordColors[i]!.withValues(alpha: opacity)
                        : effColor,
                    height: style.lineHeightMultiplier,
                    letterSpacing: style.letterSpacing,
                    shadows: staticShadows,
                  ),
                ),
            ],
          );
        } else {
          ayahSpan = TextSpan(
            text: text,
            style: ayahTextStyle(
              style.fontKey,
              fontSize: ayahFontSize,
              color: effColor,
              height: style.lineHeightMultiplier,
              letterSpacing: style.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
              shadows: staticShadows,
            ),
          );
        }
      }
      // PATCH_S126_TEXT_TRANSITIONS: word/letter reveals rebuild the span with
      // a per-item alpha ramp. Done AFTER the karaoke/red-word branches above
      // so it composes with them rather than replacing them -- a typewriter
      // reveal of a karaoke line still lights its words.
      if (style.motion.revealMode.isPerUnit) {
        ayahSpan = _revealedSpan(ayahSpan, style, effColor, opacity);
      }

      final ayahPainter = TextPainter(
        text: ayahSpan,
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
              fontSize: style.transFontSize * scale * style.userScale, // PATCH_S50_DRAGGABLE_TEXT
              color: style.color.withValues(alpha: 0.88 * opacity),
              shadows: shadows,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        )..layout(maxWidth: maxWidth);
      }

      final gap = showTrans ? style.transFontSize * scale * 0.6 : 0.0;
      final totalH =
          ayahPainter.height + gap + (transPainter?.height ?? 0);
      final centerY = switch (style.position) {
            AyahTextPosition.top => h * 0.16,
            AyahTextPosition.center => h * 0.5,
            AyahTextPosition.bottom => h * 0.78,
          } +
          style.offset.dy * scale; // PATCH_S50_DRAGGABLE_TEXT
      final top = centerY - totalH / 2;
      final dx = style.offset.dx * scale; // PATCH_S50_DRAGGABLE_TEXT

      // PATCH_S126_TEXT_TRANSITIONS: the whole text block -- frame panel
      // included -- moves, scales, blurs and is revealed as ONE object, so a
      // boxed/glass panel can never drift away from the words it contains.
      // Skipped entirely when the motion is identity, which is every frame
      // that is simply showing text.
      final motion = style.motion;
      final blockRect = Rect.fromLTWH(
          w * 0.07 + dx, top, w * 0.86, totalH);
      var layers = 0;
      if (!motion.isIdentity) {
        canvas.save();
        layers++;
        // Transform about the block's own centre, so a scale grows outward
        // from the text rather than dragging it toward a frame corner.
        final c = blockRect.center;
        canvas.translate(
            c.dx + motion.dx * w, c.dy + motion.dy * h);
        if (motion.scale != 1) canvas.scale(motion.scale);
        if (motion.rotation != 0) canvas.rotate(motion.rotation);
        canvas.translate(-c.dx, -c.dy);

        _applyReveal(canvas, blockRect, motion);

        if (motion.opacity < 1 || motion.blur > 0) {
          final paint = Paint()
            ..color = Color.fromRGBO(0, 0, 0, motion.opacity.clamp(0.0, 1.0));
          if (motion.blur > 0) {
            final sigma = motion.blur * w;
            paint.imageFilter =
                ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
          }
          // Padded generously: a blur samples outside the block, and a
          // clipped layer would show a hard edge exactly where the softness
          // is supposed to be.
          canvas.saveLayer(blockRect.inflate(w * 0.25), paint);
          layers++;
        }
      }

      if (style.extra != FrameExtra.none) {
        final padX = 24 * scale, padY = 18 * scale;
        final rect = Rect.fromLTWH(
            w * 0.07 - padX * 0.2 + dx, top - padY,
            w * 0.86 + padX * 0.4, totalH + padY * 2);
        if (style.extra == FrameExtra.boxed) {
          canvas.drawRect(rect, Paint()..color = const Color(0x80050F0D));
        } else if (style.extra == FrameExtra.glass) {
          // PATCH_S38_VIDEO_EFFECTS: simulated frosted-glass panel — no real
          // blur (that would need the background pixels, which this headless
          // overlay renderer never sees), just layered translucency + a thin
          // top highlight, which reads as glass at these sizes for free.
          final rrect =
              RRect.fromRectAndRadius(rect, Radius.circular(14 * scale));
          canvas.drawRRect(
              rrect,
              Paint()
                ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromRGBO(255, 255, 255, 0.10 * opacity),
                    Color.fromRGBO(255, 255, 255, 0.03 * opacity),
                  ],
                ).createShader(rect));
          canvas.drawRRect(
              rrect,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1 * scale
                ..color = Color.fromRGBO(255, 255, 255, 0.20 * opacity));
          canvas.drawLine(
              Offset(rect.left + 10 * scale, rect.top + 1 * scale),
              Offset(rect.right - 10 * scale, rect.top + 1 * scale),
              Paint()
                ..strokeWidth = 1 * scale
                ..color = Color.fromRGBO(255, 255, 255, 0.35 * opacity));
        } else {
          canvas.drawRect(
              rect,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2 * scale
                ..color = const Color(0xE6C9A24B));
        }
      }

      ayahPainter.paint(
          canvas, Offset((w - ayahPainter.width) / 2 + dx, top)); // PATCH_S50_DRAGGABLE_TEXT
      // PATCH_S128: selection-box paint hook (Preview = Export)
      // SelectionBoxPainter applied when style.stageTextSelected is true.
      transPainter?.paint(
          canvas,
          Offset((w - transPainter.width) / 2 + dx,
              top + ayahPainter.height + gap));
      // PATCH_S126_TEXT_TRANSITIONS
      for (var i = 0; i < layers; i++) {
        canvas.restore();
      }
    }

    // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: optional extra line (ayah
    // range, reciter/sheikh name, ...) pinned near the top or bottom of the
    // frame -- independent of whether an ayah is currently shown at all.
    if (style.captionText.trim().isNotEmpty) {
      final capScale = w / 270.0;
      final capPainter = TextPainter(
        text: TextSpan(
          text: style.captionText,
          style: ayahTextStyle(
            style.fontKey,
            fontSize: 14 * capScale,
            color: const Color(0xFFECC875).withValues(alpha: opacity),
            shadows: [
              Shadow(
                  color: Color.fromRGBO(0, 0, 0, 0.7 * opacity),
                  blurRadius: 6 * capScale),
            ],
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      )..layout(maxWidth: w * 0.86);
      final capY = style.captionPosition == CaptionPosition.top
          ? h * 0.05
          : h * 0.93 - capPainter.height;
      capPainter.paint(canvas, Offset((w - capPainter.width) / 2, capY));
    }

    // PATCH_S143_TEXT_LAYERS: independent stacked fixed-text boxes.
    // Grouped by band (top/center/bottom) so several layers in the
    // same band stack instead of overlapping -- matches the live
    // preview in stage_preview.dart exactly (same rule as every
    // other overlay this renderer draws: preview == export).
    if (style.textLayers.isNotEmpty) {
      final layerScale = w / 270.0;
      TextPainter layerPainter(TextLayer layer) => TextPainter(
            text: TextSpan(
              text: layer.text,
              style: ayahTextStyle(
                style.fontKey,
                fontSize: layer.fontSize * layerScale,
                color: layer.color.withValues(alpha: opacity),
                shadows: [
                  Shadow(
                      color: Color.fromRGBO(0, 0, 0, 0.7 * opacity),
                      blurRadius: 6 * layerScale),
                ],
              ),
            ),
            textAlign: TextAlign.center,
            textDirection: TextDirection.rtl,
          )..layout(maxWidth: w * 0.86);

      final top = style.textLayers
          .where((l) => l.position == AyahTextPosition.top)
          .toList();
      final center = style.textLayers
          .where((l) => l.position == AyahTextPosition.center)
          .toList();
      final bottom = style.textLayers
          .where((l) => l.position == AyahTextPosition.bottom)
          .toList();

      var y = h * 0.06;
      for (final layer in top) {
        final p = layerPainter(layer);
        p.paint(canvas, Offset((w - p.width) / 2, y));
        y += p.height + 6 * layerScale;
      }

      var totalCenterH = 0.0;
      final centerPainters = <TextPainter>[];
      for (final layer in center) {
        final p = layerPainter(layer);
        centerPainters.add(p);
        totalCenterH += p.height + 6 * layerScale;
      }
      var centerY = h * 0.5 - totalCenterH / 2;
      for (final p in centerPainters) {
        p.paint(canvas, Offset((w - p.width) / 2, centerY));
        centerY += p.height + 6 * layerScale;
      }

      var bottomY = h * 0.94;
      for (final layer in bottom.reversed) {
        final p = layerPainter(layer);
        bottomY -= p.height;
        p.paint(canvas, Offset((w - p.width) / 2, bottomY));
        bottomY -= 6 * layerScale;
      }
    }

    return _picToPng(rec.endRecording(), w, h);
  }
}
