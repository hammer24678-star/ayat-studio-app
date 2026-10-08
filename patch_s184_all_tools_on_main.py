#!/usr/bin/env python3
"""
patch_s184_all_tools_on_main.py - Ayat Studio S184 (run from repo root, after S181 + S182 + S183)

The 5 big tabs (آيات / النص / الشكل / الوسائط / المزيد) were pages with 6-10 things
each, hidden behind one button. Now every one of those things is its own tool on
the main screen, like CapCut / Premiere:

  1) ONE FLAT TOOL STRIP under the timeline (scroll sideways):
     الفيديو - المقاس - التحويل - السرعة - الآيات - النص - الإطار - الظل - التوهج -
     اللافتة - الشفافية - الحركة - الترجمة - ملصقات - الخلفية - كروما - تأثيرات -
     قوالب - اللون - تحسين - الصوت - القارئ - النص المفرَّغ - لمسات - علامة -
     تصدير سريع - الإخراج
  2) SELECT SOMETHING AND ITS TOOLS APPEAR in the bar (selection is kept while a
     tool is open, so you tweak and keep working):
       text on stage / text block : النمط الإطار الظل التوهج اللافتة الشفافية الحركة
       main clip                  : اللون الصوت تحسين المقاس الخلفية كروما
       ayah block                 : النمط الحركة الترجمة القارئ
  3) THE TOOL PANEL IS RESIZABLE: drag the little handle at its top (or double
     tap it) to make it taller/shorter; the stage and timeline stay on screen.

Idempotent; every anchor is verified before anything is written.
"""
import os, sys

MARK = 'PATCH_S184_PRO_MAIN'
F = {'home': 'lib/screens/home_screen.dart', 'te': 'lib/widgets/text_editor_pro.dart'}
for p in F.values():
    if not os.path.exists(p):
        sys.exit('Run from the repo root (missing %s).' % p)
T = {k: open(p, encoding='utf-8').read() for k, p in F.items()}
if any(MARK in t for t in T.values()):
    print('  OK      already applied'); sys.exit(0)
if 'PATCH_S183_TEXT_BAR' not in T['home'] or 'PATCH_S182_WHISPER_MAIN' not in T['home']:
    sys.exit('S182 + S183 are not applied yet.')

# ------------------------------------------------------- text_editor_pro
TE_FIELD_OLD = "  final VoidCallback? onPickCustomFont;\n  const TextEditorPro({super.key, required this.state,\n    this.segmentTexts = const [], this.canvasWidth = 1080, this.onPickCustomFont});\n"
TE_FIELD_NEW = ("  final VoidCallback? onPickCustomFont;\n"
  "  final TextEditorTab? only; // " + MARK + ": show just this one page (no inner tab row)\n"
  "  const TextEditorPro({super.key, required this.state,\n"
  "    this.segmentTexts = const [], this.canvasWidth = 1080, this.onPickCustomFont, this.only});\n")
TE_TAB_OLD = "  TextEditorTab _tab = TextEditorTab.text;\n"
TE_TAB_NEW = "  late TextEditorTab _tab = widget.only ?? TextEditorTab.text; // " + MARK + "\n"
TE_BUILD_OLD = "    builder: (c, _) => Column(children: [_tabRow(), _body()]));\n"
TE_BUILD_NEW = "    builder: (c, _) => Column(children: [if (widget.only == null) _tabRow(), _body()])); // " + MARK + "\n"

# ------------------------------------------------------------------ home
H_FRAC_OLD = "  int _toolOpen = -1;\n"
H_FRAC_NEW = H_FRAC_OLD + "  double _panelFrac = 0.36; // " + MARK + ": height of the tool panel (drag its handle)\n"

H_PANELH_OLD = "      final panelH = (c.maxHeight * 0.36).clamp(0.0, 420.0);\n"
H_PANELH_NEW = ("      // " + MARK + ": resizable, never so tall that the stage disappears\n"
  "      final panelH = max(0.0, min(c.maxHeight * _panelFrac, c.maxHeight - 330.0))\n"
  "          .clamp(0.0, 560.0)\n          .toDouble();\n")

H_TOOLLIST_START = "  List<(int, IconData, String)> _toolList() => [\n"
H_TOOLLIST_END = "        (102, Icons.auto_fix_high, 'لمسات'),\n      ];\n"
H_TOOLLIST_NEW = """  // """ + MARK + """: one flat strip, every old tab section is its own tool.
  List<(int, IconData, String)> _toolList() => [
        (100, Icons.movie_outlined, 'الفيديو'),
        (101, Icons.aspect_ratio, 'المقاس'),
        (112, Icons.open_with, 'التحويل'),
        (107, Icons.speed, 'السرعة'),
        (120, Icons.menu_book_outlined, 'الآيات'),
        (121, Icons.text_fields, 'النص'),
        (122, Icons.border_style, 'الإطار'),
        (123, Icons.filter_frames, 'الظل'),
        (124, Icons.wb_sunny_outlined, 'التوهج'),
        (125, Icons.label_outline, 'اللافتة'),
        (126, Icons.opacity, 'الشفافية'),
        (108, Icons.animation, 'الحركة'),
        (109, Icons.closed_caption_outlined, 'الترجمة'),
        (110, Icons.emoji_emotions_outlined, 'ملصقات'),
        (127, Icons.wallpaper, 'الخلفية'),
        (128, Icons.layers_outlined, 'كروما'),
        (130, Icons.auto_awesome_outlined, 'تأثيرات'),
        (131, Icons.dashboard_customize_outlined, 'قوالب'),
        (103, Icons.palette_outlined, 'اللون'),
        (111, Icons.high_quality_outlined, 'تحسين'),
        (104, Icons.equalizer, 'الصوت'),
        (129, Icons.record_voice_over_outlined, 'القارئ'),
        (105, Icons.subtitles_outlined, 'النص المفرَّغ'),
        (102, Icons.auto_fix_high, 'لمسات'),
        (132, Icons.branding_watermark_outlined, 'علامة'),
        (106, Icons.ios_share, 'تصدير سريع'),
        (133, Icons.tune, 'الإخراج'),
      ];

  Widget _teOnly(TextEditorTab t) => TextEditorPro(
        key: ValueKey('te-${t.name}'),
        state: state,
        segmentTexts: state.unifiedTexts,
        canvasWidth: 1080,
        onPickCustomFont: _pickCustomFont,
        only: t,
      );
"""

H_HANDLE_OLD = "      child: Column(\n        children: [\n          SizedBox(\n            height: 46,\n"
H_HANDLE_NEW = """      child: Column(
        children: [
          // """ + MARK + """: drag to resize the panel, double tap to toggle
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: (d) {
              final hh = MediaQuery.of(context).size.height * 0.8;
              setState(() => _panelFrac =
                  (_panelFrac - d.delta.dy / hh).clamp(0.2, 0.6).toDouble());
            },
            onDoubleTap: () => setState(
                () => _panelFrac = _panelFrac > 0.45 ? 0.36 : 0.58),
            child: SizedBox(
              height: 20,
              child: Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AyatColors.parchmentDim,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 46,
"""

H_BODY_OLD = "      case 102:\n        return MagicCard(state: state, onToast: _toast);\n"
H_BODY_NEW = H_BODY_OLD + """      // """ + MARK + """: the old tab sections, one tool each
      case 120:
        return _ayahPanel();
      case 121:
        return _teOnly(TextEditorTab.text);
      case 122:
        return _teOnly(TextEditorTab.border);
      case 123:
        return _teOnly(TextEditorTab.shadow);
      case 124:
        return _teOnly(TextEditorTab.glow);
      case 125:
        return _teOnly(TextEditorTab.label);
      case 126:
        return _teOnly(TextEditorTab.opacity);
      case 127:
        return _bgPanel();
      case 128:
        return _chromaPanel();
      case 129:
        return _recitersPanel();
      case 130:
        return _effectsPanel();
      case 131:
        return _templatesPanel();
      case 132:
        return _watermarkSection();
      case 133:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _exportPanel(),
            const SizedBox(height: 16),
            _exportButton(),
          ],
        );
"""

H_OPENFROM_OLD = "    setState(() => _selMain = false);\n    if (_toolOpen != id) _openTool(id);\n"
H_OPENFROM_NEW = "    _openTool(id); // " + MARK + ": keep the selection, tap again to close the tool\n"

def tool(icon, label, id):
    return "(%s, '%s', () => _openToolFromClip(%d), _toolOpen == %d)," % (icon, label, id, id)

H_MAIN_OLD = "        (Icons.speed, 'السرعة', () => _openToolFromClip(107), false),\n"
H_MAIN_NEW = ("        (Icons.speed, 'السرعة', () => _openToolFromClip(107), _toolOpen == 107),\n"
  "        // " + MARK + ": every tool of the main clip, one tap away\n"
  + "".join("        " + tool(*a) + "\n" for a in [
      ('Icons.palette_outlined', 'اللون', 103), ('Icons.equalizer', 'الصوت', 104),
      ('Icons.high_quality_outlined', 'تحسين', 111), ('Icons.aspect_ratio', 'المقاس', 101),
      ('Icons.wallpaper', 'الخلفية', 127), ('Icons.layers_outlined', 'كروما', 128)]))

H_TEXT_OLD = "      (Icons.vertical_align_center, 'الموضع', _cycleTextPos, false),\n"
H_TEXT_NEW = (H_TEXT_OLD + "      // " + MARK + ": the whole look of the text, from the bar\n"
  + "".join("      " + tool(*a) + "\n" for a in [
      ('Icons.text_fields', 'النمط', 121), ('Icons.border_style', 'الإطار', 122),
      ('Icons.filter_frames', 'الظل', 123), ('Icons.wb_sunny_outlined', 'التوهج', 124),
      ('Icons.label_outline', 'اللافتة', 125), ('Icons.opacity', 'الشفافية', 126),
      ('Icons.animation', 'الحركة', 108)]))

H_SEG_OLD = "        (Icons.animation, 'انتقال', _openTransitionSheet, false),\n        (Icons.zoom_in, 'تكبير', _zoomToSelection, false),\n      ];\n"
H_SEG_NEW = ("        (Icons.animation, 'انتقال', _openTransitionSheet, false),\n"
  "        (Icons.zoom_in, 'تكبير', _zoomToSelection, false),\n"
  "        // " + MARK + "\n"
  + "".join("        " + tool(*a) + "\n" for a in [
      ('Icons.text_fields', 'النمط', 121), ('Icons.animation', 'الحركة', 108),
      ('Icons.closed_caption_outlined', 'الترجمة', 109), ('Icons.record_voice_over_outlined', 'القارئ', 129)])
  + "      ];\n")

H_CUE_OLD = "      (Icons.edit_outlined, 'تعديل النص', () => _cueEditText(i), false),\n"
H_CUE_NEW = (H_CUE_OLD
  + "".join("      " + tool(*a) + "\n" for a in [
      ('Icons.text_fields', 'النمط', 121), ('Icons.border_style', 'الإطار', 122),
      ('Icons.filter_frames', 'الظل', 123)]))

EDITS = {
  'te': [('ctor + field', TE_FIELD_OLD, TE_FIELD_NEW), ('initial tab', TE_TAB_OLD, TE_TAB_NEW),
         ('hide tab row', TE_BUILD_OLD, TE_BUILD_NEW)],
  'home': [
    ('panel fraction field', H_FRAC_OLD, H_FRAC_NEW),
    ('panel height', H_PANELH_OLD, H_PANELH_NEW),
    ('resize handle', H_HANDLE_OLD, H_HANDLE_NEW),
    ('tool bodies', H_BODY_OLD, H_BODY_NEW),
    ('keep selection when opening a tool', H_OPENFROM_OLD, H_OPENFROM_NEW),
    ('main clip tools', H_MAIN_OLD, H_MAIN_NEW),
    ('text tools', H_TEXT_OLD, H_TEXT_NEW),
    ('ayah block tools', H_SEG_OLD, H_SEG_NEW),
    ('text block tools', H_CUE_OLD, H_CUE_NEW),
  ],
}
bad = []
for k, eds in EDITS.items():
    for label, old, _ in eds:
        n = T[k].count(old)
        if n != 1:
            bad.append('%s: %s (found %d)' % (F[k], label, n))
h = T['home']
if h.count(H_TOOLLIST_START) != 1 or h.count(H_TOOLLIST_END) != 1 or h.index(H_TOOLLIST_START) > h.index(H_TOOLLIST_END):
    bad.append('home: tool list anchors')
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for k, eds in EDITS.items():
    for label, old, new in eds:
        T[k] = T[k].replace(old, new, 1)
        print('  PATCHED', F[k].split('/')[-1], '-', label)
h = T['home']
i = h.index(H_TOOLLIST_START); j = h.index(H_TOOLLIST_END) + len(H_TOOLLIST_END)
T['home'] = h[:i] + H_TOOLLIST_NEW + h[j:]
print('  PATCHED home_screen.dart - flat tool strip')
for k, p in F.items():
    open(p, 'w', encoding='utf-8').write(T[k])
print('S184 applied. Next: git add -A && git commit -m "S184: every tool on the main screen" && git push')
