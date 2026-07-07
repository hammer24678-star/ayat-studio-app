// The live stage: phone-frame preview showing the chosen background or the
// uploaded video, with the ayah text overlaid in the selected font/color/
// position — including the live typewriter reveal while an auto-sync
// timeline is playing back.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../services/overlay_renderer.dart';
import '../theme/ayat_fonts.dart';
import '../theme/ayat_theme.dart';

/// What the overlay is currently showing. During auto-sync playback the
/// typewriter ticker feeds partial text through here; otherwise it mirrors
/// the statically selected ayah.
class StageOverlayText {
  final String text;
  final String translation;
  final String reference;
  const StageOverlayText(this.text, this.translation, [this.reference = '']);
}

class _CornersPainter extends CustomPainter {
  final double scale;
  const _CornersPainter(this.scale);
  @override
  void paint(Canvas canvas, Size size) {
    OverlayRenderer.paintCornerOrnaments(
        canvas, size.width, size.height, scale, const Color(0x8CC9A24B));
  }

  @override
  bool shouldRepaint(_CornersPainter old) => old.scale != scale;
}

class StagePreview extends StatelessWidget {
  final StudioState state;
  final VideoPlayerController? videoController;
  final ValueNotifier<StageOverlayText?> liveOverride;
  const StagePreview({
    super.key,
    required this.state,
    required this.videoController,
    required this.liveOverride,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: state.squareRatio ? 1 : 9 / 16,
      child: LayoutBuilder(builder: (context, constraints) {
        final scale = constraints.maxWidth / 270; // HTML preview design width
        final controller = videoController;
        // audio-only uploads initialize with a zero-size video surface —
        // keep showing the background instead of a degenerate FittedBox
        final videoReady = controller != null &&
            controller.value.isInitialized &&
            controller.value.size.width > 0;
        return ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Container(
            decoration: BoxDecoration(
              gradient: state.useCustomBg && state.customBgPath != null
                  ? null
                  : kBackgrounds[state.bgIndex].gradient,
              image: state.useCustomBg && state.customBgPath != null
                  ? DecorationImage(
                      image: FileImage(File(state.customBgPath!)),
                      fit: BoxFit.cover)
                  : null,
              border: Border.all(color: AyatColors.hairline),
              borderRadius: BorderRadius.circular(26),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (videoReady)
                  FittedBox(
                    fit: BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: controller.value.size.width,
                      height: controller.value.size.height,
                      child: VideoPlayer(controller),
                    ),
                  ),
                if (videoReady && state.chromaEnabled)
                  PositionedDirectional(
                    top: 10,
                    start: 10,
                    end: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: AyatColors.ink.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AyatColors.hairline),
                      ),
                      child: const Text(
                        'إزالة الخلفية (الكروم) ستُطبَّق فعليًا في الفيديو المُصدَّر',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10, color: AyatColors.goldBright),
                      ),
                    ),
                  ),
                ValueListenableBuilder<StageOverlayText?>(
                  valueListenable: liveOverride,
                  builder: (context, live, _) {
                    final text = live?.text ?? state.ayahText;
                    final trans = live?.translation ?? state.translationText;
                    final ref = live?.reference ?? state.ayahReference;
                    if (text.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'اختر آية، أو ارفع فيديو واستخدم التعرّف أو المزامنة التلقائية',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12 * scale.clamp(0.8, 1.6),
                                color: AyatColors.parchmentDim),
                          ),
                        ),
                      );
                    }
                    return Stack(fit: StackFit.expand, children: [
                      CustomPaint(painter: _CornersPainter(scale)),
                      _overlay(context, text, trans, ref, scale),
                    ]);
                  },
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _overlay(BuildContext context, String text, String trans, String ref,
      double scale) {
    final alignY = switch (state.textPosition) {
      AyahTextPosition.top => -0.68,
      AyahTextPosition.center => 0.0,
      AyahTextPosition.bottom => 0.56,
    };
    final shadows = [
      Shadow(color: const Color(0xA6000000), blurRadius: 8 * scale),
    ];
    BoxDecoration? deco;
    if (state.extra == FrameExtra.boxed) {
      deco = BoxDecoration(
        color: const Color(0x80050F0D),
        borderRadius: BorderRadius.circular(6),
      );
    } else if (state.extra == FrameExtra.framed) {
      deco = BoxDecoration(
        border: Border.all(color: const Color(0xE6C9A24B), width: 1.5),
      );
    }
    return Align(
      alignment: Alignment(0, alignY),
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 0.07 * 270 * scale / 2),
        padding: deco != null
            ? EdgeInsets.symmetric(horizontal: 14 * scale, vertical: 10 * scale)
            : EdgeInsets.zero,
        decoration: deco,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              text,
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
              style: ayahTextStyle(
                state.fontKey,
                fontSize: state.ayahFontSize * scale,
                color: state.textColor,
                height: 1.5,
                shadows: shadows,
              ),
            ),
            if (state.showTranslation && trans.isNotEmpty) ...[
              SizedBox(height: 4 * scale),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 400),
                child: Text(
                  trans,
                  key: ValueKey(trans),
                  textAlign: TextAlign.center,
                  style: translationTextStyle(
                    fontSize: state.transFontSize * scale,
                    color: state.textColor.withValues(alpha: 0.88),
                    shadows: shadows,
                  ),
                ),
              ),
            ],
            if (ref.isNotEmpty) ...[
              SizedBox(height: 3 * scale),
              Text(
                ref,
                textAlign: TextAlign.center,
                style: translationTextStyle(
                  fontSize: state.transFontSize * scale * 0.82,
                  color: AyatColors.goldBright,
                  shadows: shadows,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
