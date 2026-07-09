// PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS
// REAL EXPORT — the native counterpart of the HTML prototype's canvas +
// MediaRecorder pipeline, rebuilt on ffmpeg for an actual MP4:
//   • background gradient / custom image, or the uploaded video (cover-fit)
//   • real chroma-key (ffmpeg chromakey) with the chosen key color and the
//     same threshold/softness sliders
//   • the ayah text overlay rendered by Flutter's text engine (exact same
//     fonts/wrapping as the preview) — as a PNG frame sequence when an
//     auto-sync timeline exists, so each word lights up on screen in the
//     exported video exactly when it's recited (karaoke-style; long ayahs
//     split into 2-3+ sequential parts, see karaoke.dart)
//   • optional rain/snow/light-dust particle loop composited over the
//     video/background, under the text (see stage_effects.dart)
//   • bismillah intro / outro title cards as standalone segments,
//     concatenated before/after the clip (never composited over it)
//   • audio priority: attached reciter recitation > the video's own track >
//     silence; ayah-boundary trim honored via -ss/-t
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' show Color;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:media_store_plus/media_store_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import 'karaoke.dart'; // PATCH_S33_KARAOKE_WORD_HIGHLIGHT
import 'overlay_renderer.dart';
import 'stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS

class ExportService {
  // PATCH_S33_KARAOKE_WORD_HIGHLIGHT: word-lighting pace now comes from
  // karaoke.dart (proportional to each part's slice of the recitation).
  static const double fadeMs = 300; // PATCH_S27_FADE_TEXT_ANIMATIONS: fade in/out duration
  static const double titleCardSec = 2.2;
  static const int overlayFps = 6; // typewriter granularity in the export
  // PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS: no more 120s cap and no more forced 1080 tier --
  // duration follows the full trim, resolution follows the source video.
  // This is only a safety ceiling against pathological 8K phone footage
  // stalling ffmpeg on-device, not a feature limit.
  static const int maxExportResolutionCap = 3840;

  // PATCH_S37_CANCEL_LONG_JOBS: user-requested abort. Kills any running
  // ffmpeg session immediately and makes the frame-render loops bail at
  // their next iteration.
  static bool _cancelRequested = false;
  static Future<void> cancel() async {
    _cancelRequested = true;
    await FFmpegKit.cancel();
  }

  static void _checkCancel() {
    if (_cancelRequested) throw Exception('تم إلغاء التصدير');
  }

  static Future<String> export({
    required StudioState state,
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    _cancelRequested = false; // PATCH_S37_CANCEL_LONG_JOBS
    final work = Directory.systemTemp.createTempSync('ayat_export');
    try {
      onStatus?.call('جارٍ تجهيز الخلفية والنصوص…');

      // ---- durations & audio probing ----
      double duration;
      var videoHasAudio = false;
      var videoHasVideoStream = true; // PATCH_S23_AUDIO_ONLY_UPLOAD_FIX
      double clipStart = 0;
      // PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS: w/h default to the static-export tier and are
      // overridden below to follow the source video, if any.
      // PATCH_S53_LANDSCAPE_EXPORT: canvas size for the audio-only/static-export case now
      // comes from the 3-way ratio picker instead of a squareRatio bool.
      final ratioSpec =
          kAspectRatios.firstWhere((r) => r.$1 == state.aspectRatio);
      var w = ratioSpec.$3;
      var h = ratioSpec.$4;
      if (state.hasVideo) {
        final info = await _probe(state.videoPath!);
        videoHasAudio = info.hasAudio;
        videoHasVideoStream = info.hasVideo;
        final full = info.duration ?? 8;
        if (info.width != null &&
            info.height != null &&
            info.width! > 0 &&
            info.height! > 0) {
          // PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS: export at the source's own resolution, only
          // downscaling if it exceeds the safety ceiling.
          // PATCH_S54_PRO_EXPORT_CONTROLS: with a fit mode selected the
          // canvas is the aspect-ratio picker's frame instead of the
          // source size (rotation swaps the source dims first).
          int srcW = info.width!;
          int srcH = info.height!;
          if (state.videoRotationQuarterTurns.isOdd) {
            final t = srcW;
            srcW = srcH;
            srcH = t;
          }
          if (state.videoFit != VideoFitMode.source) {
            srcW = ratioSpec.$3;
            srcH = ratioSpec.$4;
          }
          final longest = srcW > srcH ? srcW : srcH;
          final scale = longest > maxExportResolutionCap
              ? maxExportResolutionCap / longest
              : 1.0;
          w = (srcW * scale).round();
          h = (srcH * scale).round();
        }
        if (state.trimStart != null && state.trimEnd != null) {
          clipStart = state.trimStart!;
          // PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS: no more maxExportSec clamp -- full trim length.
          duration = max(0.5, state.trimEnd! - state.trimStart!);
        } else if (state.trimManualEnd > 0 &&
            (state.trimManualStart > 0.05 ||
                state.trimManualEnd < full - 0.05)) {
          // PATCH_S34_PLAYER_CONTROLS_TRIM: free manual cut from the range
          // slider — used only when no ayah-boundary trim is chosen.
          clipStart = state.trimManualStart.clamp(0.0, full);
          duration =
              max(0.5, min(state.trimManualEnd, full) - clipStart);
        } else {
          // PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS: no more maxExportSec clamp -- full source length.
          duration = full;
        }
      } else {
        duration = state.staticDurationSec.clamp(2, 60).toDouble();
      }
      // PATCH_S54_PRO_EXPORT_CONTROLS: optional user resolution cap on top
      // of the safety ceiling, applied to video and static exports alike.
      final userCap = switch (state.exportResolution) {
        ExportResolutionCap.source => maxExportResolutionCap,
        ExportResolutionCap.hd1080 => 1920,
        ExportResolutionCap.hd720 => 1280,
      };
      final longestSide = max(w, h);
      if (longestSide > userCap) {
        final s = userCap / longestSide;
        w = (w * s).round();
        h = (h * s).round();
      }
      if (w.isOdd) w += 1; // encoders require even dimensions
      if (h.isOdd) h += 1;

      // ---- background PNG (needed for chroma, static export, title cards) ----
      final bgPng = '${work.path}/bg.png';
      await File(bgPng).writeAsBytes(await OverlayRenderer.renderBackgroundPng(
        w: w,
        h: h,
        bgIndex: state.bgIndex,
        customBgPath: state.useCustomBg ? state.customBgPath : null,
      ));

      // ---- PATCH_S40_MULTI_BG_CYCLE: optional cycling-background timeline
      // (null when inactive — _buildMainCommand then uses the single bgPng)
      final bgSegments = await _buildBgCycleSegments(
        state: state,
        work: work,
        w: w,
        h: h,
        clipStart: clipStart,
        duration: duration,
      );

      // ---- text overlay: animated sequence (auto-sync) or single PNG ----
      final style = OverlayStyle(
        fontKey: state.fontKey,
        ayahFontSize: state.ayahFontSize,
        transFontSize: state.transFontSize,
        color: state.textColor,
        position: state.textPosition,
        extra: state.extra,
        showTranslation: state.showTranslation,
        glowEnabled: state.glowEnabled, // PATCH_S46_DEFAULT_FONT_AND_GLOW
        glowIntensity: state.glowIntensity,
        letterSpacing: state.letterSpacing, // PATCH_S48_TEXT_SPACING_TOGGLES
        lineHeightMultiplier: state.lineHeightMultiplier,
        offset: state.textOffset, // PATCH_S50_DRAGGABLE_TEXT
        userScale: state.textUserScale,
      );
      String? overlaySeqPattern;
      String? overlayPng;
      if (state.hasVideo && state.timelineActive && state.timeline.isNotEmpty) {
        final seqDir = Directory('${work.path}/seq')..createSync();
        await _renderKaraokeSequence(
          dir: seqDir.path,
          state: state,
          style: style,
          w: w,
          h: h,
          clipStart: clipStart,
          duration: duration,
          onStatus: onStatus,
        );
        overlaySeqPattern = '${seqDir.path}/ov_%05d.png';
      } else if (state.hasAyah) {
        overlayPng = '${work.path}/overlay.png';
        await File(overlayPng)
            .writeAsBytes(await OverlayRenderer.renderTextOverlayPng(
          w: w,
          h: h,
          text: state.ayahText,
          translation: state.translationText,
          style: style,
        ));
      }

      // ---- PATCH_S34_STAGE_EFFECTS: transparent particle loop frames ----
      // Rendered by the exact same painter as the live preview, then tiled
      // over the whole clip by ffmpeg with -stream_loop. Drawn at up to
      // 1080 wide and upscaled in the filter graph — particles are soft
      // shapes, so this keeps 4K exports fast at no visible cost.
      String? effectSeqPattern;
      if (state.effect != StageEffect.none) {
        onStatus?.call('جارٍ رسم تأثير ${state.effect.label}…');
        final fxDir = Directory('${work.path}/fx')..createSync();
        final fxW = min(w, 1080);
        var fxH = (h * fxW / w).round();
        if (fxH.isOdd) fxH += 1;
        for (var i = 0; i < StageEffects.exportFrameCount; i++) {
          _checkCancel(); // PATCH_S37_CANCEL_LONG_JOBS
          final bytes = await StageEffects.renderEffectFramePng(
            w: fxW,
            h: fxH,
            effect: state.effect,
            timeSec: i / StageEffects.exportFps,
            intensity: state.effectIntensity,
          );
          final name = 'fx_${i.toString().padLeft(3, '0')}.png';
          await File('${fxDir.path}/$name').writeAsBytes(bytes);
        }
        effectSeqPattern = '${fxDir.path}/fx_%03d.png';
      }

      // ---- main segment ----
      onStatus?.call('جارٍ التصدير الفعلي…');
      final mainMp4 = '${work.path}/main.mp4';
      final reciterPath = state.selectedReciterAudio;
      final cmd = _buildMainCommand(
        state: state,
        w: w,
        h: h,
        duration: duration,
        clipStart: clipStart,
        bgPng: bgPng,
        bgSegments: bgSegments, // PATCH_S40_MULTI_BG_CYCLE
        overlaySeqPattern: overlaySeqPattern,
        overlayPng: overlayPng,
        effectSeqPattern: effectSeqPattern, // PATCH_S34_STAGE_EFFECTS
        reciterPath: reciterPath,
        videoHasAudio: videoHasAudio,
        videoHasVideoStream: videoHasVideoStream, // PATCH_S23_AUDIO_ONLY_UPLOAD_FIX
        outPath: mainMp4,
      );
      await _run(cmd, duration, (f) => onProgress?.call(f * 0.8));

      // ---- intro / outro cards, then concat ----
      final parts = <String>[];
      if (state.showIntro) {
        onStatus?.call('جارٍ إنشاء بطاقة البسملة…');
        parts.add(await _renderTitleSegment(
            work, 'intro', kBasmala, state, w, h));
      }
      parts.add(mainMp4);
      if (state.showOutro) {
        onStatus?.call('جارٍ إنشاء بطاقة الخاتمة…');
        parts.add(await _renderTitleSegment(
            work, 'outro',
            state.outroText.trim().isEmpty ? kDefaultOutro : state.outroText,
            state, w, h));
      }

      final docs = await getApplicationDocumentsDirectory();
      final outPath =
          '${docs.path}/ayat_studio_${DateTime.now().millisecondsSinceEpoch}.mp4';
      if (parts.length == 1) {
        await File(mainMp4).copy(outPath);
      } else {
        onStatus?.call('جارٍ دمج المقاطع…');
        final listFile = File('${work.path}/concat.txt');
        listFile.writeAsStringSync(
            parts.map((p) => "file '$p'").join('\n'));
        // identical encode params across segments, so stream copy is enough;
        // fall back to a re-encode if some device's muxer still objects.
        final copyCmd =
            '-y -f concat -safe 0 -i "${listFile.path}" -c copy "$outPath"';
        try {
          await _run(copyCmd, null, null);
        } catch (_) {
          final reencodeCmd =
              '-y -f concat -safe 0 -i "${listFile.path}" ${_encodeParams(state.exportQuality)} "$outPath"';
          await _run(reencodeCmd, null, null);
        }
      }
      onProgress?.call(1);
      // PATCH_S25_SAVE_TO_DOWNLOADS: also publish a copy into the public Download/
      // folder so the video shows up in the device's file manager /
      // Downloads app right away -- the path above alone is app-
      // private storage and invisible outside the app. Best-effort:
      // export already succeeded even if this extra copy fails.
      if (Platform.isAndroid) {
        try {
          // PATCH_S30_FIX_S25_SAVEFILE_SIGNATURE: saveFile has no fileName param on the real
          // media_store_plus 0.1.3 API -- it takes the name from
          // tempFilePath's own basename. Passing fileName here is
          // what broke the CI build ("No named parameter with the
          // name 'fileName'").
          await MediaStore().saveFile(
            tempFilePath: outPath,
            dirType: DirType.download,
            dirName: DirName.download,
          );
        } catch (_) {
          // Non-fatal -- the Share button below still works from outPath.
        }
      }
      return outPath;
    } finally {
      work.delete(recursive: true).ignore();
    }
  }

  // PATCH_S33_KARAOKE_WORD_HIGHLIGHT
  // Renders the karaoke overlay as a PNG frame sequence: each ayah part is
  // shown whole with the already-recited words lit and the rest dimmed,
  // exactly like the live preview (same karaoke.dart timing). Frames are
  // deduplicated: a PNG is only rendered when the lit-word count or fade
  // actually changes; identical frames reuse the previously encoded bytes,
  // so a 2-minute clip stays fast.
  static Future<void> _renderKaraokeSequence({
    required String dir,
    required StudioState state,
    required OverlayStyle style,
    required int w,
    required int h,
    required double clipStart,
    required double duration,
    void Function(String status)? onStatus,
  }) async {
    final frames = (duration * overlayFps).ceil() + 1;
    final cache = <String, List<int>>{};
    final chunkCache = <TimelineSegment, List<KaraokeChunk>>{};
    for (var i = 0; i < frames; i++) {
      _checkCancel(); // PATCH_S37_CANCEL_LONG_JOBS
      if (i % (overlayFps * 5) == 0) {
        onStatus?.call(
            'جارٍ رسم إضاءة الكلمات مع التلاوة… ${(i * 100 / frames).round()}٪');
      }
      final videoT = clipStart + i / overlayFps;
      TimelineSegment? seg;
      for (final s in state.timeline) {
        if (videoT >= s.start && videoT < s.end) {
          seg = s;
          break;
        }
      }
      String text = '', trans = '';
      List<String>? words;
      var lit = 0;
      String key = 'empty';
      double opacity = 1.0; // PATCH_S27_FADE_TEXT_ANIMATIONS
      if (seg != null) {
        final cue =
            karaokeCueAt(chunkCache[seg] ??= buildKaraokeChunks(seg), videoT);
        final chunk = cue.chunk;
        text = chunk.text;
        trans = chunk.translation;
        // PATCH_S51_KARAOKE_TOGGLE: burn in plain static text instead of
        // per-word lighting when the toggle is off -- renderTextOverlayPng
        // already renders static text whenever karaokeWords is null/empty.
        words = state.karaokeEnabled ? chunk.words : null;
        lit = state.karaokeEnabled ? cue.litWords : 0;
        // PATCH_S27_FADE_TEXT_ANIMATIONS: fade in over the first 300ms and out over the
        // last 300ms of this part's on-screen window.
        final msIntoChunk = (videoT - chunk.start) * 1000;
        final msToChunkEnd = (chunk.end - videoT) * 1000;
        final fadeIn = (msIntoChunk / fadeMs).clamp(0.0, 1.0);
        final fadeOut = (msToChunkEnd / fadeMs).clamp(0.0, 1.0);
        opacity = fadeIn < fadeOut ? fadeIn : fadeOut;
        key =
            '${seg.ayah.surahNum}:${seg.ayah.num}:${chunk.index}:$lit:${(opacity * 20).round()}';
      }
      var bytes = cache[key];
      if (bytes == null) {
        bytes = await OverlayRenderer.renderTextOverlayPng(
            w: w,
            h: h,
            text: text,
            translation: trans,
            style: style,
            opacity: opacity,
            karaokeWords: words,
            litWords: lit);
        cache[key] = bytes;
      }
      final name = 'ov_${i.toString().padLeft(5, '0')}.png';
      await File('$dir/$name').writeAsBytes(bytes);
    }
  }

  // PATCH_S38_VIDEO_EFFECTS: export-time video effects. All ffmpeg-side, all
  // optional/off-by-default except softTransitions — none touch the audio.

  // Background-image-only Ken Burns: pre-scales the still image up, then
  // zoompan()s slowly into it. d=1 makes zoompan advance exactly one output
  // frame per input frame it consumes — the robust pattern for a single
  // -loop 1 image input (no total frame count to precompute; it just keeps
  // pace with however many frames -t/-loop end up producing). Never applied
  // to the uploaded recitation video itself, only to generated backgrounds.
  static String _staticImageFilterChain(int w, int h, bool kenBurns) {
    if (!kenBurns) return 'scale=$w:$h,fps=30';
    final bigW = (w * 1.28).round();
    final bigH = (h * 1.28).round();
    return 'scale=$bigW:$bigH,'
        "zoompan=z='min(zoom+0.0007,1.16)':d=1:s=${w}x$h:fps=30";
  }

  static String _colorGradeFilter(ColorGrade g) => switch (g) {
        ColorGrade.none => '',
        // warm gold: lift saturation/contrast a touch, push red up, blue down
        ColorGrade.warmGold =>
          'eq=saturation=1.15:gamma=1.05:contrast=1.05,'
              'colorbalance=rs=0.12:gs=0.02:bs=-0.12:rm=0.08:bm=-0.08',
        // night teal: slightly desaturated and darker, push blue up
        ColorGrade.nightTeal =>
          'eq=saturation=0.9:contrast=1.08:brightness=-0.02,'
              'colorbalance=rs=-0.10:bs=0.15:rm=-0.06:bm=0.10',
        // classic sepia via a fixed channel-mix matrix
        ColorGrade.sepia =>
          'colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131',
        // soft mono: desaturated, not harsh pure B&W, small contrast lift
        ColorGrade.softMono => 'hue=s=0,eq=contrast=1.06:brightness=0.01',
      };

  static String _vignetteFilter(int intensity) {
    // ffmpeg's vignette angle: smaller angle = stronger/darker corners.
    // The 0..100 slider maps onto a mild..strong range computed here in
    // Dart, so no ffmpeg-side expression parsing is needed.
    final angle =
        (1.35 - intensity.clamp(0, 100) / 100 * 1.0).clamp(0.30, 1.35);
    return 'vignette=angle=${angle.toStringAsFixed(3)}';
  }

  static String _grainFilter(int intensity) {
    final amt = (intensity.clamp(0, 100) / 100 * 26 + 4).round();
    return 'noise=alls=$amt:allf=t+u';
  }

  // Combined color-grade + vignette + grain chain, shared by the main clip
  // and the bismillah/outro title cards so a chosen look stays consistent
  // across all exported segments. Empty string when nothing is enabled.
  static String _postFilterChain(StudioState state) {
    final parts = <String>[];
    final grade = _colorGradeFilter(state.colorGrade);
    if (grade.isNotEmpty) parts.add(grade);
    if (state.vignetteEnabled) {
      parts.add(_vignetteFilter(state.vignetteIntensity));
    }
    if (state.grainEnabled) parts.add(_grainFilter(state.grainIntensity));
    return parts.join(',');
  }

  // PATCH_S40_MULTI_BG_CYCLE: the ordered (backgroundPngPath, seconds)
  // timeline behind the cycling background. Returns null when cycling isn't
  // active (fewer than 2 backgrounds chosen, or a custom/AI-art background
  // is in use — those stay single-background), in which case callers fall
  // back to the plain bgPng.
  static Future<List<({String path, double dur})>?> _buildBgCycleSegments({
    required StudioState state,
    required Directory work,
    required int w,
    required int h,
    required double clipStart,
    required double duration,
  }) async {
    if (!state.multiBgEnabled ||
        state.useCustomBg ||
        state.multiBgIndexes.length < 2 ||
        duration <= 0) {
      return null;
    }

    // One PNG per selected background, rendered once — reused by every
    // cycle slot that comes back around to it.
    final pngs = <String>[];
    for (var i = 0; i < state.multiBgIndexes.length; i++) {
      _checkCancel();
      final p = '${work.path}/bg_multi_$i.png';
      await File(p).writeAsBytes(await OverlayRenderer.renderBackgroundPng(
        w: w,
        h: h,
        bgIndex: state.multiBgIndexes[i],
      ));
      pngs.add(p);
    }

    // ---- boundary times, seconds into the export (0..duration) ----
    final bounds = <double>[0];
    if (state.bgSwitchTrigger == BgSwitchTrigger.ayahs &&
        state.timelineActive &&
        state.timeline.isNotEmpty) {
      final n = state.bgSwitchAyahs.clamp(1, 10);
      var count = 0;
      for (final seg in state.timeline) {
        final segEnd = (seg.end - clipStart).clamp(0.0, duration);
        if (segEnd <= 0) continue; // ayah lies entirely before the trim
        count++;
        if (count % n == 0 && segEnd < duration) bounds.add(segEnd);
      }
    } else {
      // No active auto-sync timeline (or seconds explicitly chosen) — fall
      // back to a fixed-interval switch.
      final step = state.bgSwitchSeconds.clamp(3, 30).toDouble();
      var t = step;
      while (t < duration) {
        bounds.add(t);
        t += step;
      }
    }
    bounds.add(duration);

    // Safety cap — a pathological combo (3s interval on a very long export)
    // would otherwise build an unwieldy filter_complex graph.
    const maxSegments = 40;
    if (bounds.length - 1 > maxSegments) {
      final step = duration / maxSegments;
      bounds
        ..clear()
        ..add(0);
      var t = step;
      while (t < duration) {
        bounds.add(t);
        t += step;
      }
      bounds.add(duration);
    }

    final segs = <({String path, double dur})>[];
    for (var i = 0; i < bounds.length - 1; i++) {
      final d = bounds[i + 1] - bounds[i];
      if (d < 0.05) continue; // drop rounding-noise slivers
      segs.add((path: pngs[i % pngs.length], dur: d));
    }
    if (segs.length < 2) return null; // not enough runway to actually cycle
    return segs;
  }

  // PATCH_S40_MULTI_BG_CYCLE: ffmpeg inputs + filter fragment turning N
  // looped stills into one background stream, joined by a hard-cut concat
  // or a pairwise xfade chain. Ken Burns is intentionally skipped here —
  // zoompan's frame math assumes one continuous still, which breaks across
  // a cut/crossfade boundary.
  static ({String inputs, List<String> filters, String outLabel, int count})
      _bgCycleChain({
    required int startIdx,
    required int w,
    required int h,
    required List<({String path, double dur})> segments,
    required BgTransitionStyle transition,
    required double crossfadeDur,
  }) {
    var idx = startIdx;
    final inputsBuf = StringBuffer();
    final filters = <String>[];
    final segLabels = <String>[];
    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      inputsBuf
          .write('-loop 1 -t ${seg.dur.toStringAsFixed(3)} -i "${seg.path}" ');
      final segIdx = idx++;
      final lbl = 'bgseg$i';
      filters.add('[$segIdx:v]scale=$w:$h,fps=30,format=yuv420p[$lbl]');
      segLabels.add(lbl);
    }

    if (transition == BgTransitionStyle.hardCut) {
      final ins = segLabels.map((l) => '[$l]').join();
      filters.add('${ins}concat=n=${segLabels.length}:v=1:a=0[bgv]');
      return (
        inputs: inputsBuf.toString(),
        filters: filters,
        outLabel: 'bgv',
        count: idx - startIdx,
      );
    }

    // PATCH_S70_MORE_TRANSITIONS: any non-hardCut style chains xfade pairwise using that
    // style's own ffmpeg transition name (was hardcoded to 'fade' -- crossfade
    // was the only style that existed at the time). Duration is still clamped
    // to whichever neighbouring slot is shorter, so a short switch interval can
    // never ask xfade for more overlap than a slot actually has.
    var running = segLabels[0];
    var elapsed = segments[0].dur;
    final xfadeName = transition.ffmpegXfadeName;
    for (var i = 1; i < segLabels.length; i++) {
      final safeDur =
          min(crossfadeDur, min(segments[i - 1].dur, segments[i].dur) * 0.9)
              .clamp(0.05, crossfadeDur);
      final offset = max(0.0, elapsed - safeDur);
      final outLbl = i == segLabels.length - 1 ? 'bgv' : 'bgx$i';
      filters.add('[$running][${segLabels[i]}]xfade=transition=$xfadeName:'
          'duration=${safeDur.toStringAsFixed(3)}:offset=${offset.toStringAsFixed(3)}[$outLbl]');
      running = outLbl;
      elapsed += segments[i].dur - safeDur;
    }
    return (
      inputs: inputsBuf.toString(),
      filters: filters,
      outLabel: 'bgv',
      count: idx - startIdx,
    );
  }

  // PATCH_S54_PRO_EXPORT_CONTROLS: user-selectable encoder tier.
  static String _encodeParams([ExportQuality q = ExportQuality.high]) {
    final (crf, abr) = switch (q) {
      ExportQuality.high => (18, 192),
      ExportQuality.balanced => (21, 160),
      ExportQuality.compact => (26, 128),
    };
    return '-c:v libx264 -preset veryfast -crf $crf -pix_fmt yuv420p '
        '-c:a aac -ar 44100 -ac 2 -b:a ${abr}k -movflags +faststart';
  }

  // PATCH_S54_PRO_EXPORT_CONTROLS: audio chain for the exported track —
  // optional apad, volume and gentle fades. Empty when nothing applies.
  static String _audioFilterArgs(StudioState state,
      {required bool needsPad, required double duration}) {
    final parts = <String>[];
    if (needsPad) parts.add('apad');
    if ((state.audioVolume - 1.0).abs() > 0.01) {
      parts.add(
          'volume=${state.audioVolume.clamp(0.0, 2.0).toStringAsFixed(2)}');
    }
    if (state.audioFadeIn) parts.add('afade=t=in:st=0:d=1.0');
    if (state.audioFadeOut) {
      final st = max(0.0, duration - 1.5);
      parts.add('afade=t=out:st=${st.toStringAsFixed(3)}:d=1.5');
    }
    return parts.isEmpty ? '' : '-af "${parts.join(',')}"';
  }

  static String _buildMainCommand({
    required StudioState state,
    required int w,
    required int h,
    required double duration,
    required double clipStart,
    required String bgPng,
    required List<({String path, double dur})>? bgSegments, // PATCH_S40_MULTI_BG_CYCLE
    required String? overlaySeqPattern,
    required String? overlayPng,
    required String? effectSeqPattern, // PATCH_S34_STAGE_EFFECTS
    required String? reciterPath,
    required bool videoHasAudio,
    required bool videoHasVideoStream, // PATCH_S23_AUDIO_ONLY_UPLOAD_FIX
    required String outPath,
  }) {
    final inputs = StringBuffer('-y ');
    final filters = <String>[];
    var idx = 0;

    String base;
    if (state.hasVideo && videoHasVideoStream) { // PATCH_S23_AUDIO_ONLY_UPLOAD_FIX
      // PATCH_S34_PLAYER_CONTROLS_TRIM: seek for the ayah-boundary trim OR the manual cut.
      final trim =
          clipStart > 0.001 ? '-ss ${clipStart.toStringAsFixed(3)} ' : '';
      inputs.write('$trim-t ${duration.toStringAsFixed(3)} -i "${state.videoPath}" ');
      final vIdx = idx++;
      // PATCH_S54_PRO_EXPORT_CONTROLS: rotation/mirror first, then fit the
      // frame onto the canvas — fill-crop (default look) or letterboxed
      // over a blurred, darkened copy of itself.
      final rot = switch (state.videoRotationQuarterTurns % 4) {
        1 => 'transpose=1,',
        2 => 'transpose=1,transpose=1,',
        3 => 'transpose=2,',
        _ => '',
      };
      final mir = state.videoMirror ? 'hflip,' : '';
      if (state.videoFit == VideoFitMode.fitBlur) {
        filters.add('[$vIdx:v]$rot${mir}split=2[vfa][vfb]');
        filters.add('[vfa]scale=$w:$h:force_original_aspect_ratio=increase,'
            'crop=$w:$h,boxblur=20:2,eq=brightness=-0.08[vbg]');
        filters.add(
            '[vfb]scale=$w:$h:force_original_aspect_ratio=decrease[vfg]');
        filters.add('[vbg][vfg]overlay=(W-w)/2:(H-h)/2,fps=30[v0]');
      } else {
        filters.add(
            '[$vIdx:v]$rot${mir}scale=$w:$h:force_original_aspect_ratio=increase,'
            'crop=$w:$h,fps=30[v0]');
      }
      if (state.chromaEnabled) {
        // PATCH_S40_MULTI_BG_CYCLE: single bgPng (optionally Ken Burns —
        // PATCH_S38_VIDEO_EFFECTS) or the cycling multi-bg chain, either way
        // one [bgv] label to composite the keyed foreground onto.
        String bgLabel;
        if (bgSegments != null) {
          final chain = _bgCycleChain(
            startIdx: idx,
            w: w,
            h: h,
            segments: bgSegments,
            transition: state.bgTransitionStyle,
            crossfadeDur: state.bgCrossfadeDuration,
          );
          inputs.write(chain.inputs);
          idx += chain.count;
          filters.addAll(chain.filters);
          bgLabel = chain.outLabel;
        } else {
          inputs.write('-loop 1 -i "$bgPng" ');
          final bgIdx = idx++;
          filters.add(
              '[$bgIdx:v]${_staticImageFilterChain(w, h, state.kenBurnsEnabled)}[bgv]');
          bgLabel = 'bgv';
        }
        final keyHex = _hex(state.chromaColor);
        final sim = (0.45 - (state.chromaThreshold - 40) / 100 * 0.30)
            .clamp(0.10, 0.45)
            .toStringAsFixed(3);
        final blend =
            (state.chromaSoftness / 300).clamp(0.02, 0.30).toStringAsFixed(3);
        filters.add('[v0]chromakey=0x$keyHex:$sim:$blend[fg]');
        filters.add('[$bgLabel][fg]overlay=shortest=1[base]');
        base = 'base';
      } else {
        base = 'v0';
      }
    } else {
      // PATCH_S40_MULTI_BG_CYCLE: same single-vs-cycling split for the
      // no-video (static background) export.
      if (bgSegments != null) {
        final chain = _bgCycleChain(
          startIdx: idx,
          w: w,
          h: h,
          segments: bgSegments,
          transition: state.bgTransitionStyle,
          crossfadeDur: state.bgCrossfadeDuration,
        );
        inputs.write(chain.inputs);
        idx += chain.count;
        filters.addAll(chain.filters);
        base = chain.outLabel;
      } else {
        inputs.write('-loop 1 -t ${duration.toStringAsFixed(3)} -i "$bgPng" ');
        final bgIdx = idx++;
        // PATCH_S38_VIDEO_EFFECTS: was a plain fps=30 — now optionally Ken Burns.
        filters.add(
            '[$bgIdx:v]${_staticImageFilterChain(w, h, state.kenBurnsEnabled)}[base]');
        base = 'base';
      }
    }

    // PATCH_S34_STAGE_EFFECTS: particle loop over the video/background,
    // under the ayah text — same z-order as the live preview.
    if (effectSeqPattern != null) {
      inputs.write(
          '-framerate ${StageEffects.exportFps} -stream_loop -1 -start_number 0 -i "$effectSeqPattern" ');
      final fxIdx = idx++;
      filters.add('[$fxIdx:v]format=rgba,scale=$w:$h[fx]');
      filters.add('[$base][fx]overlay=0:0[basefx]');
      base = 'basefx';
    }

    if (overlaySeqPattern != null) {
      inputs.write(
          '-framerate $overlayFps -start_number 0 -i "$overlaySeqPattern" ');
      final ovIdx = idx++;
      filters.add('[$ovIdx:v]format=rgba[ovf]');
      filters.add('[$base][ovf]overlay=0:0[outv]');
    } else if (overlayPng != null) {
      inputs.write('-loop 1 -i "$overlayPng" ');
      final ovIdx = idx++;
      // gentle fade-in so the static text appears like the preview reveal;
      // PATCH_S27_FADE_TEXT_ANIMATIONS: and fade back out near the end instead of a hard cut.
      final fadeOutStart = (duration - 0.6).clamp(0.0, double.infinity);
      final fadeOutFilter = duration > 1.3
          ? ',fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=0.6:alpha=1'
          : '';
      filters.add('[$ovIdx:v]format=rgba,fade=t=in:st=0:d=0.6:alpha=1$fadeOutFilter[ovf]');
      filters.add('[$base][ovf]overlay=0:0:shortest=1[outv]');
    } else {
      filters.add('[$base]null[outv]');
    }

    String audioMap;
    var audioFilter = '';
    if (reciterPath != null) {
      inputs.write('-i "$reciterPath" ');
      audioMap = '-map $idx:a';
      // pad recitation with silence up to -t
      // PATCH_S54_PRO_EXPORT_CONTROLS: + volume/fades
      audioFilter =
          _audioFilterArgs(state, needsPad: true, duration: duration);
      idx++;
    } else if (state.hasVideo && !videoHasVideoStream && videoHasAudio) {
      // PATCH_S23_AUDIO_ONLY_UPLOAD_FIX: the "video" upload was actually an audio-only
      // recitation file -- the visual branch above used bgPng instead
      // of this input, so its audio never got wired in; pull it in
      // here the same way an attached reciter track would be.
      // PATCH_S34_PLAYER_CONTROLS_TRIM: honor the trim/cut on it too.
      final aTrim =
          clipStart > 0.001 ? '-ss ${clipStart.toStringAsFixed(3)} ' : '';
      inputs.write('$aTrim-t ${duration.toStringAsFixed(3)} -i "${state.videoPath}" ');
      audioMap = '-map $idx:a';
      audioFilter =
          _audioFilterArgs(state, needsPad: true, duration: duration);
      idx++;
    } else if (state.hasVideo && videoHasVideoStream && videoHasAudio) {
      audioMap = '-map 0:a';
      // PATCH_S54_PRO_EXPORT_CONTROLS: volume/fades on the clip's own track
      audioFilter =
          _audioFilterArgs(state, needsPad: false, duration: duration);
    } else {
      inputs.write(
          '-f lavfi -t ${duration.toStringAsFixed(3)} -i anullsrc=channel_layout=stereo:sample_rate=44100 ');
      audioMap = '-map $idx:a';
      idx++;
    }

    // PATCH_S38_VIDEO_EFFECTS: color grade / vignette / grain, plus soft
    // fades toward the bismillah/outro cards (which live in separate
    // segments concatenated before/after this one — see export()), applied
    // to the composited [outv] before mapping. Audio is untouched by all of
    // this.
    final post = _postFilterChain(state);
    var outLabel = 'outv';
    if (post.isNotEmpty) {
      filters.add('[outv]$post[outv2]');
      outLabel = 'outv2';
    }
    if (state.softTransitions && (state.showIntro || state.showOutro)) {
      final fades = <String>[];
      if (state.showIntro) fades.add('fade=t=in:st=0:d=0.4');
      if (state.showOutro) {
        final fadeOutStart = (duration - 0.4).clamp(0.0, double.infinity);
        fades.add('fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=0.4');
      }
      filters.add('[$outLabel]${fades.join(',')}[outv3]');
      outLabel = 'outv3';
    }

    return '$inputs-filter_complex "${filters.join(';')}" '
        '-map "[$outLabel]" $audioMap $audioFilter '
        '-t ${duration.toStringAsFixed(3)} ${_encodeParams(state.exportQuality)} "$outPath"';
  }

  static Future<String> _renderTitleSegment(Directory work, String name,
      String text, StudioState state, int w, int h) async {
    final png = '${work.path}/$name.png';
    await File(png).writeAsBytes(await OverlayRenderer.renderTitleCardPng(
      w: w,
      h: h,
      text: text,
      bgIndex: state.bgIndex,
      customBgPath: state.useCustomBg ? state.customBgPath : null,
    ));
    final mp4 = '${work.path}/$name.mp4';
    // PATCH_S38_VIDEO_EFFECTS: same Ken Burns + color grade/vignette/grain
    // as the main clip, plus a gentle fade in/out of its own when soft
    // transitions are on — keeps the bismillah/outro consistent with the
    // chosen look and less abrupt.
    final vf = <String>[_staticImageFilterChain(w, h, state.kenBurnsEnabled)];
    final post = _postFilterChain(state);
    if (post.isNotEmpty) vf.add(post);
    if (state.softTransitions) {
      final fadeOutStart = (titleCardSec - 0.35).clamp(0.0, double.infinity);
      vf.add('fade=t=in:st=0:d=0.35');
      vf.add('fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=0.35');
    }
    final cmd = '-y -loop 1 -t $titleCardSec -i "$png" '
        '-f lavfi -t $titleCardSec -i anullsrc=channel_layout=stereo:sample_rate=44100 '
        '-vf "${vf.join(',')}" -map 0:v -map 1:a ${_encodeParams(state.exportQuality)} "$mp4"';
    await _run(cmd, titleCardSec, null);
    return mp4;
  }

  static String _hex(Color c) {
    String two(double v) =>
        ((v * 255).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0');
    return '${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
  }

  static Future<void> _run(String cmd, double? durationSec,
      void Function(double fraction)? onProgress) async {
    final completer = Completer<void>();
    await FFmpegKit.executeAsync(cmd, (session) async {
      final rc = await session.getReturnCode();
      if (ReturnCode.isSuccess(rc)) {
        completer.complete();
      } else if (_cancelRequested) {
        // PATCH_S37_CANCEL_LONG_JOBS: the non-success rc is our own abort,
        // not a real encoder failure — surface it as the cancel message.
        completer.completeError(Exception('تم إلغاء التصدير'));
      } else {
        final logs = await session.getAllLogsAsString() ?? '';
        final tail = logs.length > 600 ? logs.substring(logs.length - 600) : logs;
        completer.completeError(
            Exception('تعذّر التصدير (ffmpeg rc=$rc)\n$tail'));
      }
    }, null, (stats) {
      if (durationSec != null && durationSec > 0 && onProgress != null) {
        final ms = stats.getTime().toDouble();
        onProgress((ms / 1000 / durationSec).clamp(0.0, 1.0));
      }
    });
    return completer.future;
  }

  // PATCH_S23_AUDIO_ONLY_UPLOAD_FIX: also report whether the file actually has a video
  // stream, since the same picker/state field is used for both real
  // video uploads and audio-only recitation uploads.
  static Future<({double? duration, bool hasAudio, bool hasVideo, int? width, int? height})>
      _probe(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    double? dur;
    var hasAudio = false;
    var hasVideoStream = false;
    int? width;
    int? height;
    if (info != null) {
      dur = double.tryParse(info.getDuration() ?? '');
      for (final s in info.getStreams()) {
        if (s.getType() == 'audio') hasAudio = true;
        if (s.getType() == 'video') {
          hasVideoStream = true;
          // PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS: native resolution, so export can follow it.
          width ??= s.getWidth();
          height ??= s.getHeight();
        }
      }
    }
    return (
      duration: dur,
      hasAudio: hasAudio,
      hasVideo: hasVideoStream,
      width: width,
      height: height,
    );
  }
}
