#!/usr/bin/env python3
"""
patch_s186_smooth_and_control.py - Ayat Studio S186 (run from repo root, after S185)

  1) CONTROL: a new «ضبط» button on the text bar and on the ayah-block bar opens a
     live fine-tune sheet with sliders for: size, letter spacing, line height,
     opacity, transition length - plus «إعادة الموضع» and «إعادة الحجم».
     (The text itself is still draggable / pinchable on the stage.)
  2) SMOOTH: every button of the selected-clip bars now has the same press-shrink
     and tick feedback as the main tool strip (they were plain flat taps).
Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S186_SMOOTH_CONTROL'
HOME = 'lib/screens/home_screen.dart'
if not os.path.exists(HOME): sys.exit('Run from the repo root (missing %s).' % HOME)
h = open(HOME, encoding='utf-8').read()
if MARK in h: print('  OK      already applied'); sys.exit(0)
if 'PATCH_S185_POLISH' not in h: sys.exit('S185 is not applied yet.')

INK_OLD = "            return InkWell(\n              borderRadius: BorderRadius.circular(14),\n              onTap: it.$3,\n"
INK_NEW = ("            return PressableScale( // " + MARK + "\n"
           "              borderRadius: BorderRadius.circular(14),\n"
           "              pressedScale: 0.9,\n"
           "              onTap: () {\n                HapticFeedback.selectionClick();\n                it.$3();\n              },\n")
TXT_OLD = "      (Icons.text_increase, 'أكبر', () => _nudgeTextSize(0.1), false),\n"
TXT_NEW = TXT_OLD + "      (Icons.tune, 'ضبط', _openTextTuneSheet, false), // " + MARK + "\n"
SEG_OLD = "        (Icons.record_voice_over_outlined, 'القارئ', () => _openToolFromClip(129), _toolOpen == 129),\n      ];\n"
SEG_NEW = ("        (Icons.record_voice_over_outlined, 'القارئ', () => _openToolFromClip(129), _toolOpen == 129),\n"
           "        (Icons.tune, 'ضبط', _openTextTuneSheet, false), // " + MARK + "\n      ];\n")
METH_OLD = "  void _nudgeTextSize(double d) {\n"
METH = r"""  // PATCH_S186_SMOOTH_CONTROL: live fine-tune of the text, every value on a slider.
  Widget _tuneSlider(String label, String shown, double value, double min,
      double max, void Function(double) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AyatColors.parchment)),
            ),
            Text(shown,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: AyatColors.goldBright)),
          ],
        ),
        Slider(
          value: value.clamp(min, max).toDouble(),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }

  void _openTextTuneSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AyatColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) => SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.62),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('ضبط النص',
                      style: Theme.of(ctx).textTheme.headlineMedium),
                  const SizedBox(height: 6),
                  _tuneSlider(
                      'الحجم',
                      '${(state.textUserScale * 100).round()}٪',
                      state.textUserScale,
                      0.4,
                      3.0,
                      (v) => state.update(() => state.textUserScale = v)),
                  _tuneSlider(
                      'تباعد الأحرف',
                      state.letterSpacing.toStringAsFixed(1),
                      state.letterSpacing,
                      0,
                      12,
                      (v) => state.update(() => state.letterSpacing = v)),
                  _tuneSlider(
                      'ارتفاع السطر',
                      state.lineHeightMultiplier.toStringAsFixed(2),
                      state.lineHeightMultiplier,
                      1.0,
                      2.4,
                      (v) => state.update(() => state.lineHeightMultiplier = v)),
                  _tuneSlider(
                      'الشفافية',
                      '${(state.overallOpacity * 100).round()}٪',
                      state.overallOpacity,
                      0.1,
                      1.0,
                      (v) => state.update(() => state.overallOpacity = v)),
                  _tuneSlider(
                      'مدة الانتقال',
                      '${state.textTransitionMs} م.ث',
                      state.textTransitionMs.toDouble(),
                      100,
                      2000,
                      (v) => state
                          .update(() => state.textTransitionMs = v.round())),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            state.update(() => state.textOffset = Offset.zero);
                          },
                          icon: const Icon(Icons.center_focus_strong, size: 18),
                          label: const Text('إعادة الموضع'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            state.update(() => state.textUserScale = 1.0);
                          },
                          icon: const Icon(Icons.restart_alt, size: 18),
                          label: const Text('إعادة الحجم'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

"""
EDITS = [('clip bar buttons', INK_OLD, INK_NEW, 2), ('text bar button', TXT_OLD, TXT_NEW, 1),
         ('ayah block bar button', SEG_OLD, SEG_NEW, 1), ('tune sheet', METH_OLD, METH + METH_OLD, 1)]
bad = ['%s (found %d)' % (l, h.count(o)) for l, o, _, n in EDITS if h.count(o) != n]
if bad: sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))
for l, o, n, _ in EDITS:
    h = h.replace(o, n); print('  PATCHED home_screen.dart -', l)
open(HOME, 'w', encoding='utf-8').write(h)
print('S186 applied. Next: git add -A && git commit -m "S186: smooth bars + text fine-tune" && git push')
