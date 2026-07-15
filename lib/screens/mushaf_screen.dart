// PATCH_S74_MUSHAF_UI_POLISH
import 'dart:math'; // PATCH_S111_MUSHAF_AYAH_ROSETTE: cos/sin/pi for petal layout
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart'; // PATCH_S108_MUSHAF_AYAH_ORNAMENT_REDESIGN

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

// PATCH_S108_MUSHAF_AYAH_ORNAMENT_REDESIGN: Eastern Arabic-Indic digits
// (٠١٢٣٤٥٦٧٨٩) for the ayah-end ornament, matching printed mushaf
// convention instead of Western digits.
const _kEasternArabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
String _easternArabicNumeral(int n) =>
    n.toString().split('').map((d) => _kEasternArabicDigits[int.parse(d)]).join();

// PATCH_S112_MUSHAF_AYAH_ROSETTE_FIX: matches a real printed-mushaf
// ayah-stop -- a single thin scalloped ring (one continuous outline, not
// a cluster of filled circles), left UNFILLED so the digit sits directly
// on the page and stays legible, drawn in the app's gold-on-ink palette.
Widget _ayahRosetteOrnament(int num, {double size = 26}) {
  return SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: const _AyahRosettePainter(),
        ),
        Text(
          _easternArabicNumeral(num),
          style: GoogleFonts.amiriQuran(
            textStyle: const TextStyle(
              color: AyatColors.goldBright,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
      ],
    ),
  );
}

class _AyahRosettePainter extends CustomPainter {
  const _AyahRosettePainter();

  static const _teeth = 10;

  Path _scallopedRing(Offset center, double baseR, double bumpR) {
    final path = Path();
    const step = 2 * pi / _teeth;
    for (var i = 0; i <= _teeth; i++) {
      final angle = i * step;
      final midAngle = angle - step / 2;
      final outerPt = center + Offset(cos(angle), sin(angle)) * baseR;
      final bumpPt = center + Offset(cos(midAngle), sin(midAngle)) * bumpR;
      if (i == 0) {
        path.moveTo(outerPt.dx, outerPt.dy);
      } else {
        path.quadraticBezierTo(bumpPt.dx, bumpPt.dy, outerPt.dx, outerPt.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * 0.30;
    final bumpR = size.width * 0.5;

    final ring = _scallopedRing(center, baseR, bumpR);

    // Left unfilled -- the digit reads straight off the paragraph
    // background inside the ring, exactly like the printed page.
    canvas.drawPath(
      ring,
      Paint()
        ..color = AyatColors.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );

    // Faint inner circle, echoing the thin double-ring on printed
    // ayah-stop marks, still fully see-through.
    canvas.drawCircle(
      center,
      baseR * 0.82,
      Paint()
        ..color = AyatColors.goldDim.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
        iconTheme: const IconThemeData(color: AyatColors.gold),
        actionsIconTheme: const IconThemeData(color: AyatColors.gold),
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
            // PATCH_S74_MUSHAF_UI_POLISH: bordered pill matching the app's
            // card/chip language instead of the bare default dropdown.
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: AyatColors.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AyatColors.hairline),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _surah,
                  dropdownColor: AyatColors.surface2,
                  iconEnabledColor: AyatColors.gold,
                  style: const TextStyle(color: AyatColors.parchment),
                  items: [
                    for (final s in _surahs)
                      DropdownMenuItem(
                          value: s.$1, child: Text('سورة ${s.$2}')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _surah = v);
                  },
                ),
              ),
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
                        // PATCH_S74_MUSHAF_UI_POLISH: soft-bordered "page" panel around the
                        // ayah text, matching the surah-name card above it, instead of the
                        // text sitting bare on the ink background.
                        Container(
                          padding: const EdgeInsets.fromLTRB(18, 22, 18, 26),
                          decoration: BoxDecoration(
                            color: AyatColors.surface.withValues(alpha: 0.55),
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: AyatColors.hairline),
                          ),
                          child: Directionality(
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
                                    // PATCH_S74_MUSHAF_UI_POLISH: bumped 22->24pt and 1.8->2.0
                                    // line-height, added slight letter-spacing, for readability.
                                    style: ayahTextStyle(
                                      widget.fontKey,
                                      fontSize: 24,
                                      height: 2.0,
                                      color: AyatColors.parchment,
                                    ).copyWith(letterSpacing: 0.2),
                                  ),
                                  WidgetSpan(
                                    alignment: PlaceholderAlignment.middle,
                                    // PATCH_S111_MUSHAF_AYAH_ROSETTE: traditional
                                    // 8-petal flower/rosette ayah-end ornament,
                                    // like a real printed mushaf, redrawn in the
                                    // app's own gold-on-ink palette. Replaces the
                                    // S108 flat gradient circle.
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(horizontal: 5),
                                      child: _ayahRosetteOrnament(a.num),
                                    ),
                                  ),
                                  const TextSpan(text: '  '),
                                ],
                              ],
                            ),
                            textAlign: TextAlign.justify,
                          ),
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
