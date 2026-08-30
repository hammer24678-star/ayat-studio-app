// PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
// Professional tabbed text editor. Everything here is LOOK only —
// content (which words) and timing (when) stay in the الآيات tab.
// One global style applies to ALL ayat by design, so "apply to all"
// is inherent; "حفظ كشكل افتراضي" carries it to future projects.
import 'package:flutter/material.dart';
import '../theme/ayat_theme.dart';
import '../theme/ayat_fonts.dart'; // PATCH_S145: ayahTextStyle for chip previews
import '../models/studio_state.dart';
import '../i18n/app_strings.dart'; // PATCH_S139_MUSHAF_AR_EN_AND_I18N_WIDGETS
import '../services/app_settings.dart'; // PATCH_S139_MUSHAF_AR_EN_AND_I18N_WIDGETS
import 'color_picker_dialog.dart' show showAyatColorPicker;

enum TextEditorTab { text, border, shadow, glow, label, opacity }

// PATCH_S132_GAUNTLET_LOOP: the tab strip read t.name.toUpperCase() --
// the raw Dart enum identifier, English by construction, with no
// translation possible via a literal string replace (there was no
// literal string to replace). Real Arabic labels instead.
const Map<TextEditorTab, String> _kTabLabelsAr = {
  TextEditorTab.text: 'النص',
  TextEditorTab.border: 'الإطار',
  TextEditorTab.shadow: 'الظل',
  TextEditorTab.glow: 'التوهج',
  TextEditorTab.label: 'اللافتة',
  TextEditorTab.opacity: 'الشفافية',
};
// S128LabelShape mirrors S128LabelShape on StudioState
// PATCH_S128_FIX2_TEXT_EDITOR_PRO: enum: removed, using S128LabelShape
class TextEditorPro extends StatefulWidget {
  final StudioState state;
  final List<String> segmentTexts; // for unified one-line sizing
  final double canvasWidth;
  final VoidCallback? onPickCustomFont;
  const TextEditorPro({super.key, required this.state,
    this.segmentTexts = const [], this.canvasWidth = 1080, this.onPickCustomFont});
  @override
  State<TextEditorPro> createState() => _TextEditorProState();
}

class _TextEditorProState extends State<TextEditorPro> {
  TextEditorTab _tab = TextEditorTab.text;
  StudioState get s => widget.state;

  static const _quick = [Color(0xFFF4A7B9), Color(0xFFEF5350), Color(0xFFFF9800),
    Color(0xFFFFEB3B), Color(0xFF4CAF50), Color(0xFF26C6DA), Color(0xFF3F51B5),
    Color(0xFF9C4DFF)];
  // PATCH_S148_REMAINING_FONTS_AND_SELECTED_CHIP_FIX: this row used to
  // list only Google-Fonts substitutes plus 2 of the S145 bundled fonts --
  // it never included 'elgharib', 'tharwatemara', or 'digitalmadina', and
  // digitalmadina is the actual app default (studio_state.dart). That
  // meant whenever one of those three was the active font (including on
  // a fresh project, every time), none of these chips matched s.fontKey
  // and NONE of them showed as selected -- even though a real font was
  // applied. Every bundled asset font is listed here now, so whichever
  // one is active always shows as selected.
  static const _fonts = [
    ('elgharib', 'الغريب نون حفص'), ('digitalmadina', 'المدينة الرقمية'),
    ('tharwatemara', 'ثروت عمارة'), ('digitalkhatt', 'الرقمي الجديد'),
    ('elgharib_a001', 'الغريب A001'), ('elgharib_lpmq', 'الغريب اللجنة'),
    ('elgharib_a603', 'الغريب A603'), ('elgharib_eid', 'الغريب عيد الأضحى'),
    ('elgharib_qcf4', 'أسماء السور'), ('pf_monumenta', 'PF مونومنتا'),
    ('naskh', 'نسخ'), ('ruqaa', 'رقعة'), ('andalus', 'أندلس'),
    ('qalam', 'القلم'), ('kufi', 'الكوفي'),
  ];

  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: s,
    builder: (c, _) => Column(children: [_tabRow(), _body()]));

  // PATCH_S132_GAUNTLET_LOOP: Wrap instead of a fixed-width Row (was
  // clipping the rightmost tab on narrow screens -- shot-2/shot-3 bug),
  // Arabic labels instead of the raw English enum identifier.
  Widget _tabRow() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6,
      children: [for (final t in TextEditorTab.values)
        GestureDetector(onTap: () => setState(() => _tab = t),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: _tab == t ? AyatColors.gold.withValues(alpha: .18) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _tab == t ? AyatColors.gold : Colors.transparent)),
            child: Text(_kTabLabelsAr[t]!, style: TextStyle(
              fontSize: 12, letterSpacing: 1,
              color: _tab == t ? AyatColors.goldBright : AyatColors.goldDim))))]));

  Widget _body() => switch (_tab) {
    TextEditorTab.text => _text(), TextEditorTab.border => _border(),
    TextEditorTab.shadow => _shadow(), TextEditorTab.glow => _glow(),
    TextEditorTab.label => _label(), TextEditorTab.opacity => _opacity()};

  // ── TEXT ──
  Widget _text() => SingleChildScrollView(child: Column(children: [
    Wrap(spacing: 8, runSpacing: 8, children: [
      for (final f in _fonts) _chip(f.$2, f.$1, s.fontKey == f.$1,
          () => s.update(() => s.fontKey = f.$1)),
      _chip('خط قرآني', 'amiri_quran', s.fontKey == 'amiri_quran',
          () => s.update(() => s.fontKey = 'amiri_quran')),
      // PATCH_S129_WIRE_AND_SIMPLIFY_UI: was hardcoded to onPressed: null
      ActionChip(avatar: const Icon(Icons.add, size: 14),
        label: Text(AppStrings(AppSettings.instance.lang).t('textEditorPro.addFont')),
        onPressed: widget.onPickCustomFont)]),

    _slider('الحجم', s.ayahFontSize, 14, 30, 0,
        (v) => s.update(() => s.ayahFontSize = v)),
    _slider('تباعد الأحرف', s.letterSpacing, 0, 12, 0,
        (v) => s.update(() => s.letterSpacing = v)),
    SwitchListTile(
      title: Text(AppStrings(AppSettings.instance.lang).t('textEditorPro.unifiedLineForAllAyat'),
          style: const TextStyle(fontSize: 13)),
      subtitle: Text(_unifiedHint(), style: const TextStyle(fontSize: 11)),
      value: s.unifiedOneLine, activeColor: AyatColors.gold,
      onChanged: (v) => s.update(() => s.unifiedOneLine = v)),
    _colorArea(),
    Row(children: [
      Expanded(child: OutlinedButton.icon(
        onPressed: s.saveStyleAsDefault,
        icon: const Icon(Icons.save_outlined, size: 16),
        label: Text(AppStrings(AppSettings.instance.lang).t('textEditorPro.saveAsDefaultShape')))),
      const SizedBox(width: 8),
      Expanded(child: Text(
        AppStrings(AppSettings.instance.lang).t('textEditorPro.currentShapeAppliesNote'),
        style: TextStyle(fontSize: 10, color: AyatColors.goldDim)))]),
  ]));

  String _unifiedHint() {
    if (!s.unifiedOneLine) return 'اجعل كل الآيات سطرًا واحدًا بنفس الحجم المشترك';
    final u = _computeUnified();
    return u == null ? 'أضف آيات أولًا ليُحسب الحجم المشترك'
                     : 'الحجم المشترك المحسوب: ${u.toInt()}';
  }
  double? _computeUnified() {
    if (widget.segmentTexts.isEmpty) return null;
    double fit(String t) {
      var lo = 20.0, hi = 140.0;
      for (var i = 0; i < 14; i++) {
        final mid = (lo + hi) / 2;
        final tp = TextPainter(text: TextSpan(text: t,
            style: TextStyle(fontSize: mid)), textDirection: TextDirection.rtl)
          ..layout();
        if (tp.width > widget.canvasWidth * 0.92) hi = mid; else lo = mid;
      }
      return lo;
    }
    return widget.segmentTexts.map(fit).reduce((a, b) => a < b ? a : b);
  }

  Widget _colorArea() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      GestureDetector(onTap: _pickColor, child: Container(width: 150, height: 90,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
          gradient: const LinearGradient(colors: [Color(0xFFFF0000), Color(0xFF00FF00),
            Color(0xFF0000FF)]), border: Border.all(color: AyatColors.goldDim)))),
      const SizedBox(width: 10),
      Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in s.favoriteColors) GestureDetector(
          onTap: () => s.update(() => s.textColor = f),
          onLongPress: () => s.update(() => s.favoriteColors.remove(f)),
          child: _swatch(f)),
        GestureDetector(onTap: () => s.update(
            () => s.favoriteColors.add(s.textColor)),
          child: Container(width: 34, height: 26, alignment: Alignment.center,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AyatColors.goldDim)),
            child: const Icon(Icons.add, size: 14)))]))]),
    const SizedBox(height: 8),
    Text(AppStrings(AppSettings.instance.lang).t('textEditorPro.quickColors'),
        style: TextStyle(fontSize: 11, color: AyatColors.goldDim)),
    Wrap(spacing: 8, runSpacing: 6,
      children: [for (final q in _quick)
        GestureDetector(onTap: () => s.update(() => s.textColor = q),
          child: _swatch(q))]),
  ]);
  Widget _swatch(Color c) => Container(width: 34, height: 26, margin: const EdgeInsets.all(2),
    decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(6),
      border: Border.all(color: c == s.textColor ? AyatColors.goldBright : Colors.black26,
        width: c == s.textColor ? 2 : 1)));
  void _pickColor() async {
    // Uses the app's showAyatColorPicker (lib/widgets/color_picker_dialog.dart).
    // Import is soft-wired by home_screen; fall back to a simple dialog if missing.
    try {
      // ignore: undefined_function
      final c = await showAyatColorPicker(context, s.textColor);
      if (c != null) s.update(() => s.textColor = c);
    } catch (_) {
      /* color picker not imported yet — no-op */
    }
  }

  // ── BORDER / SHADOW / GLOW / LABEL / OPACITY ──
  Widget _border() => _card('الحد', Icons.border_style, s.textBorderEnabled,
    (v) => s.update(() => s.textBorderEnabled = v), [
    _slider('السمك', s.textBorderWidth, 1, 20, 0, (v) => s.update(() => s.textBorderWidth = v))]);
  Widget _shadow() => _card('الظل', Icons.filter_frames, s.shadowEnabled,
    (v) => s.update(() => s.shadowEnabled = v), [
    _slider('المسافة', s.shadowDistance, 0, 40, 0, (v) => s.update(() => s.shadowDistance = v)),
    _slider('الضبابية', s.shadowBlur, 0, 60, 0, (v) => s.update(() => s.shadowBlur = v))]);
  // PATCH_S145_GLOW_KARAOKE_SETTINGS: the on/off switch this card
  // already had (s.glowEnabled) was real and correctly wired -- but the
  // two sliders under it (glowSize/glowSharpness) were never read by
  // either the live stage or the export renderer, so moving them did
  // nothing. The one field that actually controls how strong the glow
  // looks (glowIntensity, 0..1.5, used for both the plain-text glow and
  // the karaoke lit-word glow while الشيخ is reciting) now has the real
  // slider. The second switch below restores "تظليل الكلمات مع التلاوة
  // (كاريوكي)" -- on/off for the word-by-word lighting itself, not just
  // its glow -- which used to live in the now-orphaned old _textPanel()
  // and has had no reachable control anywhere since PATCH_S128 replaced
  // that screen with this one.
  Widget _glow() => _card('التوهج', Icons.wb_sunny_outlined, s.glowEnabled,
    (v) => s.update(() => s.glowEnabled = v), [
    _slider('شدّة التوهّج', s.glowIntensity, 0, 1.5, 2,
        (v) => s.update(() => s.glowIntensity = v)),
    const SizedBox(height: 6),
    SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('تظليل الكلمات مع التلاوة (كاريوكي)',
          style: TextStyle(fontSize: 13)),
      subtitle: const Text(
          'عند الإيقاف: تُعرض الآية كاملة دون إضاءة كل كلمة على حدة',
          style: TextStyle(fontSize: 11)),
      value: s.karaokeEnabled,
      activeColor: AyatColors.gold,
      onChanged: (v) => s.update(() => s.karaokeEnabled = v),
    ),
  ]);
  Widget _label() => _card('الخلفية (Label)', Icons.label_outline, s.labelEnabled,
    (v) => s.update(() => s.labelEnabled = v), [
    Row(children: [for (final sh in S128LabelShape.values)
      GestureDetector(onTap: () => s.update(() => s.labelShape = sh),
        child: Container(width: 40, height: 30, margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: s.labelShape == sh ? AyatColors.gold.withValues(alpha: .25) : Colors.transparent,
            border: Border.all(color: s.labelShape == sh ? AyatColors.gold : AyatColors.goldDim),
            borderRadius: sh == S128LabelShape.rounded ? BorderRadius.circular(8)
              : sh == S128LabelShape.circle ? BorderRadius.circular(15)
              : sh == S128LabelShape.pill ? BorderRadius.circular(15) : BorderRadius.circular(4)),
          alignment: Alignment.center,
          child: Text(sh.name[0], style: const TextStyle(fontSize: 10))))]),
    _slider('الشفافية', s.labelOpacity, 0, 100, 0,
        (v) => s.update(() => s.labelOpacity = v / 100))]);
  Widget _opacity() => _slider('الشفافية العامة', s.overallOpacity * 100, 10, 100, 0,
      (v) => s.update(() => s.overallOpacity = v / 100));

  Widget _card(String t, IconData ic, bool on, ValueChanged<bool> set,
      List<Widget> body) =>
    Container(margin: const EdgeInsets.all(8), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: AyatColors.surface,
        borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        SwitchListTile(title: Row(children: [Icon(ic, size: 18, color: AyatColors.gold),
          const SizedBox(width: 8), Text(t, style: const TextStyle(fontSize: 14))]),
          value: on, activeColor: AyatColors.gold, onChanged: set),
        if (on) ...body]));

  Widget _slider(String t, double v, double mn, double mx, int dp,
          ValueChanged<double> set) =>
    Row(children: [SizedBox(width: 76, child: Text(t,
        style: TextStyle(fontSize: 12, color: AyatColors.goldDim))),
      Expanded(child: Slider(activeColor: AyatColors.gold, value: v,
        min: mn, max: mx, onChanged: set)),
      SizedBox(width: 40, child: Text(dp == 0 ? v.toInt().toString() : v.toStringAsFixed(dp),
        style: const TextStyle(fontSize: 12)))]);

  // PATCH_S145_FONT_BUTTONS_REAL_FONTS: each button now previews its
  // own actual font (via the same ayahTextStyle() the live stage and
  // the exporter use) instead of every label rendering in one shared
  // generic style regardless of which font it names -- and a touch
  // roomier so the preview is actually legible.
  Widget _chip(String label, String fontKey, bool sel, VoidCallback on) =>
      ChoiceChip(
        label: Text(label, style: ayahTextStyle(fontKey, fontSize: 15)),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        selected: sel,
        onSelected: (_) => on(),
      );
}

// Shared painter so PREVIEW and EXPORT draw the label identically
// (Preview = Export rule).
void paintLabel(Canvas canvas, Rect r, StudioState s) {
  if (!s.labelEnabled) return;
  final p = Paint()..color = s.labelColor.withValues(alpha: s.labelOpacity);
  final rr = r.inflate(14);
  switch (s.labelShape) {
    case S128LabelShape.rounded: canvas.drawRRect(
        RRect.fromRectAndRadius(rr, const Radius.circular(10)), p); break;
    case S128LabelShape.circle: canvas.drawOval(rr, p); break;
    case S128LabelShape.pill: canvas.drawRRect(
        RRect.fromRectAndRadius(rr, Radius.circular(rr.height / 2)), p); break;
    case S128LabelShape.scallop: case S128LabelShape.hexagon:
      canvas.drawRRect(RRect.fromRectAndRadius(rr, const Radius.circular(6)), p); break;
  }
}
