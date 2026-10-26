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
import 'dart:math' as math;
import 'dart:typed_data'; // PATCH_S201

import 'package:http/http.dart' as http;
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import 'app_settings.dart'; // PATCH_S207_WHISPER_SETTINGS

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
  // PATCH_S200_WHISPER_FALLBACK: tiers that failed to run this session, and
  // tiers that have run successfully at least once this session.
  static final Set<WhisperModelSize> _badTiers = <WhisperModelSize>{};
  static final Set<WhisperModelSize> _provenTiers = <WhisperModelSize>{};

  /// Last Whisper failure, with model/file details (also appended to errors).
  static String? lastError;

  static WhisperModel get _model => _modelSpecs[_size]!.model;

  // PATCH_S123_WHISPER_THREADS: the package hardcodes 6 worker threads. On a
  // 4-core phone that oversubscribes -- whisper.cpp's per-layer barriers make
  // the extra threads pure contention, and a long auto-sync scan is a
  // sustained thermal load, so oversubscription also pushes the phone into
  // throttling sooner. Leave one core for the UI/decoder, cap at 8 (whisper.cpp
  // stops scaling past that on ARM), and never drop below 2.
  // PATCH_S164_BIG_CORE_THREADS: whisper_ggml_plus runs on the CPU only on
  // Android. On a big.LITTLE phone the slow cores finish each layer late and
  // every other thread waits for them, so "all cores" is slower than "fast
  // cores". Count the cores whose max frequency is within 70% of the fastest;
  // when sysfs can't be read (some Android builds block it) fall back to a
  // core-count heuristic. Computed once.
  static int? _threadsMemo;
  // PATCH_S207_WHISPER_SETTINGS: Settings can pin the thread count (0 = auto).
  static int get _threads {
    final pinned = AppSettings.instance.whisperThreads;
    return pinned > 0 ? pinned : autoThreads;
  }

  static int get autoThreads => _threadsMemo ??= _pickThreads();
  static int get cpuCores => Platform.numberOfProcessors;

  static int _pickThreads() {
    final total = Platform.numberOfProcessors;
    try {
      final freqs = <int>[];
      for (var i = 0; i < total; i++) {
        final f = File(
            '/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq');
        if (!f.existsSync()) continue;
        final v = int.tryParse(f.readAsStringSync().trim());
        if (v != null && v > 0) freqs.add(v);
      }
      if (freqs.length == total && total >= 4) {
        final top = freqs.reduce(math.max);
        final fast = freqs.where((f) => f >= top * 0.7).length;
        return math.max(2, math.min(6, fast));
      }
    } catch (_) {
      // fall through to the heuristic
    }
    if (total >= 6) return 4; // typical 1+3+4 / 2+4 / 4+4 layouts
    return math.max(2, total - 1);
  }
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
  // PATCH_S163: a GGML model starts with the 'lmgg' magic. A saved HTML/JSON
  // error page (captive portal, rate-limit page) is printable ASCII instead,
  // and would otherwise be cached forever as a "model" that fails to load.
  static Future<bool> _hasGgmlMagic(File f) async {
    try {
      final raf = await f.open();
      final head = await raf.read(4);
      await raf.close();
      if (head.length < 4) return false;
      if (head[0] == 0x6c && head[1] == 0x6d && head[2] == 0x67 && head[3] == 0x67) {
        return true;
      }
      return !head.every((b) => b >= 0x20 && b <= 0x7e);
    } catch (_) {
      return true; // an IO hiccup must not block a possibly-good file
    }
  }

  // PATCH_S163: 3 attempts, each resuming from the .part file, with a short
  // back-off. Only after all three fail does ensureReady() fall back to `small`.
  static Future<void> _downloadAndVerify(
      WhisperModelSize size, {void Function(String status)? onStatus}) async {
    Object? last;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        await _downloadAndVerifyOnce(size, onStatus: onStatus);
        return;
      } catch (e) {
        last = e;
        if (attempt < 2) {
          onStatus?.call('انقطع التنزيل — إعادة المحاولة (${attempt + 2}/3)…');
          await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
        }
      }
    }
    throw last ?? Exception('تعذّر تنزيل نموذج التعرّف');
  }

  static Future<void> _downloadAndVerifyOnce(
      WhisperModelSize size, {void Function(String status)? onStatus}) async {
    final spec = _modelSpecs[size]!;
    final path = await _controller.getPath(spec.model);
    final file = File(path);
    final needsDownload = !(await file.exists()) ||
        (await file.length()) < spec.minExpectedBytes ||
        !(await _hasGgmlMagic(file)); // PATCH_S163

    if (needsDownload) {
      // PATCH_S57_RESUMABLE_MODEL_DOWNLOAD: tester feedback — the old
      // download showed no percentage and restarted from zero whenever the
      // app was left or the phone locked. Now it streams into a .part file
      // with a live percent, and an interrupted download RESUMES from the
      // exact byte it stopped at (HTTP Range) on the next attempt instead
      // of starting over.
      await file.parent.create(recursive: true);
      final part = File('$path.part');
      var have = await part.exists() ? await part.length() : 0;
      final uri = Uri.parse('$_releaseBaseUrl/${spec.assetName}');
      final request = http.Request('GET', uri);
      if (have > 0) request.headers['range'] = 'bytes=$have-';
      final client = http.Client(); // PATCH_S163: closed in the finally below
      final http.StreamedResponse response;
      try {
        response =
            await client.send(request).timeout(const Duration(seconds: 30));
      } catch (_) {
        client.close();
        rethrow;
      }
      if (response.statusCode == 200) {
        have = 0; // server ignored the range — start clean
      } else if (response.statusCode != 206) {
        client.close();
        if (response.statusCode == 416) {
          // stale/oversized .part — drop it so the retry starts clean
          try {
            if (await part.exists()) await part.delete();
          } catch (_) {}
        }
        throw Exception(
            'تعذّر تنزيل نموذج التعرّف من GitHub (HTTP ${response.statusCode})');
      }
      final total = have + (response.contentLength ?? 0);
      final sink = part.openWrite(
          mode: have > 0 ? FileMode.append : FileMode.write);
      var got = have;
      var lastShownPct = -1;
      try {
        await for (final chunk
            in response.stream.timeout(const Duration(seconds: 45))) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) {
            final pct = (got * 100 ~/ total);
            if (pct != lastShownPct) {
              lastShownPct = pct;
              onStatus?.call(
                  'جارٍ تنزيل نموذج التعرّف على الآيات (مرة واحدة فقط)… $pct٪\n'
                  'أبقِ التطبيق مفتوحًا — ولو انقطع التنزيل سيُستأنف من $pct٪ وليس من الصفر.');
            }
          }
        }
      } finally {
        // keep whatever arrived — that's exactly what resume picks up from
        await sink.close();
        client.close(); // PATCH_S163
      }
      if (total > 0 && got < total) { // PATCH_S198_REVIEW: cut short but still above the minimum
        throw Exception(
            'انقطع تنزيل النموذج — أعد المحاولة وسيُستأنف تلقائيًا من حيث توقف');
      }
      if (await part.length() < spec.minExpectedBytes) {
        throw Exception(
            'انقطع تنزيل النموذج — أعد المحاولة وسيُستأنف تلقائيًا من حيث توقف');
      }
      if (!await _hasGgmlMagic(part)) {
        try {
          await part.delete();
        } catch (_) {}
        throw Exception('ملف النموذج المنزَّل غير صالح — أعد المحاولة');
      }
      await part.rename(path);
    }
  }

  // PATCH_S75_COMPACT_PICKER_FALLBACK: if the selected tier can't be downloaded/verified (e.g. a tier
  // whose asset isn't published yet, or a transient network/HTTP error) this
  // no longer throws straight into the caller's face. Unless the failing tier
  // is already `small` (the long-standing safe default, always published),
  // it falls back to `small` and retries once, so auto-sync/detect still
  // works. `_size` itself is updated on fallback so the UI can re-sync its
  // displayed selection via currentSize.
  // PATCH_S163: two flows asking at once (auto-sync + detect) share ONE
  // download instead of both writing the same .part file.
  static Future<void>? _readyInFlight;
  static Future<void> ensureReady({void Function(String status)? onStatus}) {
    if (_modelReady) return Future<void>.value();
    return _readyInFlight ??= _ensureReadyImpl(onStatus: onStatus)
        .whenComplete(() => _readyInFlight = null);
  }

  static Future<void> _ensureReadyImpl(
      {void Function(String status)? onStatus}) async {
    if (_modelReady) return;
    // PATCH_S200_WHISPER_FALLBACK: a tier that already failed to run this
    // session is not tried again - go straight to the safe one.
    if (_badTiers.contains(_size) && _size != WhisperModelSize.small) {
      _size = WhisperModelSize.small;
    }
    try {
      await _downloadAndVerify(_size, onStatus: onStatus);
    } catch (e) {
      if (_size == WhisperModelSize.small) rethrow;
      lastError = 'download ${_size.name}: ${_describe(e)}'; // PATCH_S200_WHISPER_FALLBACK
      final failedLabel = labelFor(_size).split(' — ').first;
      onStatus?.call('تعذّر تحميل "$failedLabel" — سيتم استخدام "دقيق" مؤقتًا…');
      _size = WhisperModelSize.small;
      await _downloadAndVerify(_size, onStatus: onStatus);
    }
    _modelReady = true;
    onStatus?.call('النموذج جاهز');
  }

  // ---------------------------------------------------------------------
  // PATCH_S200_WHISPER_FALLBACK
  // S75 only fell back to `small` when the model could not be DOWNLOADED. A
  // tier that downloads fine and then fails to load/run left every
  // transcribe call failing - and whisper_ggml_plus reports some native
  // failures as a null result (not an exception), which callers read as "no
  // speech". These helpers recover from a broken model file, fall back to
  // `small` for the session when the chosen tier cannot run, and carry the
  // real reason in the error text.
  // ---------------------------------------------------------------------

  static String _describe(Object? e) {
    final msg = '$e'.replaceFirst('Exception: ', '');
    return '${e.runtimeType}: ${msg.length > 300 ? msg.substring(0, 300) : msg}';
  }

  static Future<bool> _modelFileHealthy(WhisperModelSize size) async {
    try {
      final spec = _modelSpecs[size]!;
      final f = File(await _controller.getPath(spec.model));
      return await f.exists() &&
          await f.length() >= spec.minExpectedBytes &&
          await _hasGgmlMagic(f);
    } catch (_) {
      return true; // can't tell - don't blame the file
    }
  }

  static Future<String> _modelInfo() async {
    try {
      final f = File(await _controller.getPath(_modelSpecs[_size]!.model));
      if (!await f.exists()) return 'tier=${_size.name} file=missing';
      final mb = (await f.length()) / (1024 * 1024);
      final magic = await _hasGgmlMagic(f) ? 'ok' : 'BAD';
      return 'tier=${_size.name} file=${mb.toStringAsFixed(0)}MB '
          'magic=$magic threads=$_threads';
    } catch (_) {
      return 'tier=${_size.name}';
    }
  }

  // ---------------------------------------------------------------------
  // PATCH_S207_WHISPER_VAD_NULL
  // whisper_ggml_plus 1.5.x puts `"vad_model_path": null` in the request
  // whenever VAD is off (short windows, word-split scans, or when its bundled
  // VAD model can't be prepared). Its native side then does
  // json.value("vad_model_path", "") - and nlohmann::json THROWS on a null
  // there: "[json.exception.type_error.302] type must be string, but is null".
  // Every call is therefore sent with an EMPTY path (never null), and if the
  // package still reports that error the call is repeated once with VAD off.
  // ---------------------------------------------------------------------
  static Future<dynamic> _transcribeNative({
    required String audioPath,
    String lang = 'ar',
    bool withTimestamps = true,
    bool splitOnWord = false,
    bool convert = false,
    int? threads,
    bool speedUp = false,
    WhisperVadMode vadMode = WhisperVadMode.auto,
  }) async {
    Future<dynamic> go(WhisperVadMode v) => _controller.transcribe(
          model: _model,
          audioPath: audioPath,
          lang: lang,
          withTimestamps: withTimestamps,
          splitOnWord: splitOnWord,
          convert: convert,
          threads: threads ?? _threads,
          speedUp: speedUp,
          vadMode: v,
          vadModelPath: '',
        );
    try {
      return await go(vadMode);
    } catch (e) {
      if (vadMode != WhisperVadMode.disabled && '$e'.contains('type_error')) {
        return await go(WhisperVadMode.disabled);
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // PATCH_S207_WHISPER_SETTINGS: what the Settings screen needs.
  // ---------------------------------------------------------------------

  /// Size in bytes of the downloaded, usable model file for [size]; null when
  /// it is missing or too small to be the real thing.
  static Future<int?> downloadedBytes(WhisperModelSize size) async {
    try {
      final spec = _modelSpecs[size]!;
      final f = File(await _controller.getPath(spec.model));
      if (!await f.exists()) return null;
      final n = await f.length();
      return n >= spec.minExpectedBytes ? n : null;
    } catch (_) {
      return null;
    }
  }

  /// Deletes the downloaded file of [size] (and any half-finished download)
  /// so the next run fetches it again.
  static Future<void> deleteModel(WhisperModelSize size) async {
    if (size == _size) await release();
    try {
      final spec = _modelSpecs[size]!;
      final path = await _controller.getPath(spec.model);
      final f = File(path);
      if (await f.exists()) await f.delete();
      final part = File('$path.part');
      if (await part.exists()) await part.delete();
    } catch (_) {
      // best effort
    }
    if (size == _size) _modelReady = false;
    _badTiers.remove(size);
    _provenTiers.remove(size);
  }

  /// Forgets which tiers failed this session and the last error text.
  static void resetDiagnostics() {
    _badTiers.clear();
    _provenTiers.clear();
    lastError = null;
  }

  static Future<T> _guarded<T>(
    Future<T> Function() run, {
    void Function(String status)? onStatus,
    bool fallbackOnError = true,
  }) async {
    final tier = _size;
    Object? err;
    try {
      final r = await run();
      if (r != null) {
        _provenTiers.add(tier);
        return r;
      }
      // null = "no speech" OR a failure the package swallowed. With a valid
      // model file it is treated as no speech (the old behaviour).
      if (await _modelFileHealthy(tier)) return r;
      err = StateError('no result and the model file is invalid');
    } catch (e) {
      if (!fallbackOnError) rethrow;
      err = e;
    }

    lastError = '${await _modelInfo()} | ${_describe(err)}';

    // 1) a broken cached model file: drop it and fetch it again, once
    if (!await _modelFileHealthy(tier)) {
      try {
        final f = File(await _controller.getPath(_modelSpecs[tier]!.model));
        if (await f.exists()) await f.delete();
        _modelReady = false;
        await ensureReady(onStatus: onStatus);
        final again = await run();
        if (again != null) {
          _provenTiers.add(_size);
          return again;
        }
      } catch (e2) {
        lastError = '$lastError | redownload: ${_describe(e2)}';
      }
    }

    // 2) nothing safer to fall back to, or this tier already worked once
    //    this session (so this failure is about this audio, not the model)
    if (tier == WhisperModelSize.small || _provenTiers.contains(tier)) {
      throw Exception('تعذّر التعرّف على الكلام\n$lastError');
    }

    // 3) fall back to `small` for the rest of the session
    onStatus?.call(
        'تعذّر تشغيل "${labelFor(tier).split(' — ').first}" على هذا الجهاز — جارٍ استخدام "دقيق"…');
    _size = WhisperModelSize.small;
    _modelReady = false;
    try {
      await ensureReady(onStatus: onStatus);
      final r2 = await run();
      if (r2 != null) {
        _badTiers.add(tier);
        _provenTiers.add(WhisperModelSize.small);
        return r2;
      }
      lastError = '$lastError | small also returned no result';
    } catch (e3) {
      lastError = '$lastError | small: ${_describe(e3)}';
    }
    // small could not run it either, so the chosen tier was not the culprit
    _size = tier;
    _modelReady = false;
    throw Exception('تعذّر التعرّف على الكلام\n$lastError');
  }

  // ---------------------------------------------------------------------
  // PATCH_S201_WHISPER_AUDIT
  //
  // 1) Short windows. whisper.cpp pads every input to a 30-second window
  //    before the encoder runs, so a 6-second scan window spends ~80% of the
  //    encoder's time on padding. whisper_ggml_plus exposes exactly one knob
  //    for that - speedUp, which halves the encoder context to 15 s - and
  //    audio longer than 15 s would lose its tail under it. So it would be
  //    used ONLY for audio that fits with room to spare (every scan /
  //    gap-rescue / re-transcribe window does). It trades a little accuracy
  //    for ~35-40% less scan time and has not been measured on Quran audio,
  //    so [fastShortWindows] ships OFF - set it to true to try it.
  //    Short windows also skip the bundled Silero VAD: the package turns it
  //    on by default for the non-word-split calls but never for the word-split
  //    ones, so the S61 fallback and the re-transcribe pass heard different
  //    audio than the main scan. These windows are already RMS-gated and known
  //    to hold speech, so all three paths now behave the same.
  // ---------------------------------------------------------------------
  static bool get fastShortWindows => AppSettings.instance.whisperFastShort; // PATCH_S207_WHISPER_SETTINGS
  static const double _shortWindowMaxSec = 12.0;

  /// Duration of a 16 kHz mono 16-bit WAV from its size (44-byte header).
  static double _wavSeconds(String path) {
    try {
      final dataBytes = File(path).lengthSync() - 44;
      return dataBytes <= 0 ? 0.0 : dataBytes / 32000.0;
    } catch (_) {
      return double.infinity; // unknown length -> never take the fast path
    }
  }

  static ({bool speedUp, WhisperVadMode vad}) _fastParams(String wavPath) {
    final short = _wavSeconds(wavPath) <= _shortWindowMaxSec;
    return (
      speedUp: short && fastShortWindows,
      vad: (short || !AppSettings.instance.whisperVad)
          ? WhisperVadMode.disabled
          : WhisperVadMode.auto, // PATCH_S207_WHISPER_SETTINGS
    );
  }

  /// PATCH_S201: frees the native Whisper context (the model's weights plus
  /// its working buffers - roughly the model file's size again). It otherwise
  /// stays resident for the life of the app, next to FFmpeg exports. Safe to
  /// call any time: the next transcribe simply loads the model again.
  static Future<void> release() async {
    try {
      await _controller.dispose(model: _model);
    } catch (_) {
      // best effort
    }
  }

  // PATCH_S201: "detect ayah from video" only needs to hear where the
  // recitation starts, but it used to transcribe the video's ENTIRE
  // soundtrack (minutes of CPU) and then match that whole transcript against
  // single ayat. This copies about the first [maxSec] seconds of actual speech
  // (leading silence skipped) of a 16 kHz mono 16-bit WAV into a temp file and
  // returns its path. Returns null when the file is already short enough, is
  // not the expected format, holds no speech, or anything goes wrong - the
  // caller then simply uses the original file (the old behaviour).
  static Future<String?> _leadingSpeechWav(String wavPath, double maxSec) async {
    const rate = 16000;
    const frame = 1600; // 100 ms
    RandomAccessFile? raf;
    try {
      raf = await File(wavPath).open();
      final fileLen = await raf.length();
      final head = await raf.read(math.min(fileLen, 4096));
      if (head.length < 44 ||
          String.fromCharCodes(head.sublist(0, 4)) != 'RIFF' ||
          String.fromCharCodes(head.sublist(8, 12)) != 'WAVE') {
        return null;
      }
      final hd = ByteData.sublistView(head);
      var off = 12;
      var dataStart = -1;
      var dataLen = 0;
      var formatOk = false;
      while (off + 8 <= head.length) {
        final id = String.fromCharCodes(head.sublist(off, off + 4));
        final size = hd.getUint32(off + 4, Endian.little);
        if (id == 'fmt ' && off + 24 <= head.length) {
          formatOk = hd.getUint16(off + 8, Endian.little) == 1 && // PCM
              hd.getUint16(off + 10, Endian.little) == 1 && // mono
              hd.getUint32(off + 12, Endian.little) == rate &&
              hd.getUint16(off + 22, Endian.little) == 16; // bits
        } else if (id == 'data') {
          dataStart = off + 8;
          dataLen = size;
          break;
        }
        off += 8 + size + (size.isOdd ? 1 : 0);
      }
      if (!formatOk || dataStart < 0) return null;
      final avail = fileLen - dataStart;
      if (dataLen <= 0 || dataLen > avail) dataLen = avail; // streamed WAVs
      final totalSamples = dataLen ~/ 2;
      if (totalSamples <= ((maxSec + 2) * rate).floor()) return null;

      // look for the first speech in the first two minutes
      final want = math.min(totalSamples, ((120 + maxSec) * rate).floor());
      await raf.setPosition(dataStart);
      final raw = Uint8List.fromList(await raf.read(want * 2));
      final n = raw.length ~/ 2;
      final pcm = raw.buffer.asInt16List(0, n);
      final nFrames = n ~/ frame;
      if (nFrames < 5) return null;
      final rms = List<double>.filled(nFrames, 0);
      for (var f = 0; f < nFrames; f++) {
        var sum = 0.0;
        final base = f * frame;
        for (var i = 0; i < frame; i++) {
          final v = pcm[base + i] / 32768.0;
          sum += v * v;
        }
        rms[f] = math.sqrt(sum / frame);
      }
      // same idea as TimelineBuilder.adaptiveSilenceThreshold: just above the
      // clip's own room tone, never below the proven fixed gate
      final sorted = [...rms]..sort();
      final noiseFloor = sorted[(sorted.length * 0.1).floor()];
      final gate = (noiseFloor * 2.2).clamp(0.008, 0.02).toDouble();
      var onset = -1;
      for (var f = 0; f + 1 < nFrames; f++) {
        if (rms[f] >= gate && rms[f + 1] >= gate) {
          onset = f;
          break;
        }
      }
      if (onset < 0) return null;

      final startSample = math.max(0, onset * frame - rate ~/ 2); // 0.5 s lead-in
      final endSample = math.min(n, startSample + (maxSec * rate).floor());
      if (endSample - startSample < rate) return null;

      final dataBytes = (endSample - startSample) * 2;
      final header = ByteData(44);
      void putAscii(int at, String s) {
        for (var i = 0; i < s.length; i++) {
          header.setUint8(at + i, s.codeUnitAt(i));
        }
      }

      putAscii(0, 'RIFF');
      header.setUint32(4, 36 + dataBytes, Endian.little);
      putAscii(8, 'WAVE');
      putAscii(12, 'fmt ');
      header.setUint32(16, 16, Endian.little);
      header.setUint16(20, 1, Endian.little); // PCM
      header.setUint16(22, 1, Endian.little); // mono
      header.setUint32(24, rate, Endian.little);
      header.setUint32(28, rate * 2, Endian.little); // byte rate
      header.setUint16(32, 2, Endian.little); // block align
      header.setUint16(34, 16, Endian.little); // bits per sample
      putAscii(36, 'data');
      header.setUint32(40, dataBytes, Endian.little);

      final out = BytesBuilder();
      out.add(header.buffer.asUint8List());
      out.add(pcm.buffer.asUint8List(startSample * 2, dataBytes));
      final outPath = '${Directory.systemTemp.path}/'
          'ayat_lead_${DateTime.now().microsecondsSinceEpoch}.wav';
      await File(outPath).writeAsBytes(out.takeBytes(), flush: true);
      return outPath;
    } catch (_) {
      return null;
    } finally {
      await raf?.close();
    }
  }

  /// Transcribes a 16kHz mono WAV file (extract audio with ffmpeg first —
  /// see MediaService.extractWav16kMono) and returns the Arabic transcript.
  static Future<String> transcribeWav(
    String wavPath, {
    void Function(String status)? onStatus,
    // PATCH_S201: when set, only about the first [leadSeconds] seconds of
    // actual speech are transcribed (see _leadingSpeechWav).
    double? leadSeconds,
  }) async {
    await ensureReady(onStatus: onStatus);
    onStatus?.call('جارٍ التعرّف على الكلام…');
    // PATCH_S201: optionally trim to the first seconds of speech.
    final lead = leadSeconds == null
        ? null
        : await _leadingSpeechWav(wavPath, leadSeconds);
    final path = lead ?? wavPath;
    final fast = _fastParams(path); // PATCH_S201
    try {
      // PATCH_S200_WHISPER_FALLBACK: guarded - see _guarded().
      final result = await _guarded(
        () => _transcribeNative(
          audioPath: path,
          lang: 'ar',
          threads: _threads, // PATCH_S123_WHISPER_THREADS
          convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass
          speedUp: fast.speedUp, // PATCH_S201: short windows only
          vadMode: fast.vad, // PATCH_S201
        ),
        onStatus: onStatus,
      );
      return result?.transcription.text.trim() ?? '';
    } finally {
      if (lead != null) File(lead).delete().ignore(); // PATCH_S201
    }
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
    // PATCH_S200_WHISPER_FALLBACK: guarded. The word-split attempt keeps
    // throwing untouched so TimelineBuilder's S61 retry still happens.
    final fast = _fastParams(wavPath); // PATCH_S201
    final result = await _guarded(
      () => _transcribeNative(
        audioPath: wavPath,
        lang: 'ar',
        withTimestamps: true,
        splitOnWord: splitOnWord,
        threads: _threads, // PATCH_S123_WHISPER_THREADS
        speedUp: fast.speedUp, // PATCH_S201: short windows only
        vadMode: fast.vad, // PATCH_S201
        convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass
      ),
      onStatus: onStatus,
      fallbackOnError: !splitOnWord,
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
