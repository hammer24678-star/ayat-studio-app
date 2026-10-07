#!/usr/bin/env python3
"""
patch_s175_capcut_extras.py - Ayat Studio S175 (run from repo root, after S174)

CapCut features the studio did not have yet:
  - Export frame rate 24/25/30/50/60 (export presets page; replaces fixed 30)
  - Enhance: sharpen + denoise the picture (exporter: unsharp / hqdn3d)
  - Voice clean-up: noise reduction + loudness normalize (afftdn / loudnorm)
  - Stickers page: Islamic / ornament / nature glyphs as stackable layers
  - Tool pages for what already existed but was buried: Speed, Animation
    (text in/out), Captions + subtitles
  - Fullscreen preview button

Idempotent; every anchor is verified before anything is written.
"""
import os, sys

MARK = 'PATCH_S175_CAPCUT'
HOME = 'lib/screens/home_screen.dart'
STATE = 'lib/models/studio_state.dart'
EXPORT = 'lib/services/export_service.dart'
PANELS = 'lib/widgets/pro_panels.dart'
NEWF = 'lib/widgets/pro_capcut.dart'

if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
for p in (HOME, STATE, EXPORT, PANELS):
    if not os.path.exists(p):
        sys.exit('missing ' + p)

def rd(p):
    return open(p, encoding='utf-8').read()

home, state, export, panels = rd(HOME), rd(STATE), rd(EXPORT), rd(PANELS)
if MARK in home:
    print('  OK      already applied')
    sys.exit(0)
if 'PATCH_S174_PRO_EDITOR' not in home:
    sys.exit('S174 not applied yet - run patch_s174_pro_editor.py first.')

NEW_CAPCUT = r"""// PATCH_S175_CAPCUT
// CapCut-style extras: Stickers page + Enhance page (picture sharpen/denoise,
// voice clean-up). Export frame rate lives in pro_panels.dart (ProExportPresets).
import 'package:flutter/material.dart';
import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';
import 'gold_switch.dart';

Widget _ccTitle(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: AyatColors.goldBright,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 8),
          Text(text, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );

// ------------------------------------------------------------- stickers

const Map<String, List<String>> _kStickerSets = {
  'إسلامي': ['﷽', 'ﷲ', '☪', '۞', '۩', '❂', '﴾', '﴿', 'ﷺ', '﷼'],
  'زخارف': ['✦', '✧', '❖', '✺', '❁', '❀', '✿', '❃', '❋', '✷', '⁂', '❦'],
  'طبيعة': ['☀', '☾', '★', '☁', '❄', '🌙', '🌿', '🌸', '🕌', '🌹', '⭐', '✨'],
};

class ProStickers extends StatefulWidget {
  final StudioState state;
  final void Function(String) onToast;
  const ProStickers({super.key, required this.state, required this.onToast});

  @override
  State<ProStickers> createState() => _ProStickersState();
}

class _ProStickersState extends State<ProStickers> {
  double _size = 56;
  AyahTextPosition _pos = AyahTextPosition.center;
  Color _color = AyatColors.goldBright;

  static const _colors = <Color>[
    AyatColors.goldBright,
    Color(0xFFFFFFFF),
    Color(0xFFECE2CB),
    Color(0xFF7FD6B0),
    Color(0xFFE8837A),
    Color(0xFF8AB4F8),
  ];

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final e in _kStickerSets.entries) ...[
            _ccTitle(context, e.key),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final g in e.value)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      st.addTextLayer(TextLayer(
                        text: g,
                        position: _pos,
                        fontSize: _size,
                        color: _color,
                      ));
                      widget.onToast('أُضيف الملصق');
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AyatColors.surface2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AyatColors.hairline),
                      ),
                      child: Text(g,
                          style: const TextStyle(
                              fontSize: 24, color: AyatColors.parchment)),
                    ),
                  ),
              ],
            ),
          ],
          _ccTitle(context, 'الحجم'),
          Slider(
            value: _size,
            min: 24,
            max: 140,
            onChanged: (v) => setState(() => _size = v),
          ),
          _ccTitle(context, 'الموضع'),
          Wrap(
            spacing: 8,
            children: [
              for (final p in const [
                (AyahTextPosition.top, 'أعلى'),
                (AyahTextPosition.center, 'وسط'),
                (AyahTextPosition.bottom, 'أسفل'),
              ])
                ChoiceChip(
                  label: Text(p.$2),
                  selected: _pos == p.$1,
                  onSelected: (_) => setState(() => _pos = p.$1),
                ),
            ],
          ),
          _ccTitle(context, 'اللون'),
          Wrap(
            spacing: 10,
            children: [
              for (final c in _colors)
                GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _color == c
                            ? AyatColors.parchment
                            : AyatColors.hairline,
                        width: _color == c ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (st.textLayers.isNotEmpty) ...[
            _ccTitle(context, 'الطبقات (${st.textLayers.length})'),
            for (var i = 0; i < st.textLayers.length; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(
                  st.textLayers[i].text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 18, color: st.textLayers[i].color),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: AyatColors.parchmentDim),
                  onPressed: () => st.removeTextLayerAt(i),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- enhance

class ProEnhance extends StatelessWidget {
  final StudioState state;
  const ProEnhance({super.key, required this.state});

  Widget _slider(BuildContext context, String label, int value,
      ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.bodyMedium)),
            Text('$value',
                style: const TextStyle(
                    fontSize: 12, color: AyatColors.parchmentDim)),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 100,
          divisions: 20,
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }

  Widget _switchRow(BuildContext context, String label, String sub, bool v,
      ValueChanged<bool> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 2),
                Text(sub,
                    style: const TextStyle(
                        fontSize: 11, color: AyatColors.parchmentDim)),
              ],
            ),
          ),
          GoldSwitch(value: v, onChanged: onChanged),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _ccTitle(context, 'تحسين الصورة (عند التصدير)'),
          _slider(context, 'حدّة الصورة', state.enhanceSharpen,
              (v) => state.update(() => state.enhanceSharpen = v)),
          _slider(context, 'تقليل الضجيج', state.enhanceDenoise,
              (v) => state.update(() => state.enhanceDenoise = v)),
          _ccTitle(context, 'تنقية الصوت (عند التصدير)'),
          _switchRow(context, 'إزالة الضجيج', 'يخفّف الهسهسة وضجيج الخلفية',
              state.audioDenoise,
              (v) => state.update(() => state.audioDenoise = v)),
          _switchRow(context, 'موازنة الصوت', 'مستوى صوت موحّد (-16 LUFS)',
              state.audioNormalize,
              (v) => state.update(() => state.audioNormalize = v)),
          const SizedBox(height: 6),
          const Text(
            'هذه التأثيرات تُطبَّق في الملف المُصدَّر ولا تظهر في المعاينة.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AyatColors.parchmentDim),
          ),
        ],
      ),
    );
  }
}
"""

FULLSCREEN = r"""  // PATCH_S175_CAPCUT: fullscreen preview (the player's corner button).
  Widget _fullscreenButton() {
    return Material(
      color: const Color(0x99050F0D),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: _openFullscreen,
        child: const Padding(
          padding: EdgeInsets.all(7),
          child: Icon(Icons.fullscreen, size: 20, color: AyatColors.parchment),
        ),
      ),
    );
  }

  void _openFullscreen() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: StagePreview(
                  state: state,
                  videoController: _video,
                  liveOverride: _liveOverlay,
                ),
              ),
              PositionedDirectional(
                top: 8,
                end: 8,
                child: IconButton(
                  icon: const Icon(Icons.fullscreen_exit,
                      color: AyatColors.parchment),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }

"""

PREVIEW_OLD = (
"              child: Center(\n"
"                child: StagePreview(\n"
"                  state: state,\n"
"                  videoController: _video,\n"
"                  liveOverride: _liveOverlay,\n"
"                ),\n"
"              ),\n")
PREVIEW_NEW = (
"              child: Stack(\n"
"                children: [\n"
"                  Center(\n"
"                    child: StagePreview(\n"
"                      state: state,\n"
"                      videoController: _video,\n"
"                      liveOverride: _liveOverlay,\n"
"                    ),\n"
"                  ),\n"
"                  PositionedDirectional(\n"
"                    end: 6,\n"
"                    bottom: 6,\n"
"                    child: _fullscreenButton(), // " + MARK + "\n"
"                  ),\n"
"                ],\n"
"              ),\n")

FPS_PANEL = (
"        _proTitle(context, 'معدل الإطارات'), // " + MARK + "\n"
"        Wrap(\n"
"          spacing: 8,\n"
"          children: [\n"
"            for (final f in const [24, 25, 30, 50, 60])\n"
"              ChoiceChip(\n"
"                label: Text('$f'),\n"
"                selected: state.exportFps == f,\n"
"                onSelected: (_) => state.update(() => state.exportFps = f),\n"
"              ),\n"
"          ],\n"
"        ),\n")

ENHANCE_FILTERS = (
"    // " + MARK + ": CapCut 'Enhance' - denoise / sharpen\n"
"    if (state.enhanceDenoise > 0) {\n"
"      final d = (state.enhanceDenoise / 100 * 6).toStringAsFixed(2);\n"
"      final dt = (state.enhanceDenoise / 100 * 9).toStringAsFixed(2);\n"
"      parts.add('hqdn3d=$d:$d:$dt:$dt');\n"
"    }\n"
"    if (state.enhanceSharpen > 0) {\n"
"      final a = (state.enhanceSharpen / 100 * 1.5).toStringAsFixed(2);\n"
"      parts.add('unsharp=5:5:$a:5:5:0.0');\n"
"    }\n")

VIG_OLD = ("    if (state.vignetteEnabled) {\n"
"      parts.add(_vignetteFilter(state.vignetteIntensity));\n")

files = []  # (path, text, [(label, old, new)])
files.append((HOME, home, [
 ('home import',
  "import '../widgets/pro_panels.dart'; // PATCH_S174_PRO_EDITOR\n",
  "import '../widgets/pro_panels.dart'; // PATCH_S174_PRO_EDITOR\nimport '../widgets/pro_capcut.dart'; // " + MARK + "\n"),
 ('tool list',
  "        (106, Icons.ios_share, 'تصدير سريع'),\n",
  "        (106, Icons.ios_share, 'تصدير سريع'),\n"
  "        (107, Icons.speed, 'السرعة'), // " + MARK + "\n"
  "        (108, Icons.animation, 'الحركة'),\n"
  "        (109, Icons.closed_caption_outlined, 'الترجمة'),\n"
  "        (110, Icons.emoji_emotions_outlined, 'ملصقات'),\n"
  "        (111, Icons.high_quality_outlined, 'تحسين'),\n"),
 ('tool body',
  "      case 106:\n        return ProExportPresets(\n            state: state, busy: _busy, onExport: _export);\n",
  "      case 106:\n        return ProExportPresets(\n            state: state, busy: _busy, onExport: _export);\n"
  "      case 107: // " + MARK + "\n        return _speedSection();\n"
  "      case 108:\n        return _textTransitionSection();\n"
  "      case 109:\n        return Column(\n"
  "          crossAxisAlignment: CrossAxisAlignment.stretch,\n"
  "          children: [\n"
  "            _captionSection(),\n"
  "            const Divider(height: 32, color: AyatColors.hairline),\n"
  "            _subtitleSection(),\n"
  "          ],\n        );\n"
  "      case 110:\n        return ProStickers(state: state, onToast: _toast);\n"
  "      case 111:\n        return ProEnhance(state: state);\n"),
 ('preview fullscreen', PREVIEW_OLD, PREVIEW_NEW),
 ('fullscreen methods', "  Widget _toolPanel(double h) {\n",
  FULLSCREEN + "  Widget _toolPanel(double h) {\n"),
]))
files.append((STATE, state, [
 ('state fields', "  bool audioFadeOut = false;\n",
  "  bool audioFadeOut = false;\n"
  "  // " + MARK + ": CapCut-style export + clean-up controls\n"
  "  int exportFps = 30; // 24 | 25 | 30 | 50 | 60\n"
  "  int enhanceSharpen = 0; // 0..100, picture sharpen (export)\n"
  "  int enhanceDenoise = 0; // 0..100, picture denoise (export)\n"
  "  bool audioDenoise = false; // voice noise reduction (export)\n"
  "  bool audioNormalize = false; // loudness normalize (export)\n"),
]))
files.append((EXPORT, export, [
 ('fps field', "  static const double titleCardSec = 2.2;\n",
  "  static const double titleCardSec = 2.2;\n  static int _fps = 30; // " + MARK + ": chosen export frame rate\n"),
 ('fps set',
  "    _cancelRequested = false; // PATCH_S37_CANCEL_LONG_JOBS\n",
  "    _cancelRequested = false; // PATCH_S37_CANCEL_LONG_JOBS\n    _fps = state.exportFps.clamp(24, 60); // " + MARK + "\n"),
 ('fps 1', "    if (!kenBurns) return 'scale=$w:$h,fps=30';\n",
  "    if (!kenBurns) return 'scale=$w:$h,fps=$_fps';\n"),
 ('fps 2', ":fps=30\";\n", ":fps=$_fps\";\n"),
 ('fps 3', "scale=$w:$h,fps=30,format=yuv420p[$lbl]", "scale=$w:$h,fps=$_fps,format=yuv420p[$lbl]"),
 ('fps 4', "overlay=(W-w)/2:(H-h)/2,fps=30[v0]", "overlay=(W-w)/2:(H-h)/2,fps=$_fps[v0]"),
 ('fps 5', "'crop=$w:$h,fps=30[v0]'", "'crop=$w:$h,fps=$_fps[v0]'"),
 ('enhance', VIG_OLD, ENHANCE_FILTERS + VIG_OLD),
 ('audio clean',
  "    final parts = <String>[];\n    if (state.audioFadeIn) parts.add('afade=t=in:st=0:d=1.0');\n",
  "    final parts = <String>[];\n"
  "    // " + MARK + ": voice clean-up before the fades\n"
  "    if (state.audioDenoise) parts.add('afftdn=nf=-25');\n"
  "    if (state.audioNormalize) parts.add('loudnorm=I=-16:TP=-1.5:LRA=11');\n"
  "    if (state.audioFadeIn) parts.add('afade=t=in:st=0:d=1.0');\n"),
]))
files.append((PANELS, panels, [
 ('fps chips',
  "        const SizedBox(height: 4),\n        Text('الإطار الحالي:",
  FPS_PANEL + "        const SizedBox(height: 4),\n        Text('الإطار الحالي:"),
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

open(NEWF, 'w', encoding='utf-8').write(NEW_CAPCUT)
print('  WROTE   ' + NEWF)
print('S175 applied. Next: git add -A && git commit -m "S175: CapCut extras" && git push')
