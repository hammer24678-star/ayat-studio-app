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
  // PATCH_S42_AUTOSYNC_MAX: true when this segment was never acoustically
  // matched — it was inserted because its neighbours are the same surah with
  // exactly this ayah missing between them and there was recitation time in
  // the gap. The UI flags these so the user knows to double-check them.
  final bool inferred;
  TimelineSegment({
    required this.start,
    required this.end,
    required this.ayah,
    required this.confidence,
    this.inferred = false,
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

  // PATCH_S42_AUTOSYNC_MAX: the segment playing at clip-time [t], if any —
  // shared by the karaoke ticker, the loop-one-ayah control and the ribbon.
  TimelineSegment? segmentAt(double t) {
    for (final s in timeline) {
      if (t >= s.start && t < s.end) return s;
    }
    return null;
  }

  // PATCH_S42_AUTOSYNC_MAX: how much of the clip the detected timeline
  // covers (for the post-scan summary).
  double timelineCoverageFraction() {
    if (timeline.isEmpty) return 0;
    final total = videoDurationSec > 0 ? videoDurationSec : timeline.last.end;
    if (total <= 0) return 0;
    var covered = 0.0;
    for (final s in timeline) {
      covered += s.end - s.start;
    }
    return (covered / total).clamp(0.0, 1.0);
  }

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

  // PATCH_S36_TIMELINE_EDITOR: remove one wrongly detected segment. The trim
  // range indexes into [timeline], so it resets rather than dangle.
  // PATCH_S42_SYNC_QOL: returns the removed segment so the UI can offer undo.
  TimelineSegment? removeTimelineSegment(int index) {
    if (index < 0 || index >= timeline.length) return null;
    final removed = timeline.removeAt(index);
    timelineActive = timeline.isNotEmpty;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
    return removed;
  }

  // PATCH_S42_SYNC_QOL: undo of removeTimelineSegment — puts the segment
  // back where it was. Trim indexes reset for the same dangling reason.
  void insertTimelineSegment(int index, TimelineSegment segment) {
    timeline.insert(index.clamp(0, timeline.length), segment);
    timelineActive = true;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
  }

  // PATCH_S36_TIMELINE_EDITOR: nudge a segment's start/end by [startDelta]/
  // [endDelta] seconds. A segment keeps at least 0.3s of length, and moving
  // an edge past a neighbour pulls the neighbour's shared boundary along
  // (detected boundaries are shared after normalization, so this behaves
  // like dragging the cut point between two ayat).
  void nudgeTimelineSegment(int index,
      {double startDelta = 0, double endDelta = 0}) {
    if (index < 0 || index >= timeline.length) return;
    final seg = timeline[index];
    if (startDelta != 0) {
      final floor = index > 0 ? timeline[index - 1].start + 0.3 : 0.0;
      seg.start = (seg.start + startDelta).clamp(floor, seg.end - 0.3);
      if (index > 0 && timeline[index - 1].end > seg.start) {
        timeline[index - 1].end = seg.start;
      }
    }
    if (endDelta != 0) {
      final ceil = index + 1 < timeline.length
          ? timeline[index + 1].end - 0.3
          : (videoDurationSec > 0 ? videoDurationSec : double.infinity);
      seg.end = (seg.end + endDelta).clamp(seg.start + 0.3, ceil);
      if (index + 1 < timeline.length &&
          timeline[index + 1].start < seg.end) {
        timeline[index + 1].start = seg.end;
      }
    }
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
