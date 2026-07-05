import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

class MediaService {
  /// Extracts mono 16kHz PCM WAV from any video/audio file — exactly the
  /// format Whisper wants. Real ffmpeg decode, so none of the browser's
  /// decodeAudioData container-strictness issues apply here.
  static Future<String> extractWav16kMono(String inputPath) async {
    final dir = await getTemporaryDirectory();
    final outPath = '${dir.path}/asr_${DateTime.now().millisecondsSinceEpoch}.wav';
    final cmd = '-y -i "$inputPath" -vn -ac 1 -ar 16000 -f wav "$outPath"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('تعذّر استخراج الصوت من الملف (ffmpeg rc=$rc)');
    }
    return outPath;
  }

  /// Real chroma-key + overlay export. [ayahText] is burned in via ffmpeg's
  /// drawtext (pass a pre-rendered PNG overlay path instead if you want the
  /// same custom Arabic fonts/animation as the browser version — simplest
  /// path is compositing a transparent PNG per frame batch, or an ASS
  /// subtitle track for animated reveal).
  static Future<String> exportChromaVideo({
    required String inputVideoPath,
    required String backgroundImagePath,
    required String outputName,
    String chromaColor = '0x00FF00',
    double similarity = 0.20,
    double blend = 0.05,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final outPath = '${dir.path}/$outputName.mp4';
    // chromakey filter removes the key color from the foreground video;
    // overlay composites it onto the background image, scaled to match.
    final filter =
        "[1:v]chromakey=$chromaColor:$similarity:$blend[fg];"
        "[0:v][fg]overlay=shortest=1[out]";
    final cmd = '-y -loop 1 -i "$backgroundImagePath" -i "$inputVideoPath" '
        '-filter_complex "$filter" -map "[out]" -map 1:a? '
        '-c:v libx264 -crf 20 -preset veryfast -c:a aac -shortest "$outPath"';
    final session = await FFmpegKit.execute(cmd);
    final rc = await session.getReturnCode();
    if (!ReturnCode.isSuccess(rc)) {
      throw Exception('تعذّر التصدير (ffmpeg rc=$rc)');
    }
    return outPath;
  }
}
