#!/usr/bin/env python3
"""
patch_s176_smooth_polish.py - Ayat Studio S176 (run from repo root, after S175)

Smoothness + motion pass over the studio. Everything goes through the existing
AppMotion system, so Settings > "حركات الواجهة" still turns ALL of it off.

  - Tool panel glides open/closed (size + fade) instead of popping
  - Switching tools cross-fades + slides the page; scroll resets to top
  - Panel title swaps smoothly
  - Tool strip: gold indicator grows, icon springs up and recolors, labels
    fade between colors, press-scale on every tool, selected tool auto-centers
  - Clip toolbar <-> tool strip swap slides instead of jumping
  - Upload hero fades in
  - Fullscreen preview: smooth route + immersive mode (status bar hidden)
  - Export presets: press-scale + animated selection border
  - Stickers: pop on tap + haptic, layer rows animate in, color dots animate

Idempotent; every anchor is verified before anything is written.
"""
import os, sys

MARK = 'PATCH_S176_SMOOTH'
HOME = 'lib/screens/home_screen.dart'
MOTION = 'lib/widgets/motion.dart'
PANELS = 'lib/widgets/pro_panels.dart'
CAPCUT = 'lib/widgets/pro_capcut.dart'

if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
for p in (HOME, MOTION, PANELS, CAPCUT):
    if not os.path.exists(p):
        sys.exit('missing ' + p)

def rd(p):
    return open(p, encoding='utf-8').read()

home, motion, panels, capcut = rd(HOME), rd(MOTION), rd(PANELS), rd(CAPCUT)
if MARK in home:
    print('  OK      already applied')
    sys.exit(0)
if 'PATCH_S175_CAPCUT' not in home:
    sys.exit('S175 not applied yet - run patch_s175_capcut_extras.py first.')

MOTION_ADD = r"""
// PATCH_S176_SMOOTH: cross-fade + slide between two states of the same slot
// (tool pages, toolbars). Keyed child => animated swap. Honours the motion
// switch via AppMotion.d.
class SmoothSwap extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final Offset slide; // fraction of the child's size it travels
  const SmoothSwap({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 280),
    this.slide = const Offset(0, 0.04),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.d(duration),
      reverseDuration: AppMotion.d(duration * 0.7),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: AlignmentDirectional.topStart,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (c, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(begin: slide, end: Offset.zero).animate(anim),
          child: c,
        ),
      ),
      child: child,
    );
  }
}

// PATCH_S176_SMOOTH: a panel that grows from / shrinks into its bottom edge
// (size + fade) rather than popping in and out of the layout.
class SmoothReveal extends StatelessWidget {
  final bool show;
  final Widget? child; // only built by the caller while shown
  final Duration duration;
  const SmoothReveal({
    super.key,
    required this.show,
    this.child,
    this.duration = const Duration(milliseconds: 340),
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: AppMotion.d(duration),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.bottomCenter,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (c, anim) => SizeTransition(
        sizeFactor: anim,
        axisAlignment: -1,
        child: FadeTransition(opacity: anim, child: c),
      ),
      child: show && child != null
          ? KeyedSubtree(key: const ValueKey('s176-revealed'), child: child!)
          : const SizedBox.shrink(key: ValueKey('s176-hidden')),
    );
  }
}
"""

STRIP_NEW = r"""            return PressableScale(
              borderRadius: BorderRadius.circular(14),
              pressedScale: 0.9, // PATCH_S176_SMOOTH
              onTap: () => _openTool(t.$1),
              child: SizedBox(
                width: 76,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: AppMotion.d(AppMotion.medium),
                      curve: Curves.easeOutCubic,
                      width: sel ? 22 : 0,
                      height: 3,
                      margin: const EdgeInsets.only(bottom: 5),
                      decoration: BoxDecoration(
                        color: AyatColors.goldBright,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    AnimatedScale(
                      scale: sel ? 1.18 : 1.0,
                      duration: AppMotion.d(AppMotion.medium),
                      curve: AppMotion.spring,
                      child: TweenAnimationBuilder<Color?>(
                        tween: ColorTween(end: col),
                        duration: AppMotion.d(AppMotion.medium),
                        builder: (_, c, __) => Icon(t.$2, size: 23, color: c),
                      ),
                    ),
                    const SizedBox(height: 3),
                    AnimatedDefaultTextStyle(
                      duration: AppMotion.d(AppMotion.medium),
                      curve: Curves.easeOutCubic,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: col),
                      child: Text(t.$3,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
            );
"""

STRIP_OLD = r"""            return InkWell(
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
"""

OPEN_TOOL_OLD = r"""  void _openTool(int id) {
    HapticFeedback.selectionClick();
    setState(() {
      _toolOpen = _toolOpen == id ? -1 : id;
      if (id < 100) _selectedTab = id;
    });
  }
"""
OPEN_TOOL_NEW = r"""  void _openTool(int id) {
    HapticFeedback.selectionClick();
    final switching = _toolOpen != -1 && _toolOpen != id; // PATCH_S176_SMOOTH
    setState(() {
      _toolOpen = _toolOpen == id ? -1 : id;
      if (id < 100) _selectedTab = id;
    });
    if (switching && _scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
    _centerTool(id);
  }

  // PATCH_S176_SMOOTH: glide the tapped tool to the middle of the strip.
  void _centerTool(int id) {
    final idx = _toolList().indexWhere((t) => t.$1 == id);
    if (idx < 0 || !_stripCtrl.hasClients) return;
    final pos = _stripCtrl.position;
    final target =
        (8 + idx * 76.0 + 38 - pos.viewportDimension / 2)
            .clamp(0.0, pos.maxScrollExtent);
    _stripCtrl.animateTo(target,
        duration: AppMotion.d(const Duration(milliseconds: 420)),
        curve: Curves.easeOutCubic);
  }
"""

SLOT_NEW = (
"          // " + MARK + ": the panel glides open/closed\n"
"          SmoothReveal(\n"
"            show: _toolOpen != -1,\n"
"            child: _toolOpen != -1 ? _toolPanel(panelH) : null,\n"
"          ),\n")

FULL_OLD_HEAD = ("  void _openFullscreen() {\n"
"    Navigator.of(context).push(MaterialPageRoute<void>(\n"
"      builder: (ctx) => Scaffold(\n")
FULL_NEW_HEAD = ("  Future<void> _openFullscreen() async {\n"
"    HapticFeedback.selectionClick(); // " + MARK + "\n"
"    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);\n"
"    await Navigator.of(context).push(AppMotion.route<void>(Builder(\n"
"      builder: (ctx) => Scaffold(\n")
FULL_OLD_TAIL = ("      ),\n"
"    ));\n"
"  }\n"
"\n"
"  Widget _toolPanel(double h) {\n")
FULL_NEW_TAIL = ("      ),\n"
"    )));\n"
"    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);\n"
"  }\n"
"\n"
"  Widget _toolPanel(double h) {\n")

LAYERS_OLD_A = ("            for (var i = 0; i < st.textLayers.length; i++)\n"
"              ListTile(\n")
LAYERS_NEW_A = ("            for (var i = 0; i < st.textLayers.length; i++)\n"
"              FadeSlideIn(\n"
"                key: ObjectKey(st.textLayers[i]), // " + MARK + "\n"
"                from: const Offset(0, 8),\n"
"                child: ListTile(\n")
LAYERS_OLD_B = ("                  onPressed: () => st.removeTextLayerAt(i),\n"
"                ),\n"
"              ),\n"
"          ],\n")
LAYERS_NEW_B = ("                  onPressed: () {\n"
"                    HapticFeedback.selectionClick();\n"
"                    st.removeTextLayerAt(i);\n"
"                  },\n"
"                ),\n"
"              ),\n"
"            ),\n"
"          ],\n")

files = []
files.append((HOME, home, [
 ('strip controller field', "  final _scrollCtrl = ScrollController();\n",
  "  final _scrollCtrl = ScrollController();\n  final _stripCtrl = ScrollController(); // " + MARK + "\n"),
 ('strip controller dispose',
  "    _scrollCtrl.dispose(); // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX\n",
  "    _scrollCtrl.dispose(); // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX\n    _stripCtrl.dispose(); // " + MARK + "\n"),
 ('openTool', OPEN_TOOL_OLD, OPEN_TOOL_NEW),
 ('panel slot', "          if (_toolOpen != -1) _toolPanel(panelH),\n", SLOT_NEW),
 ('swap toolbars',
  "          _hasSelSeg ? _clipToolStrip() : _toolStrip(), // PATCH_S174_PRO_EDITOR\n",
  "          SmoothSwap( // " + MARK + "\n"
  "            slide: const Offset(0, 0.3),\n"
  "            child: KeyedSubtree(\n"
  "              key: ValueKey(_hasSelSeg),\n"
  "              child: _hasSelSeg ? _clipToolStrip() : _toolStrip(),\n"
  "            ),\n"
  "          ),\n"),
 ('upload hero', "              child: _uploadHero(),\n",
  "              child: FadeSlideIn(child: _uploadHero()), // " + MARK + "\n"),
 ('fullscreen head', FULL_OLD_HEAD, FULL_NEW_HEAD),
 ('fullscreen tail', FULL_OLD_TAIL, FULL_NEW_TAIL),
 ('panel title swap',
  "                  child: Text(cur.$3,\n                      style: Theme.of(context).textTheme.headlineMedium),\n",
  "                  child: SmoothSwap( // " + MARK + "\n"
  "                    slide: const Offset(0.08, 0),\n"
  "                    child: Text(cur.$3,\n"
  "                        key: ValueKey(cur.$1),\n"
  "                        style: Theme.of(context).textTheme.headlineMedium),\n"
  "                  ),\n"),
 ('panel body swap', "              child: _toolBody(),\n",
  "              child: SmoothSwap( // " + MARK + "\n"
  "                child: KeyedSubtree(\n"
  "                  key: ValueKey(_toolOpen),\n"
  "                  child: _toolBody(),\n"
  "                ),\n"
  "              ),\n"),
 ('strip list controller',
  "          itemCount: tools.length,\n",
  "          controller: _stripCtrl, // " + MARK + "\n          itemCount: tools.length,\n"),
 ('strip items', STRIP_OLD, STRIP_NEW),
]))
files.append((MOTION, motion, [
 ('motion helpers', "class _BurstPainter extends CustomPainter {\n",
  MOTION_ADD.lstrip('\n') + "\nclass _BurstPainter extends CustomPainter {\n"),
]))
files.append((PANELS, panels, [
 ('panels import', "import 'gold_switch.dart';\n",
  "import 'gold_switch.dart';\nimport 'motion.dart'; // " + MARK + "\n"),
 ('preset press', "            return GestureDetector(\n              onTap: () => state.update(() {\n                state.aspectRatio",
  "            return PressableScale( // " + MARK + "\n              onTap: () => state.update(() {\n                state.aspectRatio"),
 ('preset animated', "              child: Container(\n                margin: const EdgeInsets.only(bottom: 8),\n",
  "              child: AnimatedContainer(\n                duration: AppMotion.d(AppMotion.medium),\n                curve: Curves.easeOutCubic,\n                margin: const EdgeInsets.only(bottom: 8),\n"),
]))
files.append((CAPCUT, capcut, [
 ('capcut imports', "import 'package:flutter/material.dart';\n",
  "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart'; // " + MARK + "\n"),
 ('capcut motion import', "import 'gold_switch.dart';\n",
  "import 'gold_switch.dart';\nimport 'motion.dart';\n"),
 ('sticker press', "                  InkWell(\n                    borderRadius: BorderRadius.circular(12),\n",
  "                  PressableScale(\n                    borderRadius: BorderRadius.circular(12),\n                    pressedScale: 0.85,\n"),
 ('sticker haptic', "                    onTap: () {\n                      st.addTextLayer(TextLayer(\n",
  "                    onTap: () {\n                      HapticFeedback.lightImpact();\n                      st.addTextLayer(TextLayer(\n"),
 ('color dot', "                  child: Container(\n                    width: 30,\n",
  "                  child: AnimatedContainer(\n                    duration: AppMotion.d(AppMotion.fast),\n                    curve: Curves.easeOut,\n                    width: 30,\n"),
 ('layer rows a', LAYERS_OLD_A, LAYERS_NEW_A),
 ('layer rows b', LAYERS_OLD_B, LAYERS_NEW_B),
]))

bad = []
for path, text, eds in files:
    for label, old, _ in eds:
        n = text.count(old)
        if n != 1:
            bad.append('%s: %s (found %d)' % (path, label, n))
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for path, text, eds in files:
    for label, old, new in eds:
        text = text.replace(old, new, 1)
        print('  PATCHED', path.split('/')[-1], '-', label)
    open(path, 'w', encoding='utf-8').write(text)

print('S176 applied. Next: git add -A && git commit -m "S176: smooth polish" && git push')
