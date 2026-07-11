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
// PATCH_S76_QURAN_MODEL_DEFAULT
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

// PATCH_S43_MODEL_SIZE_PICKER: selectable accuracy/speed tiers. `small` stays the default
// (matches S41's baseline), `tiny`/`base` trade accuracy for a much faster
// scan on older devices or quick previews, `medium` is a further accuracy
// step up for users who want the best possible sync and don't mind the
// extra download size + scan time.
// PATCH_S66_QURAN_TUNED_MODEL: `quranTuned` is a 5th tier -- a Quran-recitation fine-tune
// (tarteel-ai/whisper-base-ar-quran + KheemP's LoRA adapter merged, same size
// class as `base`) instead of a generic-speech Whisper checkpoint. This is the
// actual lever on sync accuracy -- see prepare-quran-model.yml for how the
// .bin asset this tier downloads is produced (one-time HF->GGML conversion
// job, run on demand, not on every build).
enum WhisperModelSize { tiny, base, small, medium, quranTuned }

class _ModelSpec {
  final WhisperModel model;
  final String assetName;
  final int minExpectedBytes;
  final String labelAr;
  const _ModelSpec(this.model, this.assetName, this.minExpectedBytes, this.labelAr);
}

const Map<WhisperModelSize, _ModelSpec> _modelSpecs = {
  WhisperModelSize.tiny: _ModelSpec(
      WhisperModel.tiny, 'ggml-tiny.bin', 50 * 1024 * 1024, 'سريع جدًا (~75MB) — أقل دقة'),
  WhisperModelSize.base: _ModelSpec(
      WhisperModel.base, 'ggml-base.bin', 100 * 1024 * 1024, 'سريع (~148MB) — دقة متوسطة'),
  WhisperModelSize.small: _ModelSpec(
      WhisperModel.small, 'ggml-small.bin', 400 * 1024 * 1024, 'دقيق (~466MB)'),
  WhisperModelSize.medium: _ModelSpec(
      WhisperModel.medium, 'ggml-medium.bin', 1300 * 1024 * 1024, 'الأدق (~1.5GB) — أبطأ'),
  // PATCH_S66_QURAN_TUNED_MODEL: reuses the `largeV3Turbo` enum tag purely as a path/routing key --
  // see the enum-level comment above for why. Not actually large-v3-turbo.
  // Size target matches `base`'s architecture converted to GGML fp16 (~148MB);
  // minExpectedBytes mirrors base's own threshold for the same reason.
  WhisperModelSize.quranTuned: _ModelSpec(
      WhisperModel.largeV3Turbo, 'ggml-quran-lora-base.bin', 100 * 1024 * 1024,
      'دقة القرآن (الافتراضي، ~148MB) — نموذج مخصص لتلاوة القرآن'),
};

class WhisperService {
  // PATCH_S43_MODEL_SIZE_PICKER: mutable (was a S41 const) so the user can switch tiers at
  // runtime; setModelSize() below is the only writer.
  // PATCH_S76_QURAN_MODEL_DEFAULT: default is now the Quran-tuned tier;
  // `small` remains the guaranteed-published fallback target in
  // ensureReady() below (S75), unchanged.
  static WhisperModelSize _size = WhisperModelSize.quranTuned;
  static final WhisperController _controller = WhisperController();
  static bool _modelReady = false;

  static WhisperModel get _model => _modelSpecs[_size]!.model;
  static WhisperModelSize get currentSize => _size; // PATCH_S43_MODEL_SIZE_PICKER
  static String labelFor(WhisperModelSize size) => _modelSpecs[size]!.labelAr; // PATCH_S43_MODEL_SIZE_PICKER

  /// PATCH_S43_MODEL_SIZE_PICKER: switch model tier. Safe to call any time (including
  /// mid-session); forces the next ensureReady() call to re-verify/
  /// re-download the newly selected tier's model file instead of trusting
  /// the previous tier's "ready" flag.
  static void setModelSize(WhisperModelSize size) {
    if (size == _size) return;
    _size = size;
    _modelReady = false;
  }

  // Filled in automatically at CI build time via --dart-define (see the
  // "Build release APK" step), using the `${{ github.repository }}` GitHub
  // Actions context — so this never needs a hardcoded username. The
  // fallback below only matters for a local `flutter run` outside CI.
  static const String _releaseBaseUrl = String.fromEnvironment(
    'MODEL_RELEASE_BASE_URL',
    defaultValue:
        'https://github.com/REPLACE_OWNER/ayat_studio_app/releases/download/models',
  );
  // PATCH_S84_CLEANUP: the S43 _assetName/_minExpectedBytes getters became
  // dead once S75's _downloadAndVerify started reading the spec directly.

  /// Ensures the model is downloaded/cached. Safe to call repeatedly — only
  /// downloads once per app run. [onStatus] gets human-readable Arabic
  /// status text.
  // PATCH_S75_COMPACT_PICKER_FALLBACK: download/verify for whichever tier `size` currently points at.
  // Pulled out of ensureReady() so it can be attempted for the selected tier
  // first, then retried for a fallback tier without duplicating this logic.
  static Future<void> _downloadAndVerify(
      WhisperModelSize size, {void Function(String status)? onStatus}) async {
    final spec = _modelSpecs[size]!;
    final path = await _controller.getPath(spec.model);
    final file = File(path);
    final needsDownload =
        !(await file.exists()) || (await file.length()) < spec.minExpectedBytes;

    if (needsDownload) {
      onStatus?.call('جارٍ تنزيل نموذج التعرّف على الكلام من GitHub (أول تشغيل فقط)…');
      await file.parent.create(recursive: true);
      final uri = Uri.parse('$_releaseBaseUrl/${spec.assetName}');
      final request = http.Request('GET', uri);
      final response = await http.Client().send(request);
      if (response.statusCode != 200) {
        throw Exception('تعذّر تنزيل نموذج التعرّف من GitHub (HTTP ${response.statusCode})');
      }
      final sink = file.openWrite();
      await response.stream.pipe(sink);
      await sink.close();
      if (await file.length() < spec.minExpectedBytes) {
        await file.delete();
        throw Exception('اكتمل التنزيل لكن حجم الملف غير سليم — أعد المحاولة');
      }
    }
  }

  // PATCH_S75_COMPACT_PICKER_FALLBACK: if the selected tier can't be downloaded/verified (e.g. a tier
  // whose asset isn't published yet, or a transient network/HTTP error) this
  // no longer throws straight into the caller's face. Unless the failing tier
  // is already `small` (the long-standing safe default, always published),
  // it falls back to `small` and retries once, so auto-sync/detect still
  // works. `_size` itself is updated on fallback so the UI can re-sync its
  // displayed selection via currentSize.
  static Future<void> ensureReady({void Function(String status)? onStatus}) async {
    if (_modelReady) return;
    try {
      await _downloadAndVerify(_size, onStatus: onStatus);
    } catch (e) {
      if (_size == WhisperModelSize.small) rethrow;
      final failedLabel = labelFor(_size).split(' — ').first;
      onStatus?.call('تعذّر تحميل "$failedLabel" — سيتم استخدام "دقيق" مؤقتًا…');
      _size = WhisperModelSize.small;
      await _downloadAndVerify(_size, onStatus: onStatus);
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

  // PATCH_S31_ACCURATE_SYNC: same as transcribeWav, but also returns
  // Whisper's own natural phrase-level segments with real timestamps, so
  // the caller can time each detected ayah to when it was actually spoken
  // instead of guessing from an outer scan window's fixed boundaries.
  // whisper_ggml_plus types fromTs/toTs as Duration built from whisper.cpp's
  // centisecond ticks (Duration(milliseconds: ts * 10) in the package
  // source), i.e. real audio time — used directly, only clamped to the WAV
  // we actually fed it.
  static Future<WhisperTranscript> transcribeWavWithSegments(
    String wavPath, {
    required double audioDurationSec,
    void Function(String status)? onStatus,
    bool splitOnWord = false, // PATCH_S55_WORD_TIMESTAMPS
  }) async {
    await ensureReady(onStatus: onStatus);
    onStatus?.call('جارٍ التعرّف على الكلام…');
    final result = await _controller.transcribe(
      model: _model,
      audioPath: wavPath,
      lang: 'ar',
      withTimestamps: true,
      splitOnWord: splitOnWord,
    );
    final text = result?.transcription.text.trim() ?? '';
    final rawSegments = result?.transcription.segments ?? const [];
    final segments = <TranscriptSegment>[
      for (final s in rawSegments)
        if (s.text.trim().isNotEmpty)
          TranscriptSegment(
            (s.fromTs.inMilliseconds / 1000.0).clamp(0.0, audioDurationSec),
            (s.toTs.inMilliseconds / 1000.0).clamp(0.0, audioDurationSec),
            s.text.trim(),
          ),
    ];
    return WhisperTranscript(text, segments);
  }
}

// PATCH_S31_ACCURATE_SYNC: one of Whisper's own natural phrase-level
// segments, with timestamps in seconds relative to the start of the WAV it
// was given.
class TranscriptSegment {
  final double startSec;
  final double endSec;
  final String text;
  TranscriptSegment(this.startSec, this.endSec, this.text);
}

class WhisperTranscript {
  final String text;
  final List<TranscriptSegment> segments;
  WhisperTranscript(this.text, this.segments);
}
