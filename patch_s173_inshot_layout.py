#!/usr/bin/env python3
"""
patch_s173_inshot_layout.py - Ayat Studio S173 (run from repo root, after S172)

WHY: the studio screen was one long scrolling Column (status, ratio, preview,
transport, upload, tabs, panel, magic card, export). S165-S172 kept chasing a
paint glitch inside that column (export button at the top, cards painted over
the preview). Instead of a 7th workaround, the screen is rebuilt the way
InShot does it - nothing scrolls except the open tool panel:

  AppBar : title | undo redo | gold "تصدير" pill (like InShot's SAVE) | menu
  Body   : status pill (only while busy / has text)
           STAGE PREVIEW (fills all free space, never scrolls)
           transport bar (when a video is loaded)
           bottom tool panel (opens on tap, ~42% height, scrolls inside)
           TOOL STRIP: horizontal icons - الفيديو | المقاس | <5 tabs> | لمسات

Every existing panel/handler is reused unchanged (_mediaButtons, _ratioToggle,
_panelBody, MagicCard, _trimCard, _timelineEditorCard, _manualCutCard, export).
No FadeSlideIn / Breathing / animated layers in the layout any more.

Idempotent; anchor-checked: nothing is written unless every anchor exists.
"""
import os, sys

P = 'lib/screens/home_screen.dart'
if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
if not os.path.exists(P):
    sys.exit('missing ' + P)
src = open(P, encoding='utf-8').read()
MARK = 'PATCH_S173_INSHOT_LAYOUT'
if MARK in src:
    print('  OK      already applied'); sys.exit(0)

# ---------------------------------------------------------------- 1. state
STATE_A = "  int _selectedTab = 0;\n"
STATE_B = ("  int _selectedTab = 0;\n"
           "  // " + MARK + ": which bottom tool panel is open (-1 = none).\n"
           "  // 100 = video, 101 = size, 102 = magic, 0..n-1 = the tab index.\n"
           "  int _toolOpen = -1;\n")

# ------------------------------------------------- 2. appbar export pill
START = ("        ],\n      ),\n      body: Stack(\n        children: [\n"
         "          const Positioned.fill(child: _AmbientGlow()), // PATCH_S165_UI_REFRESH\n")
END = "  // PATCH_S165_UI_REFRESH: a touch of depth - top-lit gradient + soft shadow.\n"

NEW_TAIL = r'''          Padding(
            padding: const EdgeInsetsDirectional.only(end: 6),
            child: Center(child: _exportPill()), // PATCH_S173_INSHOT_LAYOUT
          ),
        ],
      ),
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientGlow()),
          SafeArea(
            child: ListenableBuilder(
              listenable: state,
              builder: (context, _) => _studioBody(),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // PATCH_S173_INSHOT_LAYOUT: preview on top, tool strip at the bottom.
  // ---------------------------------------------------------------------

  // (id, icon, label). 100/101/102 are extra tools, 0..n-1 the existing tabs.
  List<(int, IconData, String)> _toolList() => [
        (100, Icons.movie_outlined, 'الفيديو'),
        (101, Icons.aspect_ratio, 'المقاس'),
        for (var i = 0; i < _tabs.length; i++) (i, _tabs[i].$1, _tabs[i].$2),
        (102, Icons.auto_fix_high, 'لمسات'),
      ];

  void _openTool(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      _toolOpen = _toolOpen == id ? -1 : id;
      if (id < 100) _selectedTab = id;
    });
  }

  Widget _studioBody() {
    return LayoutBuilder(builder: (context, c) {
      final panelH = (c.maxHeight * 0.42).clamp(0.0, 460.0);
      final hasStatus = _busy || state.corpusStatus.isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasStatus)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: _statusCard(),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Center(
                child: StagePreview(
                  state: state,
                  videoController: _video,
                  liveOverride: _liveOverlay,
                ),
              ),
            ),
          ),
          if (_video != null && _video!.value.isInitialized)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _transportBar(),
            ),
          if (!state.hasVideo && _toolOpen == -1)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: _uploadHero(),
            ),
          if (_toolOpen != -1) _toolPanel(panelH),
          _toolStrip(),
        ],
      );
    });
  }

  Widget _toolPanel(double h) {
    final tools = _toolList();
    final cur =
        tools.firstWhere((t) => t.$1 == _toolOpen, orElse: () => tools.first);
    return Container(
      height: h,
      decoration: BoxDecoration(
        color: AyatColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border.all(color: AyatColors.hairline),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 46,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AyatColors.goldBright,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(cur.$3,
                      style: Theme.of(context).textTheme.headlineMedium),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down,
                      color: AyatColors.goldBright),
                  onPressed: () => setState(() => _toolOpen = -1),
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(16, 4, 16, 24),
              child: _toolBody(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolBody() {
    switch (_toolOpen) {
      case 100:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _mediaButtons(),
            if (state.detectedLabel.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(state.detectedLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12, color: AyatColors.goldBright)),
            ],
            if (state.matchConfidenceText.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(state.matchConfidenceText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, color: AyatColors.parchmentDim)),
            ],
            if (state.hasVideo && state.videoDurationSec > 1) ...[
              const SizedBox(height: 12),
              _manualCutCard(),
            ],
            if (state.timelineActive) ...[
              const SizedBox(height: 12),
              _trimCard(),
              const SizedBox(height: 12),
              _timelineEditorCard(),
            ],
            if (!state.hasVideo) ...[
              const SizedBox(height: 12),
              _staticDurationRow(),
            ],
          ],
        );
      case 101:
        return _ratioToggle();
      case 102:
        return MagicCard(state: state, onToast: _toast);
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panelBody(),
            if (_toolOpen == _tabs.length - 1) ...[
              const SizedBox(height: 16),
              _exportButton(),
            ],
          ],
        );
    }
  }

  Widget _toolStrip() {
    final tools = _toolList();
    return Container(
      height: 68,
      decoration: const BoxDecoration(
        color: AyatColors.ink,
        border: Border(top: BorderSide(color: AyatColors.hairline)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: tools.length,
          itemBuilder: (context, i) {
            final t = tools[i];
            final sel = _toolOpen == t.$1;
            final col = sel ? AyatColors.goldBright : AyatColors.parchmentDim;
            return InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openTool(t.$1),
              child: SizedBox(
                width: 76,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 22,
                      height: 3,
                      margin: const EdgeInsets.only(bottom: 5),
                      decoration: BoxDecoration(
                        color: sel ? AyatColors.goldBright : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    Icon(t.$2, size: 23, color: col),
                    const SizedBox(height: 3),
                    Text(t.$3,
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
        ),
      ),
    );
  }

  // The InShot-style "SAVE": compact gold pill in the app bar.
  Widget _exportPill() {
    final disabled = _busy;
    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: disabled
              ? null
              : () {
                  HapticFeedback.mediumImpact();
                  _export();
                },
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AyatColors.goldBright, AyatColors.gold],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.movie_creation_outlined,
                    size: 16, color: AyatColors.ink),
                SizedBox(width: 6),
                Text('تصدير',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AyatColors.ink)),
              ],
            ),
          ),
        ),
      ),
    );
  }

'''

# ------------------------------------- 3. silence now-unused-element warnings
IGN = [
    ("  Widget _panelCard() {\n",
     "  // ignore: unused_element\n  Widget _panelCard() {\n"),
    ("  Widget _simpleTopTabs() => _tabChips();\n",
     "  // ignore: unused_element\n  Widget _simpleTopTabs() => _tabChips();\n"),
    ("class _Breathing extends StatefulWidget {\n",
     "// ignore: unused_element\nclass _Breathing extends StatefulWidget {\n"),
]

missing = []
if src.count(STATE_A) != 1: missing.append('state anchor')
if src.count(START) != 1: missing.append('body start anchor')
if src.count(END) != 1: missing.append('body end anchor')
for a, _ in IGN:
    if src.count(a) != 1: missing.append(a.strip()[:50])
if missing:
    print('  NOTHING WRITTEN. Anchors missing or not unique:')
    for m in missing: print('   -', m)
    sys.exit(1)

i0 = src.index(START)
i1 = src.index(END)
if i1 < i0:
    sys.exit('  NOTHING WRITTEN. anchors out of order')
src = src[:i0] + NEW_TAIL + src[i1:]
src = src.replace(STATE_A, STATE_B)
for a, b in IGN:
    src = src.replace(a, b)

if src.count('{') != src.count('}') or src.count('(') != src.count(')'):
    sys.exit('  NOTHING WRITTEN. bracket balance check failed')

open(P, 'w', encoding='utf-8').write(src)
print('  PATCHED', P)
print('Done. Next: git add -A && git commit -m "S173: InShot-style studio layout" && git push')
