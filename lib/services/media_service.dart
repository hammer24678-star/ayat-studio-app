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
}
