#!/usr/bin/env python3
"""
patch_s207_whisper_pip_files.py
===============================
Ayat Studio S207 - run from the repo root (after S206):

    python3 patch_s207_whisper_pip_files.py

What was wrong (all found in the 2026-10-26 dump + the whisper_ggml_plus source)

  1. «تعذّر التعرّف على الكلام ... [json.exception.type_error.302] type must be
     string, but is null»  -- ROOT CAUSE: whisper_ggml_plus 1.5.x serialises
     `vad_model_path: null` whenever VAD is off (short windows, word-split
     scans) and its native code does json.value("vad_model_path", "") which
     THROWS on a null. S201 made every short window / word-split call hit it,
     so Whisper failed on every clip. Fix: always send vad_model_path = ""
     (never null) and, if the VAD model can't be prepared, retry once with VAD
     off instead of failing.
  2. The error said "try another model size from Settings" but Settings had no
     Whisper section. New section: model tier (with downloaded / not
     downloaded status), CPU threads, short-window speed-up, VAD, last error
     (copyable), delete + re-download model, reset. The main-bar picker and
     the Settings screen now stay in sync and the choice survives restarts.
  3. «تعذّر الوصول إلى الملف المحدد ... cache//file_picker/.../3_reference.wav»
     -- the picker hands back a file inside the app CACHE, which Android may
     drop at any time (and which was never cleaned by us either). Every pick
     (video, merge, audio, add-media, PIP, reciter, ambience, sequence) is now
     copied straight into app storage; merge / append / sequence outputs are
     rendered there too. Copies nothing refers to are pruned after 21 days.
  4. PIP on the stage felt loose:
       - the corner button both resized AND rotated at once -> it now only
         resizes; a separate rotate knob sits above the box (snaps every 45°,
         with a tick)
       - touch targets were 30px -> 44px
       - the box now magnets to the frame EDGES as well as the centre, with
         guide lines
       - live "size % · angle°" readout while a finger is down
       - panel: quick sizes (25/50/75/100%), fill the frame, 90° turn and
         1%-nudge arrows

Files: whisper_service, app_settings, timeline_builder, media_service,
settings_screen, home_screen, autoseg_wizard, sequence_screen, pro_pip,
app_strings. All edits apply together or not at all. Idempotent (PATCH_S207).
"""
import os, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
MARK = 'PATCH_S207'

FILES = {
    'ws':  'lib/services/whisper_service.dart',
    'as':  'lib/services/app_settings.dart',
    'tb':  'lib/services/timeline_builder.dart',
    'ms':  'lib/services/media_service.dart',
    'ss':  'lib/screens/settings_screen.dart',
    'hs':  'lib/screens/home_screen.dart',
    'aw':  'lib/widgets/autoseg_wizard.dart',
    'sq':  'lib/screens/sequence_screen.dart',
    'pp':  'lib/widgets/pro_pip.dart',
    'st':  'lib/i18n/app_strings.dart',
}
src, orig, delta = {}, {}, {}
for k, rel in FILES.items():
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        sys.exit('%s missing' % rel)
    src[k] = open(p, encoding='utf-8').read()
    orig[k] = src[k]
    delta[k] = 0

present = [k for k in src if MARK in src[k] and k != 'tb']  # tb carries no marker
if len(present) == len(src) - 1:
    print('  OK      already applied (PATCH_S207)')
    sys.exit(0)
if present:
    sys.exit('  SKIP    PATCH_S207 is only partly present (%s) - restore the files (git checkout) and re-run.' % ', '.join(present))
if 'PATCH_S206' not in src['hs']:
    sys.exit('  SKIP    apply patch_s206_stickers.py first.')


def bal(s):
    return (s.count('{') - s.count('}'), s.count('(') - s.count(')'), s.count('[') - s.count(']'))


def add_delta(k, old, new):
    a, b = bal(old), bal(new)
    d = tuple(x - y for x, y in zip(b, a))
    delta[k] = tuple(x + y for x, y in zip(delta[k], d)) if delta[k] != 0 else d


def fix(k, label, old, new, n_exp=1):
    n = src[k].count(old)
    if n != n_exp:
        sys.exit('  SKIP    %s: anchor found %d times (need exactly %d) - nothing written' % (label, n, n_exp))
    src[k] = src[k].replace(old, new)
    add_delta(k, old, new)
    print('  PATCHED %s' % label)


def fix_between(k, label, start, end, new):
    s = src[k]
    if s.count(start) != 1 or s.count(end) != 1:
        sys.exit('  SKIP    %s: markers found %d/%d times (need 1/1) - nothing written' % (label, s.count(start), s.count(end)))
    i, j = s.index(start), s.index(end)
    if j <= i:
        sys.exit('  SKIP    %s: end marker precedes start marker' % label)
    old = s[i:j]
    src[k] = s[:i] + new + s[j:]
    add_delta(k, old, new)
    print('  PATCHED %s' % label)


# =====================================================================
# whisper_service.dart
# =====================================================================
fix('ws', 'whisper_service.dart - import AppSettings',
    "import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';\n",
    "import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';\n\nimport 'app_settings.dart'; // PATCH_S207_WHISPER_SETTINGS\n")

fix('ws', 'whisper_service.dart - threads from Settings',
    "  static int get _threads => _threadsMemo ??= _pickThreads();\n",
    r'''  // PATCH_S207_WHISPER_SETTINGS: Settings can pin the thread count (0 = auto).
  static int get _threads {
    final pinned = AppSettings.instance.whisperThreads;
    return pinned > 0 ? pinned : autoThreads;
  }

  static int get autoThreads => _threadsMemo ??= _pickThreads();
  static int get cpuCores => Platform.numberOfProcessors;
''')

fix('ws', 'whisper_service.dart - fast short windows from Settings',
    "  static bool fastShortWindows = false;\n",
    "  static bool get fastShortWindows => AppSettings.instance.whisperFastShort; // PATCH_S207_WHISPER_SETTINGS\n")

fix('ws', 'whisper_service.dart - VAD switch',
    "      vad: short ? WhisperVadMode.disabled : WhisperVadMode.auto,\n",
    "      vad: (short || !AppSettings.instance.whisperVad)\n"
    "          ? WhisperVadMode.disabled\n"
    "          : WhisperVadMode.auto, // PATCH_S207_WHISPER_SETTINGS\n")

fix('ws', 'whisper_service.dart - transcribeWav through the safe wrapper',
    "        () => _controller.transcribe(\n          model: _model,\n          audioPath: path,\n",
    "        () => _transcribeNative(\n          audioPath: path,\n")

fix('ws', 'whisper_service.dart - transcribeWavWithSegments through the safe wrapper',
    "      () => _controller.transcribe(\n        model: _model,\n        audioPath: wavPath,\n",
    "      () => _transcribeNative(\n        audioPath: wavPath,\n")

fix('ws', 'whisper_service.dart - wrapper + Settings API',
    "  static Future<T> _guarded<T>(\n",
    r'''  // ---------------------------------------------------------------------
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
''')

# =====================================================================
# timeline_builder.dart - the message now points at a real place
# =====================================================================
fix('tb', 'timeline_builder.dart - error text points at the Whisper settings',
    "'جرّب حجم نموذج مختلف من الإعدادات أو أعد تشغيل التطبيق.'",
    "'جرّب حجم نموذج مختلف من الإعدادات ← التعرّف على الكلام، أو أعد تشغيل التطبيق.'")

# =====================================================================
# app_settings.dart
# =====================================================================
fix('as', 'app_settings.dart - fields',
    "  bool get classicTabs => _classicTabs;\n",
    r'''  bool get classicTabs => _classicTabs;

  // ---- PATCH_S207_WHISPER_SETTINGS ----
  /// Model tier chosen on the Settings screen (index into WhisperModelSize);
  /// null until the user has chosen one anywhere.
  int? _whisperTier;
  int? get whisperTierIndex => _whisperTier;

  /// CPU threads for Whisper; 0 = pick automatically.
  int _whisperThreads = 0;
  int get whisperThreads => _whisperThreads;

  /// ~35-40% faster scans of short windows, slightly less accurate.
  bool _whisperFastShort = false;
  bool get whisperFastShort => _whisperFastShort;

  /// Silero VAD (skips silence) for long windows.
  bool _whisperVad = true;
  bool get whisperVad => _whisperVad;
''')

fix('as', 'app_settings.dart - load',
    "    _classicTabs = p.getBool('${_prefix}classicTabs') ?? _classicTabs;\n    notifyListeners();",
    r'''    _classicTabs = p.getBool('${_prefix}classicTabs') ?? _classicTabs;
    // PATCH_S207_WHISPER_SETTINGS
    _whisperTier = p.getInt('${_prefix}whisperTier');
    _whisperThreads =
        (p.getInt('${_prefix}whisperThreads') ?? _whisperThreads).clamp(0, 8);
    _whisperFastShort =
        p.getBool('${_prefix}whisperFastShort') ?? _whisperFastShort;
    _whisperVad = p.getBool('${_prefix}whisperVad') ?? _whisperVad;
    notifyListeners();''')

fix('as', 'app_settings.dart - setters',
    "    _write((p) => p.setBool('${_prefix}classicTabs', v));\n  }\n}\n",
    r'''    _write((p) => p.setBool('${_prefix}classicTabs', v));
  }

  // PATCH_S207_WHISPER_SETTINGS
  void setWhisperTierIndex(int v) {
    if (v == _whisperTier) return;
    _whisperTier = v;
    _write((p) => p.setInt('${_prefix}whisperTier', v));
  }

  void setWhisperThreads(int v) {
    final c = v.clamp(0, 8);
    if (c == _whisperThreads) return;
    _whisperThreads = c;
    _write((p) => p.setInt('${_prefix}whisperThreads', c));
  }

  void setWhisperFastShort(bool v) {
    if (v == _whisperFastShort) return;
    _whisperFastShort = v;
    _write((p) => p.setBool('${_prefix}whisperFastShort', v));
  }

  void setWhisperVad(bool v) {
    if (v == _whisperVad) return;
    _whisperVad = v;
    _write((p) => p.setBool('${_prefix}whisperVad', v));
  }
}
''')

# =====================================================================
# media_service.dart - picked files + outputs live in app storage
# =====================================================================
fix('ms', 'media_service.dart - keepPicked / keptDir / pruneKept',
    "class MediaService {\n",
    r'''class MediaService {
  // PATCH_S207_KEEP_PICKED
  // file_picker returns a copy inside the app's CACHE folder
  // (cache/file_picker/<stamp>/<name>). Android may empty a cache folder at
  // any moment, which is exactly the "تعذّر الوصول إلى الملف المحدد" error
  // seen after picking a clip and tapping Whisper a minute later. Everything
  // the user picks is copied into app storage right away, and the long
  // renders (merge / append / sequence) are written there too.
  static Future<Directory> keptDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/picked_media');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Copies [src] into app storage and returns the new path. Files that are
  /// already in app storage, or that don't sit in a cache folder, are
  /// returned unchanged. Throws a readable Exception when [src] is gone.
  static Future<String> keepPicked(String src) async {
    final f = File(src);
    if (!await f.exists()) {
      throw Exception('تعذّر الوصول إلى الملف المحدد — اخترْه من جديد.');
    }
    final dir = await keptDir();
    if (src.startsWith(dir.path)) return src;
    final fragile = src.contains('/file_picker/') || src.contains('/cache/');
    if (!fragile) return src;
    var name = src.split('/').last.replaceAll(RegExp('["\$`\\\\\\r\\n]'), '_');
    if (name.trim().isEmpty) name = 'file';
    final folder = Directory(
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}');
    await folder.create(recursive: true);
    final dst = '${folder.path}/$name';
    await f.copy(dst);
    if (src.contains('/file_picker/')) f.delete().ignore();
    return dst;
  }

  /// Deletes kept copies older than [days] days that nothing in [protect]
  /// points at. Best effort; never throws.
  static Future<void> pruneKept(Set<String> protect, {int days = 21}) async {
    try {
      final dir = await keptDir();
      final cutoff = DateTime.now().subtract(Duration(days: days));
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        if (protect.contains(e.path)) continue;
        final st = await e.stat();
        if (st.modified.isBefore(cutoff)) {
          try {
            await e.delete();
          } catch (_) {}
        }
      }
      await for (final e in dir.list(followLinks: false)) {
        if (e is! Directory) continue;
        try {
          if (await e.list().isEmpty) await e.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

''')

fix('ms', 'media_service.dart - merge output in app storage',
    "    final dir = await getTemporaryDirectory();\n    final outPath =\n        '${dir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.mp4';",
    "    final dir = await keptDir(); // PATCH_S207_KEEP_PICKED\n    final outPath =\n        '${dir.path}/merged_${DateTime.now().millisecondsSinceEpoch}.mp4';")
fix('ms', 'media_service.dart - append output in app storage',
    "    final dir = await getTemporaryDirectory();\n    final outPath =\n        '${dir.path}/appended_${DateTime.now().millisecondsSinceEpoch}.mp4';",
    "    final dir = await keptDir(); // PATCH_S207_KEEP_PICKED\n    final outPath =\n        '${dir.path}/appended_${DateTime.now().millisecondsSinceEpoch}.mp4';")
fix('ms', 'media_service.dart - sequence output in app storage',
    "    final dir = await getTemporaryDirectory();\n    final outPath =\n        '${dir.path}/sequence_${DateTime.now().millisecondsSinceEpoch}.mp4';",
    "    final dir = await keptDir(); // PATCH_S207_KEEP_PICKED\n    final outPath =\n        '${dir.path}/sequence_${DateTime.now().millisecondsSinceEpoch}.mp4';")

# =====================================================================
# sequence_screen.dart
# =====================================================================
fix('sq', 'sequence_screen.dart - keep picked clips',
    "      final p = f.path;\n      if (p != null) await _addPath(p);\n",
    "      final p = f.path;\n      if (p == null) continue;\n      String kept = p;\n"
    "      try {\n        kept = await MediaService.keepPicked(p); // PATCH_S207_KEEP_PICKED\n"
    "      } catch (_) {}\n      await _addPath(kept);\n")

# =====================================================================
# autoseg_wizard.dart
# =====================================================================
fix('aw', 'autoseg_wizard.dart - remember the tier app-wide',
    "      WhisperService.setModelSize(_tier);\n      return const AutoSegResult(tierApplied: true);",
    "      WhisperService.setModelSize(_tier);\n"
    "      AppSettings.instance.setWhisperTierIndex(_tier.index); // PATCH_S207\n"
    "      return const AutoSegResult(tierApplied: true);")

# =====================================================================
# home_screen.dart
# =====================================================================
fix('hs', 'home_screen.dart - follow the Settings tier on start',
    "  void initState() {\n    super.initState();\n    _loadCorpus();\n",
    "  void initState() {\n    super.initState();\n    AppSettings.instance.addListener(_onWhisperPrefs); // PATCH_S207_WHISPER_SETTINGS\n    _loadCorpus();\n")

fix('hs', 'home_screen.dart - stop following on dispose',
    "    state.removeListener(_schedulePersist); // PATCH_S37_PERSISTENT_SETTINGS\n",
    "    state.removeListener(_schedulePersist); // PATCH_S37_PERSISTENT_SETTINGS\n"
    "    AppSettings.instance.removeListener(_onWhisperPrefs); // PATCH_S207_WHISPER_SETTINGS\n")

fix('hs', 'home_screen.dart - restore: Settings tier wins, prune old copies',
    "      await SettingsService.restore(state);\n      WhisperService.setModelSize(state.whisperModelSize); // PATCH_S43_MODEL_SIZE_PICKER\n",
    r'''      await SettingsService.restore(state);
      // PATCH_S207_WHISPER_SETTINGS: the tier picked on the Settings screen
      // (app-wide) wins over the one saved with the project.
      final prefTier = AppSettings.instance.whisperTierIndex;
      if (prefTier != null &&
          prefTier >= 0 &&
          prefTier < WhisperModelSize.values.length) {
        state.whisperModelSize = WhisperModelSize.values[prefTier];
      }
      WhisperService.setModelSize(state.whisperModelSize); // PATCH_S43_MODEL_SIZE_PICKER
      // PATCH_S207_KEEP_PICKED: forget kept copies nothing refers to any more
      MediaService.pruneKept(<String>{
        if (state.videoPath != null) state.videoPath!,
        for (final c in state.audioClips) c.path,
        for (final c in state.pipClips) c.path,
        for (final p in state.reciterAudioPaths)
          if (p != null) p,
        if (state.ambienceBedPath != null) state.ambienceBedPath!,
      });
''')

fix('hs', 'home_screen.dart - helpers (_onWhisperPrefs, _keepPicked)',
    "  Future<T?> _withBusy<T>(Future<T> Function() job) async {\n",
    r'''  // PATCH_S207_WHISPER_SETTINGS: the Settings screen chooses the model tier
  // app-wide; the studio follows it.
  void _onWhisperPrefs() {
    final i = AppSettings.instance.whisperTierIndex;
    if (i == null || i < 0 || i >= WhisperModelSize.values.length) return;
    final t = WhisperModelSize.values[i];
    if (!mounted || t == state.whisperModelSize) return;
    state.update(() => state.whisperModelSize = t);
    WhisperService.setModelSize(t);
  }

  // PATCH_S207_KEEP_PICKED: copy a picked file out of the picker's cache
  // folder (Android may empty it at any time) into app storage.
  Future<String?> _keepPicked(String path) async {
    try {
      return await MediaService.keepPicked(path);
    } catch (e) {
      if (mounted) _toast('$e'.replaceFirst('Exception: ', ''));
      return null;
    }
  }

  Future<T?> _withBusy<T>(Future<T> Function() job) async {
''')

fix('hs', 'home_screen.dart - _pickVideo keeps the file',
    "    final path = res?.files.single.path;\n    if (path == null) return;\n    await _video?.dispose();\n",
    "    final pickedPath = res?.files.single.path;\n    if (pickedPath == null) return;\n"
    "    final path = await _keepPicked(pickedPath); // PATCH_S207_KEEP_PICKED\n"
    "    if (path == null || !mounted) return;\n    await _video?.dispose();\n")

fix('hs', 'home_screen.dart - merge keeps the second file',
    "    final secondPath = res?.files.single.path;\n    if (secondPath == null) return;\n",
    "    final secondRaw = res?.files.single.path;\n    if (secondRaw == null) return;\n"
    "    final secondPath = await _keepPicked(secondRaw); // PATCH_S207_KEEP_PICKED\n"
    "    if (secondPath == null || !mounted) return;\n")

fix('hs', 'home_screen.dart - audio clip keeps the file',
    "    final f = res?.files.single;\n    final path = f?.path;\n    if (f == null || path == null || !mounted) return;\n    if (!await MediaService.hasAudioStream(path)) {",
    "    final f = res?.files.single;\n    final pickedPath = f?.path;\n    if (f == null || pickedPath == null || !mounted) return;\n"
    "    final path = await _keepPicked(pickedPath); // PATCH_S207_KEEP_PICKED\n"
    "    if (path == null || !mounted) return;\n    if (!await MediaService.hasAudioStream(path)) {")

fix('hs', 'home_screen.dart - add-media keeps the file',
    "    final path = res?.files.single.path;\n    if (path == null || !mounted) return;\n    var sec = 5.0;",
    "    final pickedPath = res?.files.single.path;\n    if (pickedPath == null || !mounted) return;\n"
    "    final path = await _keepPicked(pickedPath); // PATCH_S207_KEEP_PICKED\n"
    "    if (path == null || !mounted) return;\n    var sec = 5.0;")

fix('hs', 'home_screen.dart - PIP keeps the file',
    "    final path = res?.files.single.path;\n    if (path == null || !mounted) return;\n    var aspect = 9 / 16;",
    "    final pickedPath = res?.files.single.path;\n    if (pickedPath == null || !mounted) return;\n"
    "    final path = await _keepPicked(pickedPath); // PATCH_S207_KEEP_PICKED\n"
    "    if (path == null || !mounted) return;\n    var aspect = 9 / 16;")

fix('hs', 'home_screen.dart - reciter audio keeps the file',
    "    final path = res?.files.single.path;\n    if (path == null) return;\n    state.update(() => state.reciterAudioPaths[i] = path);",
    "    final pickedPath = res?.files.single.path;\n    if (pickedPath == null) return;\n"
    "    final path = await _keepPicked(pickedPath); // PATCH_S207_KEEP_PICKED\n"
    "    if (path == null || !mounted) return;\n    state.update(() => state.reciterAudioPaths[i] = path);")

fix('hs', 'home_screen.dart - ambience bed keeps the file',
    "    final path = res?.files.single.path;\n    if (path == null) return;\n    state.update(() => state.ambienceBedPath = path);",
    "    final pickedPath = res?.files.single.path;\n    if (pickedPath == null) return;\n"
    "    final path = await _keepPicked(pickedPath); // PATCH_S207_KEEP_PICKED\n"
    "    if (path == null || !mounted) return;\n    state.update(() => state.ambienceBedPath = path);")

fix('hs', 'home_screen.dart - the bar picker is remembered app-wide',
    "                            state.update(() => state.whisperModelSize = size);\n                            WhisperService.setModelSize(size);\n",
    "                            state.update(() => state.whisperModelSize = size);\n                            WhisperService.setModelSize(size);\n"
    "                            AppSettings.instance.setWhisperTierIndex(size.index); // PATCH_S207\n")

# =====================================================================
# app_strings.dart
# =====================================================================
fix('st', 'app_strings.dart - Whisper settings strings',
    "  // PATCH_S129_QURAN_CAPTION_PARITY\n  'export.chapters': [",
    r'''  // PATCH_S207_WHISPER_SETTINGS
  'whisper.title': [
    'التعرّف على الكلام (Whisper)',
    'Speech recognition (Whisper)',
    'Reconnaissance vocale (Whisper)',
    'Pengenalan suara (Whisper)',
    'تقریر کی شناخت (Whisper)',
  ],
  'whisper.model': [
    'دقة النموذج',
    'Model accuracy',
    'Précision du modèle',
    'Akurasi model',
    'ماڈل کی درستگی',
  ],
  'whisper.tier.tiny': [
    'سريع جدًا (~75MB) — أقل دقة',
    'Very fast (~75 MB) — lowest accuracy',
    'Très rapide (~75 Mo) — précision minimale',
    'Sangat cepat (~75 MB) — akurasi terendah',
    'بہت تیز (~75MB) — کم درستگی',
  ],
  'whisper.tier.base': [
    'سريع (~148MB) — دقة متوسطة',
    'Fast (~148 MB) — medium accuracy',
    'Rapide (~148 Mo) — précision moyenne',
    'Cepat (~148 MB) — akurasi sedang',
    'تیز (~148MB) — درمیانی درستگی',
  ],
  'whisper.tier.small': [
    'دقيق (~466MB)',
    'Accurate (~466 MB)',
    'Précis (~466 Mo)',
    'Akurat (~466 MB)',
    'درست (~466MB)',
  ],
  'whisper.tier.medium': [
    'الأدق (~1.5GB) — أبطأ',
    'Most accurate (~1.5 GB) — slower',
    'Le plus précis (~1,5 Go) — plus lent',
    'Paling akurat (~1,5 GB) — lebih lambat',
    'سب سے درست (~1.5GB) — سست',
  ],
  'whisper.tier.quranTuned': [
    'دقة القرآن (الافتراضي، ~148MB)',
    'Quran-tuned (default, ~148 MB)',
    'Optimisé Coran (par défaut, ~148 Mo)',
    'Khusus Al-Qur’an (bawaan, ~148 MB)',
    'قرآن کے لیے (طے شدہ، ~148MB)',
  ],
  'whisper.downloaded': [
    'محمَّل',
    'Downloaded',
    'Téléchargé',
    'Terunduh',
    'ڈاؤن لوڈ شدہ',
  ],
  'whisper.notDownloaded': [
    'غير محمَّل — يُنزَّل عند أول استخدام',
    'Not downloaded — fetched on first use',
    'Non téléchargé — récupéré au premier usage',
    'Belum diunduh — diunduh saat pertama dipakai',
    'ڈاؤن لوڈ نہیں — پہلی بار استعمال پر آئے گا',
  ],
  'whisper.threads': [
    'عدد الأنوية (Threads)',
    'CPU threads',
    'Threads du processeur',
    'Thread CPU',
    'سی پی یو تھریڈز',
  ],
  'whisper.threadsAuto': [
    'تلقائي',
    'Auto',
    'Auto',
    'Otomatis',
    'خودکار',
  ],
  'whisper.threadsHint': [
    'تلقائي يختار الأنوية السريعة فقط. جرّب رقمًا أقل إن سخن الهاتف أو تجمّد التطبيق. أنوية الجهاز:',
    'Auto uses only the fast cores. Try a lower number if the phone gets hot or the app freezes. Cores on this device:',
    'Auto n’utilise que les cœurs rapides. Essayez moins si le téléphone chauffe ou se fige. Cœurs de l’appareil :',
    'Otomatis hanya memakai inti cepat. Coba angka lebih kecil jika ponsel panas atau aplikasi macet. Inti di perangkat ini:',
    'خودکار صرف تیز کور استعمال کرتا ہے۔ فون گرم ہو یا ایپ رک جائے تو کم عدد آزمائیں۔ اس ڈیوائس کے کور:',
  ],
  'whisper.fast': [
    'تسريع المقاطع القصيرة',
    'Speed up short windows',
    'Accélérer les fenêtres courtes',
    'Percepat jendela pendek',
    'مختصر ٹکڑوں کی رفتار بڑھائیں',
  ],
  'whisper.fastHint': [
    'مسح أسرع بنحو ٣٥–٤٠٪ بدقة أقل قليلًا. مغلق افتراضيًا.',
    'Scans about 35–40% faster, slightly less accurate. Off by default.',
    'Scans environ 35–40 % plus rapides, un peu moins précis. Désactivé par défaut.',
    'Pemindaian sekitar 35–40% lebih cepat, sedikit kurang akurat. Mati secara bawaan.',
    'اسکین تقریباً 35–40٪ تیز، درستگی ذرا کم۔ بطورِ طے شدہ بند۔',
  ],
  'whisper.vad': [
    'كشف الصمت (VAD) للمقاطع الطويلة',
    'Silence detection (VAD) for long windows',
    'Détection du silence (VAD) pour les longues fenêtres',
    'Deteksi hening (VAD) untuk jendela panjang',
    'لمبے ٹکڑوں کے لیے خاموشی کی شناخت (VAD)',
  ],
  'whisper.vadHint': [
    'يتخطّى الصمت فيقلّ الهذيان. يتعطّل تلقائيًا لهذه المرة إن لم يتوفّر نموذجه.',
    'Skips silence so there is less hallucination. Skipped automatically if its model is missing.',
    'Ignore les silences pour limiter les hallucinations. Ignoré automatiquement si son modèle manque.',
    'Melewati hening agar halusinasi berkurang. Dilewati otomatis jika modelnya tidak ada.',
    'خاموشی چھوڑ دیتا ہے تاکہ غلط الفاظ کم ہوں۔ ماڈل نہ ملے تو خود چھوڑ دیا جاتا ہے۔',
  ],
  'whisper.lastError': [
    'آخر خطأ',
    'Last error',
    'Dernière erreur',
    'Kesalahan terakhir',
    'آخری خرابی',
  ],
  'whisper.copy': [
    'نسخ',
    'Copy',
    'Copier',
    'Salin',
    'کاپی',
  ],
  'whisper.redownload': [
    'حذف النموذج وإعادة تنزيله',
    'Delete model and re-download',
    'Supprimer et retélécharger le modèle',
    'Hapus model dan unduh ulang',
    'ماڈل حذف کر کے دوبارہ ڈاؤن لوڈ کریں',
  ],
  'whisper.redownloadHint': [
    'مفيد إن كان الملف تالفًا. يُنزَّل من جديد عند أول مزامنة.',
    'Useful if the file is corrupt. It is fetched again on the next sync.',
    'Utile si le fichier est corrompu. Il sera récupéré à la prochaine synchro.',
    'Berguna jika berkas rusak. Diunduh lagi saat sinkron berikutnya.',
    'فائل خراب ہو تو مفید۔ اگلی مطابقت پر دوبارہ آئے گی۔',
  ],
  'whisper.reset': [
    'إعادة ضبط خيارات Whisper',
    'Reset Whisper options',
    'Réinitialiser les options Whisper',
    'Atur ulang opsi Whisper',
    'Whisper کے اختیارات ری سیٹ کریں',
  ],
  'whisper.deleted': [
    'تم حذف النموذج — سيُنزَّل من جديد عند الحاجة',
    'Model deleted — it will be fetched again when needed',
    'Modèle supprimé — il sera récupéré en cas de besoin',
    'Model dihapus — akan diunduh lagi saat dibutuhkan',
    'ماڈل حذف ہو گیا — ضرورت پر دوبارہ آئے گا',
  ],
  // PATCH_S129_QURAN_CAPTION_PARITY
  'export.chapters': [''')

# =====================================================================
# settings_screen.dart
# =====================================================================
fix('ss', 'settings_screen.dart - imports',
    "import '../services/tafsir_service.dart';\n",
    "import '../services/tafsir_service.dart';\nimport '../services/whisper_service.dart'; // PATCH_S207_WHISPER_SETTINGS\n")
fix('ss', 'settings_screen.dart - services import',
    "import 'package:flutter/material.dart';\n",
    "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart'; // PATCH_S207_WHISPER_SETTINGS: Clipboard\n")

fix('ss', 'settings_screen.dart - Whisper section',
    "          // PATCH_S128: touch-controls guide\n",
    "          const SizedBox(height: 14),\n"
    "          _WhisperSection(s: s), // PATCH_S207_WHISPER_SETTINGS\n"
    "          // PATCH_S128: touch-controls guide\n")

src['ss'] = src['ss'].rstrip('\n') + '\n' + r'''
// PATCH_S207_WHISPER_SETTINGS: everything about Whisper in one place. The
// "try another model size from Settings" error used to point here while
// Settings had nothing of the kind.
class _WhisperSection extends StatefulWidget {
  final AppStrings s;
  const _WhisperSection({required this.s});

  @override
  State<_WhisperSection> createState() => _WhisperSectionState();
}

class _WhisperSectionState extends State<_WhisperSection> {
  final _settings = AppSettings.instance;
  Map<WhisperModelSize, int?> _have = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final m = <WhisperModelSize, int?>{};
    for (final t in WhisperModelSize.values) {
      m[t] = await WhisperService.downloadedBytes(t);
    }
    if (mounted) setState(() => _have = m);
  }

  WhisperModelSize get _tier {
    final i = _settings.whisperTierIndex;
    if (i != null && i >= 0 && i < WhisperModelSize.values.length) {
      return WhisperModelSize.values[i];
    }
    return WhisperService.currentSize;
  }

  String _mb(int bytes) {
    final mb = bytes / (1024 * 1024);
    return mb >= 1024
        ? '${(mb / 1024).toStringAsFixed(1)} GB'
        : '${mb.toStringAsFixed(0)} MB';
  }

  void _pickTier(WhisperModelSize t) {
    _settings.setWhisperTierIndex(t.index);
    WhisperService.setModelSize(t);
    setState(() {});
  }

  Future<void> _redownload() async {
    if (_busy) return;
    setState(() => _busy = true);
    await WhisperService.deleteModel(_tier);
    await _refresh();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(widget.s.t('whisper.deleted'))),
    );
  }

  void _reset() {
    _settings.setWhisperThreads(0);
    _settings.setWhisperFastShort(false);
    _settings.setWhisperVad(true);
    WhisperService.resetDiagnostics();
    setState(() {});
  }

  Widget _tierRow(WhisperModelSize t, AppStrings s) {
    final sel = _tier == t;
    final bytes = _have[t];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableScale(
        onTap: () => _pickTier(t),
        borderRadius: BorderRadius.circular(11),
        child: AnimatedContainer(
          duration: AppMotion.d(AppMotion.fast),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: sel
                ? AyatColors.gold.withValues(alpha: 0.16)
                : AyatColors.surface2,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: sel ? AyatColors.gold : AyatColors.hairline,
            ),
          ),
          child: Row(
            children: [
              Icon(
                sel ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 18,
                color: sel ? AyatColors.goldBright : AyatColors.parchmentDim,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.t('whisper.tier.${t.name}'),
                      style: GoogleFonts.tajawal(
                        color: sel
                            ? AyatColors.goldBright
                            : AyatColors.parchment,
                        fontSize: 13,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      bytes != null
                          ? '${s.t('whisper.downloaded')} ✓ · ${_mb(bytes)}'
                          : s.t('whisper.notDownloaded'),
                      style: GoogleFonts.tajawal(
                          color: AyatColors.parchmentDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _switchTile(
      String title, String hint, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      value: value,
      activeThumbColor: AyatColors.gold,
      title: Text(title,
          style: GoogleFonts.tajawal(
              color: AyatColors.parchment, fontSize: 13.5)),
      subtitle: Text(hint,
          style: GoogleFonts.tajawal(
              color: AyatColors.parchmentDim, fontSize: 11.5, height: 1.5)),
      onChanged: onChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    final err = WhisperService.lastError;
    return _Section(title: s.t('whisper.title'), children: [
      _Label(s.t('whisper.model')),
      const SizedBox(height: 8),
      for (final t in WhisperModelSize.values) _tierRow(t, s),
      const Divider(height: 26, color: AyatColors.hairline),
      _Label(s.t('whisper.threads')),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final n in const [0, 2, 3, 4, 6, 8])
            _Choice(
              label: n == 0
                  ? '${s.t('whisper.threadsAuto')} (${WhisperService.autoThreads})'
                  : '$n',
              selected: _settings.whisperThreads == n,
              onTap: () => setState(() => _settings.setWhisperThreads(n)),
            ),
        ],
      ),
      const SizedBox(height: 8),
      _Hint('${s.t('whisper.threadsHint')} ${WhisperService.cpuCores}'),
      const Divider(height: 26, color: AyatColors.hairline),
      _switchTile(
        s.t('whisper.fast'),
        s.t('whisper.fastHint'),
        _settings.whisperFastShort,
        (v) => setState(() => _settings.setWhisperFastShort(v)),
      ),
      _switchTile(
        s.t('whisper.vad'),
        s.t('whisper.vadHint'),
        _settings.whisperVad,
        (v) => setState(() => _settings.setWhisperVad(v)),
      ),
      if (err != null && err.trim().isNotEmpty) ...[
        const Divider(height: 26, color: AyatColors.hairline),
        Row(
          children: [
            _Label(s.t('whisper.lastError')),
            const Spacer(),
            TextButton.icon(
              onPressed: () => Clipboard.setData(ClipboardData(text: err)),
              icon: const Icon(Icons.copy, size: 16),
              label: Text(s.t('whisper.copy'),
                  style: GoogleFonts.tajawal(fontSize: 12)),
              style: TextButton.styleFrom(
                  foregroundColor: AyatColors.goldBright),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AyatColors.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AyatColors.hairline),
          ),
          child: SelectableText(
            err,
            textDirection: TextDirection.ltr,
            style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
                color: AyatColors.parchmentDim),
          ),
        ),
      ],
      const Divider(height: 26, color: AyatColors.hairline),
      OutlinedButton.icon(
        onPressed: _busy ? null : _redownload,
        icon: const Icon(Icons.refresh, size: 18),
        label: Text(s.t('whisper.redownload')),
      ),
      const SizedBox(height: 6),
      _Hint(s.t('whisper.redownloadHint')),
      const SizedBox(height: 6),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: _reset,
          icon: const Icon(Icons.restart_alt, size: 17),
          label: Text(s.t('whisper.reset'),
              style: GoogleFonts.tajawal(fontSize: 12)),
          style: TextButton.styleFrom(foregroundColor: AyatColors.goldBright),
        ),
      ),
    ]);
  }
}
'''
delta['ss'] = delta['ss'] if delta['ss'] != 0 else (0, 0, 0)
_appended = src['ss'][src['ss'].index('// PATCH_S207_WHISPER_SETTINGS: everything about Whisper'):]
_b = bal(_appended)
delta['ss'] = tuple(x + y for x, y in zip(delta['ss'], _b))
print('  PATCHED settings_screen.dart - _WhisperSection class appended')

# =====================================================================
# pro_pip.dart - PIP on the stage
# =====================================================================
fix('pp', 'pro_pip.dart - roomier margin (rotate knob lives in it)',
    "  static const double _pad = 22.0;\n",
    "  static const double _pad = 44.0; // PATCH_S207: room for the rotate knob\n")

fix('pp', 'pro_pip.dart - new gesture fields',
    "  double _hD0 = 1, _hA0 = 0; // corner-handle gesture: start distance / angle\n",
    "  double _hD0 = 1, _hA0 = 0; // corner-handle gesture: start distance / angle\n"
    "  // PATCH_S207: box proportions during a gesture, which frame edge the box\n"
    "  // is magnetised to, and whether the rotate knob sits on a snap angle\n"
    "  double _bAsp = 1.0;\n"
    "  bool _eL = false, _eR = false, _eT = false, _eB = false, _snapRot = false;\n")

fix('pp', 'pro_pip.dart - gesture start resets the new state',
    "    _gStart = d.focalPoint;\n    _snapV = _snapH = false;\n    HapticFeedback.selectionClick();\n  }\n",
    "    _gStart = d.focalPoint;\n    _snapV = _snapH = false;\n"
    "    _bAsp = c.boxAspect; // PATCH_S207\n"
    "    _eL = _eR = _eT = _eB = _snapRot = false;\n"
    "    HapticFeedback.selectionClick();\n  }\n")

fix_between('pp', 'pro_pip.dart - move / pinch with edge magnets + 45° snaps',
    "  void _onUpdate(ScaleUpdateDetails d, double fw, double fh) {\n",
    "  Offset? _local(Offset global) {\n",
    r'''  void _onUpdate(ScaleUpdateDetails d, double fw, double fh) {
    if (_dragId < 0) return;
    var cx = _bCx + (d.focalPoint.dx - _gStart.dx) / fw;
    var cy = _bCy + (d.focalPoint.dy - _gStart.dy) / fh;
    final w = (_bW * d.scale).clamp(0.08, 1.5).toDouble();
    var r = _bRot + d.rotation * 180 / math.pi;
    r = _snapAngle(r);
    // magnet to the middle of the frame, with a tick
    final sv = (cx - 0.5).abs() < 0.018;
    final sh = (cy - 0.5).abs() < 0.018;
    if (sv) cx = 0.5;
    if (sh) cy = 0.5;
    // PATCH_S207: and to the frame's own edges (only while the box stands
    // upright - a turned box has no flat side to line up)
    var el = false, er = false, et = false, eb = false;
    final upright = r.abs() < 0.5 || (r.abs() - 180).abs() < 0.5;
    if (upright) {
      final hw = w / 2;
      final hh = (w * fw / _bAsp / fh) / 2;
      const th = 0.014;
      if (!sv) {
        if ((cx - hw).abs() < th) {
          cx = hw;
          el = true;
        } else if ((cx + hw - 1).abs() < th) {
          cx = 1 - hw;
          er = true;
        }
      }
      if (!sh) {
        if ((cy - hh).abs() < th) {
          cy = hh;
          et = true;
        } else if ((cy + hh - 1).abs() < th) {
          cy = 1 - hh;
          eb = true;
        }
      }
    }
    if ((sv && !_snapV) ||
        (sh && !_snapH) ||
        (el && !_eL) ||
        (er && !_eR) ||
        (et && !_eT) ||
        (eb && !_eB)) {
      HapticFeedback.selectionClick();
    }
    cx = cx.clamp(0.0, 1.0).toDouble();
    cy = cy.clamp(0.0, 1.0).toDouble();
    setState(() {
      _snapV = sv;
      _snapH = sh;
      _eL = el;
      _eR = er;
      _eT = et;
      _eB = eb;
      _dCx = cx;
      _dCy = cy;
      _dW = w;
      _dRot = r;
    });
  }

  double _normDeg(double deg) => ((deg + 180) % 360) - 180;

  // PATCH_S207: every 45 degrees now, not just the right angles
  double _snapAngle(double deg) {
    var r = _normDeg(deg);
    for (final s in const [
      0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0, -180.0
    ]) {
      if ((r - s).abs() < 3.5) {
        r = s;
        break;
      }
    }
    return r;
  }

''')

fix_between('pp', 'pro_pip.dart - corner handle only resizes; new rotate knob handlers',
    "  void _hUpdate(Offset global, double fw, double fh) {\n",
    "  void _onEnd(PipClip c) {\n",
    r'''  // PATCH_S207: the corner handle used to resize AND turn at once, so a
  // plain "make it bigger" drag also twisted the box. It only resizes now.
  void _hUpdate(Offset global, double fw, double fh) {
    if (_dragId < 0) return;
    final p = _local(global);
    if (p == null) return;
    final ctr = Offset(_bCx * fw, _bCy * fh);
    final d = (p - ctr).distance;
    final w = (_bW * d / _hD0).clamp(0.08, 1.5).toDouble();
    setState(() => _dW = w);
  }

  // PATCH_S207: the knob above the box turns it - and only turns it.
  void _rStart(PipClip c, int i, Offset global, double fw, double fh) {
    final p = _local(global);
    if (p == null) return;
    widget.state.selectPip(i);
    _dragId = c.id;
    _bCx = _dCx = c.cx;
    _bCy = _dCy = c.cy;
    _bW = _dW = c.width;
    _bRot = _dRot = c.rot;
    _bAsp = c.boxAspect;
    final ctr = Offset(c.cx * fw, c.cy * fh);
    _hA0 = math.atan2(p.dy - ctr.dy, p.dx - ctr.dx);
    _snapV = _snapH = false;
    _eL = _eR = _eT = _eB = _snapRot = false;
    HapticFeedback.selectionClick();
  }

  void _rUpdate(Offset global, double fw, double fh) {
    if (_dragId < 0) return;
    final p = _local(global);
    if (p == null) return;
    final ctr = Offset(_bCx * fw, _bCy * fh);
    final a = math.atan2(p.dy - ctr.dy, p.dx - ctr.dx);
    final raw = _normDeg(_bRot + (a - _hA0) * 180 / math.pi);
    final r = _snapAngle(raw);
    final hit = (r - raw).abs() > 0.01;
    if (hit && !_snapRot) HapticFeedback.selectionClick();
    setState(() {
      _snapRot = hit;
      _dRot = r;
    });
  }

''')

fix('pp', 'pro_pip.dart - gesture end clears the guides',
    "    setState(() {\n      _dragId = -1;\n      _snapV = _snapH = false;\n    });\n    if (moved) {",
    "    setState(() {\n      _dragId = -1;\n      _snapV = _snapH = false;\n"
    "      _eL = _eR = _eT = _eB = _snapRot = false; // PATCH_S207\n    });\n    if (moved) {")

fix_between('pp', 'pro_pip.dart - handles: 44px targets, rotate knob, resize-only corner',
    "  List<Widget> _handles(\n",
    "  Widget? _clipWidget(StudioState st, int i, double t, double fw, double fh) {\n",
    r'''  List<Widget> _handles(
      PipClip c, int i, double bw, double bh, double fw, double fh) {
    final big = bw >= 70;
    // PATCH_S207: every 30px button now sits in a 44px touch target
    const hit = 44.0;
    Widget at(double x, double y, Widget child) => Positioned(
          left: x - hit / 2,
          top: y - hit / 2,
          width: hit,
          height: hit,
          child: child,
        );
    return [
      // ✕ delete
      at(
        _pad,
        _pad,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _delete(i),
          child: Center(child: _dot(Icons.close)),
        ),
      ),
      // ⇋ mirror
      if (big)
        at(
          _pad + bw,
          _pad,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.state.update(() => c.flipH = !c.flipH);
            },
            child: Center(child: _dot(Icons.flip)),
          ),
        ),
      // ⧉ copy
      if (big)
        at(
          _pad,
          _pad + bh,
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              widget.state.duplicatePipAt(i);
            },
            child: Center(child: _dot(Icons.content_copy)),
          ),
        ),
      // ⤢ size (keeps the angle)
      at(
        _pad + bw,
        _pad + bh,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _hStart(c, i, d.globalPosition, fw, fh),
          onPanUpdate: (d) => _hUpdate(d.globalPosition, fw, fh),
          onPanEnd: (_) => _onEnd(c),
          onPanCancel: () => _onEnd(c),
          child: Center(child: _dot(Icons.open_in_full)),
        ),
      ),
      // ⟳ turn - a knob above the box, joined to it by a thin stem
      Positioned(
        left: _pad + bw / 2 - 0.75,
        top: _pad - 14,
        width: 1.5,
        height: 14,
        child: const IgnorePointer(
          child: ColoredBox(color: AyatColors.goldBright),
        ),
      ),
      at(
        _pad + bw / 2,
        _pad - 24,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (d) => _rStart(c, i, d.globalPosition, fw, fh),
          onPanUpdate: (d) => _rUpdate(d.globalPosition, fw, fh),
          onPanEnd: (_) => _onEnd(c),
          onPanCancel: () => _onEnd(c),
          child: Center(child: _dot(Icons.rotate_right)),
        ),
      ),
    ];
  }

''')

fix('pp', 'pro_pip.dart - edge guides + live readout',
    "              if (_snapH)\n                Positioned(\n                  top: fh / 2 - 0.5,",
    r'''              if (_eL) _vLine(0.5),
              if (_eR) _vLine(fw - 0.5),
              if (_eT) _hLine(0.5),
              if (_eB) _hLine(fh - 0.5),
              if (_dragId >= 0)
                Positioned(
                  top: 8,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xCC050F0D),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                              color: _snapRot
                                  ? AyatColors.goldBright
                                  : AyatColors.hairline),
                        ),
                        child: Text(
                          '${(_dW * 100).round()}٪  ·  ${_dRot.round()}°',
                          style: const TextStyle(
                              fontSize: 11.5, color: AyatColors.goldBright),
                        ),
                      ),
                    ),
                  ),
                ),
              if (_snapH)
                Positioned(
                  top: fh / 2 - 0.5,''')

fix('pp', 'pro_pip.dart - guide line helpers',
    "  Widget? _clipWidget(StudioState st, int i, double t, double fw, double fh) {\n",
    r'''  // PATCH_S207: the thin gold lines shown while the box rests on a frame edge
  Widget _vLine(double x) => Positioned(
        left: x - 0.5,
        top: 0,
        bottom: 0,
        width: 1,
        child: IgnorePointer(
          child:
              ColoredBox(color: AyatColors.goldBright.withValues(alpha: 0.7)),
        ),
      );

  Widget _hLine(double y) => Positioned(
        top: y - 0.5,
        left: 0,
        right: 0,
        height: 1,
        child: IgnorePointer(
          child:
              ColoredBox(color: AyatColors.goldBright.withValues(alpha: 0.7)),
        ),
      );

  Widget? _clipWidget(StudioState st, int i, double t, double fw, double fh) {
''')

fix('pp', 'pro_pip.dart - panel: quick sizes, fill, turn 90, nudge',
    "                  _btn(Icons.south_west, 'أسفل يسار', () => _place(sel, 'bl')),\n                ],\n              ),\n",
    r'''                  _btn(Icons.south_west, 'أسفل يسار', () => _place(sel, 'bl')),
                ],
              ),
              // PATCH_S207: quick sizes, fill the frame, a quarter turn and
              // 1% nudges for the cases a finger can't land exactly
              _title(context, 'ضبط سريع'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final f in const [0.25, 0.5, 0.75, 1.0])
                    _btn(Icons.aspect_ratio, '${(f * 100).round()}٪',
                        () => state.update(() => sel.width = f)),
                  _btn(
                      Icons.fullscreen,
                      'ملء العرض',
                      () => state.update(() {
                            sel.width = 1.0;
                            sel.cx = 0.5;
                            sel.cy = 0.5;
                            sel.rot = 0;
                          })),
                  _btn(
                      Icons.rotate_90_degrees_cw_outlined,
                      'تدوير ٩٠°',
                      () => state.update(() {
                            var r = sel.rot + 90;
                            if (r > 180) r -= 360;
                            sel.rot = r;
                          })),
                  _btn(Icons.west, 'يسار', () => _nudge(sel, -0.01, 0)),
                  _btn(Icons.east, 'يمين', () => _nudge(sel, 0.01, 0)),
                  _btn(Icons.north, 'أعلى', () => _nudge(sel, 0, -0.01)),
                  _btn(Icons.south, 'أسفل', () => _nudge(sel, 0, 0.01)),
                ],
              ),
''')

fix('pp', 'pro_pip.dart - panel: _nudge helper',
    "  void _playMotion(PipClip c) {\n",
    r'''  // PATCH_S207: move by a fraction of the frame
  void _nudge(PipClip c, double dx, double dy) {
    state.update(() {
      c.cx = (c.cx + dx).clamp(0.0, 1.0).toDouble();
      c.cy = (c.cy + dy).clamp(0.0, 1.0).toDouble();
    });
  }

  void _playMotion(PipClip c) {
''')

fix('pp', 'pro_pip.dart - panel hint mentions the knob',
    "'أو استخدم الأزرار على زواياها.',",
    "'أو استخدم الأزرار على زواياها (المقبض العلوي للتدوير، والسفلي للحجم).',")

# =====================================================================
# sanity + write
# =====================================================================
bad = []
for k, rel in FILES.items():
    d = delta[k] if delta[k] != 0 else (0, 0, 0)
    got = tuple(x - y for x, y in zip(bal(src[k]), bal(orig[k])))
    if got != tuple(d):
        bad.append('%s: bracket balance changed by %s, expected %s' % (rel, got, tuple(d)))
if bad:
    sys.exit('  SKIP    balance check failed - nothing written:\n    ' + '\n    '.join(bad))
print('  all balanced')

for k, rel in FILES.items():
    if src[k] != orig[k]:
        open(os.path.join(ROOT, rel), 'w', encoding='utf-8').write(src[k])
print()
print('Done. Next:')
print('  git add -A && git commit -m "S207: Whisper null-VAD fix, Whisper settings, kept picks, PIP controls" && git push')
