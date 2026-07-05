import 'package:whisper_ggml/whisper_ggml.dart';

/// whisper_ggml manages the model file itself — WhisperController.getPath()
/// resolves where it lives on disk, and downloadModel() fetches + caches it
/// (from whisper.cpp's own official GGML URLs) the first time it's needed.
/// No manual HTTP/caching layer needed; transcribe() takes no modelPath —
/// it looks the file up via the model enum internally.
class WhisperService {
  static const WhisperModel _model = WhisperModel.base;
  static final WhisperController _controller = WhisperController();
  static bool _modelReady = false;

  /// Ensures the model is downloaded/cached. Safe to call repeatedly — only
  /// downloads once. [onStatus] gets human-readable Arabic status text.
  /// Note: whisper_ggml doesn't expose download-progress fractions, so the
  /// UI shows an indeterminate spinner during this rather than a percentage.
  static Future<void> ensureReady({void Function(String status)? onStatus}) async {
    if (_modelReady) return;
    onStatus?.call('جارٍ تنزيل نموذج التعرّف على الكلام (أول تشغيل فقط)…');
    await _controller.downloadModel(_model);
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
