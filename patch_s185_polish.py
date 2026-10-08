#!/usr/bin/env python3
"""
patch_s185_polish.py - Ayat Studio S185 (run from repo root, after S184)
Small polish:
  1) Text size slider range 14-30 -> 14-60 (in the النص tool, the old tab and the
     saved settings), so the text can really get bigger.
  2) Auto-sync / detect no longer say "upload a video first" when a video IS loaded
     but the Quran text is still loading - they say so.
  3) Pressing «تم» on the clip bars also closes the open tool panel, so the stage
     gets its room back.
Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S185_POLISH'
F = {'home': 'lib/screens/home_screen.dart', 'te': 'lib/widgets/text_editor_pro.dart',
     'set': 'lib/services/settings_service.dart'}
for p in F.values():
    if not os.path.exists(p): sys.exit('Run from the repo root (missing %s).' % p)
T = {k: open(p, encoding='utf-8').read() for k, p in F.items()}
if any(MARK in t for t in T.values()):
    print('  OK      already applied'); sys.exit(0)
if 'PATCH_S184_PRO_MAIN' not in T['home']: sys.exit('S184 is not applied yet.')

NOVID_OLD = "    if (!state.hasVideo || matcher == null) {\n      _toast('ارفع فيديو أولًا');\n      return;\n    }\n"
NOVID_NEW = ("    if (!state.hasVideo || matcher == null) { // " + MARK + "\n"
  "      _toast(!state.hasVideo\n          ? 'ارفع فيديو أولًا'\n          : 'نص القرآن ما زال يُحمَّل — انتظر لحظات ثم أعد المحاولة');\n"
  "      return;\n    }\n")
SEL = [("segment bar done", "(Icons.check_circle_outline, 'تم', () => setState(() => _selSeg = -1),\n          false),",
        "(Icons.check_circle_outline, 'تم', () => setState(() { _selSeg = -1; _toolOpen = -1; }), // " + MARK + "\n          false),"),
       ("text block bar done", "(Icons.check_circle_outline, 'تم', () => setState(() => _selCue = -1), false),",
        "(Icons.check_circle_outline, 'تم', () => setState(() { _selCue = -1; _toolOpen = -1; }), false), // " + MARK),
       ("main clip bar done", "(Icons.check_circle_outline, 'تم', () => setState(() => _selMain = false), false),",
        "(Icons.check_circle_outline, 'تم', () => setState(() { _selMain = false; _toolOpen = -1; }), false), // " + MARK),
       ("text bar done", "          state.clearStageSelection();\n          setState(() {\n            _selMain = false;\n            _selCue = -1;\n          });\n        },\n        false\n      ),\n      (Icons.text_decrease",
        "          state.clearStageSelection();\n          setState(() {\n            _selMain = false;\n            _selCue = -1;\n            _toolOpen = -1; // " + MARK + "\n          });\n        },\n        false\n      ),\n      (Icons.text_decrease")]
EDITS = {
 'te': [('size slider', "s.ayahFontSize, 14, 30, 0,", "s.ayahFontSize, 14, 60, 0, // " + MARK + "\n       ")],
 'set': [('saved size clamp', "(read<double>('ayahFontSize') ?? state.ayahFontSize).clamp(14.0, 30.0);",
          "(read<double>('ayahFontSize') ?? state.ayahFontSize).clamp(14.0, 60.0); // " + MARK)],
 'home': [('old tab size slider', "          value: state.ayahFontSize,\n          min: 14,\n          max: 30,\n",
           "          value: state.ayahFontSize,\n          min: 14,\n          max: 60, // " + MARK + "\n"),
          ('toast (detect + sync)', NOVID_OLD, NOVID_NEW)] + [(a, b, c) for a, b, c in SEL],
}
bad = []
for k, eds in EDITS.items():
    for label, old, _ in eds:
        n = T[k].count(old)
        want = 2 if label == 'toast (detect + sync)' else 1
        if n != want: bad.append('%s: %s (found %d)' % (F[k], label, n))
if bad: sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))
for k, eds in EDITS.items():
    for label, old, new in eds:
        T[k] = T[k].replace(old, new)
        print('  PATCHED', F[k].split('/')[-1], '-', label)
for k, p in F.items(): open(p, 'w', encoding='utf-8').write(T[k])
print('S185 applied. Next: git add -A && git commit -m "S185: polish" && git push')
