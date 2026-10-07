// PATCH_S175_CAPCUT
// CapCut-style extras: Stickers page + Enhance page (picture sharpen/denoise,
// voice clean-up). Export frame rate lives in pro_panels.dart (ProExportPresets).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // PATCH_S176_SMOOTH
import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';
import 'gold_switch.dart';
import 'motion.dart';

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
                  PressableScale(
                    borderRadius: BorderRadius.circular(12),
                    pressedScale: 0.85,
                    onTap: () {
                      HapticFeedback.lightImpact();
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
                  child: AnimatedContainer(
                    duration: AppMotion.d(AppMotion.fast),
                    curve: Curves.easeOut,
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
              FadeSlideIn(
                key: ObjectKey(st.textLayers[i]), // PATCH_S176_SMOOTH
                from: const Offset(0, 8),
                child: ListTile(
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
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    st.removeTextLayerAt(i);
                  },
                ),
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
