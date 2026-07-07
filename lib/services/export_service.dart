// REAL EXPORT — the native counterpart of the HTML prototype's canvas +
// MediaRecorder pipeline, rebuilt on ffmpeg for an actual MP4:
//   • background gradient / custom image, or the uploaded video (cover-fit)
//   • real chroma-key (ffmpeg chromakey) with the chosen key color and the
//     same threshold/softness sliders
//   • the ayah text overlay rendered by Flutter's text engine (exact same
//     fonts/wrapping as the preview) — as a PNG frame sequence when an
//     auto-sync timeline exists, so each ayah types itself out on screen in
//     the exported video exactly when it's recited
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
import 'package:path_provider/path_provider.dart';

import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import 'overlay_renderer.dart';

class ExportService {
  static const double typingRevealMs = 1100; // matches the preview animation
  static const double titleCardSec = 2.2;
  static const int overlayFps = 6; // typewriter granularity in the export
  static const int maxExportSec = 120;

  static Future<String> export({
    required StudioState state,
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    final w = 1080;
    final h = state.squareRatio ? 1080 : 1920;
    final work = Directory.systemTemp.createTempSync('ayat_export');
    try {
      onStatus?.call('جارٍ تجهيز الخلفية والنصوص…');

      // ---- durations & audio probing ----
      double duration;
      var videoHasAudio = false;
      var videoHasVideoStream = true; // PATCH_S23_AUDIO_ONLY_UPLOAD_FIX
      double clipStart = 0;
      if (state.hasVideo) {
        final info = await _probe(state.videoPath!);
        videoHasAudio = info.hasAudio;
        videoHasVideoStream = info.hasVideo;
        final full = info.duration ?? 8;
        if (state.trimStart != null && state.trimEnd != null) {
          clipStart = state.trimStart!;
          duration = min(state.trimEnd! - state.trimStart!, maxExportSec.toDouble());
          duration = max(0.5, duration);
        } else {
          duration = min(full, maxExportSec.toDouble());
        }
      } else {
        duration = state.staticDurationSec.clamp(2, 60).toDouble();
      }

      // ---- background PNG (needed for chroma, static export, title cards) ----
      final bgPng = '${work.path}/bg.png';
      await File(bgPng).writeAsBytes(await OverlayRenderer.renderBackgroundPng(
        w: w,
        h: h,
        bgIndex: state.bgIndex,
        customBgPath: state.useCustomBg ? state.customBgPath : null,
      ));

      // ---- text overlay: animated sequence (auto-sync) or single PNG ----
      final style = OverlayStyle(
        fontKey: state.fontKey,
        ayahFontSize: state.ayahFontSize,
        transFontSize: state.transFontSize,
        color: state.textColor,
        position: state.textPosition,
        extra: state.extra,
        showTranslation: state.showTranslation,
      );
      String? overlaySeqPattern;
      String? overlayPng;
      if (state.hasVideo && state.timelineActive && state.timeline.isNotEmpty) {
        final seqDir = Directory('${work.path}/seq')..createSync();
        await _renderTypewriterSequence(
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
        overlaySeqPattern: overlaySeqPattern,
        overlayPng: overlayPng,
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
              '-y -f concat -safe 0 -i "${listFile.path}" ${_encodeParams()} "$outPath"';
          await _run(reencodeCmd, null, null);
        }
      }
      onProgress?.call(1);
      return outPath;
    } finally {
      work.delete(recursive: true).ignore();
    }
  }

  // Renders the typewriter overlay as a PNG frame sequence. Frames are
  // deduplicated: a PNG is only rendered when the visible text actually
  // changes (during the ~1.1s reveal of each ayah); identical frames reuse
  // the previously encoded bytes, so a 2-minute clip stays fast.
  static Future<void> _renderTypewriterSequence({
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
    for (var i = 0; i < frames; i++) {
      if (i % (overlayFps * 5) == 0) {
        onStatus?.call(
            'جارٍ رسم الكتابة الحيّة للآيات… ${(i * 100 / frames).round()}٪');
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
      String key = 'empty';
      if (seg != null) {
        final frac =
            min(1.0, (videoT - seg.start) * 1000 / typingRevealMs);
        final chars = (seg.ayah.ar.length * frac).round();
        text = seg.ayah.ar.substring(0, chars);
        trans = frac >= 1 ? seg.ayah.en : '';
        key = '${seg.ayah.surahNum}:${seg.ayah.num}:$chars:${trans.isNotEmpty}';
      }
      var bytes = cache[key];
      if (bytes == null) {
        bytes = await OverlayRenderer.renderTextOverlayPng(
            w: w, h: h, text: text, translation: trans, style: style);
        cache[key] = bytes;
      }
      final name = 'ov_${i.toString().padLeft(5, '0')}.png';
      await File('$dir/$name').writeAsBytes(bytes);
    }
  }

  static String _encodeParams() =>
      '-c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p '
      '-c:a aac -ar 44100 -ac 2 -b:a 160k -movflags +faststart';

  static String _buildMainCommand({
    required StudioState state,
    required int w,
    required int h,
    required double duration,
    required double clipStart,
    required String bgPng,
    required String? overlaySeqPattern,
    required String? overlayPng,
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
      final trim = (state.trimStart != null && state.trimEnd != null)
          ? '-ss ${clipStart.toStringAsFixed(3)} '
          : '';
      inputs.write('$trim-t ${duration.toStringAsFixed(3)} -i "${state.videoPath}" ');
      final vIdx = idx++;
      filters.add(
          '[$vIdx:v]scale=$w:$h:force_original_aspect_ratio=increase,'
          'crop=$w:$h,fps=30[v0]');
      if (state.chromaEnabled) {
        inputs.write('-loop 1 -i "$bgPng" ');
        final bgIdx = idx++;
        final keyHex = _hex(state.chromaColor);
        final sim = (0.45 - (state.chromaThreshold - 40) / 100 * 0.30)
            .clamp(0.10, 0.45)
            .toStringAsFixed(3);
        final blend =
            (state.chromaSoftness / 300).clamp(0.02, 0.30).toStringAsFixed(3);
        filters.add('[v0]chromakey=0x$keyHex:$sim:$blend[fg]');
        filters.add('[$bgIdx:v]scale=$w:$h[bgv]');
        filters.add('[bgv][fg]overlay=shortest=1[base]');
        base = 'base';
      } else {
        base = 'v0';
      }
    } else {
      inputs.write('-loop 1 -t ${duration.toStringAsFixed(3)} -i "$bgPng" ');
      final bgIdx = idx++;
      filters.add('[$bgIdx:v]fps=30[base]');
      base = 'base';
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
      // gentle fade-in so the static text appears like the preview reveal
      filters.add('[$ovIdx:v]format=rgba,fade=t=in:st=0:d=0.6:alpha=1[ovf]');
      filters.add('[$base][ovf]overlay=0:0:shortest=1[outv]');
    } else {
      filters.add('[$base]null[outv]');
    }

    String audioMap;
    var audioFilter = '';
    if (reciterPath != null) {
      inputs.write('-i "$reciterPath" ');
      audioMap = '-map $idx:a';
      audioFilter = '-af apad'; // pad recitation with silence up to -t
      idx++;
    } else if (state.hasVideo && !videoHasVideoStream && videoHasAudio) {
      // PATCH_S23_AUDIO_ONLY_UPLOAD_FIX: the "video" upload was actually an audio-only
      // recitation file -- the visual branch above used bgPng instead
      // of this input, so its audio never got wired in; pull it in
      // here the same way an attached reciter track would be.
      inputs.write('-i "${state.videoPath}" ');
      audioMap = '-map $idx:a';
      audioFilter = '-af apad';
      idx++;
    } else if (state.hasVideo && videoHasVideoStream && videoHasAudio) {
      audioMap = '-map 0:a';
    } else {
      inputs.write(
          '-f lavfi -t ${duration.toStringAsFixed(3)} -i anullsrc=channel_layout=stereo:sample_rate=44100 ');
      audioMap = '-map $idx:a';
      idx++;
    }

    return '$inputs-filter_complex "${filters.join(';')}" '
        '-map "[outv]" $audioMap $audioFilter '
        '-t ${duration.toStringAsFixed(3)} ${_encodeParams()} "$outPath"';
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
    final cmd = '-y -loop 1 -t $titleCardSec -i "$png" '
        '-f lavfi -t $titleCardSec -i anullsrc=channel_layout=stereo:sample_rate=44100 '
        '-vf fps=30 -map 0:v -map 1:a ${_encodeParams()} "$mp4"';
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
  static Future<({double? duration, bool hasAudio, bool hasVideo})> _probe(String path) async {
    final session = await FFprobeKit.getMediaInformation(path);
    final info = session.getMediaInformation();
    double? dur;
    var hasAudio = false;
    var hasVideoStream = false;
    if (info != null) {
      dur = double.tryParse(info.getDuration() ?? '');
      for (final s in info.getStreams()) {
        if (s.getType() == 'audio') hasAudio = true;
        if (s.getType() == 'video') hasVideoStream = true;
      }
    }
    return (duration: dur, hasAudio: hasAudio, hasVideo: hasVideoStream);
  }
}
