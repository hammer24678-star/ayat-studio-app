#!/usr/bin/env python3
"""
patch_s202_art_whole_file.py
============================
Ayat Studio S202 - run from the repo root (after S201, or S200):

    python3 patch_s202_art_whole_file.py

AI art for the whole file, driven by Whisper, one tap from the main screen.

  1. New button on the main clip's tool row, right after the Whisper ones:
     "فن لكل الآيات". If the clip has not been auto-synced yet it runs
     Whisper first, then draws art for every ayah it found.
  2. The batch covers EVERY distinct ayah (it stopped at 10, and the button
     said 6). Three at a time; cached art is instant, so re-running or
     resuming after a cancel only draws what is missing. The first success
     turns AI art on, so each ayah's picture swaps in during playback.
  3. Auto-sync + the AI-art switch on = art starts by itself right after the
     sync finishes.
  4. Feels better: the busy overlay shows "ayah N of M" with a live ETA and a
     working cancel button, light tap haptic on press, a stronger one when
     done, a result toast; the settings card gets a progress bar and Cancel.

Free Pollinations draws roughly 2 pictures at a time, so a clip with 100+
distinct ayat takes a while - cancel any time and the rest is drawn as the
reciter reaches each ayah.

Files: lib/models/studio_state.dart, lib/screens/home_screen.dart.
All edits apply together or not at all. Idempotent (marker PATCH_S202).
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S202'
SS = os.path.join(ROOT, 'lib/models/studio_state.dart')
HS = os.path.join(ROOT, 'lib/screens/home_screen.dart')
for p in (SS, HS):
    if not os.path.exists(p):
        sys.exit('%s missing' % os.path.relpath(p, ROOT))
ss = open(SS, encoding='utf-8').read()
hs = open(HS, encoding='utf-8').read()

if MARK in ss and MARK in hs:
    print('  OK      already applied (PATCH_S202)')
    sys.exit(0)
if MARK in ss or MARK in hs:
    sys.exit('  SKIP    PATCH_S202 is only partly present - restore the files (git checkout) and re-run.')


def apply_fix(src, label, old, new):
    n = src.count(old)
    if n != 1:
        sys.exit('  SKIP    %s: anchor found %d times (need exactly 1) - nothing written' % (label, n))
    print('  PATCHED %s' % label)
    return src.replace(old, new)


# ------------------------------------------------------------ studio_state.dart
OLD_FN = r'''  static const int _aiArtBatchMax = 10; // PATCH_S163: was 6 (parallel now)
  Future<void> generateArtForTimelineBatch() async {
    if (aiArtBatchBusy || aiArtBusy) return;
    if (timeline.isEmpty) {
      aiArtError = 'شغّل المزامنة التلقائية أولًا لرصد آيات المقطع';
      notifyListeners();
      return;
    }
    final seen = <String>{};
    final targets = <Ayah>[];
    for (final seg in timeline) {
      final key = '${seg.ayah.surahNum}:${seg.ayah.num}';
      if (seen.add(key)) {
        targets.add(seg.ayah);
        if (targets.length >= _aiArtBatchMax) break;
      }
    }

    aiArtBatchBusy = true;
    aiArtBatchProgress = null;
    aiArtError = null;
    notifyListeners();
    var ok = 0;
    try {
      // PATCH_S163_AI_ART_SPEED: every target starts at once; AiArtService
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
      if (ok == 0) {
        aiArtError ??= 'تعذر توليد الفن لأي من آيات المقطع';
        aiArtBatchProgress = null;
      } else if (ok < targets.length) {
        aiArtError = null;
        aiArtBatchProgress =
            'تم توليد فن $ok من ${targets.length} آيات — البقية ستُحاول تلقائيًا أثناء التشغيل';
      } else {
        aiArtError = null;
        aiArtBatchProgress = null;
      }
    } finally {
      aiArtBatchBusy = false;
      notifyListeners();
    }
  }
'''
NEW_FN = r'''  // PATCH_S202_ART_WHOLE_FILE: the batch now covers EVERY distinct ayah of
  // the synced file (it stopped at 10), runs 3 at a time (AiArtService still
  // limits real network requests itself), can be cancelled, and reports a
  // real fraction. Art that is already cached is returned instantly, so a
  // re-run - or a run after a cancel - only draws what is still missing.
  // The first success switches AI art on, so the S84 playback path swaps
  // each ayah's picture in as the reciter reaches it.
  bool _aiArtCancel = false;
  double aiArtBatchFraction = 0;
  int aiArtBatchOk = 0;
  void cancelArtBatch() => _aiArtCancel = true;

  Future<void> generateArtForTimelineBatch({
    void Function(int done, int total)? onProgress,
  }) async {
    aiArtBatchOk = 0;
    if (aiArtBatchBusy || aiArtBusy) return;
    if (timeline.isEmpty) {
      aiArtError = 'شغّل المزامنة التلقائية أولًا لرصد آيات المقطع';
      notifyListeners();
      return;
    }
    final seen = <String>{};
    final targets = <Ayah>[];
    for (final seg in timeline) {
      if (seen.add('${seg.ayah.surahNum}:${seg.ayah.num}')) {
        targets.add(seg.ayah);
      }
    }

    aiArtBatchBusy = true;
    _aiArtCancel = false;
    aiArtBatchFraction = 0;
    aiArtBatchProgress = 'جارٍ رسم الفن لـ ${targets.length} آية…';
    aiArtError = null;
    notifyListeners();
    var ok = 0;
    var done = 0;
    var next = 0;
    try {
      Future<void> worker() async {
        while (!_aiArtCancel) {
          final i = next++;
          if (i >= targets.length) return;
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
              aiArtEnabled = true; // PATCH_S202: playback swaps the art in
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
            aiArtError = e.message; // the last error stays visible if all fail
          } catch (e) {
            aiArtError = 'تعذر توليد الفن: $e';
          }
          done++;
          aiArtBatchFraction = done / targets.length;
          aiArtBatchProgress = 'تم $done من ${targets.length}…';
          onProgress?.call(done, targets.length);
          notifyListeners();
        }
      }

      await Future.wait([for (var w = 0; w < 3; w++) worker()]);
      aiArtBatchOk = ok;
      if (_aiArtCancel) {
        aiArtError = null;
        aiArtBatchProgress = ok > 0
            ? 'أُلغي — تم رسم الفن لـ $ok من ${targets.length} آية (الباقي يُرسم أثناء التشغيل)'
            : null;
      } else if (ok == 0) {
        aiArtError ??= 'تعذر توليد الفن لأي من آيات المقطع';
        aiArtBatchProgress = null;
      } else if (ok < targets.length) {
        aiArtError = null;
        aiArtBatchProgress =
            'تم توليد فن $ok من ${targets.length} آيات — البقية ستُحاول تلقائيًا أثناء التشغيل';
      } else {
        aiArtError = null;
        aiArtBatchProgress = null;
      }
    } finally {
      aiArtBatchBusy = false;
      _aiArtCancel = false;
      aiArtBatchFraction = 0;
      notifyListeners();
    }
  }
'''
ss2 = apply_fix(ss, 'studio_state.dart - whole-file, cancellable art batch', OLD_FN, NEW_FN)

# ------------------------------------------------------------ home_screen.dart
OLD_UI = r'''          if (state.aiArtBatchBusy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text(state.aiArtBatchProgress ?? 'جارٍ توليد الفن...')),
              ]),
            )
'''
NEW_UI = r'''          if (state.aiArtBatchBusy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(
                            state.aiArtBatchProgress ?? 'جارٍ توليد الفن...')),
                    // PATCH_S202_ART_WHOLE_FILE
                    TextButton(
                        onPressed: state.cancelArtBatch,
                        child: const Text('إلغاء')),
                  ]),
                  const SizedBox(height: 6),
                  LinearProgressIndicator(
                      value: state.aiArtBatchFraction > 0
                          ? state.aiArtBatchFraction
                          : null,
                      minHeight: 3),
                ],
              ),
            )
'''
hs2 = apply_fix(hs, 'home_screen.dart - settings progress bar + cancel', OLD_UI, NEW_UI)

A_OLD = "  Future<void> _autoSync() async {\n"
A_NEW = r'''  // ---------------------------------------------------------------------
  // PATCH_S202_ART_WHOLE_FILE: one tap on the main screen. Whisper first (if
  // the clip has not been synced yet), then art for every ayah it found.
  // ---------------------------------------------------------------------
  Future<void> _artForWholeFile() async {
    if (_busy) {
      _toast('هناك عملية جارية، انتظر حتى تنتهي');
      return;
    }
    if (!state.hasVideo) {
      _toast('ارفع فيديو أولًا');
      return;
    }
    HapticFeedback.selectionClick();
    if (!state.timelineActive || state.timeline.isEmpty) {
      await _autoSync();
      if (!mounted || !state.timelineActive || state.timeline.isEmpty) return;
    }
    await _runArtBatch();
  }

  Future<void> _runArtBatch() async {
    if (!mounted || _busy || state.aiArtBatchBusy) return;
    setState(() => _busyCancelAction = state.cancelArtBatch);
    await _withBusy<void>(() async {
      _setBusyStatus('جارٍ رسم الفن لآيات المقطع…', 0);
      await state.generateArtForTimelineBatch(
        onProgress: (done, total) =>
            _setBusyStatus('جارٍ رسم الفن: آية $done من $total…', done / total),
      );
    });
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    if (state.aiArtBatchOk > 0) {
      _toast('تم رسم الفن لـ ${state.aiArtBatchOk} آية ✓ — سيتبدّل مع التلاوة تلقائيًا');
    } else if (state.aiArtError != null) {
      _toast(state.aiArtError!);
    }
  }

''' + A_OLD
hs2 = apply_fix(hs2, 'home_screen.dart - _artForWholeFile / _runArtBatch', A_OLD, A_NEW)

B_OLD = "        (Icons.auto_awesome, 'مزامنة تلقائية', () { if (!_busy) _autoSync(); }, state.timelineActive),\n"
B_NEW = B_OLD + "        (Icons.auto_fix_high, 'فن لكل الآيات', () { if (!_busy) _artForWholeFile(); }, state.aiArtBatchBusy), // PATCH_S202_ART_WHOLE_FILE\n"
hs2 = apply_fix(hs2, 'home_screen.dart - main-screen shortcut next to Whisper', B_OLD, B_NEW)

C_OLD = ("    _syncModelSizeDisplay(); // PATCH_S75_COMPACT_PICKER_FALLBACK\n  }\n\n"
         "  /// 10x/sec: while an auto-sync timeline is active, light the current\n")
C_NEW = ("    _syncModelSizeDisplay(); // PATCH_S75_COMPACT_PICKER_FALLBACK\n"
         "    // PATCH_S202_ART_WHOLE_FILE: AI art switch on -> draw the art as soon as the sync is done\n"
         "    if (mounted && state.aiArtEnabled && state.timelineActive &&\n"
         "        state.timeline.isNotEmpty && !state.aiArtBatchBusy) {\n"
         "      _toast('جارٍ رسم الفن لآيات المقطع في الخلفية…');\n"
         "      state.generateArtForTimelineBatch().then((_) {}, onError: (_) {});\n"
         "    }\n"
         "  }\n\n"
         "  /// 10x/sec: while an auto-sync timeline is active, light the current\n")
hs2 = apply_fix(hs2, 'home_screen.dart - auto-sync starts the art when AI art is on', C_OLD, C_NEW)

D_OLD = "'توليد الفن لآيات المقطع (حتى 6 آيات)'"
D_NEW = "'توليد الفن لكل آيات المقطع'"
hs2 = apply_fix(hs2, 'home_screen.dart - button label', D_OLD, D_NEW)


open(SS, 'w', encoding='utf-8').write(ss2)
open(HS, 'w', encoding='utf-8').write(hs2)

ok = True
for p in (SS, HS):
    t = re.sub(r"//[^\n]*", '', open(p, encoding='utf-8').read())
    ok = ok and all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))
print('  all balanced' if ok else '  !! UNBALANCED - check the files before committing')
print('Next: git add -A && git commit -m "S202: AI art for the whole file, driven by Whisper, one-tap shortcut" && git push')
