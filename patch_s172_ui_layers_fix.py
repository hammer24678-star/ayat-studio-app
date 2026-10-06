#!/usr/bin/env python3
"""
patch_s172_ui_layers_fix.py - Ayat Studio S172 (run from repo root, after S171)

SYMPTOM (screenshot, Oct 6): the studio screen is garbled - the gold export
button is painted at the top of the scroll area (x=0, over the basmala/status),
and the tabs / panel / magic card are painted ON TOP of the stage preview
instead of below it (the stage hint text shows through the surah field).
Layout order in code is fine, so this is a paint/compositing glitch again.
S168 removed the ShaderMask but the glitch survived, so the cause is elsewhere.

CAUSE (best evidence, not reproduced - I cannot run the app): the four widgets
that are mispainted are exactly the ones that sit BELOW the fold and are each
wrapped in FadeSlideIn (Opacity + Transform.translate, animated). They run
their whole fade while off-screen and then drop their layer, which is when the
renderer leaves them at a stale offset. The two FadeSlideIn items inside the
first screenful (status card, ratio toggle) paint fine.

FIX: no animated wrapper around the below-the-fold items (tabs, panel card,
magic card, export button) - they simply appear. The export button's
RepaintBoundary (its own layer) becomes a KeyedSubtree (no layer, same shape).

Idempotent; anchor-checked: nothing is written unless every anchor exists.
"""
import os, sys

P = 'lib/screens/home_screen.dart'
if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
if not os.path.exists(P):
    sys.exit('missing ' + P)
src = open(P, encoding='utf-8').read()
MARK = 'PATCH_S172_NO_LAYER_WRAP'
if MARK in src:
    print('  OK      already applied'); sys.exit(0)

R = [
    ("                FadeSlideIn(\n"
     "                    delay: const Duration(milliseconds: 140),\n"
     "                    child: _simpleTopTabs()), // PATCH_S128 + PATCH_S165\n",
     "                _simpleTopTabs(), // PATCH_S128 + PATCH_S165 + " + MARK + "\n"),
    ("                FadeSlideIn(\n"
     "                    delay: const Duration(milliseconds: 220),\n"
     "                    child: _panelCard()),\n",
     "                _panelCard(), // " + MARK + "\n"),
    ("                FadeSlideIn(\n"
     "                    delay: const Duration(milliseconds: 200),\n"
     "                    child: MagicCard(state: state, onToast: _toast)),\n",
     "                MagicCard(state: state, onToast: _toast), // " + MARK + "\n"),
    ("                FadeSlideIn(\n"
     "                    delay: const Duration(milliseconds: 300),\n"
     "                    child: _exportButton()), // PATCH_S165_UI_REFRESH\n",
     "                _exportButton(), // PATCH_S165_UI_REFRESH + " + MARK + "\n"),
    ("    final disabled = _busy;\n    return RepaintBoundary(\n      child: AnimatedOpacity(",
     "    final disabled = _busy;\n    return KeyedSubtree( // " + MARK + ": no own layer\n      child: AnimatedOpacity("),
]
missing = [a[:70].replace('\n', ' | ') for a, _ in R if src.count(a) != 1]
if missing:
    print('  NOTHING WRITTEN. Anchors missing or not unique:')
    for m in missing: print('   -', m)
    sys.exit(1)
for a, b in R:
    src = src.replace(a, b)
open(P, 'w', encoding='utf-8').write(src)
print('  PATCHED', P)
print('Done. Next: git add -A && git commit -m "S172: no animated layers on below-fold cards" && git push')
