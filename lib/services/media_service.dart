import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class MediaService {
  /// Extracts mono 16kHz PCM WAV from any video/audio file — exactly the
  /// format Whisper wants. Real ffmpeg decode, so none of the browser's
  /// decodeAudioData container-strictness issues apply here.
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
}
