// The live stage: phone-frame preview showing the chosen background or the
// uploaded video, with the ayah text overlaid in the selected font/color/
// position — including the karaoke word-lighting while an auto-sync
// timeline is playing back, tap-to-pause, and the optional particle effect
// (rain/snow/light-dust) layer.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../services/stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS
import '../theme/ayat_fonts.dart';
import '../theme/ayat_theme.dart';

/// What the overlay is currently showing. During auto-sync playback the
/// karaoke ticker feeds the current ayah part through here; otherwise it
/// mirrors the statically selected ayah.
class StageOverlayText {
  final String text;
  final String translation;
  // PATCH_S27_FADE_TEXT_ANIMATIONS: identifies which ayah/segment this reveal belongs to,
  // so the stage can fade BETWEEN ayahs without re-fading on every
  // word of the same ayah part's karaoke lighting.
  final String segmentKey;
  // PATCH_S33_KARAOKE_WORD_HIGHLIGHT: when set, [text]'s words are rendered
  // individually — the first [litWords] bright (already recited), the
  // rest dimmed until the reciter reaches them.
  final List<String>? karaokeWords;
  final int litWords;
  const StageOverlayText(this.text, this.translation,
      [this.segmentKey = '', this.karaokeWords, this.litWords = 0]);
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
    with TickerProviderStateMixin {
  // PATCH_S28_ANIMATED_BACKGROUND: a slow, subtle sheen sweep across the preset gradient
  // backgrounds. Purely decorative -- skipped whenever a video or a
  // custom image is actually showing (see build() below), so it never
  // competes with real content.
  late final AnimationController _bgAnim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat(reverse: true);

  // PATCH_S34_STAGE_EFFECTS: drives one seamless particle loop; only runs
  // while an effect is actually selected.
  late final AnimationController _fxAnim = AnimationController(
    vsync: this,
    duration: Duration(
        milliseconds: (StageEffects.loopSeconds * 1000).round()),
  );

  // PATCH_S34_PLAYER_CONTROLS_TRIM: transient ▶/⏸ flash after tapping the video.
  IconData? _tapFlashIcon;
  Timer? _tapFlashTimer;

  @override
  void dispose() {
    _bgAnim.dispose();
    _fxAnim.dispose();
    _tapFlashTimer?.cancel();
    super.dispose();
  }

  // PATCH_S34_PLAYER_CONTROLS_TRIM: tap anywhere on the stage to pause/resume
  // the uploaded video, with a short feedback icon flash.
  void _togglePlayback() {
    final c = widget.videoController;
    if (c == null || !c.value.isInitialized) return;
    final nowPlaying = !c.value.isPlaying;
    if (nowPlaying) {
      c.play();
    } else {
      c.pause();
    }
    _tapFlashTimer?.cancel();
    setState(() =>
        _tapFlashIcon = nowPlaying ? Icons.play_arrow : Icons.pause);
    _tapFlashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _tapFlashIcon = null);
    });
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
        // PATCH_S34_STAGE_EFFECTS: run the particle loop only when needed.
        if (state.effect != StageEffect.none) {
          if (!_fxAnim.isAnimating) _fxAnim.repeat();
        } else if (_fxAnim.isAnimating) {
          _fxAnim.stop();
        }
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
                    !(state.useCustomBg && state.customBgPath != null) &&
                    state.bgAnimated) // PATCH_S29_BG_ANIMATION_TOGGLE
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
                // PATCH_S34_STAGE_EFFECTS: particles over the video/background,
                // under the ayah text so the words stay readable.
                if (state.effect != StageEffect.none)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: StageEffectPainter(
                        effect: state.effect,
                        loop: _fxAnim,
                        intensity: state.effectIntensity,
                      ),
                    ),
                  ),
                // PATCH_S34_PLAYER_CONTROLS_TRIM: tap the stage to pause/resume.
                if (controller != null && controller.value.isInitialized)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _togglePlayback,
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
                    // PATCH_S27_FADE_TEXT_ANIMATIONS: fade between ayahs/segments instead of
                    // popping instantly. Keyed on the segment identity (falls
                    // back to the raw text when there is none) so an in-
                    // progress typewriter reveal of the SAME ayah does not
                    // re-trigger the fade on every new character.
                    final overlayKey = (live != null && live.segmentKey.isNotEmpty)
                        ? live.segmentKey
                        : text;
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      switchInCurve: Curves.easeOut,
                      switchOutCurve: Curves.easeIn,
                      child: KeyedSubtree(
                        key: ValueKey(overlayKey),
                        child: _overlay(context, live, text, trans, scale),
                      ),
                    );
                  },
                ),
                // PATCH_S34_PLAYER_CONTROLS_TRIM: brief ▶/⏸ feedback after a tap.
                if (_tapFlashIcon != null)
                  Center(
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AyatColors.ink.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_tapFlashIcon,
                            size: 34 * scale.clamp(0.8, 1.6),
                            color: AyatColors.goldBright),
                      ),
                    ),
                  ),
                // PATCH_S34_STAGE_EFFECTS: deliberate ✕ chip to cancel the
                // active effect — a plain tap elsewhere only pauses/resumes.
                if (state.effect != StageEffect.none)
                  PositionedDirectional(
                    top: 10,
                    start: 10,
                    child: GestureDetector(
                      onTap: () =>
                          state.update(() => state.effect = StageEffect.none),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AyatColors.ink.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: AyatColors.hairline),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.close,
                                size: 13, color: AyatColors.goldBright),
                            const SizedBox(width: 4),
                            Text(
                              'إيقاف تأثير ${state.effect.label}',
                              style: const TextStyle(
                                  fontSize: 10, color: AyatColors.goldBright),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _overlay(BuildContext context, StageOverlayText? live, String text,
      String trans, double scale) {
    final state = widget.state; // PATCH_S28_ANIMATED_BACKGROUND: now a State method, not a field
    final alignY = switch (state.textPosition) {
      AyahTextPosition.top => -0.68,
      AyahTextPosition.center => 0.0,
      AyahTextPosition.bottom => 0.56,
    };
    final shadows = [
      Shadow(color: const Color(0xA6000000), blurRadius: 8 * scale),
    ];
    // PATCH_S33_KARAOKE_WORD_HIGHLIGHT: during auto-sync playback, draw each
    // word separately — already-recited words bright with a glow, the
    // rest dimmed until الشيخ reaches them.
    final karaokeWords = live?.karaokeWords;
    final ayahFontSize = state.ayahFontSize * scale * ayahAutoFontScale(text) * state.textUserScale; // PATCH_S24_AUTO_SHRINK_LONG_AYAH, PATCH_S50_DRAGGABLE_TEXT
    Widget ayahWidget;
    if (karaokeWords != null && karaokeWords.isNotEmpty) {
      // PATCH_S46_DEFAULT_FONT_AND_GLOW: glow now optional + intensity-scaled
      final litShadows = [
        ...shadows,
        if (state.glowEnabled)
          Shadow(
              color: state.textColor
                  .withValues(alpha: 0.55 * state.glowIntensity.clamp(0, 1.5)),
              blurRadius: 14 * scale * state.glowIntensity),
      ];
      final dimColor = state.textColor.withValues(alpha: 0.30);
      ayahWidget = Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < karaokeWords.length; i++)
              TextSpan(
                text: i == 0 ? karaokeWords[i] : ' ${karaokeWords[i]}',
                style: ayahTextStyle(
                  state.fontKey,
                  fontSize: ayahFontSize,
                  color: i < live!.litWords ? state.textColor : dimColor,
                  height: state.lineHeightMultiplier,
                  letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
                  shadows: i < live.litWords ? litShadows : shadows,
                ),
              ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
      );
    } else {
      // PATCH_S46_DEFAULT_FONT_AND_GLOW: static ayah text also gets the glow when enabled.
      final staticShadows = state.glowEnabled
          ? [
              ...shadows,
              Shadow(
                  color: state.textColor.withValues(
                      alpha: 0.55 * state.glowIntensity.clamp(0, 1.5)),
                  blurRadius: 14 * scale * state.glowIntensity),
            ]
          : shadows;
      ayahWidget = Text(
        text,
        textAlign: TextAlign.center,
        textDirection: TextDirection.rtl,
        style: ayahTextStyle(
          state.fontKey,
          fontSize: ayahFontSize,
          color: state.textColor,
          height: state.lineHeightMultiplier,
          letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
          shadows: staticShadows,
        ),
      );
    }
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
    } else if (state.extra == FrameExtra.glass) {
      // PATCH_S38_VIDEO_EFFECTS: live-preview twin of the export renderer's
      // frosted-glass panel (layered translucency, no real blur).
      deco = BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x1AFFFFFF), Color(0x08FFFFFF)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33FFFFFF), width: 1),
      );
    }
    // PATCH_S50_DRAGGABLE_TEXT: one GestureDetector handles both drag-to-reposition
    // (one finger) and pinch-to-resize (two fingers) -- onScaleUpdate
    // fires for single-finger pans too, so a separate onPanUpdate would
    // only fight it. gestureStartUserScale is a plain local, not a
    // field: ScaleUpdateDetails.scale is cumulative from onScaleStart,
    // so each gesture needs its own starting snapshot, and a fresh
    // closure over a local is enough since _overlay reruns every build.
    double gestureStartUserScale = state.textUserScale;
    return GestureDetector(
      onScaleStart: (_) => gestureStartUserScale = state.textUserScale,
      onScaleUpdate: (details) {
        state.update(() {
          state.textOffset += details.focalPointDelta / scale;
          state.textUserScale =
              (gestureStartUserScale * details.scale).clamp(0.6, 1.8);
        });
      },
      onDoubleTap: () => state.update(() {
        state.textOffset = Offset.zero;
        state.textUserScale = 1.0;
      }),
      child: Transform.translate(
        offset: Offset(
            state.textOffset.dx * scale, state.textOffset.dy * scale),
        child: Align(
          alignment: Alignment(0, alignY),
          child: Container(
            margin: EdgeInsets.symmetric(horizontal: 0.07 * 270 * scale / 2),
            padding: deco != null
                ? EdgeInsets.symmetric(
                    horizontal: 14 * scale, vertical: 10 * scale)
                : EdgeInsets.zero,
            decoration: deco,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ayahWidget,
                if (state.showTranslation && trans.isNotEmpty) ...[
                  SizedBox(height: 4 * scale),
                  Text(
                    trans,
                    textAlign: TextAlign.center,
                    style: translationTextStyle(
                      fontSize:
                          state.transFontSize * scale * state.textUserScale,
                      color: state.textColor.withValues(alpha: 0.88),
                      shadows: shadows,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
