#!/usr/bin/env python3
"""
patch_s208_whisper_fixes.py
===========================
Ayat Studio S208 - run from the repo root (after S207):

    python3 patch_s208_whisper_fixes.py

Fixes three real problems found by auditing lib/services/whisper_service.dart
at 1faa1e7 (S207). Only that one file is touched.

  1. MODEL-SWITCH RACE (ensureReady / _ensureReadyImpl)
     If the tier changed while a download/verify was in flight (Settings ->
     pick another tier, or the studio re-syncing the picker), the old job
     still finished with `_modelReady = true` - for the NEW tier whose file
     may not exist. whisper_ggml_plus then tries its own HuggingFace download,
     which is unreachable on some networks. Now every tier change bumps an
     epoch; a job only marks the model ready if the tier did not change under
     it, and ensureReady() loops until the CURRENT tier is really ready.

  2. VAD PATH + RETRY (_transcribeNative)
     S207 always sends vadModelPath: '' - also when VAD is ON (the 12-25 s
     windows used by "detect ayah from video", leadSeconds: 25). An empty path
     can stop the package from preparing its bundled VAD model, and the failure
     is not a type_error, so it was rethrown; _guarded() then blamed the model
     tier and fell back to `small` for nothing. Now '' is sent only when VAD
     is disabled (that is the S207 null fix), the package default is used when
     VAD is on, and ANY failure with VAD on is retried once with VAD off.

  3. SEGMENT CLAMP GUARD (transcribeWavWithSegments)
     double.clamp(0.0, audioDurationSec) throws ArgumentError when the upper
     bound is below 0 or NaN. A zero/odd-length window would abort the whole
     scan window instead of just returning no words. Bound is now sanitised.

Idempotent (marker PATCH_S208). Every edit is anchor-checked first; if any
anchor is missing or ambiguous NOTHING is written.
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S208'
path = os.path.join(ROOT, 'lib/services/whisper_service.dart')
if not os.path.exists(path):
    sys.exit('lib/services/whisper_service.dart missing')

s = open(path, encoding='utf-8').read()
if MARK in s:
    print('  OK      whisper_service.dart (already applied)')
    sys.exit(0)

edits = []  # (label, old, new)

# ---------------------------------------------------------------- 1. epoch
edits.append((
    'tier-change epoch counter',
    "  static WhisperModelSize get currentSize => _size; // PATCH_S43_MODEL_SIZE_PICKER\n",
    "  // PATCH_S208_TIER_EPOCH: bumped on every real tier change so an in-flight\n"
    "  // download/verify for the OLD tier can never mark the NEW one as ready.\n"
    "  static int _sizeEpoch = 0;\n"
    "  static WhisperModelSize get currentSize => _size; // PATCH_S43_MODEL_SIZE_PICKER\n",
))

edits.append((
    'setModelSize bumps the epoch',
    "    if (size == _size) return;\n"
    "    _size = size;\n"
    "    _modelReady = false;\n"
    "  }\n",
    "    if (size == _size) return;\n"
    "    _size = size;\n"
    "    _sizeEpoch++; // PATCH_S208_TIER_EPOCH\n"
    "    _modelReady = false;\n"
    "  }\n",
))

edits.append((
    'ensureReady loops until the current tier is ready',
    "  static Future<void>? _readyInFlight;\n"
    "  static Future<void> ensureReady({void Function(String status)? onStatus}) {\n"
    "    if (_modelReady) return Future<void>.value();\n"
    "    return _readyInFlight ??= _ensureReadyImpl(onStatus: onStatus)\n"
    "        .whenComplete(() => _readyInFlight = null);\n"
    "  }\n",
    "  static Future<void>? _readyInFlight;\n"
    "  // PATCH_S208_TIER_EPOCH: a job that finished for a tier the user has since\n"
    "  // left leaves _modelReady false, so go round again for the CURRENT tier.\n"
    "  static Future<void> ensureReady(\n"
    "      {void Function(String status)? onStatus}) async {\n"
    "    for (var round = 0; round < 5; round++) {\n"
    "      if (_modelReady) return;\n"
    "      await (_readyInFlight ??= _ensureReadyImpl(onStatus: onStatus)\n"
    "          .whenComplete(() => _readyInFlight = null));\n"
    "    }\n"
    "    if (!_modelReady) {\n"
    "      throw Exception('تغيّر نموذج التعرّف أثناء التحضير — أعد المحاولة');\n"
    "    }\n"
    "  }\n",
))

edits.append((
    '_ensureReadyImpl remembers the epoch it started in',
    "      {void Function(String status)? onStatus}) async {\n"
    "    if (_modelReady) return;\n"
    "    // PATCH_S200_WHISPER_FALLBACK: a tier that already failed to run this\n",
    "      {void Function(String status)? onStatus}) async {\n"
    "    if (_modelReady) return;\n"
    "    final epoch = _sizeEpoch; // PATCH_S208_TIER_EPOCH\n"
    "    // PATCH_S200_WHISPER_FALLBACK: a tier that already failed to run this\n",
))

edits.append((
    '_ensureReadyImpl only marks ready if the tier did not change',
    "    _modelReady = true;\n"
    "    onStatus?.call('النموذج جاهز');\n"
    "  }\n",
    "    // PATCH_S208_TIER_EPOCH: the tier was switched while this ran (the\n"
    "    // internal fallback to `small` does not count) - not ready for the NEW one.\n"
    "    if (epoch != _sizeEpoch) return;\n"
    "    _modelReady = true;\n"
    "    onStatus?.call('النموذج جاهز');\n"
    "  }\n",
))

# ---------------------------------------------------------------- 2. VAD
edits.append((
    '_transcribeNative: VAD path only when VAD is off, retry on any VAD failure',
    "    Future<dynamic> go(WhisperVadMode v) => _controller.transcribe(\n"
    "          model: _model,\n"
    "          audioPath: audioPath,\n"
    "          lang: lang,\n"
    "          withTimestamps: withTimestamps,\n"
    "          splitOnWord: splitOnWord,\n"
    "          convert: convert,\n"
    "          threads: threads ?? _threads,\n"
    "          speedUp: speedUp,\n"
    "          vadMode: v,\n"
    "          vadModelPath: '',\n"
    "        );\n"
    "    try {\n"
    "      return await go(vadMode);\n"
    "    } catch (e) {\n"
    "      if (vadMode != WhisperVadMode.disabled && '$e'.contains('type_error')) {\n"
    "        return await go(WhisperVadMode.disabled);\n"
    "      }\n"
    "      rethrow;\n"
    "    }\n",
    "    // PATCH_S208_VAD_PATH: '' (never null) only when VAD is OFF - that is the\n"
    "    // S207 null fix. With VAD ON the package must prepare/use its own bundled\n"
    "    // model, so the argument is left out and an empty path cannot override it.\n"
    "    Future<dynamic> go(WhisperVadMode v) => v == WhisperVadMode.disabled\n"
    "        ? _controller.transcribe(\n"
    "            model: _model,\n"
    "            audioPath: audioPath,\n"
    "            lang: lang,\n"
    "            withTimestamps: withTimestamps,\n"
    "            splitOnWord: splitOnWord,\n"
    "            convert: convert,\n"
    "            threads: threads ?? _threads,\n"
    "            speedUp: speedUp,\n"
    "            vadMode: v,\n"
    "            vadModelPath: '',\n"
    "          )\n"
    "        : _controller.transcribe(\n"
    "            model: _model,\n"
    "            audioPath: audioPath,\n"
    "            lang: lang,\n"
    "            withTimestamps: withTimestamps,\n"
    "            splitOnWord: splitOnWord,\n"
    "            convert: convert,\n"
    "            threads: threads ?? _threads,\n"
    "            speedUp: speedUp,\n"
    "            vadMode: v,\n"
    "          );\n"
    "    try {\n"
    "      return await go(vadMode);\n"
    "    } catch (e) {\n"
    "      // Any failure with VAD on (type_error, VAD model missing/unloadable)\n"
    "      // is retried once without it, so _guarded() never blames the tier for\n"
    "      // a VAD problem. If that also fails, ITS error is the real cause.\n"
    "      if (vadMode != WhisperVadMode.disabled) {\n"
    "        return await go(WhisperVadMode.disabled);\n"
    "      }\n"
    "      rethrow;\n"
    "    }\n",
))

# ---------------------------------------------------------------- 3. clamp
edits.append((
    'segment time clamp bound sanitised',
    "    final text = result?.transcription.text.trim() ?? '';\n"
    "    final rawSegments = result?.transcription.segments ?? const [];\n"
    "    final segments = <TranscriptSegment>[\n",
    "    final text = result?.transcription.text.trim() ?? '';\n"
    "    final rawSegments = result?.transcription.segments ?? const [];\n"
    "    // PATCH_S208_CLAMP_GUARD: clamp(0, x) throws when x < 0 or NaN\n"
    "    final maxT = (audioDurationSec.isFinite && audioDurationSec > 0)\n"
    "        ? audioDurationSec\n"
    "        : double.maxFinite;\n"
    "    final segments = <TranscriptSegment>[\n",
))
edits.append((
    'segment from-time clamp',
    "            (s.fromTs.inMilliseconds / 1000.0).clamp(0.0, audioDurationSec),\n",
    "            (s.fromTs.inMilliseconds / 1000.0).clamp(0.0, maxT),\n",
))
edits.append((
    'segment to-time clamp',
    "            (s.toTs.inMilliseconds / 1000.0).clamp(0.0, audioDurationSec),\n",
    "            (s.toTs.inMilliseconds / 1000.0).clamp(0.0, maxT),\n",
))

# ---- verify every anchor exists exactly once BEFORE touching anything ----
problems = []
for label, old, _ in edits:
    n = s.count(old)
    if n != 1:
        problems.append('  %-62s found %d times' % (label, n))
if problems:
    print('  SKIP    anchors not matching (S207 text changed?) - nothing touched:')
    print('\n'.join(problems))
    sys.exit(1)

for label, old, new in edits:
    s = s.replace(old, new)
    print('  PATCHED %s' % label)

open(path, 'w', encoding='utf-8').write(s)

t = re.sub(r"//[^\n]*", '', s)
bal = all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))
print('  all balanced' if bal else '  !! UNBALANCED - check the file')
print('Next: git add -A && git commit -m "S208: Whisper tier-switch race, VAD path + retry, clamp guard" && git push')
