// PATCH_S125_SEQUENCE: the studio works on one clip. This is where several
// become one — pick clips, trim each, order them, choose how they join, and
// render the result into a single file that then becomes the working clip.
//
// Deliberately a pre-pass and not a timeline UI: everything downstream
// (auto-sync, the ayah overlay, effects, export) keeps seeing exactly what it
// saw before — one source — so none of it had to change or be re-tested.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_settings.dart';
import '../services/media_service.dart';
import '../theme/ayat_theme.dart';
import '../widgets/motion.dart';

class SequenceScreen extends StatefulWidget {
  /// The clip already loaded in the studio, if any — it seeds the sequence so
  /// the common case is "add another one after what I already have".
  final String? initialClipPath;
  final int frameWidth;
  final int frameHeight;

  const SequenceScreen({
    super.key,
    this.initialClipPath,
    this.frameWidth = 1080,
    this.frameHeight = 1920,
  });

  @override
  State<SequenceScreen> createState() => _SequenceScreenState();
}

class _SequenceScreenState extends State<SequenceScreen> {
  final List<SequenceClip> _clips = [];
  SequenceTransition _transition = SequenceTransition.cut;
  double _transitionSec = 0.5;
  bool _busy = false;
  String _status = '';

  @override
  void initState() {
    super.initState();
    final seed = widget.initialClipPath;
    if (seed != null) _addPath(seed);
  }

  Future<void> _addPath(String path) async {
    // A clip whose length we can't read can't be trimmed or offset, so probe
    // first and fall back to a sane default rather than a zero-length clip
    // that would silently vanish from the render.
    final probed = await MediaService.probedDurationSec(path);
    if (!mounted) return;
    setState(() {
      _clips.add(SequenceClip(
        path: path,
        duration: (probed ?? 5).clamp(0.3, 3600),
      ));
    });
  }

  Future<void> _pick() async {
    final res = await FilePicker.platform
        .pickFiles(type: FileType.video, allowMultiple: true);
    if (res == null) return;
    for (final f in res.files) {
      final p = f.path;
      if (p != null) await _addPath(p);
    }
  }

  Future<void> _render() async {
    if (_clips.length < 2) return;
    setState(() {
      _busy = true;
      _status = 'جارٍ تركيب المقاطع… قد يستغرق هذا وقتًا حسب الطول والعدد.';
    });
    try {
      final out = await MediaService.renderSequence(
        _clips,
        width: widget.frameWidth,
        height: widget.frameHeight,
        transition: _transition,
        transitionSec: _transitionSec,
      );
      if (!mounted) return;
      Navigator.pop(context, out);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = '$e';
      });
    }
  }

  String _fmt(double sec) {
    final m = sec ~/ 60;
    final s = (sec % 60).toStringAsFixed(1);
    return m > 0 ? '${m}د ${s}ث' : '${s}ث';
  }

  @override
  Widget build(BuildContext context) {
    final total = MediaService.sequenceDuration(
      _clips,
      transition: _transition,
      transitionSec: _transitionSec,
    );
    return Scaffold(
      backgroundColor: AyatColors.ink,
      appBar: AppBar(
        title: const Text('تركيب عدة مقاطع'),
        iconTheme: const IconThemeData(color: AyatColors.gold),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'أضيفي مقاطع بالترتيب الذي تريدينه، وقصّي كل واحد على حدة، '
                'واختاري طريقة الانتقال بينها. النتيجة ملف واحد يصبح هو مقطع '
                'الاستوديو — فتعمل عليه المزامنة التلقائية والتأثيرات والتصدير '
                'كالمعتاد.',
                style: GoogleFonts.tajawal(
                    color: AyatColors.parchmentDim, fontSize: 12, height: 1.7),
              ),
            ),
            Expanded(
              child: _clips.isEmpty
                  ? Center(
                      child: Text('لم تتم إضافة أي مقطع بعد',
                          style: GoogleFonts.tajawal(
                              color: AyatColors.parchmentDim)),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: _clips.length,
                      // onReorderItem, not the deprecated onReorder: the new
                      // callback already accounts for the item having been
                      // lifted out at oldIndex, so no off-by-one adjustment
                      // is needed here (and doing it anyway would move a
                      // downward drag one slot too far).
                      onReorderItem: (from, to) => setState(() {
                        _clips.insert(to, _clips.removeAt(from));
                      }),
                      itemBuilder: (context, i) => _clipCard(i),
                    ),
            ),
            _footer(total),
          ],
        ),
      ),
    );
  }

  Widget _clipCard(int i) {
    final c = _clips[i];
    final name = c.path.split('/').last;
    return Padding(
      key: ValueKey('${c.path}#$i'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: AyatColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AyatColors.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                      color: AyatColors.gold, shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: const TextStyle(
                          color: AyatColors.ink,
                          fontSize: 12,
                          fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.tajawal(
                        color: AyatColors.parchment, fontSize: 12.5),
                  ),
                ),
                IconButton(
                  tooltip: 'إزالة',
                  icon: const Icon(Icons.delete_outline,
                      color: AyatColors.parchmentDim, size: 20),
                  onPressed: () => setState(() => _clips.removeAt(i)),
                ),
                const Icon(Icons.drag_handle, color: AyatColors.gold),
              ],
            ),
            const SizedBox(height: 6),
            Text('يبدأ عند ${_fmt(c.start)} · المدة ${_fmt(c.duration)}',
                style: GoogleFonts.tajawal(
                    color: AyatColors.parchmentDim, fontSize: 11)),
            Row(
              children: [
                Expanded(
                  child: _trimField(
                    label: 'بداية (ث)',
                    value: c.start,
                    onChanged: (v) => setState(
                        () => _clips[i] = c.copyWith(start: v.clamp(0, 36000))),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _trimField(
                    label: 'مدة (ث)',
                    value: c.duration,
                    onChanged: (v) => setState(() =>
                        _clips[i] = c.copyWith(duration: v.clamp(0.3, 3600))),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _trimField({
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return TextFormField(
      initialValue: value.toStringAsFixed(1),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: AyatColors.parchment, fontSize: 13),
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (v) {
        final parsed = double.tryParse(v);
        if (parsed != null) onChanged(parsed);
      },
    );
  }

  Widget _footer(double total) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AyatColors.surface,
        border: Border(top: BorderSide(color: AyatColors.hairline)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_clips.length >= 2) ...[
            Text('الانتقال بين المقاطع',
                style: GoogleFonts.tajawal(
                    color: AyatColors.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in SequenceTransition.values)
                  ChoiceChip(
                    label: Text(t.labelAr),
                    selected: _transition == t,
                    onSelected: (_) => setState(() => _transition = t),
                  ),
              ],
            ),
            if (_transition != SequenceTransition.cut) ...[
              const SizedBox(height: 4),
              Text('مدة الانتقال: ${_transitionSec.toStringAsFixed(1)}ث',
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchmentDim, fontSize: 11.5)),
              Slider(
                value: _transitionSec,
                min: 0.2,
                max: 2.0,
                divisions: 18,
                onChanged: (v) => setState(() => _transitionSec = v),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              'الطول النهائي التقريبي: ${_fmt(total)}'
              '${_transition != SequenceTransition.cut ? ' (كل انتقال يقصّر الناتج بمقدار مدته)' : ''}',
              style: GoogleFonts.tajawal(
                  color: AyatColors.parchmentDim, fontSize: 11.5),
            ),
            const SizedBox(height: 10),
          ],
          if (_status.isNotEmpty) ...[
            Text(_status,
                style: GoogleFonts.tajawal(
                    color: AyatColors.goldBright, fontSize: 11.5, height: 1.6)),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _pick,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('إضافة مقاطع'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: PressableScale(
                  onTap: (_busy || _clips.length < 2) ? null : _render,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: (_busy || _clips.length < 2)
                          ? AyatColors.surface2
                          : AyatColors.gold.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: (_busy || _clips.length < 2)
                            ? AyatColors.hairline
                            : AyatColors.gold,
                      ),
                    ),
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AyatColors.goldBright),
                          )
                        : Text(
                            'تركيب المقاطع',
                            style: GoogleFonts.tajawal(
                              color: _clips.length < 2
                                  ? AyatColors.parchmentDim
                                  : AyatColors.goldBright,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (_clips.length < 2)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('أضيفي مقطعين على الأقل للتركيب.',
                  style: GoogleFonts.tajawal(
                      color: AyatColors.parchmentDim, fontSize: 11.5)),
            ),
        ],
      ),
    );
  }
}

/// Opens the sequence builder and returns the rendered file, or null.
Future<String?> openSequenceBuilder(
  BuildContext context, {
  String? initialClipPath,
  int frameWidth = 1080,
  int frameHeight = 1920,
}) {
  // Route direction follows the app language like every other push.
  AppSettings.instance.textDirection;
  return Navigator.of(context).push<String>(
    AppMotion.route(SequenceScreen(
      initialClipPath: initialClipPath,
      frameWidth: frameWidth,
      frameHeight: frameHeight,
    )),
  );
}
