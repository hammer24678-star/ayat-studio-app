// PATCH_S174_PRO_EDITOR
// The "pages" of the pro editor, as bottom-sheet panels:
//   ProColorPage      - Resolve's Color page / Premiere's Lumetri basics
//   ProAudioMixer     - Resolve's Fairlight / Premiere's Essential Sound: faders
//   ProTranscript     - Premiere's text-based editing, driven by the ayah timeline
//   ProExportPresets  - CapCut / Resolve "Deliver" one-tap platform presets
// Every control here edits a field the preview and the exporter already read.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../services/app_settings.dart';
import '../theme/ayat_theme.dart';
import 'gold_switch.dart';
import 'motion.dart'; // PATCH_S176_SMOOTH

// ------------------------------------------------------------------ shared

Widget _proTitle(BuildContext context, String text) => Padding(
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

/// Slider row in the Resolve style: label, numeric readout, and a
/// double-tap on the label resets the control to its neutral value.
class _ProSlider extends StatelessWidget {
  final String label;
  final String readout;
  final double value;
  final double min;
  final double max;
  final double neutral;
  final ValueChanged<double> onChanged;
  const _ProSlider({
    required this.label,
    required this.readout,
    required this.value,
    required this.min,
    required this.max,
    required this.neutral,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final changed = (value - neutral).abs() > (max - min) * 0.004;
    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: () => onChanged(neutral),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: Theme.of(context).textTheme.bodyLarge),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AyatColors.surface3,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  readout,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color:
                        changed ? AyatColors.goldBright : AyatColors.parchmentDim,
                  ),
                ),
              ),
            ],
          ),
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
}

// ------------------------------------------------------------------- color

class ProColorPage extends StatelessWidget {
  final StudioState state;
  const ProColorPage({super.key, required this.state});

  static const Map<ColorGrade, List<Color>> _swatch = {
    ColorGrade.none: [Color(0xFF3A4A44), Color(0xFF14211D)],
    ColorGrade.warmGold: [Color(0xFFE8B84A), Color(0xFF7A4A12)],
    ColorGrade.nightTeal: [Color(0xFF1E6F78), Color(0xFF07202A)],
    ColorGrade.sepia: [Color(0xFFC9A877), Color(0xFF5B4126)],
    ColorGrade.softMono: [Color(0xFFBDBDBD), Color(0xFF3A3A3A)],
  };

  @override
  Widget build(BuildContext context) {
    final t = AppSettings.instance.strings;
    String signed(double v) =>
        '${v >= 0 ? '+' : ''}${v.round()}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _proTitle(context, 'اللوكات'),
        SizedBox(
          height: 82,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final g in kColorGrades)
                GestureDetector(
                  onTap: () => state.update(() => state.colorGrade = g.$1),
                  child: Container(
                    width: 76,
                    margin: const EdgeInsetsDirectional.only(end: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _swatch[g.$1] ??
                            const [Color(0xFF3A4A44), Color(0xFF14211D)],
                      ),
                      border: Border.all(
                        color: state.colorGrade == g.$1
                            ? AyatColors.goldBright
                            : AyatColors.hairline,
                        width: state.colorGrade == g.$1 ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      t.t(g.$2),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _proTitle(context, 'التصحيح الأساسي'),
        _ProSlider(
          label: 'السطوع',
          readout: signed(state.adjustBrightness * 400),
          value: state.adjustBrightness,
          min: -0.25,
          max: 0.25,
          neutral: 0,
          onChanged: (v) => state.update(() => state.adjustBrightness = v),
        ),
        _ProSlider(
          label: 'التباين',
          readout: signed((state.adjustContrast - 1) * 250),
          value: state.adjustContrast,
          min: 0.7,
          max: 1.4,
          neutral: 1,
          onChanged: (v) => state.update(() => state.adjustContrast = v),
        ),
        _ProSlider(
          label: 'التشبّع',
          readout: signed((state.adjustSaturation - 1) * 100),
          value: state.adjustSaturation,
          min: 0,
          max: 2,
          neutral: 1,
          onChanged: (v) => state.update(() => state.adjustSaturation = v),
        ),
        _ProSlider(
          label: 'ضبابية الخلفية',
          readout: state.videoBlur.toStringAsFixed(1),
          value: state.videoBlur,
          min: 0,
          max: 6,
          neutral: 0,
          onChanged: (v) => state.update(() => state.videoBlur = v),
        ),
        _proTitle(context, 'مؤثرات الصورة'),
        ToggleRow(
          label: 'تعتيم الحواف (فينييت)',
          value: state.vignetteEnabled,
          onChanged: (v) => state.update(() => state.vignetteEnabled = v),
        ),
        if (state.vignetteEnabled)
          _ProSlider(
            label: 'قوة التعتيم',
            readout: '${state.vignetteIntensity}',
            value: state.vignetteIntensity.toDouble(),
            min: 0,
            max: 100,
            neutral: 50,
            onChanged: (v) =>
                state.update(() => state.vignetteIntensity = v.round()),
          ),
        ToggleRow(
          label: 'حبيبات الفيلم',
          value: state.grainEnabled,
          onChanged: (v) => state.update(() => state.grainEnabled = v),
        ),
        if (state.grainEnabled)
          _ProSlider(
            label: 'كمية الحبيبات',
            readout: '${state.grainIntensity}',
            value: state.grainIntensity.toDouble(),
            min: 0,
            max: 100,
            neutral: 30,
            onChanged: (v) =>
                state.update(() => state.grainIntensity = v.round()),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () => state.update(() {
              state.colorGrade = ColorGrade.none;
              state.vignetteEnabled = false;
              state.grainEnabled = false;
              state.resetManualAdjust();
            }),
            icon: const Icon(Icons.restart_alt, size: 18),
            label: const Text('إعادة ضبط اللون'),
          ),
        ),
        const SizedBox(height: 4),
        Text('اضغط مرتين على اسم أي شريط لإعادته إلى قيمته الأصلية.',
            style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

// ------------------------------------------------------------------- audio

class ProAudioMixer extends StatelessWidget {
  final StudioState state;
  final VoidCallback onPickAmbience;
  const ProAudioMixer(
      {super.key, required this.state, required this.onPickAmbience});

  static String _db(double v) {
    if (v <= 0.001) return '-∞ dB';
    final d = 20 * math.log(v) / math.ln10;
    return '${d >= 0 ? '+' : ''}${d.toStringAsFixed(1)} dB';
  }

  Widget _strip(
    BuildContext context, {
    required String label,
    required String readout,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required Color accent,
    bool dim = false,
  }) {
    return Expanded(
      child: Opacity(
        opacity: dim ? 0.45 : 1,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AyatColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AyatColors.hairline),
          ),
          child: Column(
            children: [
              Text(readout,
                  style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w800,
                      color: accent)),
              SizedBox(
                height: 150,
                width: 44,
                child: RotatedBox(
                  quarterTurns: 3,
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accent,
                      thumbColor: accent,
                    ),
                    child: Slider(
                      value: value.clamp(min, max).toDouble(),
                      min: min,
                      max: max,
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: AyatColors.parchment)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasReciter = state.selectedReciterAudio != null;
    final hasAmbience = state.ambienceBedPath != null;
    final muted = state.muteAudio;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _proTitle(context, 'مازج الصوت'),
        SizedBox(
          height: 218,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _strip(
                context,
                label: hasReciter ? 'التلاوة' : 'صوت المقطع',
                readout: _db(state.audioVolume),
                value: state.audioVolume,
                min: 0,
                max: 2,
                accent: AyatColors.goldBright,
                dim: muted,
                onChanged: (v) => state.update(() => state.audioVolume = v),
              ),
              if (hasReciter && state.hasVideo)
                _strip(
                  context,
                  label: 'صوت المقطع تحت التلاوة',
                  readout: '${(state.originalAudioMix * 100).round()}٪',
                  value: state.originalAudioMix,
                  min: 0,
                  max: 1,
                  accent: const Color(0xFF6FA8DC),
                  dim: muted,
                  onChanged: (v) =>
                      state.update(() => state.originalAudioMix = v),
                ),
              if (hasAmbience)
                _strip(
                  context,
                  label: 'الخلفية الصوتية',
                  readout: '${(state.ambienceBedVolume * 100).round()}٪',
                  value: state.ambienceBedVolume,
                  min: 0,
                  max: 1,
                  accent: const Color(0xFF8BC48A),
                  dim: muted,
                  onChanged: (v) =>
                      state.update(() => state.ambienceBedVolume = v),
                ),
              Expanded(
                child: GestureDetector(
                  onTap: () =>
                      state.update(() => state.muteAudio = !state.muteAudio),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: muted
                          ? const Color(0x33E53935)
                          : AyatColors.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: muted
                              ? const Color(0xFFE53935)
                              : AyatColors.hairline),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          muted ? Icons.volume_off : Icons.volume_up_outlined,
                          size: 30,
                          color: muted
                              ? const Color(0xFFE53935)
                              : AyatColors.goldBright,
                        ),
                        const SizedBox(height: 6),
                        Text(muted ? 'مكتوم' : 'كتم الكل',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ToggleRow(
          label: 'دخول تدريجي للصوت',
          value: state.audioFadeIn,
          onChanged: (v) => state.update(() => state.audioFadeIn = v),
        ),
        ToggleRow(
          label: 'خفوت تدريجي في النهاية',
          value: state.audioFadeOut,
          onChanged: (v) => state.update(() => state.audioFadeOut = v),
        ),
        if (hasAmbience)
          ToggleRow(
            label: 'دخول وخروج تدريجي للخلفية',
            value: state.ambienceBedFade,
            onChanged: (v) => state.update(() => state.ambienceBedFade = v),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onPickAmbience,
                icon: const Icon(Icons.graphic_eq, size: 18),
                label: Text(hasAmbience ? 'تغيير الخلفية' : 'إضافة خلفية صوتية'),
              ),
            ),
            if (hasAmbience) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'إزالة الخلفية',
                onPressed: () => state.update(() => state.ambienceBedPath = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- transcript

class ProTranscript extends StatefulWidget {
  final StudioState state;
  final VideoPlayerController? controller;
  final ValueChanged<String> onToast;
  final ValueChanged<int> onSelectSeg;
  const ProTranscript({
    super.key,
    required this.state,
    required this.controller,
    required this.onToast,
    required this.onSelectSeg,
  });

  @override
  State<ProTranscript> createState() => _ProTranscriptState();
}

class _ProTranscriptState extends State<ProTranscript> {
  final Set<int> _sel = {};
  String _q = '';

  static String _fmt(double s) {
    final tenths = (s * 10).round(); // PATCH_S197_DETAILS
    final m = tenths ~/ 600;
    final sec = (tenths % 600) / 10;
    return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';
  }

  void _seek(double sec) {
    final c = widget.controller;
    if (c == null || !c.value.isInitialized) return;
    c.seekTo(Duration(milliseconds: (sec * 1000).round() + 30));
  }

  void _deleteSelected() {
    final st = widget.state;
    final idx = _sel.where((i) => i < st.timeline.length).toList()
      ..sort((a, b) => b.compareTo(a));
    if (idx.isEmpty) return;
    for (final i in idx) {
      st.removeTimelineSegment(i);
    }
    setState(_sel.clear);
    widget.onSelectSeg(-1);
    widget.onToast('تم حذف ${idx.length} من الخط الزمني (يمكن التراجع)');
  }

  void _trimToSelection() {
    final st = widget.state;
    final idx = _sel.where((i) => i < st.timeline.length).toList()..sort();
    if (idx.isEmpty) return;
    st.update(() {
      st.trimFromIndex = idx.first;
      st.trimToIndex = idx.last;
    });
    widget.onToast(
        'سيُصدَّر من آية ${st.timeline[idx.first].ayah.num} حتى آية ${st.timeline[idx.last].ayah.num}');
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.state;
    final tl = st.timeline;
    if (tl.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'شغّل المزامنة التلقائية أولًا — ستظهر هنا الآيات المرصودة كنص تحرّره مباشرة: علّم، احذف، أو اقصّ النطاق.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    final q = _q.trim();
    final rows = <int>[
      for (var i = 0; i < tl.length; i++)
        if (q.isEmpty || tl[i].displayText.contains(q) || '${tl[i].ayah.num}' == q)
          i,
    ];
    final selDur = _sel
        .where((i) => i < tl.length)
        .fold<double>(0, (a, i) => a + (tl[i].end - tl[i].start));
    final hasTrim = st.trimFromIndex >= 0 && st.trimToIndex >= 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          onChanged: (v) => setState(() => _q = v),
          decoration: InputDecoration(
            hintText: 'ابحث في نص التلاوة أو رقم الآية…',
            prefixIcon: const Icon(Icons.search, size: 20),
            isDense: true,
            filled: true,
            fillColor: AyatColors.surface2,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AyatColors.hairline),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              _sel.isEmpty
                  ? 'اضغط الآية للانتقال إليها · علّم الصناديق للتحرير'
                  : 'محدد: ${_sel.length} · ${selDur.toStringAsFixed(1)} ث',
              style: const TextStyle(
                  fontSize: 11, color: AyatColors.parchmentDim),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              onPressed: _sel.isEmpty ? null : _trimToSelection,
              icon: const Icon(Icons.content_cut, size: 16),
              label: const Text('قصّ النطاق'),
            ),
            FilledButton.tonalIcon(
              onPressed: _sel.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('حذف المحدد'),
            ),
            TextButton(
              onPressed: () => setState(() {
                if (_sel.length == rows.length) {
                  _sel.clear();
                } else {
                  _sel
                    ..clear()
                    ..addAll(rows);
                }
              }),
              child: Text(_sel.length == rows.length ? 'إلغاء التحديد' : 'تحديد الكل'),
            ),
            if (hasTrim)
              TextButton(
                onPressed: () => st.update(() {
                  st.trimFromIndex = -1;
                  st.trimToIndex = -1;
                }),
                child: const Text('إلغاء القص'),
              ),
          ],
        ),
        const SizedBox(height: 6),
        for (final i in rows)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: (hasTrim && i >= st.trimFromIndex && i <= st.trimToIndex)
                  ? const Color(0x22ECC875)
                  : AyatColors.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _sel.contains(i)
                    ? AyatColors.goldBright
                    : AyatColors.hairline,
              ),
            ),
            child: Row(
              children: [
                Checkbox(
                  value: _sel.contains(i),
                  activeColor: AyatColors.gold,
                  checkColor: AyatColors.ink,
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _sel.add(i);
                    } else {
                      _sel.remove(i);
                    }
                  }),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      _seek(tl[i].start);
                      widget.onSelectSeg(i);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tl[i].displayText,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${tl[i].ayah.num} · ${_fmt(tl[i].start)} – ${_fmt(tl[i].end)}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: tl[i].confidence < 0.4
                                  ? AyatColors.goldBright
                                  : AyatColors.parchmentDim,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------- presets

class _ExportPreset {
  final String title;
  final String sub;
  final IconData icon;
  final AyatAspectRatio aspect;
  final ExportResolutionCap res;
  final ExportQuality quality;
  const _ExportPreset(
      this.title, this.sub, this.icon, this.aspect, this.res, this.quality);
}

const List<_ExportPreset> _kPresets = [
  _ExportPreset('ريلز · تيك توك · شورتس', '9:16 · 1080p · جودة عالية',
      Icons.smartphone, AyatAspectRatio.story916, ExportResolutionCap.hd1080,
      ExportQuality.high),
  _ExportPreset('يوتيوب', '16:9 · 1080p · جودة عالية', Icons.smart_display_outlined,
      AyatAspectRatio.landscape169, ExportResolutionCap.hd1080,
      ExportQuality.high),
  _ExportPreset('منشور إنستغرام', '4:5 · 1080p · متوازن',
      Icons.crop_portrait, AyatAspectRatio.portrait45,
      ExportResolutionCap.hd1080, ExportQuality.balanced),
  _ExportPreset('مربع', '1:1 · 1080p · متوازن', Icons.crop_square,
      AyatAspectRatio.square11, ExportResolutionCap.hd1080,
      ExportQuality.balanced),
  _ExportPreset('حالة واتساب · تيليجرام', '9:16 · 720p · حجم صغير',
      Icons.chat_bubble_outline, AyatAspectRatio.story916,
      ExportResolutionCap.hd720, ExportQuality.compact),
];

class ProExportPresets extends StatelessWidget {
  final StudioState state;
  final bool busy;
  final VoidCallback onExport;
  const ProExportPresets({
    super.key,
    required this.state,
    required this.busy,
    required this.onExport,
  });

  @override
  Widget build(BuildContext context) {
    final fs = state.frameSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _proTitle(context, 'إعدادات جاهزة للمنصات'),
        for (final p in _kPresets)
          Builder(builder: (context) {
            final on = state.aspectRatio == p.aspect &&
                state.exportResolution == p.res &&
                state.exportQuality == p.quality;
            return PressableScale( // PATCH_S176_SMOOTH
              onTap: () => state.update(() {
                state.aspectRatio = p.aspect;
                state.exportResolution = p.res;
                state.exportQuality = p.quality;
              }),
              child: AnimatedContainer(
                duration: AppMotion.d(AppMotion.medium),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: on ? const Color(0x22ECC875) : AyatColors.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: on ? AyatColors.goldBright : AyatColors.hairline,
                    width: on ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(p.icon,
                        color: on
                            ? AyatColors.goldBright
                            : AyatColors.parchmentDim),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.title,
                              style: Theme.of(context).textTheme.bodyLarge),
                          const SizedBox(height: 2),
                          Text(p.sub,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AyatColors.parchmentDim)),
                        ],
                      ),
                    ),
                    if (on)
                      const Icon(Icons.check_circle,
                          size: 20, color: AyatColors.goldBright),
                  ],
                ),
              ),
            );
          }),
        _proTitle(context, 'معدل الإطارات'), // PATCH_S175_CAPCUT
        Wrap(
          spacing: 8,
          children: [
            for (final f in const [24, 25, 30, 50, 60])
              ChoiceChip(
                label: Text('$f'),
                selected: state.exportFps == f,
                onSelected: (_) => state.update(() => state.exportFps = f),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text('الإطار الحالي: ${fs.$1}×${fs.$2}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: busy ? null : onExport,
          icon: const Icon(Icons.movie_creation_outlined, size: 18),
          label: const Text('تصدير ثم مشاركة'),
        ),
      ],
    );
  }
}
