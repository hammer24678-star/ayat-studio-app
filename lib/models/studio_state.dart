import 'package:flutter/material.dart';
import '../data/studio_presets.dart';
import '../services/ayah_matcher.dart';
import '../services/ai_art_service.dart'; // PATCH_S32_AI_ART_NANO_BANANA
import '../services/stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS

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
  String detectedLabel = '';
  String matchConfidenceText = '';
  bool get hasAyah => ayahText.isNotEmpty;

  // ---- uploaded media ----
  String? videoPath;
  bool get hasVideo => videoPath != null;
  // PATCH_S34_PLAYER_CONTROLS_TRIM: known once the preview player initializes;
  // drives the seek bar and the manual-cut range slider.
  double videoDurationSec = 0;

  // ---- PATCH_S34_STAGE_EFFECTS: decorative particle overlay ----
  StageEffect effect = StageEffect.none;
  double effectIntensity = 0.7; // 0.2..1.0

  // ---- PATCH_S34_PLAYER_CONTROLS_TRIM: manual cut (seconds, free-range) ----
  // Unlike the ayah-boundary trim below, this cuts anywhere. -1 end = unset.
  double trimManualStart = 0;
  double trimManualEnd = -1;
  bool get manualTrimSet =>
      hasVideo &&
      trimManualEnd > 0 &&
      (trimManualStart > 0.05 ||
          (videoDurationSec > 0 && trimManualEnd < videoDurationSec - 0.05));

  // ---- background ----
  int bgIndex = 0;
  bool useCustomBg = false;
  String? customBgPath;
  bool bgAnimated = true; // PATCH_S29_BG_ANIMATION_TOGGLE: animated sheen on/off (preset backgrounds only)

  // ---- PATCH_S32_AI_ART_NANO_BANANA: AI art background ----
  bool aiArtEnabled = false;
  bool aiArtBusy = false;
  int? _aiArtSurah;
  int? _aiArtAyahNum;
  String? _aiArtAyahText;
  int _aiArtSeedOffset = 0;
  bool get hasAiArt => useCustomBg && aiArtEnabled && _aiArtSurah != null;

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
      {String confidenceText = '', int? surahNum, int? ayahNum}) {
    ayahText = ar;
    translationText = en;
    detectedLabel = label;
    matchConfidenceText = confidenceText;
    notifyListeners();
    // PATCH_S32_AI_ART_NANO_BANANA: only ayat resolved against the real corpus carry a
    // surah/ayah number -- free-typed unmatched text is skipped since
    // there is nothing reliable to cache the art against.
    if (aiArtEnabled && surahNum != null && ayahNum != null) {
      _aiArtSeedOffset = 0;
      _generateAiArt(surahNum, ayahNum, ar);
    }
  }

  // PATCH_S32_AI_ART_NANO_BANANA
  Future<void> _generateAiArt(int surahNum, int ayahNum, String arText) async {
    _aiArtSurah = surahNum;
    _aiArtAyahNum = ayahNum;
    _aiArtAyahText = arText;
    aiArtBusy = true;
    notifyListeners();
    try {
      final path = await AiArtService.artFor(
        surahNum: surahNum,
        ayahNum: ayahNum,
        ayahArabic: arText,
        seedOffset: _aiArtSeedOffset,
      );
      if (path != null) {
        useCustomBg = true;
        customBgPath = path;
      }
    } finally {
      aiArtBusy = false;
      notifyListeners();
    }
  }

  // PATCH_S32_AI_ART_NANO_BANANA: manual regenerate -- bumps the seed instead of touching
  // anything paid; no-ops quietly if there is no current ayah to redo.
  Future<void> regenerateAiArt() async {
    if (_aiArtSurah == null || _aiArtAyahNum == null || _aiArtAyahText == null) {
      return;
    }
    _aiArtSeedOffset += 1;
    await _generateAiArt(_aiArtSurah!, _aiArtAyahNum!, _aiArtAyahText!);
  }

  void setVideo(String path) {
    videoPath = path;
    // A new video invalidates any previously detected timeline/trim range.
    timeline = [];
    timelineActive = false;
    trimFromIndex = -1;
    trimToIndex = -1;
    // PATCH_S34_PLAYER_CONTROLS_TRIM: and any manual cut from the old clip.
    videoDurationSec = 0;
    trimManualStart = 0;
    trimManualEnd = -1;
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
