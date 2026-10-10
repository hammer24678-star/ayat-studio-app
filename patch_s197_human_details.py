#!/usr/bin/env python3
"""
patch_s197_human_details.py - Ayat Studio S197 (run from repo root, after S196)

The small things a person notices without being able to say why:

  1) Time never reads "0:60.0": 59.96s used to round up into an impossible
     60.0 seconds (4 places: timing editor, go-to-time, ruler ticks, list).
  2) Toasts stay on screen as long as they take to read (long messages used
     to vanish after 2.2s).
  3) Export pill: fades instead of snapping, and shows a small spinner while
     a job is running so it never looks "dead".
  4) Export-done dialog: the file path no longer scrambles inside the RTL
     sentence, and tapping share gives a tick.
  5) «إلغاء العملية» gives a tick.
  6) The tool strip fades at both edges - tells you it scrolls (29 tools).
  7) Dragging the tool panel dismisses the keyboard.
  8) Go-to-time: number-friendly keyboard, text pre-selected, «Go» key
     submits, and Arabic decimal separators (٫ ، ,) are understood.
  9) No keyboard autocorrect on Quran text boxes (the keyboard used to
     "fix" ayah words): typing sheet, edit-text dialog, mushaf search.

Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S197_DETAILS'
F = {
  'home':  'lib/screens/home_screen.dart',
  'extra': 'lib/widgets/pro_extras.dart',
  'tl':    'lib/widgets/pro_timeline.dart',
  'pan':   'lib/widgets/pro_panels.dart',
  'qts':   'lib/widgets/quran_text_sheet.dart',
  'stage': 'lib/widgets/stage_preview.dart',
  'mush':  'lib/screens/mushaf_screen.dart',
}
for p in F.values():
    if not os.path.exists(p):
        sys.exit('Run from the repo root (missing %s).' % p)
T = {k: open(p, encoding='utf-8').read() for k, p in F.items()}
if any(MARK in t for t in T.values()):
    print('  OK      already applied'); sys.exit(0)
if 'PATCH_S196_FIXES' not in T['home']:
    sys.exit('S196 is not applied yet.')

M = ' // ' + MARK

# --- tenth-of-a-second formatting that cannot round up to 60.0 -------------
def fmt_old(ind):
    return (ind + "final m = s ~/ 60;\n" + ind + "final sec = s - m * 60;\n")
def fmt_new(ind, v='s'):
    return (ind + "final tenths = (" + v + " * 10).round(); // " + MARK + "\n"
            + ind + "final m = tenths ~/ 600;\n"
            + ind + "final sec = (tenths % 600) / 10;\n")

EDITS = {
 'home': [
  ('fine time', fmt_old('    ') + "    return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';\n  }\n\n",
                fmt_new('    ') + "    return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';\n  }\n\n"),
  ('toast lasts as long as it is read',
   "        duration: const Duration(milliseconds: 2200),\n",
   "        duration: Duration(\n            milliseconds: (1800 + msg.length * 55).clamp(2200, 6500).toInt())," + M + "\n"),
  ('export pill fade',
   "    return Opacity(\n      opacity: disabled ? 0.5 : 1,\n",
   "    return AnimatedOpacity(" + M + "\n      duration: const Duration(milliseconds: 220),\n      opacity: disabled ? 0.55 : 1,\n"),
  ('export pill spinner',
   "              children: const [\n                Icon(Icons.movie_creation_outlined,\n                    size: 16, color: AyatColors.ink),\n                SizedBox(width: 6),\n                Text('تصدير',",
   "              children: [\n                disabled\n                    ? const SizedBox(\n                        width: 16,\n                        height: 16,\n                        child: CircularProgressIndicator(\n                            strokeWidth: 2, color: AyatColors.ink))\n                    : const Icon(Icons.movie_creation_outlined,\n                        size: 16, color: AyatColors.ink)," + M + "\n                const SizedBox(width: 6),\n                const Text('تصدير',"),
  ('done dialog path stays LTR',
   "        content: Text('تم حفظ المقطع بصيغة MP4:\\n$path$sizeNote',",
   "        content: Text('تم حفظ المقطع بصيغة MP4:\\n\\u2066$path\\u2069$sizeNote',"),
  ('share tick',
   "            onPressed: () => SharePlus.instance\n                .share(ShareParams(files: [XFile(path)])),\n",
   "            onPressed: () {" + M + "\n              HapticFeedback.selectionClick();\n              SharePlus.instance.share(ShareParams(files: [XFile(path)]));\n            },\n"),
  ('cancel tick',
   "              onPressed: () {\n                final action = _busyCancelAction;\n",
   "              onPressed: () {\n                HapticFeedback.lightImpact();" + M + "\n                final action = _busyCancelAction;\n"),
  ('strip edge fade open',
   "        child: ListView.builder(\n          scrollDirection: Axis.horizontal,\n          padding: const EdgeInsets.symmetric(horizontal: 8),\n          controller: _stripCtrl, // PATCH_S176_SMOOTH\n",
   "        child: ShaderMask(" + M + "\n          blendMode: BlendMode.dstIn,\n          shaderCallback: (r) => const LinearGradient(\n            colors: [\n              Color(0x00000000),\n              Color(0xFF000000),\n              Color(0xFF000000),\n              Color(0x00000000),\n            ],\n            stops: [0.0, 0.05, 0.95, 1.0],\n          ).createShader(r),\n          child: ListView.builder(\n          scrollDirection: Axis.horizontal,\n          padding: const EdgeInsets.symmetric(horizontal: 8),\n          controller: _stripCtrl, // PATCH_S176_SMOOTH\n"),
  ('strip edge fade close',
   "          },\n        ),\n      ),\n    );\n  }\n\n  // The InShot-style \"SAVE\": compact gold pill in the app bar.\n  Widget _exportPill() {",
   "          },\n        ),\n        ),\n      ),\n    );\n  }\n\n  // The InShot-style \"SAVE\": compact gold pill in the app bar.\n  Widget _exportPill() {"),
  ('panel drag closes keyboard',
   "              controller: _scrollCtrl,\n              padding: EdgeInsets.fromLTRB(16, 4, 16, 24),\n",
   "              controller: _scrollCtrl,\n              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag," + M + "\n              padding: EdgeInsets.fromLTRB(16, 4, 16, 24),\n"),
 ],
 'extra': [
  ('time format', "String _fmtTime(double s) {\n" + fmt_old('  '),
                  "String _fmtTime(double s) {\n" + fmt_new('  ')),
  ('parse arabic separators',
   "  if (t.isEmpty) return null;\n  if (!t.contains(':')) return double.tryParse(t);\n",
   "  t = t.replaceAll('٫', '.').replaceAll('،', '.').replaceAll(',', '.'); // " + MARK + "\n  if (t.isEmpty) return null;\n  if (!t.contains(':')) return double.tryParse(t);\n"),
  ('go-to-time selected',
   "  final ctl = TextEditingController(text: _fmtTime(current));\n",
   "  final ctl = TextEditingController(text: _fmtTime(current));\n  ctl.selection = TextSelection(baseOffset: 0, extentOffset: ctl.text.length);" + M + "\n"),
  ('go-to-time keyboard',
   "          autofocus: true,\n          textDirection: TextDirection.ltr,\n          decoration: const InputDecoration(hintText: 'مثال: 1:25.5 أو 85'),\n",
   "          autofocus: true,\n          keyboardType: TextInputType.datetime," + M + "\n          textInputAction: TextInputAction.go,\n          autocorrect: false,\n          textDirection: TextDirection.ltr,\n          decoration: const InputDecoration(hintText: 'مثال: 1:25.5 أو 85'),\n"),
 ],
 'tl': [
  ('tick format', "String _fmtTick(double t, double step) {\n  final m = t ~/ 60;\n  final sec = t - m * 60;\n  if (step < 1) return",
                  "String _fmtTick(double t, double step) {\n" + fmt_new('  ', 't') + "  if (step < 1) return"),
 ],
 'pan': [
  ('list time', "  static String _fmt(double s) {\n" + fmt_old('    '),
                "  static String _fmt(double s) {\n" + fmt_new('    ')),
 ],
 'qts': [
  ('no autocorrect on ayah typing',
   "                controller: _ctrl,\n                autofocus: true,\n                minLines: 1,\n",
   "                controller: _ctrl,\n                autofocus: true,\n                autocorrect: false," + M + "\n                minLines: 1,\n"),
 ],
 'stage': [
  ('no autocorrect on edit text',
   "                controller: ctrl,\n                autofocus: true,\n                maxLines: 4,\n",
   "                controller: ctrl,\n                autofocus: true,\n                autocorrect: false," + M + "\n                maxLines: 4,\n"),
 ],
 'mush': [
  ('no autocorrect on search',
   "              autofocus: true,\n              textInputAction: TextInputAction.search,\n",
   "              autofocus: true,\n              autocorrect: false," + M + "\n              textInputAction: TextInputAction.search,\n"),
 ],
}

bad = []
for k, eds in EDITS.items():
    for label, old, _ in eds:
        n = T[k].count(old)
        if n != 1:
            bad.append('%s - %s (found %d)' % (F[k], label, n))
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for k, eds in EDITS.items():
    for label, old, new in eds:
        T[k] = T[k].replace(old, new, 1)
        print('  PATCHED %s - %s' % (os.path.basename(F[k]), label))
for k, p in F.items():
    open(p, 'w', encoding='utf-8').write(T[k])
print('S197 applied. Next: git add -A && git commit -m "S197: human details" && git push')
