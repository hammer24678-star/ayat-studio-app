import 'package:flutter/material.dart';
import '../data/studio_presets.dart';
import '../services/ayah_matcher.dart';

/// Reveals [text] word-by-word for the typewriter effect. Word units look
/// far better for Arabic than character slicing: with character slicing the
/// glyphs of the growing word keep reshaping (connected forms change as
/// letters arrive), which reads as flicker; whole words land fully shaped.
String revealWordsByFraction(String text, double frac) {
  if (frac >= 1) return text;
  if (frac <= 0) return '';
  final words = text.split(' ');
  final count = (words.length * frac).ceil().clamp(0, words.length);
  return words.take(count).join(' ');
}

/// One detected span of the auto-sync timeline: [ayah] was heard between
/// [start] and [end] (seconds into the uploaded clip).
class TimelineSegment {
  double start;
  double end;
  final Ayah ayah;
  double confidence;
  TimelineSegment({
    required this.start,
    required this.end,
    required this.ayah,
    required this.confidence,
  });
}

/// Central mutable app state — the Flutter counterpart of the HTML
/// prototype's single `state` object. Everything the stage preview and the
/// exporter read lives here so they can never disagree.
class StudioState extends ChangeNotifier {
  // ---- corpus ----
  List<Ayah> ayaat = [];
  AyahMatcher? matcher;
  String corpusStatus = 'جارٍ تحميل القرآن الكريم كاملاً…';

  // ---- currently displayed ayah ----
  String ayahText = '';
  String translationText = '';
  String ayahReference = ''; // e.g. «سورة الرحمن — آية ١٣», shown on-canvas
  String detectedLabel = '';
  String matchConfidenceText = '';
  bool get hasAyah => ayahText.isNotEmpty;

  // ---- uploaded media ----
  String? videoPath;
  bool get hasVideo => videoPath != null;

  // ---- background ----
  int bgIndex = 0;
  bool useCustomBg = false;
  String? customBgPath;

  // ---- chroma key ----
  bool chromaEnabled = false;
  Color chromaColor = const Color(0xFF00FF00);
  int chromaThreshold = 90; // same 40..140 scale as the HTML sliders
  int chromaSoftness = 45; // 10..90

  // ---- reciters ----
  int reciterIndex = 0;
  final List<String?> reciterAudioPaths = List.filled(kReciters.length, null);
  String? get selectedReciterAudio => reciterAudioPaths[reciterIndex];

  // ---- text formatting ----
  int templateIndex = 0;
  String fontKey = 'amiri';
  final List<AyahFontChoice> customFonts = [];
  double ayahFontSize = 20; // 14..30, preview-relative like the HTML slider
  double transFontSize = 12; // 9..18
  Color textColor = const Color(0xFFECE2CB);
  AyahTextPosition textPosition = AyahTextPosition.bottom;
  FrameExtra extra = FrameExtra.none;
  bool showTranslation = true;

  // ---- intro / outro cards ----
  bool showIntro = false;
  bool showOutro = false;
  String outroText = kDefaultOutro;

  // ---- auto-sync timeline ----
  List<TimelineSegment> timeline = [];
  bool timelineActive = false;

  // ---- trim (ayah-boundary indexes into [timeline], -1 = whole clip) ----
  int trimFromIndex = -1;
  int trimToIndex = -1;
  double? get trimStart =>
      (trimFromIndex >= 0 && trimToIndex >= 0) ? timeline[trimFromIndex].start : null;
  double? get trimEnd =>
      (trimFromIndex >= 0 && trimToIndex >= 0) ? timeline[trimToIndex].end : null;

  // ---- output ----
  bool squareRatio = false; // false = 9:16, true = 1:1
  int staticDurationSec = 6; // export length when no video is loaded (2..60)

  List<AyahFontChoice> get allFonts => [...kBuiltInFonts, ...customFonts];

  void setAyah(String ar, String en, String label,
      {String confidenceText = '', String reference = ''}) {
    ayahText = ar;
    translationText = en;
    detectedLabel = label;
    ayahReference = reference;
    matchConfidenceText = confidenceText;
    notifyListeners();
  }

  void setVideo(String path) {
    videoPath = path;
    // A new video invalidates any previously detected timeline/trim range.
    timeline = [];
    timelineActive = false;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
  }

  void setTimeline(List<TimelineSegment> segments) {
    timeline = segments;
    timelineActive = segments.isNotEmpty;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
  }

  void applyTemplate(int index) {
    templateIndex = index;
    final t = kTemplates[index];
    fontKey = t.fontKey;
    textColor = t.color;
    textPosition = t.pos;
    extra = t.extra;
    notifyListeners();
  }

  void update(void Function() mutate) {
    mutate();
    notifyListeners();
  }
}
