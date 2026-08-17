import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart'; // PATCH_S96_HONEST_SCAN_DURATION
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class MediaService {
  // PATCH_S96_HONEST_SCAN_DURATION: the container's own declared duration
  // (read via ffprobe), used only as a cross-check -- see
  // TimelineBuilder.build(). Never trusted alone: a container can overstate
  // its duration just as easily as understate it (same lesson as PATCH_S89's
  // export-duration fix, just the opposite direction of mismatch).
  static Future<double?> probedDurationSec(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) return null;
      return double.tryParse(info.getDuration() ?? '');
    } catch (_) {
      return null;
    }
  }

  /// Extracts mono 16kHz PCM WAV from any video/audio file — exactly the
  /// format Whisper wants. Real ffmpeg decode, so none of the browser's
  /// decodeAudioData container-strictness issues apply here.
  // PATCH_S98_RECOVER_TRUNCATED_DECODE: bytes-only estimate of a 16-bit
  // mono 16kHz PCM WAV's duration -- fast, no re-decode needed, just
  // enough precision to compare two candidate extractions against each
  // other and against the probed source duration.
  static double? _quickWavDurationSec(String path) {
    try {
      final bytes = File(path).lengthSync();
      final dataBytes = bytes - 44; // standard WAV header size
      if (dataBytes <= 0) return null;
      return dataBytes / 2 / 16000; // 2 bytes/sample, 16000 samples/sec
    } catch (_) {
      return null;
    }
  }

  static Future<String> extractWav16kMono(String inputPath) async {
    // PATCH_S42_FFMPEG_ERROR_DETAILS: a plain "ffmpeg rc=1" told us nothing about *why* it
    // failed -- catch the one common cause we CAN diagnose upfront
    // (path doesn't actually resolve to a real file -- e.g. a
    // content:// SAF uri ffmpeg's file protocol can't open directly)
    // with a specific message, before ever shelling out to ffmpeg.
    if (!File(inputPath).existsSync()) {
      throw Exception('تعذّر الوصول إلى الملف المحدد — قد يكون مسارًا غير مباشر (SAF) أو تم حذف/نقل الملف بعد اختياره.\n$inputPath');
    }
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    final cmd = '-y -i "$inputPath" -vn -ac 1 -ar 16000 -f wav "$outPath"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      // PATCH_S42_FFMPEG_ERROR_DETAILS: surface ffmpeg's OWN console output -- the actual
      // "Unknown encoder", "Invalid data found when processing input",
      // "No such file or directory", etc. -- instead of a bare return
      // code that tells us nothing about the real cause. Tail-truncated
      // so a noisy log doesn't blow up the error banner.
      final rawLog = (await session.getOutput()) ?? '';
      final log = rawLog.length > 900 ? rawLog.substring(rawLog.length - 900) : rawLog;
      throw Exception('تعذّر استخراج الصوت من الملف (ffmpeg rc=$rc)\n$log');
    }
    // PATCH_S98_RECOVER_TRUNCATED_DECODE: the plain pass above can succeed
    // (rc=0) while still stopping early at a corrupt/discontinuous point in
    // the source -- ffmpeg's strict demuxer treats that as "done", not as
    // an error. If the result comes up meaningfully short of what the
    // container itself claims, give a second, more tolerant pass a chance
    // to push through whatever stopped the first one.
    final probedSec = await probedDurationSec(inputPath);
    final decodedSec = _quickWavDurationSec(outPath);
    if (probedSec != null &&
        decodedSec != null &&
        decodedSec < probedSec * 0.9) {
      final retryPath =
          '${dir.path}/asr_retry_${DateTime.now().millisecondsSinceEpoch}.wav';
      // PATCH_S99_WIDEN_PROBE_WINDOW: -analyzeduration/-probesize widen how
      // far ffmpeg looks ahead before it starts decoding -- fixes a
      // DIFFERENT cause than the error-tolerance flags above: ffmpeg
      // simply not looking far enough into the file to find where the
      // real stream continues, with no corruption involved at all.
      final retryCmd = '-y -err_detect ignore_err '
          '-fflags +genpts+igndts+discardcorrupt '
          '-analyzeduration 100000000 -probesize 100000000 '
          '-i "$inputPath" -vn -ac 1 -ar 16000 -f wav "$retryPath"';
      final retrySession = await FFmpegKit.execute(retryCmd);
      final retryRc = await retrySession.getReturnCode();
      final retryDecodedSec =
          ReturnCode.isSuccess(retryRc) ? _quickWavDurationSec(retryPath) : null;
      if (retryDecodedSec != null && retryDecodedSec > decodedSec) {
        // the tolerant pass genuinely recovered more audio -- use it.
        File(outPath).delete().ignore();
        return retryPath;
      }
      // didn't help -- clean up the retry attempt and keep the original.
      File(retryPath).delete().ignore();
    }
    return outPath;
  }

  // PATCH_S79_CUSTOM_BG_NUMBER_AND_VIDEO_MERGE: concatenates a second video onto the end of the
  // first. Uses filter_complex (not the concat demuxer) because the
  // two clips almost certainly differ in resolution/fps/codec --
  // each is independently scaled+padded onto a common 1080x1920
  // canvas and fps-normalized before the concat filter runs, so
  // mismatched source shapes don't break the join or letterbox
  // unpredictably. Re-encodes (no way to concat mismatched sources
  // losslessly), so this takes real time on longer clips -- callers
  // should run it inside their own busy/progress wrapper.
  static Future<String> mergeVideos(
    String firstPath,
    String secondPath, {
    int width = 1080,
    int height = 1920,
  }) async {
    if (!File(firstPath).existsSync()) {
      throw Exception('تعذّر الوصول إلى الفيديو الأول — قد يكون تم حذفه أو نقله.\n$firstPath');
    }
    if (!File(secondPath).existsSync()) {
      throw Exception('تعذّر الوصول إلى الفيديو الثاني — قد يكون مسارًا غير مباشر (SAF) أو تم حذفه.\n$secondPath');
    }
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final filter = '[0:v]scale=$width:$height:force_original_aspect_ratio=decrease,'
        'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v0];'
        '[1:v]scale=$width:$height:force_original_aspect_ratio=decrease,'
        'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v1];'
        '[0:a]aresample=44100,aformat=channel_layouts=stereo[a0];'
        '[1:a]aresample=44100,aformat=channel_layouts=stereo[a1];'
        '[v0][a0][v1][a1]concat=n=2:v=1:a=1[outv][outa]';
    final cmd = '-y -i "$firstPath" -i "$secondPath" '
        '-filter_complex "$filter" -map "[outv]" -map "[outa]" '
        '-c:v libx264 -preset veryfast -crf 20 -c:a aac -b:a 192k "$outPath"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final rawLog = (await session.getOutput()) ?? '';
      final log = rawLog.length > 900 ? rawLog.substring(rawLog.length - 900) : rawLog;
      throw Exception('تعذّر دمج الفيديوهين (ffmpeg rc=$rc)\n$log');
    }
    return outPath;
  }

  // PATCH_S125_SEQUENCE: S79's merge took exactly two clips, whole, butted
  // end to end. This is the general case -- N clips, each with its own trim,
  // joined either with a hard cut or a real transition.
  //
  // It is deliberately a PRE-PASS rather than a change to the export graph:
  // it renders the sequence to one file, which then becomes the studio's
  // working clip, so auto-sync, the ayah overlay, effects and export all
  // continue to see exactly what they saw before -- a single source. That is
  // not a multi-track NLE, and it is not pretending to be one; it is the
  // shape of multi-clip editing this app's workflow actually needs.
  //
  // filter_complex, not the concat demuxer, for S79's reason: the clips
  // almost certainly differ in resolution, fps and codec, so each is scaled,
  // padded and fps-normalised onto a common canvas first.
  static String buildSequenceCommand(
    List<SequenceClip> clips, {
    required String outPath,
    required int width,
    required int height,
    required String encodeParams,
    SequenceTransition transition = SequenceTransition.cut,
    double transitionSec = 0.5,
  }) {
    if (clips.length < 2) {
      throw ArgumentError('a sequence needs at least two clips');
    }
    final inputs = StringBuffer('-y ');
    final filters = <String>[];

    // Per-clip trim happens on the INPUT (-ss/-t before -i), which seeks
    // rather than decoding-and-discarding — on a phone that is the
    // difference between seconds and minutes on a long source.
    for (var i = 0; i < clips.length; i++) {
      final c = clips[i];
      final ss = c.start > 0.001 ? '-ss ${c.start.toStringAsFixed(3)} ' : '';
      inputs.write('$ss-t ${c.duration.toStringAsFixed(3)} -i "${c.path}" ');
      filters.add('[$i:v]scale=$width:$height:force_original_aspect_ratio=decrease,'
          'pad=$width:$height:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=30[v$i]');
      // apad keeps a silent clip from ending its audio stream early, which
      // would desync everything after it in the concat.
      filters.add('[$i:a]aresample=44100,aformat=channel_layouts=stereo,'
          'apad,atrim=0:${c.duration.toStringAsFixed(3)}[a$i]');
    }

    String vOut, aOut;
    if (transition == SequenceTransition.cut) {
      final pairs = [
        for (var i = 0; i < clips.length; i++) '[v$i][a$i]',
      ].join();
      filters.add('${pairs}concat=n=${clips.length}:v=1:a=1[outv][outa]');
      vOut = 'outv';
      aOut = 'outa';
    } else {
      // xfade overlaps the two clips, so each join SHORTENS the sequence by
      // the transition length -- the offset for join i is the running total
      // of the clips so far minus every transition already spent. Getting
      // this wrong is what makes transitions drift later and later.
      final d = transitionSec.clamp(0.1, 3.0);
      var vPrev = 'v0';
      var aPrev = 'a0';
      var elapsed = clips.first.duration;
      for (var i = 1; i < clips.length; i++) {
        final offset = (elapsed - d).clamp(0.0, double.infinity);
        final vLabel = i == clips.length - 1 ? 'outv' : 'vx$i';
        final aLabel = i == clips.length - 1 ? 'outa' : 'ax$i';
        filters.add('[$vPrev][v$i]xfade=transition=${transition.ffmpegName}:'
            'duration=${d.toStringAsFixed(3)}:'
            'offset=${offset.toStringAsFixed(3)}[$vLabel]');
        filters.add('[$aPrev][a$i]acrossfade=d=${d.toStringAsFixed(3)}[$aLabel]');
        vPrev = vLabel;
        aPrev = aLabel;
        elapsed += clips[i].duration - d;
      }
      vOut = 'outv';
      aOut = 'outa';
    }

    return '$inputs-filter_complex "${filters.join(';')}" '
        '-map "[$vOut]" -map "[$aOut]" $encodeParams "$outPath"';
  }

  /// Total length of the rendered sequence, accounting for the overlap each
  /// transition costs. Shown before rendering so nobody waits on a render to
  /// find out how long it came out.
  static double sequenceDuration(
    List<SequenceClip> clips, {
    SequenceTransition transition = SequenceTransition.cut,
    double transitionSec = 0.5,
  }) {
    if (clips.isEmpty) return 0;
    final total = clips.fold<double>(0, (a, c) => a + c.duration);
    if (transition == SequenceTransition.cut || clips.length < 2) return total;
    final d = transitionSec.clamp(0.1, 3.0);
    return (total - d * (clips.length - 1)).clamp(0.1, double.infinity);
  }

  /// Renders [clips] into one file and returns its path.
  static Future<String> renderSequence(
    List<SequenceClip> clips, {
    int width = 1080,
    int height = 1920,
    SequenceTransition transition = SequenceTransition.cut,
    double transitionSec = 0.5,
  }) async {
    for (final c in clips) {
      if (!File(c.path).existsSync()) {
        throw Exception('تعذّر الوصول إلى أحد المقاطع — قد يكون حُذف أو نُقل.\n${c.path}');
      }
    }
    final dir = await getTemporaryDirectory();
    final outPath =
        '${dir.path}/sequence_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final cmd = buildSequenceCommand(
      clips,
      outPath: outPath,
      width: width,
      height: height,
      encodeParams:
          '-c:v libx264 -preset veryfast -crf 20 -pix_fmt yuv420p -c:a aac -b:a 192k',
      transition: transition,
      transitionSec: transitionSec,
    );
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      final rawLog = (await session.getOutput()) ?? '';
      final log =
          rawLog.length > 900 ? rawLog.substring(rawLog.length - 900) : rawLog;
      throw Exception('تعذّر تركيب المقاطع (ffmpeg rc=$rc)\n$log');
    }
    return outPath;
  }
}

// PATCH_S125_SEQUENCE: one clip in the sequence, with its own in/out points.
class SequenceClip {
  final String path;

  /// Seconds into the source where this clip starts.
  final double start;

  /// How much of the source to use, in seconds.
  final double duration;
  const SequenceClip({
    required this.path,
    this.start = 0,
    required this.duration,
  });

  SequenceClip copyWith({double? start, double? duration}) => SequenceClip(
        path: path,
        start: start ?? this.start,
        duration: duration ?? this.duration,
      );
}

/// How consecutive clips are joined. Names map to ffmpeg's xfade transitions.
enum SequenceTransition {
  cut,
  fade,
  wipeleft,
  wiperight,
  slideup,
  slidedown,
  circleopen,
  dissolve,
  smoothleft,
  fadeblack,
}

extension SequenceTransitionMeta on SequenceTransition {
  String get ffmpegName => name;

  String get labelAr => switch (this) {
        SequenceTransition.cut => 'قطع مباشر',
        SequenceTransition.fade => 'تلاشٍ',
        SequenceTransition.wipeleft => 'مسح لليسار',
        SequenceTransition.wiperight => 'مسح لليمين',
        SequenceTransition.slideup => 'انزلاق لأعلى',
        SequenceTransition.slidedown => 'انزلاق لأسفل',
        SequenceTransition.circleopen => 'دائرة تتّسع',
        SequenceTransition.dissolve => 'ذوبان',
        SequenceTransition.smoothleft => 'انسياب لليسار',
        SequenceTransition.fadeblack => 'تلاشٍ عبر الأسود',
      };
}
