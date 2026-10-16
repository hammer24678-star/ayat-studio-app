#!/usr/bin/env python3
"""
patch_s200_whisper_fallback.py
==============================
Ayat Studio S200 - run from the repo root (after S199):

    python3 patch_s200_whisper_fallback.py

Why Whisper can "do nothing" even though the model downloaded fine
------------------------------------------------------------------
S75 only falls back to `small` when the selected model cannot be DOWNLOADED.
If a tier downloads fine but then fails to load or run (a truncated / bad /
incompatible file - the Quran-tuned one is converted by a CI job, so it is the
likeliest), every transcribe call fails and nothing ever recovers. Worse,
whisper_ggml_plus reports some native failures as a NULL result instead of an
exception, and the callers read null as "no speech" - so the failure is
silent.

What this patch does (whisper_service.dart + one line in home_screen.dart)
  1. A null result with an invalid model file (missing / too small / wrong
     magic) deletes that file and downloads it again, once.
  2. A tier that has never worked this session and fails to run falls back
     to `small` for the rest of the session (S75's existing toast + picker
     sync then tells the user). A tier that already worked is trusted: a
     later failure is about that audio, so no 466 MB surprise download.
  3. Every failure now carries the real reason (tier, file size, GGML magic,
     threads, exception type + text) in the error shown to the user.
  4. The picker/toast sync also runs after "detect from video audio"
     (previously only after auto-sync and the mic).

The splitOnWord:true path still throws untouched so TimelineBuilder's own
S61 retry (splitOnWord:false) keeps working exactly as before.

Idempotent (marker PATCH_S200).
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S200'
WS = os.path.join(ROOT, 'lib/services/whisper_service.dart')
HS = os.path.join(ROOT, 'lib/screens/home_screen.dart')
for p in (WS, HS):
    if not os.path.exists(p):
        sys.exit('%s missing' % os.path.relpath(p, ROOT))

ws = open(WS, encoding='utf-8').read()
hs = open(HS, encoding='utf-8').read()

if MARK in ws and MARK in hs:
    print('  OK      already applied (PATCH_S200)')
    sys.exit(0)


def apply_fix(src, label, old, new):
    n = src.count(old)
    if n != 1:
        sys.exit('  SKIP    %s: anchor found %d times (need exactly 1) - nothing written' % (label, n))
    print('  PATCHED %s' % label)
    return src.replace(old, new)


# ---------------------------------------------------------------- whisper_service.dart

A_OLD = r"""  static bool _modelReady = false;
"""
A_NEW = r"""  static bool _modelReady = false;
  // PATCH_S200_WHISPER_FALLBACK: tiers that failed to run this session, and
  // tiers that have run successfully at least once this session.
  static final Set<WhisperModelSize> _badTiers = <WhisperModelSize>{};
  static final Set<WhisperModelSize> _provenTiers = <WhisperModelSize>{};

  /// Last Whisper failure, with model/file details (also appended to errors).
  static String? lastError;
"""

B_OLD = r"""    if (_modelReady) return;
    try {
      await _downloadAndVerify(_size, onStatus: onStatus);
"""
B_NEW = r"""    if (_modelReady) return;
    // PATCH_S200_WHISPER_FALLBACK: a tier that already failed to run this
    // session is not tried again - go straight to the safe one.
    if (_badTiers.contains(_size) && _size != WhisperModelSize.small) {
      _size = WhisperModelSize.small;
    }
    try {
      await _downloadAndVerify(_size, onStatus: onStatus);
"""

C_OLD = "      final failedLabel = labelFor(_size).split(' — ').first;\n"
C_NEW = ("      lastError = 'download ${_size.name}: ${_describe(e)}'; // PATCH_S200_WHISPER_FALLBACK\n"
         + C_OLD)

D_OLD = r"""    final result = await _controller.transcribe(
      model: _model,
      audioPath: wavPath,
      lang: 'ar',
      threads: _threads, // PATCH_S123_WHISPER_THREADS
      convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass
    );
    return result?.transcription.text.trim() ?? '';
"""
D_NEW = r"""    // PATCH_S200_WHISPER_FALLBACK: guarded - see _guarded().
    final result = await _guarded(
      () => _controller.transcribe(
        model: _model,
        audioPath: wavPath,
        lang: 'ar',
        threads: _threads, // PATCH_S123_WHISPER_THREADS
        convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass
      ),
      onStatus: onStatus,
    );
    return result?.transcription.text.trim() ?? '';
"""

E_OLD = r"""    final result = await _controller.transcribe(
      model: _model,
      audioPath: wavPath,
      lang: 'ar',
      withTimestamps: true,
      splitOnWord: splitOnWord,
      threads: _threads, // PATCH_S123_WHISPER_THREADS
      convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass
    );
"""
E_NEW = r"""    // PATCH_S200_WHISPER_FALLBACK: guarded. The word-split attempt keeps
    // throwing untouched so TimelineBuilder's S61 retry still happens.
    final result = await _guarded(
      () => _controller.transcribe(
        model: _model,
        audioPath: wavPath,
        lang: 'ar',
        withTimestamps: true,
        splitOnWord: splitOnWord,
        threads: _threads, // PATCH_S123_WHISPER_THREADS
        convert: false, // PATCH_S163: already 16 kHz mono WAV — skip the per-window ffmpeg pass
      ),
      onStatus: onStatus,
      fallbackOnError: !splitOnWord,
    );
"""

F_OLD = "  /// Transcribes a 16kHz mono WAV file (extract audio with ffmpeg first —\n"
F_NEW = r"""  // ---------------------------------------------------------------------
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

""" + F_OLD

ws2 = ws
ws2 = apply_fix(ws2, 'whisper_service.dart - session tier sets + lastError', A_OLD, A_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - skip tiers that failed to run', B_OLD, B_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - record why a download fell back', C_OLD, C_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - transcribeWav guarded', D_OLD, D_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - transcribeWavWithSegments guarded', E_OLD, E_NEW)
ws2 = apply_fix(ws2, 'whisper_service.dart - _guarded() helpers', F_OLD, F_NEW)

# ---------------------------------------------------------------- home_screen.dart

G_OLD = "    if (text == null || !mounted) return;\n    if (text.isEmpty) {\n"
G_NEW = ("    if (mounted) _syncModelSizeDisplay(); // PATCH_S200: keep the picker truthful after a fallback\n"
         + G_OLD)
hs2 = apply_fix(hs, 'home_screen.dart - sync picker after detect-from-video', G_OLD, G_NEW)

open(WS, 'w', encoding='utf-8').write(ws2)
open(HS, 'w', encoding='utf-8').write(hs2)

ok = True
for p in (WS, HS):
    t = re.sub(r"//[^\n]*", '', open(p, encoding='utf-8').read())
    bal = all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))
    ok = ok and bal
print('  all balanced' if ok else '  !! UNBALANCED - check the files before committing')
print('Next: git add -A && git commit -m "S200: Whisper recovers from a broken/unrunnable model" && git push')
