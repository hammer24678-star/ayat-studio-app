// Live/from-video ASR model loading. We deliberately do NOT call
// whisper_ggml_plus's own WhisperController.downloadModel() — that fetches
// from whisper.cpp's official Hugging Face mirror, and huggingface.co is
// unreachable on at least one tester's network ("SocketException: Failed
// host lookup: 'huggingface.co'"). Instead we download the exact same
// model file ourselves from THIS repo's own GitHub Release (re-hosted
// there by the CI workflow — see .github/workflows/build-apk.yml) straight
// to the path WhisperController.getPath() expects, then call transcribe()
// normally; whisper_ggml_plus just finds the file already there and never
// starts its own download.
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

class WhisperService {
  static const WhisperModel _model = WhisperModel.small; // PATCH_S41_UPGRADE_ASR_MODEL: base -> small, big ASR accuracy jump on tajweed-style Quranic Arabic
  static final WhisperController _controller = WhisperController();
  static bool _modelReady = false;

  // Filled in automatically at CI build time via --dart-define (see the
  // "Build release APK" step), using the `${{ github.repository }}` GitHub
  // Actions context — so this never needs a hardcoded username. The
  // fallback below only matters for a local `flutter run` outside CI.
  static const String _releaseBaseUrl = String.fromEnvironment(
    'MODEL_RELEASE_BASE_URL',
    defaultValue:
        'https://github.com/REPLACE_OWNER/ayat_studio_app/releases/download/models',
  );
  static const String _assetName = 'ggml-small.bin'; // PATCH_S41_UPGRADE_ASR_MODEL

  // ggml-small.bin is ~466MB (bumped from base's ~148MB by PATCH_S41_UPGRADE_ASR_MODEL);
  // anything much smaller sitting at the target path is almost certainly
  // a partial/failed previous download, not a real cached model, so we
  // redo it rather than trust it.
  static const int _minExpectedBytes = 400 * 1024 * 1024;

  /// Ensures the model is downloaded/cached. Safe to call repeatedly — only
  /// downloads once per app run. [onStatus] gets human-readable Arabic
  /// status text.
  static Future<void> ensureReady({void Function(String status)? onStatus}) async {
    if (_modelReady) return;

    final path = await _controller.getPath(_model);
    final file = File(path);
    final needsDownload =
        !(await file.exists()) || (await file.length()) < _minExpectedBytes;

    if (needsDownload) {
      onStatus?.call('جارٍ تنزيل نموذج التعرّف على الكلام من GitHub (أول تشغيل فقط)…');
      await file.parent.create(recursive: true);
      final uri = Uri.parse('$_releaseBaseUrl/$_assetName');
      final request = http.Request('GET', uri);
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        throw Exception('تعذّر تنزيل نموذج التعرّف من GitHub (HTTP ${response.statusCode})');
      }
      final sink = file.openWrite();
      await response.stream.pipe(sink);
      await sink.close();
      if (await file.length() < _minExpectedBytes) {
        await file.delete();
        throw Exception('اكتمل التنزيل لكن حجم الملف غير سليم — أعد المحاولة');
      }
    }

    _modelReady = true;
    onStatus?.call('النموذج جاهز');
  }

  /// Transcribes a 16kHz mono WAV file (extract audio with ffmpeg first —
  /// see MediaService.extractWav16kMono) and returns the Arabic transcript.
  static Future<String> transcribeWav(
    String wavPath, {
    void Function(String status)? onStatus,
  }) async {
    await ensureReady(onStatus: onStatus);
    onStatus?.call('جارٍ التعرّف على الكلام…');
    final result = await _controller.transcribe(
      model: _model,
      audioPath: wavPath,
      lang: 'ar',
    );
    return result?.transcription.text.trim() ?? '';
  }
}
