import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Whisper model is NOT bundled as a Flutter asset — ggml-base.bin is ~141MB,
/// and GitHub hard-rejects any pushed file over 100MB (would need Git LFS to
/// commit it directly). Instead it's downloaded once on first run and cached
/// in app-support storage; every run after that is fully offline.
class WhisperService {
  static const String modelUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin';
  static const String modelFileName = 'ggml-base.bin';
  // Known size of the official ggml-base.bin — used to detect a truncated
  // previous download so we don't hand whisper_ggml a corrupt file.
  static const int expectedMinBytes = 140000000;

  static WhisperController? _controller;
  static String? _modelPath;

  /// Downloads the model (only if not already cached / previously truncated)
  /// and initializes the whisper controller once. Safe to call repeatedly.
  /// [onStatus] gets human-readable Arabic status text; [onProgress] gets a
  /// 0.0–1.0 download fraction (only fires while actually downloading).
  static Future<WhisperController> ensureReady({
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    if (_controller != null) return _controller!;

    final dir = await getApplicationSupportDirectory();
    final modelFile = File('${dir.path}/$modelFileName');
    final tmpFile = File('${dir.path}/$modelFileName.part');

    final needsDownload =
        !await modelFile.exists() || (await modelFile.length()) < expectedMinBytes;

    if (needsDownload) {
      onStatus?.call('جارٍ تنزيل نموذج التعرّف على الكلام (أول تشغيل فقط)…');
      await _downloadWithProgress(modelUrl, tmpFile, onProgress);
      if (await tmpFile.length() < expectedMinBytes) {
        await tmpFile.delete();
        throw Exception('فشل تنزيل نموذج Whisper (ملف غير مكتمل) — تحقّق من الاتصال وأعد المحاولة');
      }
      if (await modelFile.exists()) await modelFile.delete();
      await tmpFile.rename(modelFile.path);
    }

    _modelPath = modelFile.path;
    onStatus?.call('جارٍ تهيئة محرك التعرّف على الكلام…');
    _controller = WhisperController();
    onStatus?.call('النموذج جاهز');
    return _controller!;
  }

  static Future<void> _downloadWithProgress(
    String url,
    File dest,
    void Function(double fraction)? onProgress,
  ) async {
    final request = http.Request('GET', Uri.parse(url));
    final response = await http.Client().send(request);
    if (response.statusCode != 200) {
      throw Exception('تعذّر تنزيل النموذج (HTTP ${response.statusCode})');
    }
    final total = response.contentLength ?? expectedMinBytes;
    var received = 0;
    final sink = dest.openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received / total);
    }
    await sink.flush();
    await sink.close();
  }

  /// Transcribes a 16kHz mono WAV file (extract audio with ffmpeg first —
  /// see MediaService.extractWav16kMono) and returns the Arabic transcript.
  static Future<String> transcribeWav(
    String wavPath, {
    void Function(String status)? onStatus,
    void Function(double fraction)? onProgress,
  }) async {
    final controller = await ensureReady(onStatus: onStatus, onProgress: onProgress);
    final result = await controller.transcribe(
      model: WhisperModel.base,
      modelPath: _modelPath,
      audioPath: wavPath,
      lang: 'ar',
    );
    return result?.transcription.text.trim() ?? '';
  }
}
