#!/usr/bin/env python3
"""
patch_s163_ai_whisper_background_fonts.py
=========================================
Ayat Studio S163 - run from the repo root (after S162):

    python3 patch_s163_ai_whisper_background_fonts.py

Idempotent (marker PATCH_S163). Anchor-based edits; every edit reports
PATCHED / OK (already applied) / SKIP (anchor not found - nothing touched).

WHISPER   convert:false (our windows are already 16 kHz mono WAV - the package
          was spawning an ffmpeg conversion per window), model download now
          retries 3x with resume, 30s connect / 45s stall timeouts, HTTP 416
          handled, html/garbage model rejected, http client closed, concurrent
          ensureReady() calls share one download, WAV decode moved off the UI
          isolate.
AI ART    768x1344 instead of 1080x1920 (about 2x faster, same line-art look),
          2 requests in flight (auto-drops to 1 on HTTP 429), in-flight dedupe,
          one keep-alive client, no retry on timeout (moves to next model and
          marks the slow model dead for 2 min), atomic cache writes, cache dir
          cleanup no longer runs on every call, batch generates in parallel
          (6 -> 10 ayat), next ayah's art is prefetched during playback.
BACKGROUND foreground service (flutter_foreground_task) wraps every long job
          (auto-sync, detect-from-video, export) so Android keeps it alive with
          the app minimized/screen off; notification shows live status+percent.
          CI step adds the service + permissions to the generated manifest.
FONTS     ROOT CAUSE: Aref Ruqaa, Markazi Text, Qahiri and Reem Kufi have NO
          Quranic marks (waqf signs, small seen, ayah-end 06DD, ...) so ayat
          fell back to a random system font. 'andalus'/'qalam'/'kufi' now use
          Amiri / Scheherazade New / Noto Kufi Arabic (full coverage); every
          ayah style gets Amiri Quran + Scheherazade New as fallback so a
          missing glyph never drops to the system font. All fonts are
          downloaded into google_fonts/ (bundled - no runtime fetching, preview
          == export, works offline).
pubspec   -> 1.7.5+12 (+ app_info.dart)
"""
import os, re, sys, urllib.request, urllib.error

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S163'
ok = skip = 0


def P(p): return os.path.join(ROOT, p)


def edit(p, fn, label):
    global ok, skip
    if not os.path.exists(P(p)):
        skip += 1; print('  SKIP   ', p, '(missing)', label); return
    s = open(P(p), encoding='utf-8').read()
    try:
        n = fn(s)
    except KeyError as e:
        skip += 1; print('  SKIP   ', p, '-', label, '(anchor not found: %s)' % str(e)[:70]); return
    if n == s:
        ok += 1; print('  OK     ', p, '-', label, '(already applied)'); return
    open(P(p), 'w', encoding='utf-8').write(n)
    ok += 1; print('  PATCHED', p, '-', label)


def rep(s, old, new, count=1):
    if old not in s:
        raise KeyError(old.strip().split('\n')[0])
    return s.replace(old, new, count)


def rep_re(s, pattern, new):
    m = re.search(pattern, s, re.S)
    if not m:
        raise KeyError(pattern[:60])
    return s[:m.start()] + new + s[m.end():]


def new_file(p, text, label):
    global ok
    os.makedirs(os.path.dirname(P(p)), exist_ok=True)
    if os.path.exists(P(p)) and MARK in open(P(p), encoding='utf-8').read():
        ok += 1; print('  OK     ', p, '-', label, '(already applied)'); return
    open(P(p), 'w', encoding='utf-8').write(text)
    ok += 1; print('  CREATED', p, '-', label)


# ======================================================================
# 1. BackgroundJob service
# ======================================================================
BG = r"""// PATCH_S163_BACKGROUND_JOBS
// Keeps long jobs (auto-sync, detect-from-video, export) alive when the app is
// minimized or the screen turns off: an Android foreground service holds the
// process + a CPU wake lock, and its notification shows live status/percent.
// Every call is best-effort - a failure here must never break the job itself.
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

class BackgroundJob {
  static const int _serviceId = 7461;
  static const String _title = 'استوديو الآيات';
  static bool _inited = false;
  static bool _active = false;
  static String _text = '';
  static DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);

  static void _init() {
    if (_inited) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'ayat_studio_jobs',
        channelName: 'Ayat Studio background jobs',
        channelDescription:
            'Keeps long jobs running while the app is minimized',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions:
          const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    _inited = true;
  }

  static Future<void> start([String text = 'جارٍ المعالجة…']) async {
    if (!Platform.isAndroid || _active) return;
    try {
      _init();
      final perm = await FlutterForegroundTask.checkNotificationPermission();
      if (perm != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      _text = text;
      _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
      final r = await FlutterForegroundTask.startService(
        serviceId: _serviceId,
        notificationTitle: _title,
        notificationText: text,
      );
      _active = r is ServiceRequestSuccess;
    } catch (_) {
      _active = false;
    }
  }

  /// [text] null keeps the last status line; [progress] is 0..1 or null.
  /// Throttled to ~1 push/second so a fast progress callback can't spam it.
  static void update(String? text, double? progress) {
    if (!_active) return;
    if (text != null && text.trim().isNotEmpty) {
      _text = text.split('\n').first;
    }
    final now = DateTime.now();
    if (now.difference(_lastPush) < const Duration(milliseconds: 1200)) return;
    _lastPush = now;
    final pct = progress == null ? '' : ' — ${(progress * 100).round()}٪';
    try {
      FlutterForegroundTask.updateService(
        notificationTitle: _title,
        notificationText: '$_text$pct',
      ).then((_) {}, onError: (_) {});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!_active) return;
    _active = false;
    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}
  }
}
"""
new_file('lib/services/background_job.dart', BG, 'foreground-service wrapper')

# ======================================================================
# 2. Whisper service
# ======================================================================
WHISPER_WRAPPER = r"""  // PATCH_S163: a GGML model starts with the 'lmgg' magic. A saved HTML/JSON
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

"""


def whisper(s):
    if MARK in s:
        return s
    s = rep(s,
            "  static Future<void> _downloadAndVerify(\n"
            "      WhisperModelSize size, {void Function(String status)? onStatus}) async {",
            WHISPER_WRAPPER +
            "  static Future<void> _downloadAndVerifyOnce(\n"
            "      WhisperModelSize size, {void Function(String status)? onStatus}) async {")
    s = rep(s,
            "    final needsDownload =\n"
            "        !(await file.exists()) || (await file.length()) < spec.minExpectedBytes;",
            "    final needsDownload = !(await file.exists()) ||\n"
            "        (await file.length()) < spec.minExpectedBytes ||\n"
            "        !(await _hasGgmlMagic(file)); // PATCH_S163")
    s = rep(s,
            "      final response = await http.Client().send(request);\n"
            "      if (response.statusCode == 200) {\n"
            "        have = 0; // server ignored the range — start clean\n"
            "      } else if (response.statusCode != 206) {\n"
            "        throw Exception(",
            "      final client = http.Client(); // PATCH_S163: closed in the finally below\n"
            "      final http.StreamedResponse response;\n"
            "      try {\n"
            "        response =\n"
            "            await client.send(request).timeout(const Duration(seconds: 30));\n"
            "      } catch (_) {\n"
            "        client.close();\n"
            "        rethrow;\n"
            "      }\n"
            "      if (response.statusCode == 200) {\n"
            "        have = 0; // server ignored the range — start clean\n"
            "      } else if (response.statusCode != 206) {\n"
            "        client.close();\n"
            "        if (response.statusCode == 416) {\n"
            "          // stale/oversized .part — drop it so the retry starts clean\n"
            "          try {\n"
            "            if (await part.exists()) await part.delete();\n"
            "          } catch (_) {}\n"
            "        }\n"
            "        throw Exception(")
    s = rep(s,
            "        await for (final chunk in response.stream) {",
            "        await for (final chunk\n"
            "            in response.stream.timeout(const Duration(seconds: 45))) {")
    s = rep(s,
            "        // keep whatever arrived — that's exactly what resume picks up from\n"
            "        await sink.close();\n",
            "        // keep whatever arrived — that's exactly what resume picks up from\n"
            "        await sink.close();\n"
            "        client.close(); // PATCH_S163\n")
    s = rep(s,
            "      await part.rename(path);",
            "      if (!await _hasGgmlMagic(part)) {\n"
            "        try {\n"
            "          await part.delete();\n"
            "        } catch (_) {}\n"
            "        throw Exception('ملف النموذج المنزَّل غير صالح — أعد المحاولة');\n"
            "      }\n"
            "      await part.rename(path);")
    s = rep(s,
            "  static Future<void> ensureReady({void Function(String status)? onStatus}) async {\n"
            "    if (_modelReady) return;",
            "  // PATCH_S163: two flows asking at once (auto-sync + detect) share ONE\n"
            "  // download instead of both writing the same .part file.\n"
            "  static Future<void>? _readyInFlight;\n"
            "  static Future<void> ensureReady({void Function(String status)? onStatus}) {\n"
            "    if (_modelReady) return Future<void>.value();\n"
            "    return _readyInFlight ??= _ensureReadyImpl(onStatus: onStatus)\n"
            "        .whenComplete(() => _readyInFlight = null);\n"
            "  }\n\n"
            "  static Future<void> _ensureReadyImpl(\n"
            "      {void Function(String status)? onStatus}) async {\n"
            "    if (_modelReady) return;")
    # both transcribe() calls
    old = "      threads: _threads, // PATCH_S123_WHISPER_THREADS\n"
    if s.count(old) < 2:
        raise KeyError('threads: _threads')
    s = s.replace(old, old +
                  "      convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass\n")
    return s


edit('lib/services/whisper_service.dart', whisper, 'faster + robust model load/transcribe')


def timeline(s):
    if MARK in s:
        return s
    s = rep(s, "import 'dart:typed_data';\n",
            "import 'dart:typed_data';\n\n"
            "import 'package:flutter/foundation.dart' show compute; // PATCH_S163\n")
    s = rep(s, "    final pcm = _readWavMono16(wavPath);",
            "    // PATCH_S163: decode off the UI isolate (a 20-minute clip is ~38 MB of PCM)\n"
            "    final pcm = await compute(_readWavMono16, wavPath);")
    return s


edit('lib/services/timeline_builder.dart', timeline, 'WAV decode off UI isolate')

# ======================================================================
# 3. AI art service
# ======================================================================
ART_NEW = r"""  // PATCH_S163_AI_ART_SPEED
  // - one keep-alive client (was a fresh TLS handshake per request)
  // - 768x1344 (9:16, multiples of 64): ~2x faster than 1080x1920; the art is
  //   thin glowing line-art on black and is scaled to cover the frame anyway
  // - 2 requests in flight (drops to 1 for the session after an HTTP 429)
  // - identical requests in flight are shared, cache writes are atomic
  // - a model that times out / answers garbage is skipped for 2-5 minutes
  //   instead of being re-probed (and re-timed-out) for every ayah
  static final http.Client _client = http.Client();
  static final Map<String, Future<String?>> _inFlight = {};
  static final Map<String, DateTime> _deadUntil = {};
  static int _maxParallel = 2;
  static int _active = 0;
  static final List<Completer<void>> _waiters = [];

  static Future<void> _acquire() {
    if (_active < _maxParallel) {
      _active++;
      return Future<void>.value();
    }
    final c = Completer<void>();
    _waiters.add(c);
    return c.future; // slot is handed over directly by _release()
  }

  static void _release() {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete();
    } else {
      _active--;
    }
  }

  static void _markDead(String model, int minutes) {
    _deadUntil[model] = DateTime.now().add(Duration(minutes: minutes));
  }

  /// Returns a local file path to the cached (or freshly generated) art for
  /// [surahNum]:[ayahNum], or null on any failure -- caller should keep
  /// whatever background was already active if this returns null.
  static Future<String?> artFor({
    required int surahNum,
    required int ayahNum,
    required String ayahArabic,
    String ayahEnglish = '',
    int seedOffset = 0,
  }) async {
    final cached = await _fileFor(surahNum, ayahNum, seedOffset);
    if (await cached.exists() && await cached.length() > 5000) {
      return cached.path;
    }
    final running = _inFlight[cached.path];
    if (running != null) return running;
    final job = _generate(
        cached, surahNum, ayahNum, ayahArabic, ayahEnglish, seedOffset);
    _inFlight[cached.path] = job;
    try {
      return await job;
    } finally {
      _inFlight.remove(cached.path);
    }
  }

  static Future<String?> _generate(File cached, int surahNum, int ayahNum,
      String ayahArabic, String ayahEnglish, int seedOffset) async {
    final prompt = _buildPrompt(ayahArabic, ayahEnglish);
    // Deterministic seed from surah:ayah (+ offset) -- same ayah always
    // reproduces the same art; a regenerate tap bumps the offset.
    final seed = (surahNum * 1000 + ayahNum) * 97 + seedOffset;
    final keyParam = apiKey.trim().isEmpty
        ? ''
        : '&key=${Uri.encodeComponent(apiKey.trim())}';

    var models = [
      if (_workingModel != null) _workingModel!,
      ...kModelChain.where((m) => m != _workingModel),
    ];
    final now = DateTime.now();
    final alive = models.where((m) {
      final d = _deadUntil[m];
      return d == null || now.isAfter(d);
    }).toList();
    if (alive.isNotEmpty) models = alive; // never end up with nothing to try

    AiArtException? lastError;
    await _acquire();
    try {
      for (final model in models) {
        final url = Uri.parse('$_base${Uri.encodeComponent(prompt)}'
            '?width=768&height=1344&seed=$seed&model=$model'
            '&nologo=true&private=true&safe=true$keyParam');
        for (var attempt = 0; attempt < 2; attempt++) {
          if (attempt > 0) {
            await Future<void>.delayed(const Duration(milliseconds: 1500));
          }
          http.Response res;
          try {
            res = await _client.get(url).timeout(const Duration(seconds: 35));
          } on TimeoutException {
            lastError = AiArtException('انتهت مهلة توليد الفن -- حاول مرة أخرى');
            _markDead(model, 2); // slow model: skip it, don't wait twice
            break;
          } on Exception {
            lastError = AiArtException(
                'تعذر الاتصال بخدمة توليد الفن -- تحقق من الإنترنت');
            continue;
          }
          if (res.statusCode == 401 && apiKey.trim().isNotEmpty) {
            throw AiArtException(
                'المفتاح المُدخَل في الإعدادات غير صالح -- احذفه لاستخدام التوليد المجاني بدون مفتاح، أو تحقق منه في enter.pollinations.ai');
          }
          if (res.statusCode == 402 || res.statusCode == 429) {
            lastError = AiArtException(
                'تم تجاوز الحد المسموح مؤقتًا -- حاول مرة أخرى خلال دقيقة');
            _maxParallel = 1; // the provider is throttling: stop doubling up
            await Future<void>.delayed(const Duration(seconds: 3));
            continue; // retry, then next model
          }
          if (res.statusCode >= 500) {
            lastError =
                AiArtException('فشل توليد الفن (رمز الحالة: ${res.statusCode})');
            continue;
          }
          // A gated/renamed model can answer 200 with a tiny HTML/JSON error
          // body -- only a real image counts as success.
          final contentType = res.headers['content-type'] ?? '';
          final looksLikeImage = res.statusCode == 200 &&
              res.bodyBytes.length > 5000 &&
              (contentType.startsWith('image/') || contentType.isEmpty);
          if (!looksLikeImage) {
            lastError =
                AiArtException('فشل توليد الفن (رمز الحالة: ${res.statusCode})');
            _markDead(model, 5);
            break; // hard failure for this model -- try the next one
          }
          final tmp = File('${cached.path}.part');
          await tmp.writeAsBytes(res.bodyBytes, flush: true);
          await tmp.rename(cached.path);
          _workingModel = model;
          return cached.path;
        }
      }
    } finally {
      _release();
    }
    throw lastError ?? AiArtException('فشل توليد الفن -- حاول مرة أخرى لاحقًا');
  }

"""

CACHE_DIR_NEW = r"""  // PATCH_S163_AI_ART_SPEED: the old-cache cleanup + mkdir check used to run on
  // EVERY call; now once per session.
  static Directory? _cacheDirMemo;
  static Future<Directory> _cacheDir() async {
    final memo = _cacheDirMemo;
    if (memo != null) {
      if (!await memo.exists()) await memo.create(recursive: true);
      return memo;
    }
    final docs = await getApplicationDocumentsDirectory();
    // v2 cache (PATCH_S84); the pre-chain v1 dir is removed once.
    Directory('${docs.path}/ai_art_cache').delete(recursive: true).ignore();
    final dir = Directory('${docs.path}/ai_art_cache_v2');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cacheDirMemo = dir;
  }

"""


def art(s):
    if MARK in s:
        return s
    s = rep(s, "import 'dart:io';\n\nimport 'package:http/http.dart' as http;",
            "import 'dart:async';\nimport 'dart:io';\n\nimport 'package:http/http.dart' as http;")
    s = rep_re(s, r"  static Future<Directory> _cacheDir\(\) async \{.*?\n  \}\n\n(?=  static Future<File> _fileFor)",
               CACHE_DIR_NEW)
    s = rep_re(s, r"  /// Returns a local file path to the cached \(or freshly generated\).*?(?=  // PATCH_S51_AI_ART_DELETE)",
               ART_NEW)
    return s


edit('lib/services/ai_art_service.dart', art, 'faster, parallel, no dead-model re-probing')

# ======================================================================
# 4. StudioState: parallel batch + next-ayah prefetch
# ======================================================================
BATCH_NEW = r"""      // PATCH_S163_AI_ART_SPEED: every target starts at once; AiArtService
      // gates real network concurrency itself (2, or 1 after a 429). The first
      // ayah's art still takes over the background the moment it lands.
      var done = 0;
      await Future.wait([
        for (var i = 0; i < targets.length; i++)
          () async {
            final ayah = targets[i];
            try {
              final path = await AiArtService.artFor(
                surahNum: ayah.surahNum,
                ayahNum: ayah.num,
                ayahArabic: ayah.ar,
                ayahEnglish: ayah.en, // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART
              );
              if (path != null) {
                ok++;
                if (i == 0) {
                  useCustomBg = true;
                  customBgPath = path;
                  _aiArtSurah = ayah.surahNum;
                  _aiArtAyahNum = ayah.num;
                  _aiArtAyahText = ayah.ar;
                  _aiArtSeedOffset = 0;
                  _lastMatchedSurah = ayah.surahNum;
                  _lastMatchedAyahNum = ayah.num;
                  _lastMatchedAyahText = ayah.ar;
                  _lastMatchedAyahEn = ayah.en;
                }
              }
            } on AiArtException catch (e) {
              aiArtError = e.message; // last error stays visible if all fail
            } catch (e) {
              aiArtError = 'تعذر توليد الفن: $e';
            }
            done++;
            aiArtBatchProgress = 'تم $done من ${targets.length}…';
            notifyListeners();
          }(),
      ]);
"""

PREFETCH_NEW = r"""    _generateAiArt(ayah.surahNum, ayah.num, ayah.ar, ayah.en);
    _prefetchNextArt(ayah); // PATCH_S163_AI_ART_SPEED
  }

  // PATCH_S163_AI_ART_SPEED: warm the NEXT distinct ayah's art while this one
  // plays, so the crossfade finds it already on disk. Fire-and-forget.
  void _prefetchNextArt(Ayah current) {
    var seenCurrent = false;
    for (final seg in timeline) {
      final a = seg.ayah;
      if (a.surahNum == current.surahNum && a.num == current.num) {
        seenCurrent = true;
        continue;
      }
      if (seenCurrent) {
        AiArtService.artFor(
          surahNum: a.surahNum,
          ayahNum: a.num,
          ayahArabic: a.ar,
          ayahEnglish: a.en,
        ).then((_) {}, onError: (_) {});
        return;
      }
    }
  }
"""


def studio(s):
    if MARK in s:
        return s
    s = rep(s, "  static const int _aiArtBatchMax = 6;",
            "  static const int _aiArtBatchMax = 10; // PATCH_S163: was 6 (parallel now)")
    s = rep_re(s, r"      for \(var i = 0; i < targets\.length; i\+\+\) \{\n        final ayah = targets\[i\];.*?(?=      if \(ok == 0\) \{)",
               BATCH_NEW)
    s = rep(s, "    _generateAiArt(ayah.surahNum, ayah.num, ayah.ar, ayah.en);\n  }\n", PREFETCH_NEW)
    return s


edit('lib/models/studio_state.dart', studio, 'parallel batch + prefetch')

# ======================================================================
# 5. HomeScreen: wrap busy jobs in the foreground service
# ======================================================================


def home(s):
    if MARK in s:
        return s
    s = rep(s, "import '../services/media_service.dart';\n",
            "import '../services/media_service.dart';\n"
            "import '../services/background_job.dart'; // PATCH_S163\n")
    s = rep(s,
            "    _busyWatch\n      ..reset()\n      ..start(); // PATCH_S83_SYNC_QOL\n    try {\n      return await job();",
            "    _busyWatch\n      ..reset()\n      ..start(); // PATCH_S83_SYNC_QOL\n"
            "    await BackgroundJob.start(); // PATCH_S163: survive minimize / screen-off\n"
            "    try {\n      return await job();")
    s = rep(s,
            "    } finally {\n      _busyWatch.stop(); // PATCH_S83_SYNC_QOL\n",
            "    } finally {\n      await BackgroundJob.stop(); // PATCH_S163\n"
            "      _busyWatch.stop(); // PATCH_S83_SYNC_QOL\n")
    s = rep(s,
            "  void _setBusyStatus(String s, [double? progress]) {\n    if (!mounted) return;",
            "  void _setBusyStatus(String s, [double? progress]) {\n"
            "    BackgroundJob.update(s, progress ?? _busyProgress); // PATCH_S163\n"
            "    if (!mounted) return;")
    old = "onProgress: (f) => setState(() => _busyProgress = f),"
    if old not in s:
        raise KeyError(old)
    s = s.replace(old,
                  "onProgress: (f) {\n"
                  "          BackgroundJob.update(null, f); // PATCH_S163\n"
                  "          setState(() => _busyProgress = f);\n"
                  "        },")
    return s


edit('lib/screens/home_screen.dart', home, '_withBusy -> foreground service')

# ======================================================================
# 6. Fonts: mapping + fallback + preload
# ======================================================================


def fonts(s):
    if MARK in s:
        return s
    s = rep(s, "TextStyle ayahTextStyle(\n  String fontKey, {",
            "// PATCH_S163_FONTS: Aref Ruqaa / Qahiri / Markazi / Reem Kufi (and every\n"
            "// custom font) lack the Quranic annotation marks - waqf signs, small seen,\n"
            "// ayah-end U+06DD... - so those glyphs fell to a random system font. Amiri\n"
            "// Quran and Scheherazade New carry the full set; they are bundled in\n"
            "// google_fonts/ and sit behind EVERY ayah style as the fallback chain.\n"
            "List<String> _quranFallback() => [\n"
            "      GoogleFonts.amiriQuran().fontFamily!,\n"
            "      GoogleFonts.scheherazadeNew().fontFamily!,\n"
            "      GoogleFonts.notoNaskhArabic().fontFamily!,\n"
            "    ];\n\n"
            "TextStyle ayahTextStyle(\n  String fontKey, {")
    s = rep(s, "    letterSpacing: letterSpacing,\n  );\n  switch (fontKey) {",
            "    letterSpacing: letterSpacing,\n"
            "    fontFamilyFallback: _quranFallback(), // PATCH_S163_FONTS\n"
            "  );\n  switch (fontKey) {")
    s = rep(s, "GoogleFonts.markaziText(textStyle: base)", "GoogleFonts.amiri(textStyle: base)")
    s = rep(s, "GoogleFonts.qahiri(textStyle: base)", "GoogleFonts.scheherazadeNew(textStyle: base)")
    s = rep(s, "GoogleFonts.reemKufi(textStyle: base)", "GoogleFonts.notoKufiArabic(textStyle: base)")
    return s


edit('lib/theme/ayat_fonts.dart', fonts, 'quran-complete fonts + fallback chain')


def overlay(s):
    if MARK in s:
        return s
    return rep(s, "    GoogleFonts.tajawal();\n    await GoogleFonts.pendingFonts();",
               "    GoogleFonts.tajawal();\n"
               "    // PATCH_S163_FONTS: the fallback chain + the remapped styles must be\n"
               "    // loaded before the first export frame paints.\n"
               "    GoogleFonts.amiri();\n"
               "    GoogleFonts.scheherazadeNew();\n"
               "    GoogleFonts.notoNaskhArabic();\n"
               "    GoogleFonts.notoKufiArabic();\n"
               "    await GoogleFonts.pendingFonts();")


edit('lib/services/overlay_renderer.dart', overlay, 'preload fallback fonts before export')

# ======================================================================
# 7. pubspec / version / CI manifest
# ======================================================================


def pubspec(s):
    if 'flutter_foreground_task' in s and 'google_fonts/' in s and '1.7.5+12' in s:
        return s
    if 'flutter_foreground_task' not in s:
        s = rep(s, "  shared_preferences: ^2.2.2",
                "  flutter_foreground_task: ^8.17.0 # PATCH_S163: background jobs\n  shared_preferences: ^2.2.2")
    if '    - google_fonts/\n' not in s:
        s = rep(s, "    - assets/icon/\n",
                "    - assets/icon/\n    # PATCH_S163_FONTS: bundled Google fonts (google_fonts package finds\n"
                "    # them here by file name, so no runtime download)\n    - google_fonts/\n")
    s = s.replace('version: 1.7.4+11', 'version: 1.7.5+12')
    return s


edit('pubspec.yaml', pubspec, 'dependency + fonts dir + 1.7.5+12')


def appinfo(s):
    s = s.replace("const String kAppVersion = '1.7.4';", "const String kAppVersion = '1.7.5';")
    s = s.replace("const int kAppBuildNumber = 11;", "const int kAppBuildNumber = 12;")
    return s


edit('lib/app_info.dart', appinfo, 'version 1.7.5+12')

CI_STEP = """      - name: Foreground service + notification permissions for background jobs (PATCH_S163)
        run: |
          MANIFEST=android/app/src/main/AndroidManifest.xml
          for PERM in FOREGROUND_SERVICE FOREGROUND_SERVICE_DATA_SYNC WAKE_LOCK POST_NOTIFICATIONS; do
            grep -q "android.permission.$PERM\\"" "$MANIFEST" || \\
              sed -i "s|<application|<uses-permission android:name=\\"android.permission.$PERM\\"/>\\n    <application|" "$MANIFEST"
          done
          grep -q 'flutter_foreground_task.service.ForegroundService' "$MANIFEST" || \\
            sed -i 's|</application>|    <service android:name="com.pravera.flutter_foreground_task.service.ForegroundService" android:foregroundServiceType="dataSync" android:exported="false" />\\n    </application>|' "$MANIFEST"
          echo "-- manifest after background-job step:"; cat "$MANIFEST"

"""


def workflow(s):
    if 'PATCH_S163' in s:
        return s
    return rep(s, "      - name: Decode release keystore", CI_STEP + "      - name: Decode release keystore")


edit('.github/workflows/build-apk.yml', workflow, 'manifest: foreground service')

# ======================================================================
# 8. Download the fonts
# ======================================================================
RAW = 'https://raw.githubusercontent.com/google/fonts/main/ofl/'
VAR_NAS = RAW + 'notonaskharabic/NotoNaskhArabic%5Bwght%5D.ttf'
VAR_KUF = RAW + 'notokufiarabic/NotoKufiArabic%5Bwght%5D.ttf'
FONTS = {}
for w in ('ExtraLight', 'Light', 'Regular', 'Medium', 'Bold', 'ExtraBold', 'Black'):
    FONTS['Tajawal-%s.ttf' % w] = RAW + 'tajawal/Tajawal-%s.ttf' % w
for w in ('Regular', 'Bold'):
    FONTS['Amiri-%s.ttf' % w] = RAW + 'amiri/Amiri-%s.ttf' % w
    FONTS['ArefRuqaa-%s.ttf' % w] = RAW + 'arefruqaa/ArefRuqaa-%s.ttf' % w
    FONTS['ScheherazadeNew-%s.ttf' % w] = RAW + 'scheherazadenew/ScheherazadeNew-%s.ttf' % w
FONTS['AmiriQuran-Regular.ttf'] = RAW + 'amiriquran/AmiriQuran-Regular.ttf'
for w in ('Regular', 'Medium', 'Bold'):          # variable font, one file per requested weight
    FONTS['NotoNaskhArabic-%s.ttf' % w] = VAR_NAS
    FONTS['NotoKufiArabic-%s.ttf' % w] = VAR_KUF


def fetch(url):
    last = None
    for i in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'ayat-studio-patch'}), timeout=60) as r:
                return r.read()
        except Exception as e:
            last = e
    raise last


def valid_font(b):
    return len(b) > 20000 and b[:4] in (b'\x00\x01\x00\x00', b'OTTO', b'true', b'ttcf')


print('\nFonts -> google_fonts/')
os.makedirs(P('google_fonts'), exist_ok=True)
cache = {}
font_fail = []
for name, url in FONTS.items():
    dst = P('google_fonts/' + name)
    if os.path.exists(dst) and valid_font(open(dst, 'rb').read()):
        print('  have   ', name); continue
    try:
        if url not in cache:
            cache[url] = fetch(url)
        data = cache[url]
        if not valid_font(data):
            raise ValueError('not a font file')
        tmp = dst + '.tmp'
        open(tmp, 'wb').write(data)
        os.replace(tmp, dst)
        print('  got    ', name, '%d KB' % (len(data) // 1024))
    except Exception as e:
        font_fail.append(name)
        print('  FAILED ', name, '-', e)

# the 11 bundled asset fonts pubspec already declares must exist or the build fails
missing = []
ps = open(P('pubspec.yaml'), encoding='utf-8').read()
for a in re.findall(r'asset:\s*(assets/fonts/\S+)', ps):
    if not os.path.exists(P(a)):
        missing.append(a)
if missing:
    print('\n  !! pubspec declares fonts that are NOT in the repo (build will fail):')
    for a in missing:
        print('     ', a)
    print('     copy them in, or tell me which to drop from pubspec.yaml.')

# ======================================================================
# 9. Sanity
# ======================================================================


def balance_check(paths):
    bad = 0
    for p in paths:
        if not os.path.exists(P(p)):
            continue
        t = open(P(p), encoding='utf-8').read()
        t = re.sub(r"//[^\n]*", '', t)
        t = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", t)
        t = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', t)
        for a, b in ('{}', '()', '[]'):
            if t.count(a) != t.count(b):
                bad += 1
                print('  UNBALANCED', p, a, t.count(a), b, t.count(b))
    print('  all balanced' if not bad else '  !! fix the files above before building')


print('\nBalance check')
balance_check(['lib/services/whisper_service.dart', 'lib/services/ai_art_service.dart',
               'lib/services/background_job.dart', 'lib/services/timeline_builder.dart',
               'lib/models/studio_state.dart', 'lib/screens/home_screen.dart',
               'lib/theme/ayat_fonts.dart', 'lib/services/overlay_renderer.dart'])
print('\nDone: %d ok, %d skipped, %d font failures.' % (ok, skip, len(font_fail)))
print('Next: git add google_fonts lib pubspec.yaml .github && git commit -m "S163: AI/Whisper speed, background jobs, bundled Quran fonts" && git push')
