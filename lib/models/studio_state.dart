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
  // PATCH_S82_AUTOSYNC_MAX: true when this segment was never acoustically
  // matched — it was inserted because its neighbours are the same surah with
  // exactly this ayah missing between them and there was recitation time in
  // the gap. The UI flags these so the user knows to double-check them.
  final bool inferred;
  TimelineSegment({
    required this.start,
    required this.end,
    required this.ayah,
    required this.confidence,
    List<double>? wordStarts,
    this.inferred = false,
  }) : wordStarts = wordStarts ?? [];
}

/// Central mutable app state — the Flutter counterpart of the HTML
/// prototype's single `state` object. Everything the stage preview and the
/// exporter read lives here so they can never disagree.
// PATCH_S76_QURAN_MODEL_DEFAULT
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
  // PATCH_S100_FONTS_SPINSTAR_TINT: a color tint independent of the
  // colorGrade presets above -- null means off. Any color is valid
  // (picked via showAyatColorPicker); blue/gold are just quick presets
  // in the UI, not the only options.
  Color? tintColor;
  int tintIntensity = 45; // 0..100
  bool grainEnabled = false;
  int grainIntensity = 30; // 0..100
  bool kenBurnsEnabled = false; // slow zoom on background images only, never on uploaded video
  bool softTransitions = true; // fade in/out around bismillah/outro cards instead of a hard cut

  // ---- PATCH_S85_VIDEO_ADJUST: manual picture controls on top of the ----
  // preset grades — live in the preview, burned in at export (ffmpeg eq).
  double adjustBrightness = 0.0; // -0.25..0.25, 0 = neutral
  double adjustContrast = 1.0; // 0.7..1.4, 1 = neutral
  double adjustSaturation = 1.0; // 0.0..2.0, 1 = neutral
  // Blur of the video/background layer only (text and particles stay
  // sharp), in 270-reference-width units like the text sizes.
  double videoBlur = 0.0; // 0..6
  bool get hasManualAdjust =>
      adjustBrightness.abs() > 0.005 ||
      (adjustContrast - 1).abs() > 0.005 ||
      (adjustSaturation - 1).abs() > 0.005;
  void resetManualAdjust() {
    adjustBrightness = 0.0;
    adjustContrast = 1.0;
    adjustSaturation = 1.0;
    videoBlur = 0.0;
    notifyListeners();
  }

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
  // PATCH_S82_CUSTOM_BG_LIBRARY: every uploaded background is kept here,
  // uncapped -- no limit on how many. customBgPath just points at whichever
  // one is currently active.
  List<String> customBgLibrary = [];
  bool bgAnimated = true; // PATCH_S29_BG_ANIMATION_TOGGLE: animated sheen on/off (preset backgrounds only)

  // ---- PATCH_S32_AI_ART_NANO_BANANA: AI art background ----
  bool aiArtEnabled = false;
  bool aiArtBusy = false;
  // PATCH_S87_AI_ART_ONE_TAP_FLOW: batch generation for the whole
  // auto-sync segment, tracked separately from the single-ayah
  // aiArtBusy above so the two flows never fight over one spinner.
  bool aiArtBatchBusy = false;
  String? aiArtBatchProgress;
  int? _aiArtSurah;
  int? _aiArtAyahNum;
  String? _aiArtAyahText;
  int _aiArtSeedOffset = 0;
  bool get hasAiArt => useCustomBg && aiArtEnabled && _aiArtSurah != null;
  // PATCH_S69_AI_ART_FIX: surfaced to the UI instead of failing silently.
  String? aiArtError;
  // Tracked on EVERY match regardless of aiArtEnabled, so a manual
  // generate works even if the toggle was flipped on after the match
  // already happened (previously: no context, silent no-op).
  int? _lastMatchedSurah;
  int? _lastMatchedAyahNum;
  String? _lastMatchedAyahText;
  // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART: the ayah's English meaning,
  // kept alongside the Arabic so AI art can describe the actual scene.
  String? _lastMatchedAyahEn;
  // PATCH_S80_POLLINATIONS_KEYLESS_FLUX: the S69b hardcoded key is removed.
  // It was a *secret* sk_ key baked into a public APK and committed to git
  // history, which was never a safe place for it, and it's no longer
  // needed since Flux generation works fully keyless. Default is empty;
  // Settings can still set a personal key later for higher limits.
  // IMPORTANT: treat the old key as burned regardless of this patch --
  // rotate/revoke it at enter.pollinations.ai since it was already exposed.
  String pollinationsApiKey = '';

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
  // PATCH_S100_FONTS_SPINSTAR_TINT: DigitalMadina is now the bundled default font
  // (Elgharib was the default from S46 through S99).
  String fontKey = 'digitalmadina';
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
  // PATCH_S76_QURAN_MODEL_DEFAULT: default is now the Quran-tuned tier (S66),
  // not generic-speech `small` -- see whisper_service.dart for why this is
  // safe even if that tier's asset isn't published yet (S75 fallback).
  WhisperModelSize whisperModelSize = WhisperModelSize.quranTuned;

  // ---- auto-sync timeline ----
  List<TimelineSegment> timeline = [];
  bool timelineActive = false;
  // PATCH_S51_KARAOKE_TOGGLE: word-by-word highlight while الشيخ recites,
  // on by default (matches previous always-on behavior). Off falls back
  // to showing each ayah part as plain static text.
  bool karaokeEnabled = true;

  // PATCH_S82_AUTOSYNC_MAX: the segment playing at clip-time [t], if any —
  // shared by the karaoke ticker, the loop-one-ayah control and the ribbon.
  TimelineSegment? segmentAt(double t) {
    for (final s in timeline) {
      if (t >= s.start && t < s.end) return s;
    }
    return null;
  }

  // PATCH_S82_AUTOSYNC_MAX: how much of the clip the detected timeline
  // covers (for the post-scan summary).
  // PATCH_S90_HONEST_COVERAGE: the real decoded audio duration from the
  // last scan -- set by TimelineBuilder.build(), which measures it from
  // actual decoded PCM rather than a container header or the video
  // player's own (frequently absent, for audio-only files) duration.
  double detectedAudioDurationSec = 0;

  double timelineCoverageFraction() {
    if (timeline.isEmpty) return 0;
    // PATCH_S90_HONEST_COVERAGE: prefer the real decoded duration. Falling
    // back to timeline.last.end (the old behavior when videoDurationSec
    // was 0, which is the common case for audio-only files) made coverage
    // self-referential -- it could never report under-coverage because the
    // denominator moved with whatever got detected.
    final total = detectedAudioDurationSec > 0
        ? detectedAudioDurationSec
        : (videoDurationSec > 0 ? videoDurationSec : timeline.last.end);
    if (total <= 0) return 0;
    var covered = 0.0;
    for (final s in timeline) {
      covered += s.end - s.start;
    }
    return (covered / total).clamp(0.0, 1.0);
  }

  // PATCH_S88_AUTOSYNC_HONEST_FIX: mean confidence across the detected
  // timeline -- surfaced in the post-scan summary so a shaky scan reads
  // as shaky instead of a plain, encouraging-looking list of ayat.
  double timelineAverageConfidence() {
    if (timeline.isEmpty) return 0;
    final total = timeline.fold<double>(0, (sum, s) => sum + s.confidence);
    return total / timeline.length;
  }

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
    ayahText = ar;
    translationText = en;
    detectedLabel = label;
    matchConfidenceText = confidenceText;
    notifyListeners();
    // PATCH_S32_AI_ART_NANO_BANANA: only ayat resolved against the real corpus carry a
    // surah/ayah number -- free-typed unmatched text is skipped since
    // there is nothing reliable to cache the art against.
    // PATCH_S69_AI_ART_FIX: track the match UNCONDITIONALLY (not just when
    // aiArtEnabled happened to already be on) so a later manual
    // generateAiArtNow() always has something to work from.
    if (surahNum != null && ayahNum != null) {
      _lastMatchedSurah = surahNum;
      _lastMatchedAyahNum = ayahNum;
      _lastMatchedAyahText = ar;
      _lastMatchedAyahEn = en; // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART
    }
    if (aiArtEnabled && surahNum != null && ayahNum != null) {
      _aiArtSeedOffset = 0;
      _generateAiArt(surahNum, ayahNum, ar, en);
    }
  }

  // PATCH_S32_AI_ART_NANO_BANANA
  Future<void> _generateAiArt(
      int surahNum, int ayahNum, String arText, String enText) async {
    _aiArtSurah = surahNum;
    _aiArtAyahNum = ayahNum;
    _aiArtAyahText = arText;
    aiArtBusy = true;
    aiArtError = null; // PATCH_S69_AI_ART_FIX
    notifyListeners();
    try {
      final path = await AiArtService.artFor(
        surahNum: surahNum,
        ayahNum: ayahNum,
        ayahArabic: arText,
        ayahEnglish: enText, // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART
        seedOffset: _aiArtSeedOffset,
      );
      if (path != null) {
        useCustomBg = true;
        customBgPath = path;
      }
    } on AiArtException catch (e) {
      aiArtError = e.message;
    } catch (e) {
      aiArtError = 'تعذر توليد الفن: $e';
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
    await _generateAiArt(_aiArtSurah!, _aiArtAyahNum!, _aiArtAyahText!,
        _lastMatchedAyahEn ?? ''); // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART
  }

  // PATCH_S84_AI_ART_FOLLOWS_PLAYBACK: called every karaoke tick with the
  // ayah currently being recited. "فن لكل آية" used to only fire on the
  // one-shot detection paths (setAyah) -- during auto-sync playback the
  // background never changed. Now each ayah's art generates as the reciter
  // reaches it and swaps in via the existing S51 background crossfade.
  // Cheap to call at 10Hz: the attempt-dedupe below means one real
  // generation per ayah (success OR failure -- no retry spam), and cached
  // art returns without touching the network.
  int? _artAttemptSurah;
  int? _artAttemptAyah;
  void ensureArtForPlayback(Ayah ayah) {
    if (!aiArtEnabled || aiArtBusy) return;
    if (_artAttemptSurah == ayah.surahNum && _artAttemptAyah == ayah.num) {
      return;
    }
    _artAttemptSurah = ayah.surahNum;
    _artAttemptAyah = ayah.num;
    _lastMatchedSurah = ayah.surahNum;
    _lastMatchedAyahNum = ayah.num;
    _lastMatchedAyahText = ayah.ar;
    _lastMatchedAyahEn = ayah.en; // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART
    _aiArtSeedOffset = 0;
    _generateAiArt(ayah.surahNum, ayah.num, ayah.ar, ayah.en);
  }

  // PATCH_S69_AI_ART_FIX: standalone manual entry point -- works from whatever ayah
  // was last matched, with a real, visible error instead of the old
  // silent no-op when there's no context yet.
  Future<void> generateAiArtNow() async {
    if (_lastMatchedSurah == null ||
        _lastMatchedAyahNum == null ||
        _lastMatchedAyahText == null) {
      aiArtError = 'اختر آية أولًا (بالتعرف التلقائي أو من المصحف) قبل توليد الفن';
      notifyListeners();
      return;
    }
    _aiArtSeedOffset = 0;
    await _generateAiArt(_lastMatchedSurah!, _lastMatchedAyahNum!,
        _lastMatchedAyahText!,
        _lastMatchedAyahEn ?? ''); // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART
  }

  // PATCH_S87_AI_ART_ONE_TAP_FLOW: one tap generates + caches art for the
  // first [_aiArtBatchMax] unique ayat of the active auto-sync timeline
  // (in timeline order), switches the background to the first one, and
  // leaves aiArtEnabled on so the existing playback path (S84) swaps each
  // ayah's art in from the now-warm cache as the reciter reaches it --
  // no separate "follow-along" flag needed, ensureArtForPlayback already
  // does that whenever aiArtEnabled is true. artFor() is itself
  // cache-checked, so re-running this after a partial success only retries
  // whatever didn't finish, and never re-hits the network for ayat that
  // already have art.
  static const int _aiArtBatchMax = 6;
  Future<void> generateArtForTimelineBatch() async {
    if (aiArtBatchBusy || aiArtBusy) return;
    if (timeline.isEmpty) {
      aiArtError = 'شغّل المزامنة التلقائية أولًا لرصد آيات المقطع';
      notifyListeners();
      return;
    }
    final seen = <String>{};
    final targets = <Ayah>[];
    for (final seg in timeline) {
      final key = '${seg.ayah.surahNum}:${seg.ayah.num}';
      if (seen.add(key)) {
        targets.add(seg.ayah);
        if (targets.length >= _aiArtBatchMax) break;
      }
    }

    aiArtBatchBusy = true;
    aiArtBatchProgress = null;
    aiArtError = null;
    notifyListeners();
    var ok = 0;
    try {
      for (var i = 0; i < targets.length; i++) {
        final ayah = targets[i];
        aiArtBatchProgress = 'الآية ${i + 1} من ${targets.length}…';
        notifyListeners();
        try {
          final path = await AiArtService.artFor(
            surahNum: ayah.surahNum,
            ayahNum: ayah.num,
            ayahArabic: ayah.ar,
            ayahEnglish: ayah.en, // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART
          );
          if (path != null) {
            ok++;
            if (i == 0) {
              useCustomBg = true;
              customBgPath = path;
              _aiArtSurah = ayah.surahNum;
              _aiArtAyahNum = ayah.num;
              _aiArtAyahText = ayah.ar;
              _aiArtSeedOffset = 0;
            }
            _lastMatchedSurah = ayah.surahNum;
            _lastMatchedAyahNum = ayah.num;
            _lastMatchedAyahText = ayah.ar;
            _lastMatchedAyahEn = ayah.en; // PATCH_S89_EXPORT_DURATION_AND_SCENE_ART
          }
        } on AiArtException catch (e) {
          aiArtError = e.message; // last error stays visible if all fail
        } catch (e) {
          aiArtError = 'تعذر توليد الفن: $e';
        }
      }
      if (ok == 0) {
        aiArtError ??= 'تعذر توليد الفن لأي من آيات المقطع';
        aiArtBatchProgress = null;
      } else if (ok < targets.length) {
        aiArtError = null;
        aiArtBatchProgress =
            'تم توليد فن $ok من ${targets.length} آيات — البقية ستُحاول تلقائيًا أثناء التشغيل';
      } else {
        aiArtError = null;
        aiArtBatchProgress = null;
      }
    } finally {
      aiArtBatchBusy = false;
      notifyListeners();
    }
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
    // PATCH_S84_AI_ART_FOLLOWS_PLAYBACK: let the playback path regenerate
    // this ayah's art instead of the dedupe treating it as already tried.
    _artAttemptSurah = null;
    _artAttemptAyah = null;
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
    // PATCH_S90_HONEST_COVERAGE: the old scan's real decoded duration is
    // meaningless for a new file too.
    detectedAudioDurationSec = 0;
    trimManualStart = 0;
    trimManualEnd = -1;
    // PATCH_S54_PRO_EXPORT_CONTROLS: rotation/mirror are per-clip fixes.
    videoRotationQuarterTurns = 0;
    videoMirror = false;
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
  // PATCH_S83_SYNC_QOL: returns the removed segment so the UI can offer undo.
  TimelineSegment? removeTimelineSegment(int index) {
    if (index < 0 || index >= timeline.length) return null;
    final removed = timeline.removeAt(index);
    timelineActive = timeline.isNotEmpty;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
    return removed;
  }

  // PATCH_S83_SYNC_QOL: undo of removeTimelineSegment — puts the segment
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

  // PATCH_S86_TIMELINE_EDITING: split segment [index] at [atSec] (clip
  // seconds) — the inverse of mergeTimelineSegments, for when one detected
  // span actually covers two ayat. Both halves keep the ayah and
  // confidence; relabel the wrong half with [changeSegmentAyah]. Word
  // onsets are divided by time so karaoke pacing survives on both sides.
  // Returns false when [atSec] isn't usable (outside, or too close to an
  // edge to leave two real segments).
  bool splitTimelineSegment(int index, double atSec) {
    if (index < 0 || index >= timeline.length) return false;
    final seg = timeline[index];
    if (atSec < seg.start + 0.3 || atSec > seg.end - 0.3) return false;
    final first = TimelineSegment(
      start: seg.start,
      end: atSec,
      ayah: seg.ayah,
      confidence: seg.confidence,
      wordStarts: [for (final s in seg.wordStarts) if (s < atSec) s],
      inferred: seg.inferred,
    );
    final second = TimelineSegment(
      start: atSec,
      end: seg.end,
      ayah: seg.ayah,
      confidence: seg.confidence,
      wordStarts: [for (final s in seg.wordStarts) if (s >= atSec) s],
      inferred: seg.inferred,
    );
    timeline
      ..removeAt(index)
      ..insert(index, first)
      ..insert(index + 1, second);
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
    return true;
  }

  // PATCH_S86_TIMELINE_EDITING: relabel a detection with the RIGHT ayah
  // while keeping its (already reviewed) timing — beats delete + manual
  // re-add, which loses the tuned boundaries. Confidence becomes 1.0: the
  // user just told us what this span is. Word onsets stay — they describe
  // the audio, not the label. The inferred flag clears for the same reason.
  void changeSegmentAyah(int index, Ayah ayah) {
    if (index < 0 || index >= timeline.length) return;
    final seg = timeline[index];
    timeline[index] = TimelineSegment(
      start: seg.start,
      end: seg.end,
      ayah: ayah,
      confidence: 1.0,
      // PATCH_S91_RELABEL_KARAOKE_AND_SAVE_ON_CLOSE: seg.wordStarts are
      // Whisper onsets measured against the OLD (wrong) ayah's words --
      // carrying them into a different ayah desyncs karaoke lighting
      // (wrong word count, wrong text). Drop them; karaoke.dart's
      // letter-weighted fallback paces the new ayah honestly instead.
      wordStarts: const [],
    );
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
