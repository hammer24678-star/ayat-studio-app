#!/usr/bin/env python3
"""
patch_s204_story_video.py
=========================
Ayat Studio S204 - run from the repo root (after S201 + S202):

    python3 patch_s204_story_video.py

One tap -> a finished "story" video like the reference clip.

The main-screen button (now "فيديو الفن") runs the whole chain:
  Whisper sync -> AI art for every ayah -> story look -> export MP4.

  1. EXPORT NOW USES THE PER-AYAH ART. Until now only the live preview
     swapped pictures; the exported file had one fixed background. Each
     ayah's art now fills its own slot of the video (slot edges sit midway
     between one ayah's end and the next one's start, so the picture is
     already there when the ayah appears). Soft cross-fade by default.
  2. The art is visible even when the source is a video file: in this flow
     the source supplies the SOUND only (its picture would hide the art).
  3. Story look: square 1:1, twinkling starfield, ayah text at the top with
     the translation, karaoke word highlight, cross-fade between scenes.
     All of it stays editable afterwards.
  4. Many ayat: more than 30 scenes switch to hard cuts (cheap to encode);
     very short scenes (<1 s) merge into the previous one.

Files: lib/services/ai_art_service.dart, lib/services/export_service.dart,
       lib/models/studio_state.dart, lib/screens/home_screen.dart.
All edits apply together or not at all. Idempotent (marker PATCH_S204).
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S204'
P = {k: os.path.join(ROOT, v) for k, v in {
    'art': 'lib/services/ai_art_service.dart',
    'exp': 'lib/services/export_service.dart',
    'ss': 'lib/models/studio_state.dart',
    'hs': 'lib/screens/home_screen.dart',
}.items()}
for p in P.values():
    if not os.path.exists(p):
        sys.exit('%s missing' % os.path.relpath(p, ROOT))
T = {k: open(p, encoding='utf-8').read() for k, p in P.items()}

if all(MARK in t for t in T.values()):
    print('  OK      already applied (PATCH_S204)')
    sys.exit(0)
if any(MARK in t for t in T.values()):
    sys.exit('  SKIP    PATCH_S204 is only partly present - restore the files (git checkout) and re-run.')
if 'PATCH_S202_ART_WHOLE_FILE' not in T['hs']:
    sys.exit('  SKIP    apply patch_s202_art_whole_file.py first.')


def apply_fix(src, label, old, new):
    n = src.count(old)
    if n != 1:
        sys.exit('  SKIP    %s: anchor found %d times (need exactly 1) - nothing written' % (label, n))
    print('  PATCHED %s' % label)
    return src.replace(old, new)


# ------------------------------------------------------------ ai_art_service.dart
art = T['art']
A_OLD = "  static Future<File> _fileFor(int surahNum, int ayahNum, int seedOffset) async {\n"
A_NEW = """  /// PATCH_S204_STORY_VIDEO: the already-drawn picture for an ayah, or null.
  /// Never draws and never touches the network - the export only uses art
  /// that exists.
  static Future<String?> cachedPath(int surahNum, int ayahNum) async {
    try {
      final f = await _fileFor(surahNum, ayahNum, 0);
      if (await f.exists() && await f.length() > 5000) return f.path;
    } catch (_) {}
    return null;
  }

""" + A_OLD
art = apply_fix(art, 'ai_art_service.dart - cachedPath', A_OLD, A_NEW)

# ------------------------------------------------------------ studio_state.dart
ss = T['ss']
S_OLD = "  bool _aiArtCancel = false;\n  double aiArtBatchFraction = 0;\n"
S_NEW = """  // PATCH_S204_STORY_VIDEO
  bool get aiArtBatchCancelled => _aiArtCancel;

  /// While true the export shows the per-ayah art instead of the source
  /// clip's picture (the clip still supplies the sound). Set by the story
  /// button for the length of one export, then cleared.
  bool storyVideoMode = false;

  /// The look of the reference story clips: square, black starfield, ayah
  /// text on top with its translation, word-by-word highlight, soft
  /// cross-fades between the scenes.
  void applyStoryLook() {
    aspectRatio = AyatAspectRatio.square11;
    effect = StageEffect.starfield;
    textPosition = AyahTextPosition.top;
    showTranslation = true;
    karaokeEnabled = true;
    bgTransitionStyle = BgTransitionStyle.crossfade;
    bgCrossfadeDuration = 0.5;
    notifyListeners();
  }

""" + S_OLD
ss = apply_fix(ss, 'studio_state.dart - story look + flag', S_OLD, S_NEW)

# ------------------------------------------------------------ export_service.dart
ex = T['exp']

E1_OLD = "        videoHasVideoStream = info.hasVideo;\n"
E1_NEW = ("        videoHasVideoStream = info.hasVideo;\n"
          "        // PATCH_S204_STORY_VIDEO: art scenes replace the clip's picture; its sound stays\n"
          "        if (state.storyVideoMode && state.aiArtEnabled && state.timelineActive) {\n"
          "          videoHasVideoStream = false;\n"
          "        }\n")
ex = apply_fix(ex, 'export_service.dart - source supplies sound only', E1_OLD, E1_NEW)

E2_OLD = "          if (state.videoFit != VideoFitMode.source) {\n"
E2_NEW = "          if (state.videoFit != VideoFitMode.source || state.storyVideoMode) { // PATCH_S204\n"
ex = apply_fix(ex, 'export_service.dart - story frame size', E2_OLD, E2_NEW)

E3_OLD = ("    if (!state.multiBgEnabled ||\n"
          "        state.useCustomBg ||\n"
          "        state.multiBgIndexes.length < 2 ||\n")
E3_NEW = ("    // PATCH_S204_STORY_VIDEO: per-ayah art wins over every other background mode\n"
          "    _artTransition = null;\n"
          "    final artSegs = await _buildArtSegments(\n"
          "      state: state,\n"
          "      work: work,\n"
          "      w: w,\n"
          "      h: h,\n"
          "      clipStart: clipStart,\n"
          "      duration: duration,\n"
          "    );\n"
          "    if (artSegs != null) return artSegs;\n") + E3_OLD
ex = apply_fix(ex, 'export_service.dart - art slots first', E3_OLD, E3_NEW)

E4_OLD = "  // PATCH_S40_MULTI_BG_CYCLE: the ordered (backgroundPngPath, seconds)\n"
E4_NEW = r"""  // PATCH_S204_STORY_VIDEO: one background slot per ayah, filled with that
  // ayah's AI art. Slot edges sit midway between an ayah's end and the next
  // one's start. Returns null (-> the normal background logic) when AI art is
  // off, there is no synced timeline, or no picture has been drawn yet.
  static BgTransitionStyle? _artTransition;
  static double _artFade = 0.5;

  static Future<List<({String path, double dur})>?> _buildArtSegments({
    required StudioState state,
    required Directory work,
    required int w,
    required int h,
    required double clipStart,
    required double duration,
  }) async {
    if (!state.aiArtEnabled ||
        !state.timelineActive ||
        state.timeline.isEmpty ||
        duration <= 0) {
      return null;
    }
    // ayahs that overlap the exported span, in order
    final items = <({int s, int a, double t0, double t1})>[];
    for (final seg in state.timeline) {
      final t0 = seg.start - clipStart;
      final t1 = seg.end - clipStart;
      if (t1 <= 0 || t0 >= duration) continue;
      items.add((s: seg.ayah.surahNum, a: seg.ayah.num, t0: t0, t1: t1));
    }
    if (items.isEmpty) return null;

    // slot edges: 0 | midpoints | duration (kept monotonic)
    final edges = <double>[0];
    for (var i = 1; i < items.length; i++) {
      final mid = (items[i - 1].t1 + items[i].t0) / 2;
      edges.add(mid.clamp(edges.last, duration).toDouble());
    }
    edges.add(duration);

    // the picture of each slot; an ayah with no art keeps the previous scene
    final bgPng = '${work.path}/bg.png';
    final paths = <String>[];
    var any = false;
    for (final it in items) {
      final p = await AiArtService.cachedPath(it.s, it.a);
      if (p != null) any = true;
      paths.add(p ?? (paths.isEmpty ? '' : paths.last));
    }
    if (!any) return null;
    final firstArt = paths.firstWhere((p) => p.isNotEmpty);
    for (var i = 0; i < paths.length; i++) {
      if (paths[i].isEmpty) paths[i] = firstArt; // leading ayat without art
    }

    // merge neighbours with the same picture and slivers under one second
    final slots = <({String path, double dur})>[];
    for (var i = 0; i < items.length; i++) {
      final d = edges[i + 1] - edges[i];
      if (d <= 0) continue;
      if (slots.isNotEmpty &&
          (slots.last.path == paths[i] || d < 1.0)) {
        slots[slots.length - 1] =
            (path: slots.last.path, dur: slots.last.dur + d);
      } else {
        slots.add((path: paths[i], dur: d));
      }
    }
    if (slots.isEmpty) return null;
    // a tiny first slot cannot merge backwards - fold it forward instead
    if (slots.length > 1 && slots.first.dur < 1.0) {
      slots[1] = (path: slots[1].path, dur: slots[1].dur + slots.first.dur);
      slots.removeAt(0);
    }
    // safety cap for the ffmpeg graph
    const maxSlots = 120;
    while (slots.length > maxSlots) {
      final b = (slots.length / maxSlots).ceil();
      final merged = <({String path, double dur})>[];
      for (var i = 0; i < slots.length; i += b) {
        var d = 0.0;
        for (var j = i; j < min(i + b, slots.length); j++) {
          d += slots[j].dur;
        }
        merged.add((path: slots[i].path, dur: d));
      }
      slots
        ..clear()
        ..addAll(merged);
    }

    // transition: user's style, but plain cuts when there are very many scenes
    var style = state.bgTransitionStyle;
    if (slots.length > 30 || slots.length == 1) style = BgTransitionStyle.hardCut;
    final fade = state.bgCrossfadeDuration.clamp(0.2, 0.6).toDouble();
    // xfade shortens the stream by one overlap per join; every scene after the
    // first is lengthened by that overlap so the picture still ends with the audio
    // and the new scene is fully in place at the ayah boundary.
    final extra = style == BgTransitionStyle.hardCut ? 0.0 : fade;

    final rendered = <String, String>{bgPng: bgPng};
    final out = <({String path, double dur})>[];
    for (var i = 0; i < slots.length; i++) {
      _checkCancel();
      final src = slots[i].path;
      var png = rendered[src];
      if (png == null) {
        png = '${work.path}/art_${rendered.length}.png';
        await File(png).writeAsBytes(await OverlayRenderer.renderBackgroundPng(
          w: w,
          h: h,
          bgIndex: state.bgIndex,
          customBgPath: src,
        ));
        rendered[src] = png;
      }
      out.add((path: png, dur: slots[i].dur + (i == 0 ? 0.0 : extra)));
    }
    _artTransition = style;
    _artFade = fade;
    return out;
  }

""" + E4_OLD
ex = apply_fix(ex, 'export_service.dart - _buildArtSegments', E4_OLD, E4_NEW)

# both _bgCycleChain callers (different indentation) use the same two lines
for ind in ('            ', '          '):
    old = (ind + "transition: state.bgTransitionStyle,\n" +
           ind + "crossfadeDur: state.bgCrossfadeDuration,\n")
    new = (ind + "transition: _artTransition ?? state.bgTransitionStyle, // PATCH_S204\n" +
           ind + "crossfadeDur:\n" +
           ind + "    _artTransition != null ? _artFade : state.bgCrossfadeDuration,\n")
    ex = apply_fix(ex, 'export_service.dart - chain call (%d spaces)' % len(ind), old, new)

if "import 'ai_art_service.dart'" not in ex:
    imp_old = "import 'stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS\n"
    ex = apply_fix(ex, 'export_service.dart - import', imp_old,
                   imp_old + "import 'ai_art_service.dart'; // PATCH_S204\n")

# ------------------------------------------------------------ home_screen.dart
hs = T['hs']
H1_OLD = "    await _runArtBatch();\n  }\n\n  Future<void> _runArtBatch() async {\n"
H1_NEW = """    // PATCH_S204_STORY_VIDEO: an art batch the sync kicked off in the background
    // must finish first, so the export sees every picture
    while (mounted && state.aiArtBatchBusy) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    if (!mounted) return;
    await _runArtBatch(); // cached pictures return instantly
    if (!mounted || state.aiArtBatchCancelled || state.aiArtBatchOk == 0) return;
    // look + export, then give the clip's own picture back for normal editing
    state.applyStoryLook();
    state.storyVideoMode = true;
    try {
      await _export();
    } finally {
      state.storyVideoMode = false;
    }
  }

  Future<void> _runArtBatch() async {
"""
hs = apply_fix(hs, 'home_screen.dart - sync -> art -> look -> export chain', H1_OLD, H1_NEW)

H2_OLD = "'فن لكل الآيات', () { if (!_busy) _artForWholeFile(); }"
H2_NEW = "'فيديو الفن', () { if (!_busy) _artForWholeFile(); }"
hs = apply_fix(hs, 'home_screen.dart - button label', H2_OLD, H2_NEW)

for k, v in (('art', art), ('ss', ss), ('exp', ex), ('hs', hs)):
    open(P[k], 'w', encoding='utf-8').write(v)

ok = True
for p in P.values():
    t = re.sub(r"//[^\n]*", '', open(p, encoding='utf-8').read())
    ok = ok and all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))
print('  all balanced' if ok else '  !! UNBALANCED - check the files before committing')
print('Next: git add -A && git commit -m "S204: one-tap story video - per-ayah AI art in the export" && git push')
