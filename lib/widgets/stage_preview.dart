// The live stage: phone-frame preview showing the chosen background or the
// uploaded video, with the ayah text overlaid in the selected font/color/
// position — including the karaoke word-lighting while an auto-sync
// timeline is playing back, tap-to-pause, and the optional particle effect
// (rain/snow/light-dust) layer.
import 'dart:async';
import 'dart:io';
import 'dart:math'; // PATCH_S58_LIVE_EFFECTS_PREVIEW
import 'dart:ui' as ui; // PATCH_S60_FIX_POINTMODE

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
  // PATCH_S83_SYNC_QOL: small "سورة كذا — آية كذا" chip on the stage during
  // auto-sync playback, so you always know which detection is showing.
  final String? ayahLabel;
  const StageOverlayText(this.text, this.translation,
      [this.segmentKey = '', this.karaokeWords, this.litWords = 0,
      this.ayahLabel]);
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

  // PATCH_S58_LIVE_EFFECTS_PREVIEW: slow breathing zoom approximating the export's zoompan
  // Ken Burns move -- a real ffmpeg zoompan only ever zooms forward for
  // the length of the clip, but the preview loops indefinitely with no
  // export duration to pace against, so it breathes in/out instead.
  late final AnimationController _kenBurnsAnim = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  // PATCH_S58_LIVE_EFFECTS_PREVIEW: the grain dot field is regenerated on a plain ~90ms Timer,
  // not a 60fps AnimationController -- real grain reads as flicker, not
  // smooth motion, and a coarse refresh is far cheaper on-device (this
  // is a Termux/S22 build) than repainting a dense random field every
  // frame.
  final ValueNotifier<int> _grainSeed = ValueNotifier(0);
  Timer? _grainTimer;

  // PATCH_S34_PLAYER_CONTROLS_TRIM: transient ▶/⏸ flash after tapping the video.
  IconData? _tapFlashIcon;
  Timer? _tapFlashTimer;

  @override
  void dispose() {
    _bgAnim.dispose();
    _fxAnim.dispose();
    _kenBurnsAnim.dispose(); // PATCH_S58_LIVE_EFFECTS_PREVIEW
    _grainTimer?.cancel(); // PATCH_S58_LIVE_EFFECTS_PREVIEW
    _grainSeed.dispose(); // PATCH_S58_LIVE_EFFECTS_PREVIEW
    _tapFlashTimer?.cancel();
    super.dispose();
  }

  void _flash(IconData icon) {
    _tapFlashTimer?.cancel();
    setState(() => _tapFlashIcon = icon);
    _tapFlashTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _tapFlashIcon = null);
    });
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
    _flash(nowPlaying ? Icons.play_arrow : Icons.pause);
  }

  // PATCH_S83_SYNC_QOL: the standard video-player gesture — double-tap the
  // right half of the stage to jump 5s forward, the left half 5s back.
  // (Double-tapping the ayah TEXT itself still resets its drag position —
  // the text's own GestureDetector sits above this layer and wins.)
  void _doubleTapSeek(TapDownDetails details, double stageWidth) {
    final c = widget.videoController;
    if (c == null || !c.value.isInitialized) return;
    final forward = details.localPosition.dx > stageWidth / 2;
    final dur = c.value.duration;
    var target = c.value.position + Duration(seconds: forward ? 5 : -5);
    if (target < Duration.zero) target = Duration.zero;
    if (target > dur) target = dur;
    c.seekTo(target);
    _flash(forward ? Icons.forward_5 : Icons.replay_5);
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final videoController = widget.videoController;
    final liveOverride = widget.liveOverride;
    return AspectRatio(
      // PATCH_S53_LANDSCAPE_EXPORT: covers all three shapes now instead of just 9:16/1:1.
      aspectRatio: switch (state.aspectRatio) {
        AyatAspectRatio.square11 => 1.0,
        AyatAspectRatio.landscape169 => 16 / 9,
        AyatAspectRatio.story916 => 9 / 16,
      },
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
        // PATCH_S58_LIVE_EFFECTS_PREVIEW: same on-only-when-needed pattern as the particle
        // loop above, for Ken Burns and grain.
        if (state.kenBurnsEnabled) {
          if (!_kenBurnsAnim.isAnimating) _kenBurnsAnim.repeat(reverse: true);
        } else if (_kenBurnsAnim.isAnimating) {
          _kenBurnsAnim.stop();
          _kenBurnsAnim.value = 0;
        }
        if (state.grainEnabled) {
          _grainTimer ??= Timer.periodic(const Duration(milliseconds: 90),
              (_) => _grainSeed.value++);
        } else {
          _grainTimer?.cancel();
          _grainTimer = null;
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Container(
            decoration: BoxDecoration(
              gradient: state.useCustomBg && state.customBgPath != null
                  ? null
                  : kBackgrounds[state.bgIndex].gradient,
              border: Border.all(color: AyatColors.hairline),
              borderRadius: BorderRadius.circular(26),
            ),
            child: ColorFiltered(
              // PATCH_S58_LIVE_EFFECTS_PREVIEW: approximates the export's color-grade chain
              // live -- see _liveColorFilter below for how close each grade
              // gets. The exported MP4 stays the authoritative render.
              colorFilter: _liveColorFilter(state.colorGrade),
              child: ColorFiltered(
              // PATCH_S85_VIDEO_ADJUST: manual brightness/contrast/saturation
              // stacked over the preset grade, same order as the export's
              // eq filter (identity matrix when everything is neutral).
              colorFilter: _adjustColorFilter(state.adjustBrightness,
                  state.adjustContrast, state.adjustSaturation),
              child: Stack(
              fit: StackFit.expand,
              children: [
                // PATCH_S51_BG_CROSSFADE: the AI-art/custom-photo background
                // used to hard-cut via DecorationImage, so a new per-ayah AI
                // art image popped in instantly between ayat. This crossfades
                // using the same transition setting the export already
                // respects (state.bgTransitionStyle / bgCrossfadeDuration),
                // keyed on the file path so it only re-animates when the
                // actual image changes.
                if (state.useCustomBg && state.customBgPath != null)
                  Positioned.fill(
                    // PATCH_S85_VIDEO_ADJUST: the custom/AI-art photo
                    // background blurs too (matches the export, where gblur
                    // hits the composited base layer).
                    child: ImageFiltered(
                      imageFilter: state.videoBlur > 0.05
                          ? ui.ImageFilter.blur(
                              sigmaX: state.videoBlur * scale,
                              sigmaY: state.videoBlur * scale,
                              tileMode: TileMode.clamp)
                          : ui.ImageFilter.matrix(Matrix4.identity().storage),
                    child: AnimatedSwitcher(
                      duration: state.bgTransitionStyle ==
                              BgTransitionStyle.crossfade
                          ? Duration(
                              milliseconds:
                                  (state.bgCrossfadeDuration * 1000).round())
                          : Duration.zero,
                      switchInCurve: Curves.easeInOut,
                      switchOutCurve: Curves.easeInOut,
                      layoutBuilder: (current, previous) => Stack(
                        fit: StackFit.expand,
                        children: [
                          ...previous,
                          if (current != null) current,
                        ],
                      ),
                      child: state.kenBurnsEnabled
                          ? AnimatedBuilder(
                              // PATCH_S58_LIVE_EFFECTS_PREVIEW: only the photo/AI-art background is a
                              // discrete image widget in the preview tree, so
                              // that's the only case previewed here -- the flat
                              // preset gradient still gets Ken Burns at export
                              // time, just not shown live.
                              animation: _kenBurnsAnim,
                              child: Image.file(
                                File(state.customBgPath!),
                                key: ValueKey(state.customBgPath),
                                fit: BoxFit.cover,
                              ),
                              builder: (context, child) => Transform.scale(
                                scale: 1.0 + 0.08 * _kenBurnsAnim.value,
                                child: child,
                              ),
                            )
                          : Image.file(
                              File(state.customBgPath!),
                              key: ValueKey(state.customBgPath),
                              fit: BoxFit.cover,
                            ),
                    ),
                    ), // PATCH_S85_VIDEO_ADJUST: closes ImageFiltered
                  ),
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
                  // PATCH_S54_PRO_EXPORT_CONTROLS: rotation/mirror preview,
                  // and contain-fit when «احتواء + خلفية ضبابية» is chosen
                  // (the blurred fill itself is rendered in the export).
                  // PATCH_S85_VIDEO_ADJUST: optional live blur of the video
                  // layer only — text/particles above stay sharp, matching
                  // the export's gblur placement.
                  ImageFiltered(
                    imageFilter: state.videoBlur > 0.05
                        ? ui.ImageFilter.blur(
                            sigmaX: state.videoBlur * scale,
                            sigmaY: state.videoBlur * scale,
                            tileMode: TileMode.clamp)
                        : ui.ImageFilter.matrix(Matrix4.identity().storage),
                    child: FittedBox(
                    fit: state.videoFit == VideoFitMode.fitBlur
                        ? BoxFit.contain
                        : BoxFit.cover,
                    clipBehavior: Clip.hardEdge,
                    child: RotatedBox(
                      quarterTurns: state.videoRotationQuarterTurns,
                      child: Transform.flip(
                        flipX: state.videoMirror,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    ),
                  ),
                  ), // PATCH_S85_VIDEO_ADJUST: closes ImageFiltered
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
                // PATCH_S83_SYNC_QOL: double-tap left/right half seeks ∓/±5s.
                if (controller != null && controller.value.isInitialized)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: _togglePlayback,
                      onDoubleTapDown: (d) =>
                          _doubleTapSeek(d, constraints.maxWidth),
                      onDoubleTap: () {}, // keeps the recognizer armed
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
                // PATCH_S83_SYNC_QOL: which ayah the auto-sync playback is on.
                ValueListenableBuilder<StageOverlayText?>(
                  valueListenable: liveOverride,
                  builder: (context, live, _) {
                    final label = live?.ayahLabel;
                    if (label == null || label.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return PositionedDirectional(
                      bottom: 10,
                      end: 10,
                      child: IgnorePointer(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: AyatColors.ink.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AyatColors.hairline),
                          ),
                          child: Text(
                            label,
                            style: const TextStyle(
                                fontSize: 9.5, color: AyatColors.goldBright),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // PATCH_S116_LIVE_CAPTION_PREVIEW: state.captionText (the
                // "نص إضافي" field from S109) was only ever drawn by the
                // export renderer (OverlayRenderer.renderTextOverlayPng) --
                // never shown here, so it looked like the feature did
                // nothing while editing. Mirrors that same styling.
                if (state.captionText.trim().isNotEmpty)
                  PositionedDirectional(
                    top: state.captionPosition == CaptionPosition.top
                        ? 14
                        : null,
                    bottom: state.captionPosition == CaptionPosition.top
                        ? null
                        : 14,
                    start: 12,
                    end: 12,
                    child: IgnorePointer(
                      child: Text(
                        state.captionText,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13 * scale.clamp(0.8, 1.6),
                          color: AyatColors.goldBright,
                          shadows: const [
                            Shadow(
                                color: Color(0xB3000000), blurRadius: 6),
                          ],
                        ),
                      ),
                    ),
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
                // PATCH_S58_LIVE_EFFECTS_PREVIEW: vignette + grain sit on top of everything,
                // including the ayah text -- matching the export chain, where
                // the post-filter (color grade + vignette + grain) applies to
                // the already-composited frame with text burned in.
                // PATCH_S100_FONTS_SPINSTAR_TINT: sits with vignette/grain in the
                // same "on top of everything, matches the export chain" layer.
                if (state.tintColor != null && state.tintIntensity > 0)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: state.tintColor!.withValues(
                            alpha: (state.tintIntensity / 100 * 0.35)
                                .clamp(0.0, 0.35)),
                        backgroundBlendMode: BlendMode.overlay,
                      ),
                    ),
                  ),
                if (state.vignetteEnabled)
                  IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.center,
                          radius: 0.9,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(
                                alpha: (state.vignetteIntensity / 100 * 0.55)
                                    .clamp(0.0, 0.55)),
                          ],
                          stops: const [0.45, 1.0],
                        ),
                      ),
                    ),
                  ),
                if (state.grainEnabled)
                  IgnorePointer(
                    child: ValueListenableBuilder<int>(
                      valueListenable: _grainSeed,
                      builder: (context, seed, _) => CustomPaint(
                        painter: _GrainPainter(
                            seed: seed, intensity: state.grainIntensity),
                      ),
                    ),
                  ),
              ],
            ),
            ), // PATCH_S85_VIDEO_ADJUST: closes the manual-adjust ColorFiltered
            ), // PATCH_S58_LIVE_EFFECTS_PREVIEW: closes ColorFiltered
          ),
        );
      }),
    );
  }

  // PATCH_S85_VIDEO_ADJUST: the ffmpeg eq brightness/contrast/saturation
  // triple as one 4x5 color matrix: saturation via the standard luminance-
  // preserving mix, then contrast scales around mid-gray and brightness
  // offsets. Identity when everything is neutral.
  static ColorFilter _adjustColorFilter(double b, double c, double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    final o = 255 * (b + (1 - c) / 2);
    return ColorFilter.matrix([
      c * (sr + s), c * sg, c * sb, 0, o,
      c * sr, c * (sg + s), c * sb, 0, o,
      c * sr, c * sg, c * (sb + s), 0, o,
      0, 0, 0, 1, 0,
    ]);
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
      // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING: a red-flagged word
      // stays red regardless of karaoke lit/dim state -- previously
      // redWordIndices was ignored entirely on this branch, so any
      // red selection silently vanished once karaoke highlighting
      // kicked in.
      const redColor = Color(0xFFE53935);
      ayahWidget = Text.rich(
        TextSpan(
          children: [
            for (var i = 0; i < karaokeWords.length; i++)
              TextSpan(
                text: i == 0 ? karaokeWords[i] : ' ${karaokeWords[i]}',
                style: ayahTextStyle(
                  state.fontKey,
                  fontSize: ayahFontSize,
                  color: state.redWordIndices.contains(i)
                      ? redColor
                      : (i < live!.litWords ? state.textColor : dimColor),
                  height: state.lineHeightMultiplier,
                  letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
                  // PATCH_S115_HOTFIX_LIVE_LITWORDS_NULL_CHECK: `live` is
                  // non-null in this branch (karaokeWords came from
                  // live?.karaokeWords and passed the isNotEmpty check
                  // above) but the analyzer can't see that across the
                  // ternary -- same `!` the line above already uses.
                  shadows: i < live!.litWords ? litShadows : shadows,
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
      // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING: this branch never
      // looked at state.redWordIndices before, so tapping a word chip
      // in the "تلوين كلمات بالأحمر" section had zero visible effect
      // in the live preview -- it only ever reached the exported
      // video's static-text path. Mirror that path here.
      if (state.redWordIndices.isNotEmpty) {
        const redColor = Color(0xFFE53935);
        final ws = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
        ayahWidget = Text.rich(
          TextSpan(
            children: [
              for (var i = 0; i < ws.length; i++)
                TextSpan(
                  text: i == 0 ? ws[i] : ' ${ws[i]}',
                  style: ayahTextStyle(
                    state.fontKey,
                    fontSize: ayahFontSize,
                    color: state.redWordIndices.contains(i) ? redColor : state.textColor,
                    height: state.lineHeightMultiplier,
                    letterSpacing: state.letterSpacing,
                    shadows: staticShadows,
                  ),
                ),
            ],
          ),
          textAlign: TextAlign.center,
          textDirection: TextDirection.rtl,
        );
      } else {
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

// PATCH_S58_LIVE_EFFECTS_PREVIEW: rough live-preview twin of ExportService._colorGradeFilter's
// ffmpeg eq/colorbalance/colorchannelmixer chains, expressed as a 4x5
// ColorMatrix Flutter can apply every frame. Sepia uses the exact same
// channel-mix coefficients as the ffmpeg filter; warmGold/nightTeal/
// softMono are tuned approximations, not pixel-identical -- the exported
// MP4 is the authoritative render.
ColorFilter _liveColorFilter(ColorGrade g) {
  switch (g) {
    case ColorGrade.none:
      return const ColorFilter.matrix(<double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case ColorGrade.warmGold:
      return const ColorFilter.matrix(<double>[
        1.20, -0.05, -0.05, 0, 12,
        0.00, 1.05, -0.05, 0, 4,
        -0.05, -0.10, 0.95, 0, -14,
        0, 0, 0, 1, 0,
      ]);
    case ColorGrade.nightTeal:
      return const ColorFilter.matrix(<double>[
        0.90, 0.02, -0.05, 0, -8,
        0.00, 0.95, 0.00, 0, -4,
        -0.05, 0.05, 1.15, 0, 10,
        0, 0, 0, 1, 0,
      ]);
    case ColorGrade.sepia:
      return const ColorFilter.matrix(<double>[
        0.393, 0.769, 0.189, 0, 0,
        0.349, 0.686, 0.168, 0, 0,
        0.272, 0.534, 0.131, 0, 0,
        0, 0, 0, 1, 0,
      ]);
    case ColorGrade.softMono:
      return const ColorFilter.matrix(<double>[
        0.2254, 0.7581, 0.0765, 0, -5.1,
        0.2254, 0.7581, 0.0765, 0, -5.1,
        0.2254, 0.7581, 0.0765, 0, -5.1,
        0, 0, 0, 1, 0,
      ]);
  }
}

// PATCH_S58_LIVE_EFFECTS_PREVIEW: cheap film-grain approximation -- a fixed count of translucent
// dots redrawn from a seeded Random on every timer tick (see _grainTimer
// above), not on every animation frame. Mirrors the ffmpeg
// noise=alls=$amt:allf=t+u filter's 0..100 -> 4..30 intensity mapping
// closely enough to judge the look; grain is inherently random so an
// exact frame-for-frame match isn't meaningful anyway.
class _GrainPainter extends CustomPainter {
  final int seed;
  final int intensity;
  const _GrainPainter({required this.seed, required this.intensity});

  @override
  void paint(Canvas canvas, Size size) {
    final amt = (intensity.clamp(0, 100) / 100 * 26 + 4);
    final count = (size.width * size.height / 900 * (amt / 30))
        .round()
        .clamp(60, 1400);
    final rnd = Random(seed);
    final points = <Offset>[
      for (var i = 0; i < count; i++)
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
    ];
    final paint = Paint()
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: (amt / 100).clamp(0.0, 0.35));
    canvas.drawPoints(ui.PointMode.points, points, paint); // PATCH_S60_FIX_POINTMODE
  }

  @override
  bool shouldRepaint(covariant _GrainPainter old) =>
      old.seed != seed || old.intensity != intensity;
}
