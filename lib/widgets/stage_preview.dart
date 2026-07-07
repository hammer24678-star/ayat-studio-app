// The live stage: phone-frame preview showing the chosen background or the
// uploaded video, with the ayah text overlaid in the selected font/color/
// position — including the live typewriter reveal while an auto-sync
// timeline is playing back.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../theme/ayat_fonts.dart';
import '../theme/ayat_theme.dart';

/// What the overlay is currently showing. During auto-sync playback the
/// typewriter ticker feeds partial text through here; otherwise it mirrors
/// the statically selected ayah.
class StageOverlayText {
  final String text;
  final String translation;
  const StageOverlayText(this.text, this.translation);
}

class StagePreview extends StatefulWidget {
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
  State<StagePreview> createState() => _StagePreviewState();
}

class _StagePreviewState extends State<StagePreview>
    with SingleTickerProviderStateMixin {
  // PATCH_S28_ANIMATED_BACKGROUND: a slow, subtle sheen sweep across the preset gradient
  // backgrounds. Purely decorative -- skipped whenever a video or a
  // custom image is actually showing (see build() below), so it never
  // competes with real content.
  late final AnimationController _bgAnim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _bgAnim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final videoController = widget.videoController;
    final liveOverride = widget.liveOverride;
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
                // PATCH_S28_ANIMATED_BACKGROUND: only over the plain preset gradient --
                // never over real video or a custom photo background.
                if (!videoReady &&
                    !(state.useCustomBg && state.customBgPath != null))
                  AnimatedBuilder(
                    animation: _bgAnim,
                    builder: (context, _) {
                      final t = Curves.easeInOut.transform(_bgAnim.value);
                      return IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment(-1 + 2 * t, -1 + t),
                              end: Alignment(1 - t, 1 - 2 * t),
                              colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.06),
                                Colors.white.withValues(alpha: 0),
                              ],
                              stops: const [0.3, 0.5, 0.7],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
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
                    return _overlay(context, text, trans, scale);
                  },
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _overlay(BuildContext context, String text, String trans, double scale) {
    final state = widget.state; // PATCH_S28_ANIMATED_BACKGROUND: now a State method, not a field
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
                fontSize: state.ayahFontSize * scale * ayahAutoFontScale(text), // PATCH_S24_AUTO_SHRINK_LONG_AYAH
                color: state.textColor,
                height: 1.5,
                shadows: shadows,
              ),
            ),
            if (state.showTranslation && trans.isNotEmpty) ...[
              SizedBox(height: 4 * scale),
              Text(
                trans,
                textAlign: TextAlign.center,
                style: translationTextStyle(
                  fontSize: state.transFontSize * scale,
                  color: state.textColor.withValues(alpha: 0.88),
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
