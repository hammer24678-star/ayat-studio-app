// Preset data ported 1:1 from the HTML prototype (ayat_studio225.html):
// canvas background gradients (BG_CANVAS_DEFS), text templates (TEMPLATES),
// text color dots (COLORS) and reciter slot names (RECITERS).
import 'package:flutter/material.dart';

enum AyahTextPosition { top, center, bottom }

enum FrameExtra { none, boxed, framed }

class BgDef {
  final bool radial;
  final List<Color> stops;
  const BgDef({this.radial = false, required this.stops});

  Gradient get gradient => radial
      ? RadialGradient(
          center: const Alignment(-0.4, -0.6),
          radius: 1.2,
          colors: stops,
        )
      : LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: stops,
        );
}

const List<BgDef> kBackgrounds = [
  BgDef(stops: [Color(0xFF0F2B26), Color(0xFF1E4B3F), Color(0xFF173A30)]),
  BgDef(stops: [Color(0xFF241407), Color(0xFF5C2430), Color(0xFF3A1A20)]),
  BgDef(stops: [Color(0xFF0B1424), Color(0xFF1B3A63), Color(0xFF152D4D)]),
  BgDef(stops: [Color(0xFF180F1C), Color(0xFF3B2140), Color(0xFF2A1830)]),
  BgDef(stops: [Color(0xFF161005), Color(0xFF4A3A10), Color(0xFF332809)]),
  BgDef(radial: true, stops: [Color(0xFF233A34), Color(0xFF050F0D)]),
  BgDef(stops: [Color(0xFF1C1C1C), Color(0xFF050505), Color(0xFF111111)]),
  BgDef(stops: [Color(0xFF0E1E1A), Color(0xFF1E4B3F), Color(0xFF1B3A63)]),
];

/// Registered font choices for the ayah text. `family` is what actually gets
/// handed to TextStyle.fontFamily; the two built-ins resolve through
/// google_fonts, uploaded fonts through FontLoader (see StudioState).
class AyahFontChoice {
  final String label;
  final String key; // 'amiri' | 'ruqaa' | custom family name
  const AyahFontChoice(this.key, this.label);
}

const List<AyahFontChoice> kBuiltInFonts = [
  AyahFontChoice('amiri', 'أميري قرآن (كلاسيكي)'),
  AyahFontChoice('ruqaa', 'ريقعة (خط الرقعة)'),
];

class AyahTemplate {
  final String name;
  final String desc;
  final AyahTextPosition pos;
  final FrameExtra extra;
  final String fontKey;
  final Color color;
  const AyahTemplate({
    required this.name,
    required this.desc,
    required this.pos,
    required this.extra,
    required this.fontKey,
    required this.color,
  });
}

const List<AyahTemplate> kTemplates = [
  AyahTemplate(
      name: 'سطر سفلي كلاسيكي',
      desc: 'الآية أسفل الشاشة، ترجمة تحتها',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.none,
      fontKey: 'amiri',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'توسّط ذهبي',
      desc: 'الآية في المنتصف بلون ذهبي',
      pos: AyahTextPosition.center,
      extra: FrameExtra.none,
      fontKey: 'amiri',
      color: Color(0xFFECC875)),
  AyahTemplate(
      name: 'عنوان رقعة علوي',
      desc: 'خط الرقعة أعلى الشاشة',
      pos: AyahTextPosition.top,
      extra: FrameExtra.none,
      fontKey: 'ruqaa',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'بساطة بيضاء',
      desc: 'نص أبيض واضح للقراءة السريعة',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.none,
      fontKey: 'amiri',
      color: Color(0xFFFFFFFF)),
  AyahTemplate(
      name: 'لوحة زجاجية سفلية',
      desc: 'نص داخل لوحة شبه شفافة أسفل الشاشة',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.boxed,
      fontKey: 'amiri',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'إطار ذهبي متوسط',
      desc: 'نص داخل إطار مذهّب في المنتصف',
      pos: AyahTextPosition.center,
      extra: FrameExtra.framed,
      fontKey: 'ruqaa',
      color: Color(0xFFECC875)),
];

const List<Color> kTextColors = [
  Color(0xFFECE2CB),
  Color(0xFFECC875),
  Color(0xFFFFFFFF),
  Color(0xFF8FBBAF),
  Color(0xFFC9A24B),
  Color(0xFFE8D5A8),
  Color(0xFF7FA88F),
  Color(0xFFA8C5D6),
  Color(0xFFD9A5B0),
  Color(0xFFF2F2F2),
];

const List<String> kReciters = [
  'الشيخ الدوسري',
  'مشاري العفاسي',
  'عبدالباسط عبدالصمد',
  'ماهر المعيقلي',
  'ياسر الدوسري',
  'سعود الشريم',
];

const String kBasmala = 'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ';
const String kDefaultOutro = 'صدق الله العظيم';
