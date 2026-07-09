import 'package:flutter/material.dart';

import '../services/ayah_matcher.dart';
import '../theme/ayat_theme.dart';
import '../theme/ayat_fonts.dart'; // PATCH_S63_MUSHAF_FONT_FIX

// PATCH_S62_MUSHAF_READER: standalone full mushaf reading screen. Browse any surah and
// read it in full, completely separate from the video-editing workflow.
// Reuses the Ayah list already loaded once at startup -- no extra load.
class MushafScreen extends StatefulWidget {
  final List<Ayah> ayaat;
  final int initialSurah;
  final String fontKey; // PATCH_S63_MUSHAF_FONT_FIX: read the user's chosen ayah font

  const MushafScreen({
    super.key,
    required this.ayaat,
    required this.fontKey,
    this.initialSurah = 1,
  });

  @override
  State<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends State<MushafScreen> {
  late int _surah;
  late final List<(int, String)> _surahs;

  @override
  void initState() {
    super.initState();
    _surahs = <(int, String)>[];
    var last = 0;
    for (final a in widget.ayaat) {
      if (a.surahNum != last) {
        _surahs.add((a.surahNum, a.surah));
        last = a.surahNum;
      }
    }
    _surah = _surahs.any((s) => s.$1 == widget.initialSurah)
        ? widget.initialSurah
        : (_surahs.isEmpty ? 1 : _surahs.first.$1);
  }

  void _go(int delta) {
    final i = _surahs.indexWhere((s) => s.$1 == _surah);
    if (i < 0) return;
    final ni = i + delta;
    if (ni < 0 || ni >= _surahs.length) return;
    setState(() => _surah = _surahs[ni].$1);
  }

  @override
  Widget build(BuildContext context) {
    final ayat = widget.ayaat.where((a) => a.surahNum == _surah).toList();
    final name = _surahs
        .firstWhere((s) => s.$1 == _surah, orElse: () => (_surah, ''))
        .$2;

    return Scaffold(
      backgroundColor: AyatColors.ink,
      appBar: AppBar(
        title: const Text('المصحف'),
        actions: [
          IconButton(
            tooltip: 'السورة التالية',
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _go(1),
          ),
          IconButton(
            tooltip: 'السورة السابقة',
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _go(-1),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: DropdownButton<int>(
              isExpanded: true,
              value: _surah,
              items: [
                for (final s in _surahs)
                  DropdownMenuItem(value: s.$1, child: Text('سورة ${s.$2}')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _surah = v);
              },
            ),
          ),
          Expanded(
            child: ayat.isEmpty
                ? const Center(child: Text('تعذّر تحميل نص هذه السورة'))
                : SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 18),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            border: Border.all(color: AyatColors.hairline),
                            borderRadius: BorderRadius.circular(14),
                            color: AyatColors.surface2,
                          ),
                          alignment: Alignment.center,
                          child: Text('سورة $name',
                              style: Theme.of(context).textTheme.headlineLarge),
                        ),
                        Directionality(
                          textDirection: TextDirection.rtl,
                          child: Text.rich(
                            TextSpan(
                              children: [
                                for (final a in ayat) ...[
                                  TextSpan(
                                    text: '${a.ar} ',
                                    // PATCH_S63_MUSHAF_FONT_FIX: was Theme.of(context).textTheme.displayLarge
                                    // (hardcoded Amiri Quran) -- now respects the font picked
                                    // under 'خط الآية', same as the editor/export preview.
                                    style: ayahTextStyle(
                                      widget.fontKey,
                                      fontSize: 22,
                                      height: 1.8,
                                      color: AyatColors.parchment,
                                    ),
                                  ),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 3),
                                      width: 26,
                                      height: 26,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: AyatColors.gold, width: 1.2),
                                      ),
                                      child: Text(
                                        '${a.num}',
                                        style: const TextStyle(
                                          color: AyatColors.goldBright,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const TextSpan(text: '  '),
                                ],
                              ],
                            ),
                            textAlign: TextAlign.justify,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
