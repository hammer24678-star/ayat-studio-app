import 'package:flutter/material.dart';
import '../data/studio_presets.dart';
import '../services/ayah_matcher.dart';
import '../services/ai_art_service.dart'; // PATCH_S32_AI_ART_NANO_BANANA
import '../services/stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS
import '../services/whisper_service.dart'; // PATCH_S43_MODEL_SIZE_PICKER

/// One detected span of the auto-sync timeline: [ayah] was heard between
/// [start] and [end] (seconds into the uploaded clip).
class TimelineSegment {
  double start;
  double end;
  final Ayah ayah;
  double confidence;
  // PATCH_S55_WORD_TIMESTAMPS: absolute onsets (seconds into the clip) of
  // the words Whisper heard inside this segment — the karaoke lighting
  // paces itself along these instead of assuming an even reciting speed.
  final List<double> wordStarts;
  TimelineSegment({
    required this.start,
    required this.end,
    required this.ayah,
    required this.confidence,
    List<double>? wordStarts,
  }) : wordStarts = wordStarts ?? [];
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

  // ---- PATCH_S38_VIDEO_EFFECTS: export-time video effects (never audio) ----
  ColorGrade colorGrade = ColorGrade.none;
  bool vignetteEnabled = false;
  int vignetteIntensity = 50; // 0..100
  bool grainEnabled = false;
  int grainIntensity = 30; // 0..100
  bool kenBurnsEnabled = false; // slow zoom on background images only, never on uploaded video
  bool softTransitions = true; // fade in/out around bismillah/outro cards instead of a hard cut

  // ---- PATCH_S54_PRO_EXPORT_CONTROLS ----
  VideoFitMode videoFit = VideoFitMode.source;
  int videoRotationQuarterTurns = 0; // 0..3, clockwise
  bool videoMirror = false;
  ExportQuality exportQuality = ExportQuality.high;
  ExportResolutionCap exportResolution = ExportResolutionCap.source;
  double audioVolume = 1.0; // 0.0..2.0, applied to whichever track is exported
  bool audioFadeIn = false;
  bool audioFadeOut = false;

  // ---- PATCH_S40_MULTI_BG_CYCLE: cycling 2+ preset backgrounds, export-time only ----
  bool multiBgEnabled = false;
  List<int> multiBgIndexes = []; // indexes into kBackgrounds, cycle order = selection order
  BgSwitchTrigger bgSwitchTrigger = BgSwitchTrigger.seconds;
  int bgSwitchAyahs = 3; // 1..10, needs an active auto-sync timeline
  int bgSwitchSeconds = 8; // 3..30
  BgTransitionStyle bgTransitionStyle = BgTransitionStyle.hardCut;
  double bgCrossfadeDuration = 0.6; // 0.2..3.0s, only used when transition is crossfade

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
  // PATCH_S46_DEFAULT_FONT_AND_GLOW: Elgharib-NoonHafs is now the bundled default font.
  String fontKey = 'elgharib';
  final List<AyahFontChoice> customFonts = [];
  double ayahFontSize = 20; // 14..30, preview-relative like the HTML slider
  double transFontSize = 12; // 9..18
  Color textColor = const Color(0xFFECE2CB);
  AyahTextPosition textPosition = AyahTextPosition.bottom;
  FrameExtra extra = FrameExtra.none;
  bool showTranslation = true;
  // PATCH_S46_DEFAULT_FONT_AND_GLOW: glow on/off + intensity, applies to karaoke lit words
  // and, when on, to static (non-karaoke) ayah text too.
  bool glowEnabled = true;
  double glowIntensity = 1.0; // 0..1.5
  // PATCH_S48_TEXT_SPACING_TOGGLES
  double letterSpacing = 0; // -1..3
  double lineHeightMultiplier = 1.5; // 1.2..2.2, previous hardcoded value

  // PATCH_S50_DRAGGABLE_TEXT: user drag/pinch on the stage preview, on top of the
  // textPosition preset + ayahFontSize/transFontSize sliders above.
  // textOffset is stored in 270-wide reference units (same convention
  // as ayahFontSize etc.) so preview and export can both multiply it
  // by their own `scale = width / 270.0` and land on the same spot.
  Offset textOffset = Offset.zero;
  double textUserScale = 1.0; // 0.6..1.8, pinch-to-resize multiplier

  // ---- intro / outro cards ----
  bool showIntro = false;
  bool showOutro = false;
  String outroText = kDefaultOutro;

  // ---- PATCH_S43_MODEL_SIZE_PICKER: which Whisper tier drives detection/auto-sync ----
  WhisperModelSize whisperModelSize = WhisperModelSize.small;

  // ---- auto-sync timeline ----
  List<TimelineSegment> timeline = [];
  bool timelineActive = false;
  // PATCH_S51_KARAOKE_TOGGLE: word-by-word highlight while الشيخ recites,
  // on by default (matches previous always-on behavior). Off falls back
  // to showing each ayah part as plain static text.
  bool karaokeEnabled = true;

  // ---- trim (ayah-boundary indexes into [timeline], -1 = whole clip) ----
  int trimFromIndex = -1;
  int trimToIndex = -1;
  double? get trimStart =>
      (trimFromIndex >= 0 && trimToIndex >= 0) ? timeline[trimFromIndex].start : null;
  double? get trimEnd =>
      (trimFromIndex >= 0 && trimToIndex >= 0) ? timeline[trimToIndex].end : null;

  // ---- output ----
  // PATCH_S53_LANDSCAPE_EXPORT: was `bool squareRatio` (9:16 vs. 1:1 only); story916 is the
  // same default the old `false` gave.
  AyatAspectRatio aspectRatio = AyatAspectRatio.story916;
  int staticDurationSec = 6; // export length when no video is loaded (2..60)

  List<AyahFontChoice> get allFonts => [...kBuiltInFonts, ...customFonts];

  void setAyah(String ar, String en, String label,
      {String confidenceText = '', int? surahNum, int? ayahNum}) {
    pushHistory(); // PATCH_S56_UNDO_REDO
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

  // PATCH_S51_AI_ART_DELETE: wipes every cached file for this ayah from
  // disk (so a later visit regenerates fresh instead of silently reusing
  // the deleted one) and drops the current custom background back to the
  // preset gradients. Leaves aiArtEnabled untouched -- this deletes what
  // was made, it doesn't turn the feature off (use the switch for that).
  Future<void> deleteAiArt() async {
    if (_aiArtSurah == null || _aiArtAyahNum == null) return;
    await AiArtService.deleteCached(_aiArtSurah!, _aiArtAyahNum!);
    useCustomBg = false;
    customBgPath = null;
    _aiArtSeedOffset = 0;
    notifyListeners();
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
    // PATCH_S54_PRO_EXPORT_CONTROLS: rotation/mirror are per-clip fixes.
    videoRotationQuarterTurns = 0;
    videoMirror = false;
    notifyListeners();
  }

  void setTimeline(List<TimelineSegment> segments) {
    pushHistory(); // PATCH_S56_UNDO_REDO
    timeline = segments;
    timelineActive = segments.isNotEmpty;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
  }

  // PATCH_S36_TIMELINE_EDITOR: remove one wrongly detected segment. The trim
  // range indexes into [timeline], so it resets rather than dangle.
  void removeTimelineSegment(int index) {
    pushHistory(); // PATCH_S56_UNDO_REDO
    if (index < 0 || index >= timeline.length) return;
    timeline.removeAt(index);
    timelineActive = timeline.isNotEmpty;
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
    pushHistory(); // PATCH_S56_UNDO_REDO
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

  // PATCH_S49_MANUAL_SEGMENTS_MERGE: append a segment the user placed by hand -- keeps
  // [timeline] sorted by start time since playback/tick logic assumes
  // ascending order.
  void addManualSegment(Ayah ayah, double start, double end) {
    final seg = TimelineSegment(
        start: start, end: end, ayah: ayah, confidence: 1.0);
    final idx = timeline.indexWhere((s) => s.start > start);
    if (idx == -1) {
      timeline.add(seg);
    } else {
      timeline.insert(idx, seg);
    }
    timelineActive = true;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
  }

  // PATCH_S49_MANUAL_SEGMENTS_MERGE: merge segment [index] with the next one -- for when
  // auto-sync splits one continuous recited ayah (elongated/مجود
  // recitation) across two detected windows. Keeps whichever ayah had
  // the higher confidence; caller decides when offering this makes sense.
  void mergeTimelineSegments(int index) {
    if (index < 0 || index + 1 >= timeline.length) return;
    final a = timeline[index];
    final b = timeline[index + 1];
    final merged = TimelineSegment(
      start: a.start,
      end: b.end,
      ayah: a.confidence >= b.confidence ? a.ayah : b.ayah,
      confidence: (a.confidence + b.confidence) / 2,
    );
    timeline[index] = merged;
    timeline.removeAt(index + 1);
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
  }

  void applyTemplate(int index) {
    pushHistory(); // PATCH_S56_UNDO_REDO
    templateIndex = index;
    final t = kTemplates[index];
    fontKey = t.fontKey;
    textColor = t.color;
    textPosition = t.pos;
    extra = t.extra;
    notifyListeners();
  }

  void update(void Function() mutate) {
    pushHistory(); // PATCH_S56_UNDO_REDO
    mutate();
    notifyListeners();
  }

  // ---- PATCH_S56_UNDO_REDO: tester-requested undo/redo -------------------
  // Snapshot-based: before every edit a snapshot of the editable state is
  // pushed (coalesced to one step per 800ms so a slider drag is a single
  // undo step, not fifty). Media files themselves (video/model downloads)
  // are not part of history — only the edit decisions about them.
  static const int _maxHistory = 40;
  final List<Map<String, Object?>> _undoStack = [];
  final List<Map<String, Object?>> _redoStack = [];
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  bool _restoring = false;
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  Map<String, Object?> _capture() => {
        'timeline': [
          for (final s in timeline)
            TimelineSegment(
                start: s.start,
                end: s.end,
                ayah: s.ayah,
                confidence: s.confidence,
                wordStarts: List.of(s.wordStarts)),
        ],
        'timelineActive': timelineActive,
        'trimFromIndex': trimFromIndex,
        'trimToIndex': trimToIndex,
        'trimManualStart': trimManualStart,
        'trimManualEnd': trimManualEnd,
        'ayahText': ayahText,
        'translationText': translationText,
        'detectedLabel': detectedLabel,
        'matchConfidenceText': matchConfidenceText,
        'fontKey': fontKey,
        'ayahFontSize': ayahFontSize,
        'transFontSize': transFontSize,
        'textColor': textColor,
        'textPosition': textPosition,
        'extra': extra,
        'showTranslation': showTranslation,
        'templateIndex': templateIndex,
        'bgIndex': bgIndex,
        'useCustomBg': useCustomBg,
        'customBgPath': customBgPath,
        'bgAnimated': bgAnimated,
        'effect': effect,
        'effectIntensity': effectIntensity,
        'glowEnabled': glowEnabled,
        'glowIntensity': glowIntensity,
        'letterSpacing': letterSpacing,
        'lineHeightMultiplier': lineHeightMultiplier,
        'textOffset': textOffset,
        'textUserScale': textUserScale,
        'karaokeEnabled': karaokeEnabled,
        'aspectRatio': aspectRatio,
        'colorGrade': colorGrade,
        'vignetteEnabled': vignetteEnabled,
        'vignetteIntensity': vignetteIntensity,
        'grainEnabled': grainEnabled,
        'grainIntensity': grainIntensity,
        'kenBurnsEnabled': kenBurnsEnabled,
        'softTransitions': softTransitions,
        'videoFit': videoFit,
        'videoRotationQuarterTurns': videoRotationQuarterTurns,
        'videoMirror': videoMirror,
        'showIntro': showIntro,
        'showOutro': showOutro,
        'outroText': outroText,
      };

  void _apply(Map<String, Object?> s) {
    timeline = (s['timeline'] as List).cast<TimelineSegment>();
    timelineActive = s['timelineActive'] as bool;
    trimFromIndex = s['trimFromIndex'] as int;
    trimToIndex = s['trimToIndex'] as int;
    trimManualStart = s['trimManualStart'] as double;
    trimManualEnd = s['trimManualEnd'] as double;
    ayahText = s['ayahText'] as String;
    translationText = s['translationText'] as String;
    detectedLabel = s['detectedLabel'] as String;
    matchConfidenceText = s['matchConfidenceText'] as String;
    fontKey = s['fontKey'] as String;
    ayahFontSize = s['ayahFontSize'] as double;
    transFontSize = s['transFontSize'] as double;
    textColor = s['textColor'] as Color;
    textPosition = s['textPosition'] as AyahTextPosition;
    extra = s['extra'] as FrameExtra;
    showTranslation = s['showTranslation'] as bool;
    templateIndex = s['templateIndex'] as int;
    bgIndex = s['bgIndex'] as int;
    useCustomBg = s['useCustomBg'] as bool;
    customBgPath = s['customBgPath'] as String?;
    bgAnimated = s['bgAnimated'] as bool;
    effect = s['effect'] as StageEffect;
    effectIntensity = s['effectIntensity'] as double;
    glowEnabled = s['glowEnabled'] as bool;
    glowIntensity = s['glowIntensity'] as double;
    letterSpacing = s['letterSpacing'] as double;
    lineHeightMultiplier = s['lineHeightMultiplier'] as double;
    textOffset = s['textOffset'] as Offset;
    textUserScale = s['textUserScale'] as double;
    karaokeEnabled = s['karaokeEnabled'] as bool;
    aspectRatio = s['aspectRatio'] as AyatAspectRatio;
    colorGrade = s['colorGrade'] as ColorGrade;
    vignetteEnabled = s['vignetteEnabled'] as bool;
    vignetteIntensity = s['vignetteIntensity'] as int;
    grainEnabled = s['grainEnabled'] as bool;
    grainIntensity = s['grainIntensity'] as int;
    kenBurnsEnabled = s['kenBurnsEnabled'] as bool;
    softTransitions = s['softTransitions'] as bool;
    videoFit = s['videoFit'] as VideoFitMode;
    videoRotationQuarterTurns = s['videoRotationQuarterTurns'] as int;
    videoMirror = s['videoMirror'] as bool;
    showIntro = s['showIntro'] as bool;
    showOutro = s['showOutro'] as bool;
    outroText = s['outroText'] as String;
  }

  /// Pushes a pre-edit snapshot. Called automatically by [update] and the
  /// timeline mutators; call manually before any direct field mutation that
  /// should be undoable.
  void pushHistory() {
    if (_restoring) return;
    final now = DateTime.now();
    if (_undoStack.isNotEmpty &&
        now.difference(_lastPush).inMilliseconds < 800) {
      return; // coalesce rapid slider ticks into one step
    }
    _lastPush = now;
    _undoStack.add(_capture());
    if (_undoStack.length > _maxHistory) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void undoStep() {
    if (_undoStack.isEmpty) return;
    _redoStack.add(_capture());
    _restoring = true;
    _apply(_undoStack.removeLast());
    _restoring = false;
    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
  }

  void redoStep() {
    if (_redoStack.isEmpty) return;
    _undoStack.add(_capture());
    _restoring = true;
    _apply(_redoStack.removeLast());
    _restoring = false;
    _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
  }
}
