#!/usr/bin/env python3
"""
patch_s205_polish.py
====================
Ayat Studio S205 - run from the repo root (after S204):

    python3 patch_s205_polish.py

Audit fixes + UI polish found in the 2026-10-21 dump.

  UI
  1. Main tool bar: labels no longer cut to "مزامنة تلق…" - two lines,
     slightly wider cells (hints that the bar scrolls), height 72. The tool
     that is ON now sits in a soft gold pill instead of only changing
     colour, and the one-tap story button «فيديو الفن» has a faint gold
     frame so it is the obvious hero of the bar.
  2. The story button shows its stage on the progress card:
     "الخطوة ١ من ٣ · …" (sync) / ٢ (art) / ٣ (export).
  3. The "art drawn - it will swap during playback" toast no longer pops up
     in the middle of the story chain (the export starts right after it).
  Video
  4. Each art scene in the story video drifts in slowly (Ken Burns), like a
     moving illustration instead of a slideshow. Only in the story flow and
     only up to 30 scenes (cheaper encode); the normal exports are untouched.

Files: lib/screens/home_screen.dart, lib/services/export_service.dart.
All edits apply together or not at all. Idempotent (marker PATCH_S205).
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
MARK = 'PATCH_S205'
HS = os.path.join(ROOT, 'lib/screens/home_screen.dart')
EX = os.path.join(ROOT, 'lib/services/export_service.dart')
for p in (HS, EX):
    if not os.path.exists(p):
        sys.exit('%s missing' % os.path.relpath(p, ROOT))
hs = open(HS, encoding='utf-8').read()
ex = open(EX, encoding='utf-8').read()
if MARK in hs and MARK in ex:
    print('  OK      already applied (PATCH_S205)')
    sys.exit(0)
if MARK in hs or MARK in ex:
    sys.exit('  SKIP    PATCH_S205 is only partly present - restore the files (git checkout) and re-run.')
if 'PATCH_S204' not in ex:
    sys.exit('  SKIP    apply patch_s204_story_video.py first.')


def apply_fix_n(src, label, old, new, n_exp):
    n = src.count(old)
    if n != n_exp:
        sys.exit('  SKIP    %s: anchor found %d times (need exactly %d) - nothing written' % (label, n, n_exp))
    print('  PATCHED %s (x%d)' % (label, n))
    return src.replace(old, new)


def apply_fix(src, label, old, new):
    n = src.count(old)
    if n != 1:
        sys.exit('  SKIP    %s: anchor found %d times (need exactly 1) - nothing written' % (label, n))
    print('  PATCHED %s' % label)
    return src.replace(old, new)


# ------------------------------------------------------------ export_service.dart
ex = apply_fix(ex, 'export_service.dart - Ken Burns flag (decl)',
    "  static double _artFade = 0.5;\n",
    "  static double _artFade = 0.5;\n  static bool _artKenBurns = false; // PATCH_S205\n")
ex = apply_fix(ex, 'export_service.dart - Ken Burns flag (reset)',
    "    _artTransition = null;\n    final artSegs = await _buildArtSegments(\n",
    "    _artTransition = null;\n    _artKenBurns = false; // PATCH_S205\n    final artSegs = await _buildArtSegments(\n")
ex = apply_fix(ex, 'export_service.dart - Ken Burns flag (set)',
    "    _artTransition = style;\n    _artFade = fade;\n",
    "    _artTransition = style;\n    _artFade = fade;\n"
    "    _artKenBurns = state.storyVideoMode && out.length <= 30; // PATCH_S205\n")
ex = apply_fix(ex, 'export_service.dart - per-scene slow zoom',
    "      filters.add('[$segIdx:v]scale=$w:$h,fps=$_fps,format=yuv420p[$lbl]');\n",
    "      // PATCH_S205: story scenes drift in slowly instead of sitting still\n"
    "      final kb = _artKenBurns\n"
    "          ? _staticImageFilterChain(w, h, true)\n"
    "          : 'scale=$w:$h,fps=$_fps';\n"
    "      filters.add('[$segIdx:v]$kb,format=yuv420p[$lbl]');\n")

# ------------------------------------------------------------ home_screen.dart
hs = apply_fix(hs, 'home_screen.dart - chain-step field',
    "  bool _cancelPressed = false; // PATCH_S198_REVIEW\n",
    "  bool _cancelPressed = false; // PATCH_S198_REVIEW\n"
    "  String _chainStep = ''; // PATCH_S205: \"الخطوة ١ من ٣ · \" on the story chain\n")

hs = apply_fix(hs, 'home_screen.dart - step label on the progress card',
    "            _busy && _busyStatus.isNotEmpty ? _busyStatus : state.corpusStatus,\n",
    "            _busy && _busyStatus.isNotEmpty\n"
    "                ? '$_chainStep$_busyStatus' // PATCH_S205\n"
    "                : state.corpusStatus,\n")

hs = apply_fix(hs, 'home_screen.dart - step 1 (sync)',
    "    if (!state.timelineActive || state.timeline.isEmpty) {\n"
    "      await _autoSync();\n"
    "      if (!mounted || !state.timelineActive || state.timeline.isEmpty) return;\n"
    "    }\n",
    "    if (!state.timelineActive || state.timeline.isEmpty) {\n"
    "      _chainStep = 'الخطوة ١ من ٣ · '; // PATCH_S205\n"
    "      await _autoSync();\n"
    "      _chainStep = '';\n"
    "      if (!mounted || !state.timelineActive || state.timeline.isEmpty) return;\n"
    "    }\n")

hs = apply_fix(hs, 'home_screen.dart - step 2 (art)',
    "    await _runArtBatch(); // cached pictures return instantly\n"
    "    if (!mounted || state.aiArtBatchCancelled || state.aiArtBatchOk == 0) return;\n",
    "    _chainStep = 'الخطوة ٢ من ٣ · '; // PATCH_S205\n"
    "    await _runArtBatch(quiet: true); // cached pictures return instantly\n"
    "    _chainStep = '';\n"
    "    if (!mounted || state.aiArtBatchCancelled || state.aiArtBatchOk == 0) return;\n")

hs = apply_fix(hs, 'home_screen.dart - step 3 (export)',
    "    state.storyVideoMode = true;\n    try {\n      await _export();\n    } finally {\n      state.storyVideoMode = false;\n    }\n",
    "    state.storyVideoMode = true;\n    _chainStep = 'الخطوة ٣ من ٣ · '; // PATCH_S205\n    try {\n      await _export();\n    } finally {\n      state.storyVideoMode = false;\n      _chainStep = '';\n    }\n")

hs = apply_fix(hs, 'home_screen.dart - quiet art batch (signature)',
    "  Future<void> _runArtBatch() async {\n",
    "  Future<void> _runArtBatch({bool quiet = false}) async {\n")
hs = apply_fix(hs, 'home_screen.dart - quiet art batch (toast)',
    "    HapticFeedback.mediumImpact();\n    if (state.aiArtBatchOk > 0) {\n      _toast('تم رسم الفن لـ",
    "    HapticFeedback.mediumImpact();\n    if (quiet && state.aiArtBatchOk > 0) return; // PATCH_S205\n    if (state.aiArtBatchOk > 0) {\n      _toast('تم رسم الفن لـ")

OLD_BAR = """          itemBuilder: (context, k) {
            final it = items[k];
            final col = it.$4 ? AyatColors.goldBright : AyatColors.parchmentDim;
            return PressableScale( // PATCH_S186_SMOOTH_CONTROL
              borderRadius: BorderRadius.circular(14),
              pressedScale: 0.9,
              onTap: () {
                HapticFeedback.selectionClick();
                it.$3();
              },
              child: SizedBox(
                width: min(76.0, MediaQuery.of(context).size.width / 6.4), // PATCH_S182_WHISPER_MAIN
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(it.$1, size: 23, color: col),
                    const SizedBox(height: 4),
                    Text(it.$2,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: col)),
                  ],
                ),
              ),
            );
          },
"""
NEW_BAR = """          itemBuilder: (context, k) {
            final it = items[k];
            // PATCH_S205: active tool = gold pill; the story button = faint frame
            final active = it.$4;
            final hero = it.$2 == 'فيديو الفن';
            final col = active || hero ? AyatColors.goldBright : AyatColors.parchmentDim;
            return PressableScale( // PATCH_S186_SMOOTH_CONTROL
              borderRadius: BorderRadius.circular(14),
              pressedScale: 0.9,
              onTap: () {
                HapticFeedback.selectionClick();
                it.$3();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: min(80.0, MediaQuery.of(context).size.width / 5.6), // PATCH_S182_WHISPER_MAIN
                  decoration: BoxDecoration(
                    color: active
                        ? AyatColors.goldBright.withOpacity(0.14)
                        : (hero ? AyatColors.goldBright.withOpacity(0.06) : Colors.transparent),
                    borderRadius: BorderRadius.circular(14),
                    border: (active || hero)
                        ? Border.all(
                            color: AyatColors.goldBright
                                .withOpacity(active ? 0.45 : 0.22))
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(it.$1, size: 22, color: col),
                      const SizedBox(height: 3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(it.$2,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 10.5,
                                height: 1.1,
                                fontWeight: FontWeight.w700,
                                color: col)),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
"""
hs = apply_fix_n(hs, 'home_screen.dart - tool bar cells (clip bar + ayah bar)', OLD_BAR, NEW_BAR, 2)
hs = apply_fix(hs, 'home_screen.dart - ayah bar height',
    "    ];\n    return Container(\n      height: 68,\n",
    "    ];\n    return Container(\n      height: 72, // PATCH_S205\n")
hs = apply_fix(hs, 'home_screen.dart - clip bar height',
    "List<(IconData, String, VoidCallback, bool)> items) {\n    return Container(\n      height: 68,\n",
    "List<(IconData, String, VoidCallback, bool)> items) {\n    return Container(\n      height: 72, // PATCH_S205\n")

open(HS, 'w', encoding='utf-8').write(hs)
open(EX, 'w', encoding='utf-8').write(ex)
ok = True
for p in (HS, EX):
    t = re.sub(r"//[^\n]*", '', open(p, encoding='utf-8').read())
    ok = ok and all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))
print('  all balanced' if ok else '  !! UNBALANCED - check the files before committing')
print('Next: git add -A && git commit -m "S205: tool bar polish, story step labels, scene zoom" && git push')
