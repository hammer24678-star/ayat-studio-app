// PATCH_S31_UNLIMITED_EXPORT_NATURE_BGS
// استوديو الآيات — the full native studio screen, feature-matched to the
// HTML prototype: ayah selection (manual / typed / mic / from-video-audio /
// auto-sync timeline), backgrounds, chroma settings, reciters, templates,
// text formatting, ayah-boundary trim and real MP4 export.
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show HapticFeedback; // PATCH_S83_SYNC_QOL: tactile feedback
import 'package:path_provider/path_provider.dart'; // PATCH_S64_BG_UPLOAD_PERSIST
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../data/quran_repository.dart';
import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../services/ayah_matcher.dart';
import '../services/ai_art_service.dart'; // PATCH_S73C_FIX_MISSING_IMPORT: restores the import
// dropped somewhere in S73/S73b's edits -- AiArtService.apiKey is used
// below (Pollinations API key field) but the class was left unimported,
// which is what broke the release build.
import '../services/export_service.dart';
import '../services/font_service.dart'; // PATCH_S39_PERSISTENT_FONTS
import '../services/karaoke.dart'; // PATCH_S33_KARAOKE_WORD_HIGHLIGHT
import '../services/media_service.dart';
import '../services/settings_service.dart'; // PATCH_S37_PERSISTENT_SETTINGS
import '../services/stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS
import '../services/overlay_renderer.dart';
import '../services/speech_service.dart';
import '../services/timeline_builder.dart';
import '../services/whisper_service.dart';
import '../theme/ayat_theme.dart';
import '../widgets/ayat_info_dialog.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/gold_switch.dart';
import '../widgets/stage_preview.dart';
import '../widgets/timeline_ribbon.dart'; // PATCH_S83_SYNC_QOL
import 'mushaf_screen.dart'; // PATCH_S62_MUSHAF_READER

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final StudioState state = StudioState();

  VideoPlayerController? _video;
  VideoPlayerController? _reciterPreview;
  int? _previewingReciter;

  final ValueNotifier<StageOverlayText?> _liveOverlay = ValueNotifier(null);
  Timer? _syncTimer;

  bool _busy = false;
  String _busyStatus = '';
  double? _busyProgress;
  // PATCH_S83_SYNC_QOL: wall-clock of the running job — with the progress
  // fraction it yields a remaining-time estimate for BOTH export and sync.
  final Stopwatch _busyWatch = Stopwatch();
  // PATCH_S37_CANCEL_LONG_JOBS: set by long jobs (export / auto-sync) so the
  // status card can offer a working إلغاء button; cleared when the job ends.
  VoidCallback? _busyCancelAction;
  bool _listening = false;
  Timer? _persistDebounce; // PATCH_S37_PERSISTENT_SETTINGS
  bool _settingsRestored = false;

  int _selectedTab = 0;
  int _selectedSurah = 1;

  // PATCH_S83_SYNC_QOL: playback aids for reviewing a detected timeline.
  static const _speeds = [1.0, 1.25, 1.5, 0.75];
  double _playbackSpeed = 1.0;
  bool _loopAyah = false;
  TimelineSegment? _loopSeg; // the ayah the loop control snaps back to

  final _customArCtrl = TextEditingController();
  final _customEnCtrl = TextEditingController();
  late final _outroCtrl = TextEditingController(text: state.outroText);
  late final _staticDurCtrl =
      TextEditingController(text: '${state.staticDurationSec}');

  static const _tabs = [
    (Icons.menu_book_outlined, 'الآية'),
    (Icons.dark_mode_outlined, 'خلفيات'),
    (Icons.water_drop_outlined, 'تأثيرات'), // PATCH_S34_STAGE_EFFECTS
    (Icons.filter_hdr_outlined, 'كروم'),
    (Icons.graphic_eq, 'قرّاء'),
    (Icons.grid_view_outlined, 'قوالب'),
    (Icons.text_fields, 'النص'),
    (Icons.video_settings_outlined, 'تصدير'), // PATCH_S54_PRO_EXPORT_CONTROLS
  ];

  @override
  void initState() {
    super.initState();
    _loadCorpus();
    // PATCH_S26_FONT_LOAD_REBUILD: google_fonts paints with a system-fallback font while
    // the real Amiri Quran / Aref Ruqaa files are still downloading, and
    // does not rebuild this widget on its own once they're ready --
    // without the setState() below the preview could be stuck showing
    // fallback glyphs (wrong shaping/tashkeel) for the whole session.
    OverlayRenderer.ensureFontsLoaded().then((_) {
      if (mounted) setState(() {});
    });
    _syncTimer = Timer.periodic(
        const Duration(milliseconds: 100), (_) => _tickAutoSync());
    // PATCH_S39_PERSISTENT_FONTS: re-register previously imported fonts
    // FIRST, so a persisted fontKey pointing at one of them validates —
    // PATCH_S37_PERSISTENT_SETTINGS then reopens the studio the way it was
    // left and starts auto-saving style changes (debounced).
    FontService.loadSavedFonts().then((fonts) async {
      if (!mounted) return;
      if (fonts.isNotEmpty) {
        state.customFonts.addAll(fonts
            .where((f) => state.allFonts.every((e) => e.key != f.key)));
      }
      await SettingsService.restore(state);
      WhisperService.setModelSize(state.whisperModelSize); // PATCH_S43_MODEL_SIZE_PICKER
      if (!mounted) return;
      _settingsRestored = true;
      _outroCtrl.text = state.outroText;
      _staticDurCtrl.text = '${state.staticDurationSec}';
    });
    state.addListener(_schedulePersist);
  }

  // PATCH_S37_PERSISTENT_SETTINGS
  void _schedulePersist() {
    if (!_settingsRestored) return; // don't overwrite saved prefs with defaults
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 800), () {
      SettingsService.persist(state);
    });
  }

  @override
  void dispose() {
    state.removeListener(_schedulePersist); // PATCH_S37_PERSISTENT_SETTINGS
    _persistDebounce?.cancel();
    _syncTimer?.cancel();
    _video?.dispose();
    _reciterPreview?.dispose();
    _liveOverlay.dispose();
    _customArCtrl.dispose();
    _customEnCtrl.dispose();
    _outroCtrl.dispose();
    _staticDurCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCorpus() async {
    try {
      final ayaat = await QuranRepository.loadFullCorpus();
      state.update(() {
        state.ayaat = ayaat;
        state.matcher = AyahMatcher(ayaat);
        state.corpusStatus =
            'تم تحميل القرآن الكريم كاملاً (${ayaat.length} آية) ✓';
      });
    } catch (e) {
      state.update(() => state.corpusStatus = 'تعذّر تحميل القرآن الكامل: $e');
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2200),
      ));
  }

  // PATCH_S75_COMPACT_PICKER_FALLBACK: WhisperService.ensureReady() can silently fall back to a
  // different (working) tier than the one selected -- e.g. دقة القرآن isn't
  // published yet. Call this after any job that may have run ensureReady()
  // so the compact selector's displayed tier stays truthful, and let the
  // user know why it changed.
  void _syncModelSizeDisplay() {
    final actual = WhisperService.currentSize;
    if (actual != state.whisperModelSize) {
      final newLabel = WhisperService.labelFor(actual).split(' — ').first;
      state.update(() => state.whisperModelSize = actual);
      _toast('تم التبديل تلقائيًا إلى "$newLabel" لأن الخيار المحدّد غير متاح حاليًا');
    }
  }

  Future<T?> _withBusy<T>(Future<T> Function() job) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _busyProgress = null;
    });
    _busyWatch
      ..reset()
      ..start(); // PATCH_S83_SYNC_QOL
    try {
      return await job();
    } catch (e) {
      _toast('$e'.replaceFirst('Exception: ', ''));
      return null;
    } finally {
      _busyWatch.stop(); // PATCH_S83_SYNC_QOL
      if (mounted) {
        setState(() {
          _busy = false;
          _busyStatus = '';
          _busyProgress = null;
          _busyCancelAction = null; // PATCH_S37_CANCEL_LONG_JOBS
        });
      }
    }
  }

  // PATCH_S83_SYNC_QOL: linear projection of the remaining time from how
  // long the completed fraction took. Null while it can't be trusted (too
  // early, basically done, or no measurable pace yet).
  String? _busyEta() {
    final f = _busyProgress;
    if (f == null || f < 0.03 || f > 0.995) return null;
    final elapsedSec = _busyWatch.elapsedMilliseconds / 1000;
    if (elapsedSec < 2) return null;
    final remaining = (elapsedSec * (1 - f) / f).round();
    if (remaining < 1) return null;
    if (remaining < 60) return 'يتبقى نحو $remaining ث';
    return 'يتبقى نحو ${remaining ~/ 60} د ${remaining % 60} ث';
  }

  void _setBusyStatus(String s, [double? progress]) {
    if (!mounted) return;
    setState(() {
      _busyStatus = s;
      if (progress != null) _busyProgress = progress;
    });
  }

  // ---------------------------------------------------------------- media

  Future<void> _pickVideo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = res?.files.single.path;
    if (path == null) return;
    await _video?.dispose();
    _liveOverlay.value = null;
    // PATCH_S83_SYNC_QOL: playback aids belong to the previous clip
    _playbackSpeed = 1.0;
    _loopAyah = false;
    _loopSeg = null;
    final controller = VideoPlayerController.file(File(path));
    _video = controller;
    state.setVideo(path);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      // PATCH_S34_PLAYER_CONTROLS_TRIM: known duration drives the seek bar
      // and the manual-cut range slider.
      state.update(() => state.videoDurationSec =
          controller.value.duration.inMilliseconds / 1000.0);
    } catch (_) {
      // audio-only files still work for detection/auto-sync even if the
      // preview player refuses them
    }
    if (mounted) setState(() {});
    _toast('تم رفع الملف ✓');
  }

  // PATCH_S79_CUSTOM_BG_NUMBER_AND_VIDEO_MERGE: appends a second picked video/clip onto the end of
  // the one already loaded, then swaps the player over to the
  // merged file. Requires a first video to already be loaded.
  Future<void> _pickAndMergeVideo() async {
    if (!state.hasVideo) {
      _toast('ارفع فيديو أولًا قبل الدمج');
      return;
    }
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    final secondPath = res?.files.single.path;
    if (secondPath == null) return;
    final firstPath = state.videoPath!;
    final merged = await _withBusy(() async {
      _setBusyStatus('جارٍ دمج الفيديوهين…');
      return MediaService.mergeVideos(firstPath, secondPath);
    });
    if (merged == null || !mounted) return;
    await _video?.dispose();
    _liveOverlay.value = null;
    final controller = VideoPlayerController.file(File(merged));
    _video = controller;
    state.setVideo(merged);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      state.update(() => state.videoDurationSec =
          controller.value.duration.inMilliseconds / 1000.0);
    } catch (_) {
      // merged output should always be a valid mp4, but don't crash
      // the flow if the preview player still refuses it.
    }
    if (mounted) setState(() {});
    _toast('تم دمج الفيديوهين ✓');
  }

  // PATCH_S35_SMARTER_DETECTION: apply one confirmed/auto-detected match.
  void _applyDetectedAyah(AyahMatch m, {String? heardText}) {
    _liveOverlay.value = null;
    state.setAyah(
      m.ayah.ar,
      m.ayah.en,
      'تم التعرف: سورة ${m.ayah.surah} — آية ${m.ayah.num}',
      confidenceText: 'نسبة التطابق: ${(m.confidence * 100).round()}٪'
          '${heardText != null ? ' — النص المسموع: "$heardText"' : ''}',
      surahNum: m.ayah.surahNum, // PATCH_S32_AI_ART_NANO_BANANA
      ayahNum: m.ayah.num,
    );
  }

  // PATCH_S35_SMARTER_DETECTION: "did you mean…?" — instead of silently
  // committing to a borderline winner, let the user pick among the top
  // candidates. Returns (match, false), (null, true) for "use the text as
  // typed" (only when [allowRaw]), or null when dismissed.
  Future<(AyahMatch?, bool)?> _pickAyahCandidate(
    List<AyahMatch> candidates, {
    bool allowRaw = false,
  }) {
    String snippet(String s) =>
        s.length <= 90 ? s : '${s.substring(0, 90)}…';
    return showDialog<(AyahMatch?, bool)>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AyatColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AyatColors.hairline),
        ),
        title: const Text('هل تقصد إحدى هذه الآيات؟'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final m in candidates)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: AyatColors.surface2,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AyatColors.hairline),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, (m, false)),
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'سورة ${m.ayah.surah} — آية ${m.ayah.num} · ${(m.confidence * 100).round()}٪',
                            style: const TextStyle(
                                fontSize: 12, color: AyatColors.goldBright),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            snippet(m.ayah.ar),
                            textDirection: TextDirection.rtl,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (allowRaw)
                TextButton(
                  onPressed: () => Navigator.pop(context, (null, true)),
                  child: const Text('ولا واحدة — استخدم النص كما كتبته'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
        ],
      ),
    );
  }

  Future<void> _detectFromVideo() async {
    WhisperService.setModelSize(state.whisperModelSize); // PATCH_S43_MODEL_SIZE_PICKER
    final matcher = state.matcher;
    if (!state.hasVideo || matcher == null) {
      _toast('ارفع فيديو أولًا');
      return;
    }
    final text = await _withBusy(() async {
      _setBusyStatus('جارٍ استخراج الصوت…');
      final wav = await MediaService.extractWav16kMono(state.videoPath!);
      final t = await WhisperService.transcribeWav(wav,
          onStatus: (s) => _setBusyStatus(s));
      File(wav).delete().ignore();
      return t;
    });
    if (text == null || !mounted) return;
    if (text.isEmpty) {
      _toast('لم يتم استخراج أي كلام واضح من الفيديو');
      return;
    }
    // PATCH_S35_SMARTER_DETECTION: strong winner applies directly; a
    // borderline one offers the top candidates to choose from.
    final candidates = matcher.matchTop(text, k: 3, minConfidence: 0.30);
    if (candidates.isEmpty) {
      _toast('تم تفريغ الصوت لكن لم تُطابق أي آية بثقة كافية');
      return;
    }
    if (candidates.first.confidence >= 0.55 || candidates.length == 1) {
      _applyDetectedAyah(candidates.first, heardText: text);
      return;
    }
    final picked = await _pickAyahCandidate(candidates);
    if (picked?.$1 != null) _applyDetectedAyah(picked!.$1!, heardText: text);
  }

  Future<void> _autoSync() async {
    WhisperService.setModelSize(state.whisperModelSize); // PATCH_S43_MODEL_SIZE_PICKER
    final matcher = state.matcher;
    if (!state.hasVideo || matcher == null) {
      _toast('ارفع فيديو أولًا');
      return;
    }
    // pause the preview so the decoder isn't fighting the analysis pass
    await _video?.pause();
    // PATCH_S37_CANCEL_LONG_JOBS: a full scan can take minutes on long clips
    setState(() => _busyCancelAction = TimelineBuilder.requestCancel);
    await _withBusy(() async {
      // PATCH_S86_SCAN_RANGE: with a manual cut set, only the span that
      // will actually be exported gets scanned — proportionally faster.
      // PATCH_S90_HONEST_COVERAGE: build() now also returns the real
      // decoded duration -- stash it before anything below reads coverage.
      final result = await TimelineBuilder.build(
        mediaPath: state.videoPath!,
        matcher: matcher,
        scanStart: state.manualTrimSet ? state.trimManualStart : null,
        scanEnd: state.manualTrimSet ? state.trimManualEnd : null,
        onStatus: (s) => _setBusyStatus(s),
        onProgress: (f) => setState(() => _busyProgress = f),
      );
      final timeline = result.timeline;
      state.detectedAudioDurationSec = result.totalSec;
      if (timeline.isEmpty) {
        state.setTimeline([]);
        _toast('لم يتم رصد أي آية معروفة بثقة كافية في هذا الفيديو');
        return;
      }
      state.setTimeline(timeline);
      _loopSeg = null; // PATCH_S83_SYNC_QOL: old loop target no longer exists
      // PATCH_S83_SYNC_QOL: a real summary — which ayat, how much of the
      // clip they cover, and whether any were inferred and deserve review.
      final first = timeline.first.ayah;
      final last = timeline.last.ayah;
      final range = first.surahNum == last.surahNum
          ? 'سورة ${first.surah}: ${first.num}–${last.num}'
          : 'من ${first.surah} ${first.num} إلى ${last.surah} ${last.num}';
      final coverage = (state.timelineCoverageFraction() * 100).round();
      final inferredCount = timeline.where((s) => s.inferred).length;
      // PATCH_S88_AUTOSYNC_HONEST_FIX: a low-confidence scan used to render
      // as the exact same success summary as a solid one -- say so plainly
      // instead, and point at what actually helps.
      final avgConfidence = state.timelineAverageConfidence();
      const lowConfidenceWarnBar = 0.5;
      final qualityWarning = avgConfidence < lowConfidenceWarnBar
          ? '\n⚠️ متوسط الثقة منخفض (${(avgConfidence * 100).round()}٪) — '
              'التوقيت قد يكون غير دقيق. '
              '${state.whisperModelSize == WhisperModelSize.quranTuned ? 'جرّب مقطعًا أوضح صوتًا وأقل ضجيجًا.' : 'ارفع دقة التعرف (حجم النموذج) من الإعدادات إلى النموذج المخصص للقرآن للحصول على نتيجة أدق.'}'
          : '';
      state.update(() {
        state.matchConfidenceText =
            'تم رصد ${timeline.length} آية ($range) تغطي $coverage٪ من المقطع'
            '${inferredCount > 0 ? ' — منها $inferredCount مستنتجة من تسلسل المصحف، راجعها في «مراجعة الآيات المرصودة»' : ''}'
            '$qualityWarning';
        state.detectedLabel = 'مزامنة تلقائية مفعّلة — التصدير سيستخدم نفس التوقيت';
      });
      HapticFeedback.mediumImpact(); // PATCH_S83_SYNC_QOL
      _toast('تم رصد ${timeline.length} آية ✓ — التصدير سيستخدم نفس التوقيت تلقائيًا');
      await _video?.play();
    });
    _syncModelSizeDisplay(); // PATCH_S75_COMPACT_PICKER_FALLBACK
  }

  /// 10x/sec: while an auto-sync timeline is active, light the current
  /// ayah's words up in the preview in step with the playing recitation.
  /// PATCH_S33_KARAOKE_WORD_HIGHLIGHT: karaoke-style — the whole part is
  /// visible dimmed and each word brightens as الشيخ reaches it; ayahs
  /// longer than 12 words are shown as 2-3+ sequential parts.
  void _tickAutoSync() {
    final controller = _video;
    if (!state.timelineActive ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    final t = controller.value.position.inMilliseconds / 1000.0;
    // PATCH_S83_SYNC_QOL: loop-one-ayah — once the playhead crosses the end
    // of the ayah it was inside, snap back to that ayah's start. The narrow
    // trigger window means a deliberate manual seek far past the end simply
    // leaves the loop and adopts the new ayah.
    final loopSeg = _loopSeg;
    if (_loopAyah &&
        loopSeg != null &&
        controller.value.isPlaying &&
        t >= loopSeg.end - 0.05 &&
        t <= loopSeg.end + 1.0) {
      controller
          .seekTo(Duration(milliseconds: (loopSeg.start * 1000).round() + 30));
      return;
    }
    final seg = state.segmentAt(t);
    if (seg != null) _loopSeg = seg;
    if (seg == null) return; // keep the last ayah on screen between segments
    // PATCH_S84_AI_ART_FOLLOWS_PLAYBACK: per-ayah art now tracks the
    // recitation live (internal guards make this call ~free per tick).
    // Only when the background is actually visible: audio-only uploads
    // (no video surface) or chroma, where the art replaces the backdrop —
    // generating behind an opaque video would just burn bandwidth.
    if (controller.value.size.width <= 0 || state.chromaEnabled) {
      state.ensureArtForPlayback(seg.ayah);
    }
    final cue = karaokeCueAt(buildKaraokeChunks(seg), t);
    // PATCH_S27_FADE_TEXT_ANIMATIONS: stable per-part key so StagePreview only fades when
    // the ayah part actually changes, not on every newly lit word.
    final segmentKey =
        '${seg.ayah.surahNum}:${seg.ayah.num}:${cue.chunk.index}';
    // PATCH_S51_KARAOKE_TOGGLE: with the toggle off, drop the per-word
    // list entirely -- StagePreview already falls back to plain static
    // text whenever karaokeWords is null, so this reuses that path
    // instead of adding a second rendering branch.
    final words = state.karaokeEnabled ? cue.chunk.words : null;
    final litWords = state.karaokeEnabled ? cue.litWords : 0;
    final current = _liveOverlay.value;
    if (current == null ||
        current.segmentKey != segmentKey ||
        current.litWords != litWords) {
      _liveOverlay.value = StageOverlayText(
          cue.chunk.text,
          cue.chunk.translation,
          segmentKey,
          words,
          litWords,
          // PATCH_S83_SYNC_QOL: which ayah is playing, right on the stage
          'سورة ${seg.ayah.surah} — ${seg.ayah.num}'
          '${seg.inferred ? ' · مستنتجة' : ''}');
    }
  }

  Future<void> _micDetect() async {
    final matcher = state.matcher;
    if (matcher == null) return;
    if (_listening) {
      await SpeechService.stop();
      return;
    }
    setState(() => _listening = true);
    try {
      final best = await SpeechService.listenForAyah(matcher);
      if (best != null) {
        _liveOverlay.value = null;
        state.setAyah(
          best.ayah.ar,
          best.ayah.en,
          'تم التعرف: سورة ${best.ayah.surah} — آية ${best.ayah.num}',
          confidenceText: 'نسبة التطابق: ${(best.confidence * 100).round()}٪',
          surahNum: best.ayah.surahNum, // PATCH_S32_AI_ART_NANO_BANANA
          ayahNum: best.ayah.num,
        );
      } else {
        _toast('لم يتم العثور على آية مطابقة بثقة كافية — حاول التلاوة بوضوح أكبر');
      }
    } catch (e) {
      _toast('$e'.replaceFirst('Exception: ', ''));
    } finally {
      _syncModelSizeDisplay(); // PATCH_S75_COMPACT_PICKER_FALLBACK
      if (mounted) setState(() => _listening = false);
    }
  }

  // ---------------------------------------------------------------- export

  Future<void> _export() async {
    if (!state.hasAyah && !state.timelineActive && !state.hasVideo) {
      _toast('اختر آية أو ارفع فيديو أولًا');
      return;
    }
    state.staticDurationSec =
        (int.tryParse(_staticDurCtrl.text) ?? 6).clamp(2, 60);
    await _video?.pause();
    // PATCH_S37_CANCEL_LONG_JOBS
    setState(() => _busyCancelAction = () => ExportService.cancel());
    final path = await _withBusy(() async {
      _setBusyStatus('جارٍ تجهيز التصدير…', 0);
      return ExportService.export(
        state: state,
        onStatus: (s) => _setBusyStatus(s),
        onProgress: (f) => setState(() => _busyProgress = f),
      );
    });
    if (path == null || !mounted) return;
    HapticFeedback.mediumImpact(); // PATCH_S83_SYNC_QOL
    // PATCH_S83_SYNC_QOL: the file size answers "will this upload/share OK?"
    // right in the done dialog.
    String sizeNote = '';
    try {
      final mb = File(path).lengthSync() / (1024 * 1024);
      sizeNote = '\nحجم الملف: ${mb.toStringAsFixed(1)} م.ب';
    } catch (_) {}
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AyatColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AyatColors.hairline),
        ),
        title: const Text('التصدير جاهز ✓'),
        content: Text('تم حفظ المقطع بصيغة MP4:\n$path$sizeNote',
            style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق')),
          FilledButton.icon(
            onPressed: () => SharePlus.instance
                .share(ShareParams(files: [XFile(path)])),
            icon: const Icon(Icons.share, size: 16),
            label: const Text('مشاركة الفيديو'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- pickers

  Future<void> _pickCustomBg() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final pickedPath = res?.files.single.path;
    if (pickedPath == null) return;
    // PATCH_S64_BG_UPLOAD_PERSIST: the picker's path is often a transient
    // cache/content-resolver path the OS can clear at any time (that's why
    // the background used to vanish). Copy it into the app's own permanent
    // documents dir first -- same pattern ai_art_service.dart already uses
    // for AI-art backgrounds -- and store THAT path instead.
    final permanentPath = await _copyToPermanentBgStorage(pickedPath);
    state.update(() {
      // PATCH_S82_CUSTOM_BG_LIBRARY: kept, not overwritten -- every upload
      // stays available to reuse later instead of replacing the last one.
      state.customBgLibrary.add(permanentPath);
      state.useCustomBg = true;
      state.customBgPath = permanentPath;
    });
    _toast('تم رفع الخلفية وحفظها في مكتبتك ✓');
  }

  // PATCH_S64_BG_UPLOAD_PERSIST
  Future<String> _copyToPermanentBgStorage(String pickedPath) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/custom_backgrounds');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ext = pickedPath.contains('.') ? pickedPath.split('.').last : 'img';
      final dest = File(
          '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.$ext');
      await File(pickedPath).copy(dest.path);
      return dest.path;
    } catch (_) {
      // Copy failed (e.g. source already gone) -- fall back to the
      // original path; better than crashing, even if it may not survive.
      return pickedPath;
    }
  }

  Future<void> _pickCustomFont() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['ttf', 'otf']);
    final file = res?.files.single;
    if (file?.path == null) return;
    try {
      // PATCH_S39_PERSISTENT_FONTS: the font is copied into app storage and
      // re-registered on every launch — pick Elgharib-NoonHafs.ttf (or any
      // Quran font) once and it stays the selected font permanently.
      final choice = await FontService.importFont(file!.path!, file.name);
      state.update(() {
        state.customFonts.removeWhere((f) => f.key == choice.key);
        state.customFonts.add(choice);
        state.fontKey = choice.key;
      });
      _toast('تم حفظ الخط وتطبيقه — سيبقى متاحًا بعد إغلاق التطبيق ✓');
    } catch (_) {
      _toast('تعذّر تحميل هذا الملف كخط — تأكد أنه TTF أو OTF صالح');
    }
  }

  Future<void> _pickReciterAudio(int i) async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = res?.files.single.path;
    if (path == null) return;
    state.update(() => state.reciterAudioPaths[i] = path);
    _toast('تم إرفاق تلاوة لـ ${kReciters[i]} ✓');
  }

  Future<void> _toggleReciterPreview(int i) async {
    final path = state.reciterAudioPaths[i];
    if (path == null) {
      _toast('أرفق ملف تلاوة صوتية أولًا');
      return;
    }
    if (_previewingReciter == i && _reciterPreview != null) {
      await _reciterPreview!.dispose();
      setState(() {
        _reciterPreview = null;
        _previewingReciter = null;
      });
      return;
    }
    await _reciterPreview?.dispose();
    final c = VideoPlayerController.file(File(path));
    setState(() {
      _reciterPreview = c;
      _previewingReciter = i;
    });
    try {
      await c.initialize();
      await c.play();
      c.addListener(() {
        if (c.value.position >= c.value.duration &&
            !c.value.isPlaying &&
            mounted &&
            _previewingReciter == i) {
          setState(() => _previewingReciter = null);
        }
      });
    } catch (_) {
      _toast('تعذّر تشغيل هذا الملف الصوتي');
      setState(() {
        _reciterPreview = null;
        _previewingReciter = null;
      });
    }
  }

  Future<void> _applyCustomText() async {
    final matcher = state.matcher;
    final ar = _customArCtrl.text.trim();
    final en = _customEnCtrl.text.trim();
    if (ar.isEmpty) {
      _toast('اكتب نص الآية أولًا');
      return;
    }
    _liveOverlay.value = null;
    void applyMatch(AyahMatch m) {
      state.setAyah(m.ayah.ar, en.isNotEmpty ? en : m.ayah.en,
          'تم التعرّف: سورة ${m.ayah.surah} — آية ${m.ayah.num}',
          surahNum: m.ayah.surahNum, ayahNum: m.ayah.num); // PATCH_S32_AI_ART_NANO_BANANA
      _toast('تم العثور على الآية ✓ (سورة ${m.ayah.surah}:${m.ayah.num})');
    }

    void applyRaw() {
      state.setAyah(ar, en, 'نص مخصص (لم يتم العثور على تطابق في القرآن)');
      _toast('تم استخدام النص كما كتبته');
    }

    // PATCH_S35_SMARTER_DETECTION: confident match applies directly; weaker
    // ones offer the top candidates (plus "use as typed") to choose from.
    final candidates = matcher?.matchTop(ar, k: 3, minConfidence: 0.2) ??
        const <AyahMatch>[];
    if (candidates.isEmpty) {
      applyRaw();
      return;
    }
    if (candidates.first.confidence >= 0.5) {
      applyMatch(candidates.first);
      return;
    }
    final picked = await _pickAyahCandidate(candidates, allowRaw: true);
    if (picked == null) return; // dismissed — change nothing
    if (picked.$2) {
      applyRaw();
    } else if (picked.$1 != null) {
      applyMatch(picked.$1!);
    }
  }

  void _showInfo() => showAyatInfoDialog(context);

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AyatColors.ink,
      appBar: AppBar(
        title: const Text('استوديو الآيات'),
        actions: [
          IconButton(
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
            tooltip: 'معلومات عن التطبيق',
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _statusCard(),
                const SizedBox(height: 14),
                _ratioToggle(),
                const SizedBox(height: 10),
                StagePreview(
                  state: state,
                  videoController: _video,
                  liveOverride: _liveOverlay,
                ),
                // PATCH_S34_PLAYER_CONTROLS_TRIM
                if (_video != null && _video!.value.isInitialized) ...[
                  const SizedBox(height: 8),
                  _transportBar(),
                ],
                if (state.hasVideo && state.videoDurationSec > 1) ...[
                  const SizedBox(height: 8),
                  _manualCutCard(),
                ],
                const SizedBox(height: 12),
                _mediaButtons(),
                if (state.detectedLabel.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(state.detectedLabel,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 12, color: AyatColors.goldBright)),
                ],
                if (state.matchConfidenceText.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(state.matchConfidenceText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 11, color: AyatColors.parchmentDim)),
                ],
                if (state.timelineActive) ...[
                  const SizedBox(height: 12),
                  _trimCard(),
                  const SizedBox(height: 12),
                  _timelineEditorCard(), // PATCH_S36_TIMELINE_EDITOR
                ],
                const SizedBox(height: 18),
                _tabChips(),
                const SizedBox(height: 12),
                _panelCard(),
                const SizedBox(height: 18),
                if (!state.hasVideo) _staticDurationRow(),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: _busy ? null : _export,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AyatColors.gold.withValues(alpha: 0.18),
                    foregroundColor: AyatColors.goldBright,
                    side: const BorderSide(color: AyatColors.gold),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.movie_creation_outlined, size: 18),
                  label: const Text('تصدير المقطع (MP4 — بدون حد للمدة أو الدقة)'),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AyatColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AyatColors.hairline),
        ),
        child: child,
      );

  Widget _statusCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _busy && _busyStatus.isNotEmpty ? _busyStatus : state.corpusStatus,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AyatColors.goldBright),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            // PATCH_S83_SYNC_QOL: a numeric ٪ readout beside the bar
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _busyProgress,
                      minHeight: 6,
                      backgroundColor: AyatColors.surface3,
                      valueColor: const AlwaysStoppedAnimation(AyatColors.gold),
                    ),
                  ),
                ),
                if (_busyProgress != null) ...[
                  const SizedBox(width: 8),
                  Text('${(_busyProgress! * 100).round()}٪',
                      style: const TextStyle(
                          fontSize: 11, color: AyatColors.goldBright)),
                ],
              ],
            ),
            // PATCH_S83_SYNC_QOL: remaining-time projection for any job that
            // reports a fraction (export and all the auto-sync passes).
            if (_busyEta() != null) ...[
              const SizedBox(height: 6),
              Text(_busyEta()!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, color: AyatColors.parchmentDim)),
            ],
            // PATCH_S37_CANCEL_LONG_JOBS: abort export / auto-sync scan
            if (_busyCancelAction != null) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () {
                  _busyCancelAction?.call();
                  setState(() => _busyCancelAction = null);
                  _setBusyStatus('جارٍ الإلغاء…');
                },
                icon: const Icon(Icons.cancel_outlined,
                    size: 16, color: AyatColors.parchmentDim),
                label: const Text('إلغاء العملية',
                    style: TextStyle(
                        fontSize: 12, color: AyatColors.parchmentDim)),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _ratioToggle() {
    // PATCH_S53_LANDSCAPE_EXPORT: renders all three shapes from kAspectRatios instead of
    // two hardcoded chips.
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in kAspectRatios)
          ChoiceChip(
            label: Text(entry.$2),
            selected: state.aspectRatio == entry.$1,
            onSelected: (_) =>
                state.update(() => state.aspectRatio = entry.$1),
          ),
      ],
    );
  }

  // PATCH_S75_COMPACT_PICKER_FALLBACK: compact selector button shown inline; opens the full tier
  // list in a bottom sheet instead of always showing all 5 cards.
  Widget _modelSizeSelector() {
    final parts = WhisperService.labelFor(state.whisperModelSize).split(' — ');
    final sizeLabel = parts.first;
    final qualityLabel = parts.length > 1 ? parts[1] : '';
    return Material(
      color: AyatColors.ink.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: _busy ? null : _showModelSizePicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AyatColors.hairline, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sizeLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AyatColors.goldBright)),
                    if (qualityLabel.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(qualityLabel,
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.6))),
                    ],
                  ],
                ),
              ),
              Icon(Icons.unfold_more,
                  color: Colors.white.withValues(alpha: 0.5), size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // PATCH_S75_COMPACT_PICKER_FALLBACK: bottom-sheet with all 5 tiers -- same card styling S50 used
  // inline, just shown on demand. Tapping a tier updates selection and
  // closes the sheet; the actual model file is still only fetched lazily
  // the next time a detect/auto-sync job runs ensureReady().
  void _showModelSizePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AyatColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _fieldLabel('دقة التعرّف على الكلام'),
                const SizedBox(height: 8),
                for (final size in WhisperModelSize.values)
                  Builder(builder: (context) {
                    final selected = state.whisperModelSize == size;
                    final parts = WhisperService.labelFor(size).split(' — ');
                    final sizeLabel = parts.first;
                    final qualityLabel = parts.length > 1 ? parts[1] : '';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: selected
                            ? AyatColors.gold.withValues(alpha: 0.12)
                            : AyatColors.ink.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                            state.update(() => state.whisperModelSize = size);
                            WhisperService.setModelSize(size);
                            Navigator.of(sheetContext).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AyatColors.gold
                                    : AyatColors.hairline,
                                width: selected ? 1.4 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        sizeLabel,
                                        style: TextStyle(
                                          fontWeight: selected
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                          color: selected
                                              ? AyatColors.goldBright
                                              : Colors.white,
                                        ),
                                      ),
                                      if (qualityLabel.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          qualityLabel,
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.white
                                                .withValues(alpha: 0.6),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                if (selected)
                                  const Icon(Icons.check_circle,
                                      color: AyatColors.goldBright, size: 20)
                                else
                                  Icon(Icons.circle_outlined,
                                      color:
                                          Colors.white.withValues(alpha: 0.3),
                                      size: 20),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mediaButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // PATCH_S75_COMPACT_PICKER_FALLBACK: model-size picker -- controls every detect/auto-sync
        // button below via WhisperService.setModelSize(). Collapsed to one
        // compact row (current tier + chevron) that opens a bottom-sheet list
        // on tap -- same interaction pattern as a model picker, instead of
        // permanently occupying 5 full-width cards' worth of vertical space.
        _fieldLabel('دقة التعرّف على الكلام'),
        _modelSizeSelector(),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _busy ? null : _pickVideo,
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('رفع فيديو أو تلاوة صوتية'),
        ),
        const SizedBox(height: 8),
        // PATCH_S79_CUSTOM_BG_NUMBER_AND_VIDEO_MERGE
        OutlinedButton.icon(
          onPressed: (_busy || !state.hasVideo) ? null : _pickAndMergeVideo,
          icon: const Icon(Icons.video_collection_outlined, size: 18),
          label: const Text('دمج مع فيديو آخر'),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _busy ? null : _micDetect,
          icon: Icon(_listening ? Icons.stop_circle_outlined : Icons.mic,
              size: 18),
          label: Text(_listening
              ? 'جارٍ الاستماع… اضغط للإيقاف'
              : 'تعرّف من الميكروفون (مباشر)'),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _busy ? null : _detectFromVideo,
          icon: const Icon(Icons.manage_search, size: 18),
          label: const Text('تعرّف من صوت الفيديو المرفوع'),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: _busy ? null : _autoSync,
          style: ElevatedButton.styleFrom(
            side: const BorderSide(color: AyatColors.gold),
          ),
          icon: const Icon(Icons.auto_awesome, size: 18),
          // PATCH_S83_SYNC_QOL: make it clear a re-run replaces the current scan
          label: Text(state.timelineActive
              ? 'إعادة المزامنة التلقائية (تستبدل الرصد الحالي)'
              : 'مزامنة تلقائية: اكتب كل آية أثناء التلاوة'),
        ),
      ],
    );
  }

  Widget _trimCard() {
    final items = <DropdownMenuItem<int>>[
      const DropdownMenuItem(value: -1, child: Text('(المقطع كاملاً)')),
      for (var i = 0; i < state.timeline.length; i++)
        DropdownMenuItem(
          value: i,
          child: Text(
              'سورة ${state.timeline[i].ayah.surah} — آية ${state.timeline[i].ayah.num}',
              overflow: TextOverflow.ellipsis),
        ),
    ];
    void apply(int from, int to) {
      if (from != -1 && to != -1 && to < from) {
        _toast('اختر آية نهاية بعد آية البداية');
        state.update(() {
          state.trimFromIndex = -1;
          state.trimToIndex = -1;
        });
        return;
      }
      state.update(() {
        state.trimFromIndex = from;
        state.trimToIndex = to;
      });
      if (from != -1 && to != -1) {
        _toast(
            'سيُصدَّر من بداية آية ${state.timeline[from].ayah.num} حتى نهاية آية ${state.timeline[to].ayah.num}');
      }
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تصدير نطاق آيات محدد (اختياري)',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: state.trimFromIndex,
                  items: items,
                  onChanged: (v) => apply(v ?? -1, state.trimToIndex),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: state.trimToIndex,
                  items: items,
                  onChanged: (v) => apply(state.trimFromIndex, v ?? -1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'القص يلتزم دائمًا ببداية ونهاية الآية كما رصدها التعرّف الصوتي — لا يمكن القص في منتصف آية أو كلمة.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  // PATCH_S34_PLAYER_CONTROLS_TRIM ------------------------------------------

  static String _fmtSec(double s) {
    final total = s.round();
    final m = total ~/ 60;
    final sec = total % 60;
    return '$m:${sec.toString().padLeft(2, '0')}';
  }

  // PATCH_S83_SYNC_QOL: tenth-of-a-second precision for the timing editor —
  // whole seconds are useless when nudging by ±0.1s.
  static String _fmtSecFine(double s) {
    final m = s ~/ 60;
    final sec = s - m * 60;
    return '$m:${sec.toStringAsFixed(1).padLeft(4, '0')}';
  }

  // PATCH_S83_SYNC_QOL: cycle 1× → 1.25× → 1.5× → 0.75× — reviewing a long
  // detected timeline is much faster above 1× and fixing timings easier
  // below it.
  Future<void> _cycleSpeed() async {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    final i = _speeds.indexOf(_playbackSpeed);
    final next = _speeds[(i + 1) % _speeds.length];
    await c.setPlaybackSpeed(next);
    if (mounted) setState(() => _playbackSpeed = next);
  }

  static String _speedLabel(double s) =>
      s == s.roundToDouble() ? '${s.round()}×' : '$s×';

  /// Play/pause + seek bar for the uploaded clip. Tapping the stage itself
  /// also pauses/resumes (see StagePreview).
  /// PATCH_S83_SYNC_QOL: plus the ayah ribbon (tap-to-seek map of the
  /// detected timeline), loop-one-ayah and playback speed.
  Widget _transportBar() {
    final c = _video!;
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: c,
        builder: (context, v, _) {
          final durMs = max(1, v.duration.inMilliseconds);
          final posMs = v.position.inMilliseconds.clamp(0, durMs);
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.timelineActive)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 4, right: 4),
                  child: TimelineRibbon(state: state, controller: c),
                ),
              Row(
                children: [
                  // PATCH_S36_TIMELINE_EDITOR: jump between detected ayat
                  if (state.timelineActive)
                    IconButton(
                      onPressed: () => _seekToAdjacentAyah(-1),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 34, minHeight: 40),
                      icon: const Icon(Icons.skip_previous_outlined,
                          color: AyatColors.parchmentDim, size: 20),
                      tooltip: 'الآية السابقة',
                    ),
                  IconButton(
                    onPressed: () => v.isPlaying ? c.pause() : c.play(),
                    icon: Icon(
                      v.isPlaying
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      color: AyatColors.goldBright,
                    ),
                    tooltip: 'تشغيل/إيقاف',
                  ),
                  if (state.timelineActive)
                    IconButton(
                      onPressed: () => _seekToAdjacentAyah(1),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 34, minHeight: 40),
                      icon: const Icon(Icons.skip_next_outlined,
                          color: AyatColors.parchmentDim, size: 20),
                      tooltip: 'الآية التالية',
                    ),
                  if (state.timelineActive)
                    IconButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        setState(() => _loopAyah = !_loopAyah);
                        _toast(_loopAyah
                            ? 'تكرار الآية الحالية مفعّل'
                            : 'تم إيقاف تكرار الآية');
                      },
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 34, minHeight: 40),
                      icon: Icon(Icons.repeat_one,
                          color: _loopAyah
                              ? AyatColors.goldBright
                              : AyatColors.parchmentDim,
                          size: 20),
                      tooltip: 'تكرار الآية الحالية',
                    ),
                  Text(_fmtSec(posMs / 1000),
                      style: const TextStyle(
                          fontSize: 11, color: AyatColors.parchmentDim)),
                  Expanded(
                    child: Slider(
                      value: posMs.toDouble(),
                      max: durMs.toDouble(),
                      onChanged: (x) =>
                          c.seekTo(Duration(milliseconds: x.round())),
                    ),
                  ),
                  Text(_fmtSec(durMs / 1000),
                      style: const TextStyle(
                          fontSize: 11, color: AyatColors.parchmentDim)),
                  TextButton(
                    onPressed: _cycleSpeed,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(38, 40),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                    ),
                    child: Text(
                      _speedLabel(_playbackSpeed),
                      style: TextStyle(
                          fontSize: 11,
                          color: _playbackSpeed == 1.0
                              ? AyatColors.parchmentDim
                              : AyatColors.goldBright),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  // PATCH_S36_TIMELINE_EDITOR ------------------------------------------------
  // Review and fix the detected timeline by hand: tap an ayah to jump the
  // preview there, fine-tune its start/end (the karaoke lighting and the
  // export follow immediately), or delete a wrong detection.

  Widget _timelineEditorCard() {
    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Theme(
        // ExpansionTile draws its own dividers — keep the card clean
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 10),
          iconColor: AyatColors.goldBright,
          collapsedIconColor: AyatColors.parchmentDim,
          title: Text('مراجعة الآيات المرصودة (${state.timeline.length})',
              style: Theme.of(context).textTheme.labelLarge),
          subtitle: Text(
            'اضغط آية للانتقال إليها، أو عدّل توقيتها أو احذفها إن كان الرصد خاطئًا.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          children: [
            for (var i = 0; i < state.timeline.length; i++)
              _timelineSegmentRow(i),
            _timelineManualAddRow(), // PATCH_S49_MANUAL_SEGMENTS_MERGE
          ],
        ),
      ),
    );
  }

  // PATCH_S49_MANUAL_SEGMENTS_MERGE: manual-add dialog trigger + adjacent-ayah quick-add chips,
  // shown below the detected-segment list regardless of whether
  // auto-sync has run yet (a manual-only timeline is valid too).
  Widget _timelineManualAddRow() {
    final last = state.timeline.isNotEmpty ? state.timeline.last : null;
    final prevAyah = last == null ? null : _neighborAyah(last.ayah, -1);
    final nextAyah = last == null ? null : _neighborAyah(last.ayah, 1);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (prevAyah != null)
            OutlinedButton.icon(
              onPressed: () => _quickAddNeighborAyah(prevAyah, last!),
              icon: const Icon(Icons.arrow_back, size: 14),
              label: Text('إضافة آية ${prevAyah.num} — ${prevAyah.surah}'),
            ),
          if (nextAyah != null)
            OutlinedButton.icon(
              onPressed: () => _quickAddNeighborAyah(nextAyah, last!),
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: Text('إضافة آية ${nextAyah.num} — ${nextAyah.surah}'),
            ),
          OutlinedButton.icon(
            onPressed: _addManualSegmentDialog,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('إضافة آية يدويًا'),
          ),
        ],
      ),
    );
  }

  /// PATCH_S49_MANUAL_SEGMENTS_MERGE: ayah [delta] positions away from [of] in the Quran's own
  /// order (delta -1 = previous ayah overall, +1 = next), or null past
  /// either end of the corpus.
  Ayah? _neighborAyah(Ayah of, int delta) {
    final idx = state.ayaat
        .indexWhere((a) => a.surahNum == of.surahNum && a.num == of.num);
    if (idx == -1) return null;
    final j = idx + delta;
    if (j < 0 || j >= state.ayaat.length) return null;
    return state.ayaat[j];
  }

  void _quickAddNeighborAyah(Ayah ayah, TimelineSegment after) {
    final start = after.end;
    final end = state.videoDurationSec > 0
        ? (start + 4).clamp(start + 0.3, state.videoDurationSec)
        : start + 4;
    state.addManualSegment(ayah, start, end.toDouble());
    _toast('أُضيفت آية ${ayah.num} — ${ayah.surah} — عدّل توقيتها من زر الضبط');
  }

  Future<void> _addManualSegmentDialog() {
    int dialogSurah = _selectedSurah;
    int? dialogAyahIdx;
    double start = state.timeline.isNotEmpty ? state.timeline.last.end : 0;
    double end = start + 4;
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final surahs = <(int, String)>[];
          var last = 0;
          for (final a in state.ayaat) {
            if (a.surahNum != last) {
              surahs.add((a.surahNum, a.surah));
              last = a.surahNum;
            }
          }
          final ayatOfSurah = <(int, Ayah)>[
            for (var i = 0; i < state.ayaat.length; i++)
              if (state.ayaat[i].surahNum == dialogSurah) (i, state.ayaat[i]),
          ];
          Widget timeField(
              String label, double value, void Function(double) onSet) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text('$label: ${_fmtSec(value)}')),
                  OutlinedButton(
                    onPressed: () =>
                        setDialogState(() => onSet(value - 0.5)),
                    child: const Text('-٠٫٥ث'),
                  ),
                  const SizedBox(width: 6),
                  OutlinedButton(
                    onPressed: () =>
                        setDialogState(() => onSet(value + 0.5)),
                    child: const Text('+٠٫٥ث'),
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            backgroundColor: AyatColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: AyatColors.hairline),
            ),
            title: const Text('إضافة آية يدويًا'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButton<int>(
                    isExpanded: true,
                    value: surahs.any((s) => s.$1 == dialogSurah)
                        ? dialogSurah
                        : (surahs.isEmpty ? null : surahs.first.$1),
                    items: [
                      for (final s in surahs)
                        DropdownMenuItem(
                            value: s.$1, child: Text('سورة ${s.$2}')),
                    ],
                    onChanged: (v) => setDialogState(() {
                      dialogSurah = v ?? dialogSurah;
                      dialogAyahIdx = null;
                    }),
                  ),
                  DropdownButton<int>(
                    isExpanded: true,
                    value: dialogAyahIdx,
                    hint: const Text('اختر الآية'),
                    items: [
                      for (final e in ayatOfSurah)
                        DropdownMenuItem(
                            value: e.$1, child: Text('آية ${e.$2.num}')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => dialogAyahIdx = v),
                  ),
                  const SizedBox(height: 8),
                  timeField('البداية', start,
                      (v) => start = v.clamp(0, end - 0.3)),
                  timeField(
                      'النهاية',
                      end,
                      (v) => end = v.clamp(
                          start + 0.3,
                          state.videoDurationSec > 0
                              ? state.videoDurationSec
                              : v)),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء')),
              FilledButton(
                onPressed: dialogAyahIdx == null
                    ? null
                    : () {
                        // PATCH_S57_MANUAL_MULTI_AYAH_ENTRY: the very first manual add is the
                        // moment the editor card appears -- tell the user
                        // where to find it instead of leaving them to
                        // notice a new card above the fold on their own.
                        final wasEmpty = state.timeline.isEmpty;
                        state.addManualSegment(
                            state.ayaat[dialogAyahIdx!], start, end);
                        Navigator.pop(context);
                        _toast(wasEmpty
                            ? 'أُضيفت الآية الأولى ✓ — مرّري لأعلى لرؤية \'مراجعة الآيات المرصودة\' وأكملي إضافة بقية النطاق من هناك'
                            : 'أُضيفت الآية إلى الخط الزمني ✓');
                      },
                child: const Text('إضافة'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _timelineSegmentRow(int i) {
    final seg = state.timeline[i];
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AyatColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AyatColors.hairline),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () {
                final c = _video;
                if (c != null && c.value.isInitialized) {
                  c.seekTo(Duration(
                      milliseconds: (seg.start * 1000).round() + 30));
                  c.play();
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                            'سورة ${seg.ayah.surah} — آية ${seg.ayah.num}',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge),
                      ),
                      // PATCH_S82_AUTOSYNC_MAX: this ayah was inferred from
                      // mushaf order, not heard — flag it for review.
                      if (seg.inferred) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AyatColors.goldDim),
                          ),
                          child: const Text('مستنتجة',
                              style: TextStyle(
                                  fontSize: 9.5,
                                  color: AyatColors.goldBright)),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${_fmtSec(seg.start)} — ${_fmtSec(seg.end)} · ثقة ${(seg.confidence * 100).round()}٪',
                    style: TextStyle(
                        fontSize: 10.5,
                        // PATCH_S83_SYNC_QOL: low-confidence detections stand
                        // out at a glance instead of hiding in the list.
                        color: seg.confidence < 0.4
                            ? AyatColors.goldBright
                            : AyatColors.parchmentDim),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            onPressed: () => _editSegmentTiming(i),
            icon: const Icon(Icons.tune,
                size: 18, color: AyatColors.goldBright),
            tooltip: 'ضبط التوقيت',
          ),
          if (i + 1 < state.timeline.length) // PATCH_S49_MANUAL_SEGMENTS_MERGE
            IconButton(
              onPressed: () {
                state.mergeTimelineSegments(i);
                _toast('تم دمج المقطعين');
              },
              icon: const Icon(Icons.call_merge,
                  size: 18, color: AyatColors.goldBright),
              tooltip: 'دمج مع التالي',
            ),
          IconButton(
            onPressed: () {
              // PATCH_S83_SYNC_QOL: deletion is undoable from the snackbar —
              // no more re-running a whole scan over one slip of the finger.
              final removed = state.removeTimelineSegment(i);
              if (removed == null) return;
              ScaffoldMessenger.of(context)
                ..hideCurrentSnackBar()
                ..showSnackBar(SnackBar(
                  content: const Text('تم حذف الآية من الخط الزمني',
                      textAlign: TextAlign.center),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 5),
                  action: SnackBarAction(
                    label: 'تراجع',
                    textColor: AyatColors.goldBright,
                    onPressed: () => state.insertTimelineSegment(i, removed),
                  ),
                ));
            },
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AyatColors.parchmentDim),
            tooltip: 'حذف',
          ),
        ],
      ),
    );
  }

  Future<void> _editSegmentTiming(int i) {
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (i >= state.timeline.length) {
            return const SizedBox.shrink();
          }
          final seg = state.timeline[i];
          // PATCH_S83_SYNC_QOL: fine ±0.1s nudges next to the coarse ±0.5s
          // ones, and "from the playhead": pause where the ayah really
          // starts/ends and stamp that exact moment as the boundary.
          Widget nudgeRow(String label, double value,
              void Function(double delta) onNudge) {
            Widget btn(String text, double d) => OutlinedButton(
                  onPressed: () {
                    onNudge(d);
                    setDialogState(() {});
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 34),
                    padding: EdgeInsets.zero,
                    side: const BorderSide(color: AyatColors.hairline),
                  ),
                  child: Text(text, style: const TextStyle(fontSize: 12)),
                );
            final video = _video;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text('$label: ${_fmtSecFine(value)}',
                              style: Theme.of(context).textTheme.bodyLarge)),
                      TextButton.icon(
                        onPressed: video == null || !video.value.isInitialized
                            ? null
                            : () {
                                final pos =
                                    video.value.position.inMilliseconds /
                                        1000.0;
                                onNudge(pos - value);
                                setDialogState(() {});
                              },
                        icon: const Icon(Icons.my_location,
                            size: 14, color: AyatColors.goldDim),
                        label: const Text('من موضع التشغيل',
                            style: TextStyle(
                                fontSize: 11, color: AyatColors.goldDim)),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      btn('-٠٫٥', -0.5),
                      const SizedBox(width: 5),
                      btn('-٠٫١', -0.1),
                      const SizedBox(width: 5),
                      btn('+٠٫١', 0.1),
                      const SizedBox(width: 5),
                      btn('+٠٫٥', 0.5),
                    ],
                  ),
                ],
              ),
            );
          }

          return AlertDialog(
            backgroundColor: AyatColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: AyatColors.hairline),
            ),
            title: Text('توقيت آية ${seg.ayah.num} — ${seg.ayah.surah}'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                nudgeRow('البداية', seg.start,
                    (d) => state.nudgeTimelineSegment(i, startDelta: d)),
                nudgeRow('النهاية', seg.end,
                    (d) => state.nudgeTimelineSegment(i, endDelta: d)),
                const SizedBox(height: 4),
                // PATCH_S83_SYNC_QOL: hear the result without leaving the dialog
                OutlinedButton.icon(
                  onPressed: () {
                    final c = _video;
                    if (c != null && c.value.isInitialized) {
                      c.seekTo(Duration(
                          milliseconds:
                              (state.timeline[i].start * 1000).round() + 30));
                      c.play();
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AyatColors.hairline),
                  ),
                  icon: const Icon(Icons.play_arrow,
                      size: 16, color: AyatColors.goldBright),
                  label: const Text('استمع من بداية الآية',
                      style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 6),
                // PATCH_S86_TIMELINE_EDITING: split one detected span that
                // actually covers two ayat, right where the playhead is.
                OutlinedButton.icon(
                  onPressed: () {
                    final c = _video;
                    if (c == null || !c.value.isInitialized) return;
                    final pos = c.value.position.inMilliseconds / 1000.0;
                    if (state.splitTimelineSegment(i, pos)) {
                      Navigator.pop(context);
                      _toast(
                          'تم التقسيم عند موضع التشغيل ✓ — غيّر آية النصف الخاطئ من زر الضبط');
                    } else {
                      _toast(
                          'حرّك موضع التشغيل إلى داخل هذه الآية أولًا ثم اضغط تقسيم');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AyatColors.hairline),
                  ),
                  icon: const Icon(Icons.content_cut,
                      size: 15, color: AyatColors.goldBright),
                  label: const Text('تقسيم عند موضع التشغيل',
                      style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 6),
                // PATCH_S86_TIMELINE_EDITING: relabel with the right ayah,
                // keeping the reviewed timing.
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _changeSegmentAyahDialog(i);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AyatColors.hairline),
                  ),
                  icon: const Icon(Icons.swap_horiz,
                      size: 16, color: AyatColors.goldBright),
                  label: const Text('تغيير الآية (الرصد خاطئ)',
                      style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(height: 8),
                Text(
                  'التعديل يظهر فورًا في المعاينة وفي إضاءة الكلمات، ويلتزم به التصدير.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('تم')),
            ],
          );
        },
      ),
    );
  }

  // PATCH_S86_TIMELINE_EDITING: pick the correct ayah for segment [i] —
  // keeps its timing, only the label (and confidence) changes.
  Future<void> _changeSegmentAyahDialog(int i) {
    if (i < 0 || i >= state.timeline.length) return Future.value();
    int dialogSurah = state.timeline[i].ayah.surahNum;
    int? dialogAyahIdx;
    return showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final surahs = <(int, String)>[];
          var last = 0;
          for (final a in state.ayaat) {
            if (a.surahNum != last) {
              surahs.add((a.surahNum, a.surah));
              last = a.surahNum;
            }
          }
          final ayatOfSurah = <(int, Ayah)>[
            for (var j = 0; j < state.ayaat.length; j++)
              if (state.ayaat[j].surahNum == dialogSurah) (j, state.ayaat[j]),
          ];
          return AlertDialog(
            backgroundColor: AyatColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: AyatColors.hairline),
            ),
            title: const Text('اختر الآية الصحيحة لهذا المقطع'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButton<int>(
                  isExpanded: true,
                  value: surahs.any((s) => s.$1 == dialogSurah)
                      ? dialogSurah
                      : (surahs.isEmpty ? null : surahs.first.$1),
                  items: [
                    for (final s in surahs)
                      DropdownMenuItem(
                          value: s.$1, child: Text('سورة ${s.$2}')),
                  ],
                  onChanged: (v) => setDialogState(() {
                    dialogSurah = v ?? dialogSurah;
                    dialogAyahIdx = null;
                  }),
                ),
                DropdownButton<int>(
                  isExpanded: true,
                  value: dialogAyahIdx,
                  hint: const Text('اختر الآية'),
                  items: [
                    for (final e in ayatOfSurah)
                      DropdownMenuItem(
                          value: e.$1, child: Text('آية ${e.$2.num}')),
                  ],
                  onChanged: (v) => setDialogState(() => dialogAyahIdx = v),
                ),
                const SizedBox(height: 6),
                Text(
                  'التوقيت الذي ضبطته يبقى كما هو — يتغير نص الآية فقط في المعاينة والتصدير.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء')),
              FilledButton(
                onPressed: dialogAyahIdx == null
                    ? null
                    : () {
                        final ayah = state.ayaat[dialogAyahIdx!];
                        state.changeSegmentAyah(i, ayah);
                        Navigator.pop(context);
                        _toast(
                            'تم التغيير إلى سورة ${ayah.surah} — آية ${ayah.num} ✓');
                      },
                child: const Text('تطبيق'),
              ),
            ],
          );
        },
      ),
    );
  }

  // PATCH_S36_TIMELINE_EDITOR: seek to the previous/next detected ayah.
  void _seekToAdjacentAyah(int dir) {
    final c = _video;
    if (c == null || !c.value.isInitialized || state.timeline.isEmpty) return;
    final t = c.value.position.inMilliseconds / 1000.0;
    double? target;
    if (dir > 0) {
      for (final s in state.timeline) {
        if (s.start > t + 0.25) {
          target = s.start;
          break;
        }
      }
    } else {
      for (final s in state.timeline.reversed) {
        if (s.start < t - 1.0) {
          target = s.start;
          break;
        }
      }
      target ??= state.timeline.first.start;
    }
    if (target != null) {
      c.seekTo(Duration(milliseconds: (target * 1000).round() + 30));
    }
  }

  /// Free manual cut anywhere in the clip — complements the ayah-boundary
  /// trim card that appears once an auto-sync timeline exists.
  Widget _manualCutCard() {
    final dur = state.videoDurationSec;
    final end =
        min(state.trimManualEnd < 0 ? dur : state.trimManualEnd, dur);
    final start = min(max(0.0, state.trimManualStart), end);
    return _card(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('قص المقطع (من — إلى)',
                    style: Theme.of(context).textTheme.labelLarge),
              ),
              Text('${_fmtSec(start)} — ${_fmtSec(end)}',
                  style: const TextStyle(
                      fontSize: 11, color: AyatColors.goldBright)),
              if (state.manualTrimSet)
                IconButton(
                  onPressed: () => state.update(() {
                    state.trimManualStart = 0;
                    state.trimManualEnd = -1;
                  }),
                  icon: const Icon(Icons.restart_alt,
                      size: 18, color: AyatColors.parchmentDim),
                  tooltip: 'إلغاء القص',
                ),
            ],
          ),
          RangeSlider(
            values: RangeValues(start, end),
            max: dur,
            onChanged: (r) => state.update(() {
              state.trimManualStart = r.start;
              state.trimManualEnd = r.end;
            }),
          ),
          Text(
            state.trimFromIndex >= 0 && state.trimToIndex >= 0
                ? 'ملاحظة: نطاق الآيات المحدد أدناه له الأولوية على هذا القص عند التصدير.'
                // PATCH_S86_SCAN_RANGE
                : 'سيُصدَّر هذا النطاق فقط من المقطع — والمزامنة التلقائية ستفحص هذا النطاق وحده (أسرع بكثير في المقاطع الطويلة).',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- tab: تأثيرات
  // PATCH_S34_STAGE_EFFECTS

  Widget _effectsPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('تأثيرات مرئية',
            'مطر أو ثلج أو غبار ضوئي فوق الفيديو أو الخلفية — يظهر التأثير في المعاينة مباشرة ويُدمج في الفيديو المُصدَّر بنفس الشكل.'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final e in StageEffect.values)
              ChoiceChip(
                avatar: Icon(e.icon,
                    size: 15,
                    color: state.effect == e
                        ? AyatColors.goldBright
                        : AyatColors.parchmentDim),
                label: Text(e.label),
                selected: state.effect == e,
                // tapping the already-selected effect cancels it
                onSelected: (_) => state.update(() => state.effect =
                    state.effect == e ? StageEffect.none : e),
              ),
          ],
        ),
        if (state.effect != StageEffect.none) ...[
          _fieldLabel('كثافة التأثير'),
          Slider(
            value: state.effectIntensity,
            min: 0.2,
            max: 1.0,
            onChanged: (v) => state.update(() => state.effectIntensity = v),
          ),
          const SizedBox(height: 4),
          Text(
            'لإلغاء التأثير بسرعة اضغط زر ✕ أعلى المعاينة — لمس المعاينة في أي مكان آخر يوقف/يشغّل الفيديو فقط.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        // PATCH_S38_VIDEO_EFFECTS
        const Divider(height: 32, color: AyatColors.hairline),
        // PATCH_S58_LIVE_EFFECTS_PREVIEW
        _panelTitle('تأثيرات التصدير',
            'معاينة تقريبية مباشرة على المسرح أعلاه — الملف المُصدَّر هو المرجع النهائي للشكل الدقيق. بصري بحت، لا يغيّر صوت التلاوة إطلاقًا.'),
        _fieldLabel('تدرّج لوني'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in kColorGrades)
              ChoiceChip(
                label: Text(entry.$2),
                selected: state.colorGrade == entry.$1,
                onSelected: (_) =>
                    state.update(() => state.colorGrade = entry.$1),
              ),
          ],
        ),
        const SizedBox(height: 10),
        ToggleRow(
          label: 'تظليل الحواف (فينيت)',
          value: state.vignetteEnabled,
          onChanged: (v) => state.update(() => state.vignetteEnabled = v),
        ),
        if (state.vignetteEnabled)
          Slider(
            value: state.vignetteIntensity.toDouble(),
            min: 0,
            max: 100,
            onChanged: (v) =>
                state.update(() => state.vignetteIntensity = v.round()),
          ),
        ToggleRow(
          label: 'حبيبات سينمائية',
          value: state.grainEnabled,
          onChanged: (v) => state.update(() => state.grainEnabled = v),
        ),
        if (state.grainEnabled)
          Slider(
            value: state.grainIntensity.toDouble(),
            min: 0,
            max: 100,
            onChanged: (v) =>
                state.update(() => state.grainIntensity = v.round()),
          ),
        // PATCH_S85_VIDEO_ADJUST: manual picture controls, live in the
        // preview and burned in at export on top of the chosen grade.
        const Divider(height: 32, color: AyatColors.hairline),
        Row(
          children: [
            Expanded(
              child: Text('ضبط الصورة يدويًا',
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
            if (state.hasManualAdjust || state.videoBlur > 0.05)
              TextButton.icon(
                onPressed: () => state.resetManualAdjust(),
                icon: const Icon(Icons.restart_alt,
                    size: 16, color: AyatColors.parchmentDim),
                label: const Text('إعادة الضبط',
                    style: TextStyle(
                        fontSize: 11, color: AyatColors.parchmentDim)),
              ),
          ],
        ),
        _fieldLabel('السطوع'),
        Slider(
          value: state.adjustBrightness,
          min: -0.25,
          max: 0.25,
          onChanged: (v) => state.update(() => state.adjustBrightness = v),
        ),
        _fieldLabel('التباين'),
        Slider(
          value: state.adjustContrast,
          min: 0.7,
          max: 1.4,
          onChanged: (v) => state.update(() => state.adjustContrast = v),
        ),
        _fieldLabel('تشبّع الألوان'),
        Slider(
          value: state.adjustSaturation,
          min: 0.0,
          max: 2.0,
          onChanged: (v) => state.update(() => state.adjustSaturation = v),
        ),
        _fieldLabel('تمويه الفيديو/الخلفية (النص يبقى حادًا)'),
        Slider(
          value: state.videoBlur,
          min: 0.0,
          max: 6.0,
          onChanged: (v) => state.update(() => state.videoBlur = v),
        ),
        const Divider(height: 32, color: AyatColors.hairline),
        ToggleRow(
          label: 'تكبير بطيء للخلفية (كين برنز)',
          value: state.kenBurnsEnabled,
          onChanged: (v) => state.update(() => state.kenBurnsEnabled = v),
        ),
        Text(
          'يُطبَّق على الخلفية فقط (جاهزة، طبيعية، فن ذكاء اصطناعي، أو مخصّصة) — لا يُطبَّق أبدًا على فيديو التلاوة المرفوع نفسه.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        ToggleRow(
          label: 'انتقالات ناعمة حول البسملة والخاتمة',
          value: state.softTransitions,
          onChanged: (v) => state.update(() => state.softTransitions = v),
        ),
        const SizedBox(height: 6),
        Text(
          'ملاحظة: قالب «زجاج مصنفر أنيق» الجديد (تبويب قوالب) يستخدم لوحة نص زجاجية — جرّبه مع هذه التأثيرات.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  // PATCH_S59_TAB_GRID: fixed 4-column grid so 8 tabs always lay out as a
  // clean 4+4, instead of Wrap's width-driven 3/4/1 orphan row.
  Widget _tabChips() {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.55,
      children: [
        for (var i = 0; i < _tabs.length; i++) _tabButton(i),
      ],
    );
  }

  Widget _tabButton(int i) {
    final selected = _selectedTab == i;
    return Material(
      color: selected ? AyatColors.goldBright : AyatColors.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.selectionClick(); // PATCH_S83_SYNC_QOL
          setState(() => _selectedTab = i);
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AyatColors.goldBright : AyatColors.hairline,
            ),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_tabs[i].$1,
                  size: 18,
                  color: selected ? AyatColors.ink : AyatColors.parchmentDim),
              const SizedBox(height: 4),
              Text(_tabs[i].$2,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AyatColors.ink : AyatColors.parchment,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panelCard() {
    return _card(
      child: switch (_selectedTab) {
        0 => _ayahPanel(),
        1 => _bgPanel(),
        2 => _effectsPanel(), // PATCH_S34_STAGE_EFFECTS
        3 => _chromaPanel(),
        4 => _recitersPanel(),
        5 => _templatesPanel(),
        6 => _textPanel(),
        _ => _exportPanel(), // PATCH_S54_PRO_EXPORT_CONTROLS
      },
    );
  }

  // ------------------------------------------------------------ tab: تصدير
  // PATCH_S54_PRO_EXPORT_CONTROLS

  Widget _exportPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('إعدادات التصدير',
            'تحكّم احترافي في الإخراج النهائي — وبلا أي شعار أو علامة مائية أبدًا.'),
        if (state.hasVideo) ...[
          _fieldLabel(
              'ملاءمة الفيديو مع إطار ${kAspectRatios.firstWhere((r) => r.$1 == state.aspectRatio).$2}'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kVideoFitModes)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: state.videoFit == entry.$1,
                  onSelected: (_) =>
                      state.update(() => state.videoFit = entry.$1),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '«احتواء + خلفية ضبابية» يعرض الفيديو كاملًا فوق نسخة ضبابية منه تملأ الإطار (مظهر الريلز الشهير). المعاينة تعرض الاحتواء، والضبابية تُرسم في الفيديو المُصدَّر.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          _fieldLabel('تدوير وقلب الفيديو'),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => state.update(() =>
                    state.videoRotationQuarterTurns =
                        (state.videoRotationQuarterTurns + 1) % 4),
                icon:
                    const Icon(Icons.rotate_90_degrees_cw_outlined, size: 18),
                label: Text(state.videoRotationQuarterTurns == 0
                    ? 'تدوير 90°'
                    : 'تدوير: ${state.videoRotationQuarterTurns * 90}°'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () =>
                    state.update(() => state.videoMirror = !state.videoMirror),
                icon: const Icon(Icons.flip, size: 18),
                label: Text(state.videoMirror ? 'مقلوب ✓' : 'قلب أفقي'),
              ),
            ],
          ),
          const Divider(height: 32, color: AyatColors.hairline),
        ],
        _fieldLabel('جودة الترميز'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in kExportQualities)
              ChoiceChip(
                label: Text(entry.$2),
                selected: state.exportQuality == entry.$1,
                onSelected: (_) =>
                    state.update(() => state.exportQuality = entry.$1),
              ),
          ],
        ),
        _fieldLabel('دقة الإخراج'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in kExportResolutions)
              ChoiceChip(
                label: Text(entry.$2),
                selected: state.exportResolution == entry.$1,
                onSelected: (_) =>
                    state.update(() => state.exportResolution = entry.$1),
              ),
          ],
        ),
        const Divider(height: 32, color: AyatColors.hairline),
        Text('صوت التلاوة في المقطع المُصدَّر',
            style: Theme.of(context).textTheme.headlineMedium),
        _fieldLabel('مستوى الصوت: ${(state.audioVolume * 100).round()}٪'),
        Slider(
          value: state.audioVolume,
          min: 0.0,
          max: 2.0,
          divisions: 40,
          onChanged: (v) => state.update(() => state.audioVolume = v),
        ),
        ToggleRow(
          label: 'دخول تدريجي للصوت (ثانية واحدة)',
          value: state.audioFadeIn,
          onChanged: (v) => state.update(() => state.audioFadeIn = v),
        ),
        ToggleRow(
          label: 'خفوت تدريجي في نهاية المقطع',
          value: state.audioFadeOut,
          onChanged: (v) => state.update(() => state.audioFadeOut = v),
        ),
        const SizedBox(height: 6),
        Text(
          'تُطبَّق هذه الإعدادات على المسار الصوتي المُصدَّر أيًّا كان مصدره (تلاوة مرفقة أو صوت الفيديو نفسه) — التلاوة نفسها لا تُسرَّع ولا تُبطَّأ أبدًا.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _panelTitle(String title, [String? hint]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _fieldLabel(String s) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(s,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AyatColors.goldDim)),
      );

  // ------------------------------------------------------------ tab: الآية

  Widget _ayahPanel() {
    final surahs = <(int, String)>[];
    var last = 0;
    for (final a in state.ayaat) {
      if (a.surahNum != last) {
        surahs.add((a.surahNum, a.surah));
        last = a.surahNum;
      }
    }
    final ayatOfSurah = <(int, Ayah)>[
      for (var i = 0; i < state.ayaat.length; i++)
        if (state.ayaat[i].surahNum == _selectedSurah) (i, state.ayaat[i]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('اختيار الآية',
            'اختر السورة ثم الآية، أو استخدم أزرار التعرّف بالذكاء الاصطناعي، أو اكتب نصًا مخصصًا.'),
        // PATCH_S62_MUSHAF_READER: standalone full-mushaf browser, separate from
        // the single-ayah picker below it -- reuses state.ayaat, no extra load.
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute( // PATCH_S63_MUSHAF_FONT_FIX: pass the user's selected ayah font
                builder: (_) => MushafScreen(
                      ayaat: state.ayaat,
                      fontKey: state.fontKey,
                    )),
          ),
          icon: const Icon(Icons.auto_stories_outlined, size: 18),
          label: const Text('فتح المصحف كاملاً للقراءة'),
        ),
        const SizedBox(height: 6),
        Text(
          'تصفّحي أي سورة واقرئيها كاملة، بمعزل عن تحرير الفيديو.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Divider(height: 28, color: AyatColors.hairline),
        _fieldLabel('السورة'),
        DropdownButton<int>(
          isExpanded: true,
          value: surahs.any((s) => s.$1 == _selectedSurah)
              ? _selectedSurah
              : (surahs.isEmpty ? null : surahs.first.$1),
          items: [
            for (final s in surahs)
              DropdownMenuItem(value: s.$1, child: Text('سورة ${s.$2}')),
          ],
          onChanged: (v) => setState(() => _selectedSurah = v ?? 1),
        ),
        _fieldLabel('الآية'),
        DropdownButton<int>(
          isExpanded: true,
          value: null,
          hint: const Text('اختر الآية'),
          items: [
            for (final e in ayatOfSurah)
              DropdownMenuItem(value: e.$1, child: Text('آية ${e.$2.num}')),
          ],
          onChanged: (v) {
            if (v == null) return;
            final a = state.ayaat[v];
            _liveOverlay.value = null;
            state.setAyah(a.ar, a.en,
                'تم الاختيار يدويًا: سورة ${a.surah} — آية ${a.num}',
                surahNum: a.surahNum, ayahNum: a.num); // PATCH_S32_AI_ART_NANO_BANANA
          },
        ),
        _fieldLabel('أو اكتب الآية (يتم التعرّف عليها من القرآن كاملاً)'),
        TextField(
          controller: _customArCtrl,
          maxLines: 2,
          decoration:
              const InputDecoration(hintText: 'اكتب ولو جزءًا من الآية بالعربية…'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customEnCtrl,
          decoration:
              const InputDecoration(hintText: 'ترجمة المعاني (اختياري)'),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
            onPressed: _applyCustomText,
            child: const Text('تطبيق النص المخصص')),
        const Divider(height: 32, color: AyatColors.hairline),
        // PATCH_S57_MANUAL_MULTI_AYAH_ENTRY: the dropdown above sets ONE static ayah. For a
        // recitation that moves through several ayat, build a manual
        // timeline instead -- this opens the same add-a-segment dialog
        // used by the auto-sync review card, so the first ayah added
        // here becomes the start of a full multi-ayah timeline you can
        // keep extending from the card that appears above once it's
        // no longer empty.
        Text('نطاق آيات متعدد', style: Theme.of(context).textTheme.headlineMedium),
        Text(
          'لتلاوة تمر بعدة آيات، أضيفي كل آية بتوقيتها الخاص -- ستظهر بطاقة \'مراجعة الآيات المرصودة\' أعلى الشاشة بعد أول آية لإكمال الباقي أو تعديل التوقيت.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addManualSegmentDialog,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('إضافة آية إلى خط زمني متعدد'),
        ),
        const Divider(height: 32, color: AyatColors.hairline),
        Text('بطاقات افتتاحية وختامية',
            style: Theme.of(context).textTheme.headlineMedium),
        ToggleRow(
          label: 'بسملة في مقدمة المقطع',
          value: state.showIntro,
          onChanged: (v) => state.update(() => state.showIntro = v),
        ),
        ToggleRow(
          label: 'خاتمة بعد التلاوة',
          value: state.showOutro,
          onChanged: (v) => state.update(() => state.showOutro = v),
        ),
        if (state.showOutro)
          TextField(
            controller: _outroCtrl,
            decoration: const InputDecoration(hintText: 'نص الخاتمة'),
            onChanged: (v) =>
                state.outroText = v.trim().isEmpty ? kDefaultOutro : v.trim(),
          ),
        const SizedBox(height: 6),
        Text(
          'تظهر البسملة والخاتمة كشاشتين مستقلتين قبل/بعد المقطع فقط — لا تُدمجان أبدًا فوق الفيديو أو أي موسيقى.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  // ---------------------------------------------------------- tab: خلفيات

  Widget _bgPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('خلفيات جاهزة',
            'تُستخدم خلف النص إن لم تُحمّل فيديو، أو كخلفية بديلة عند تفعيل الكروم.'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 11,
          crossAxisSpacing: 11,
          childAspectRatio: 9 / 13,
          children: [
            for (var i = 0; i < kBackgrounds.length; i++)
              GestureDetector(
                onTap: () => state.update(() {
                  state.bgIndex = i;
                  state.useCustomBg = false;
                }),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: kBackgrounds[i].gradient,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: (!state.useCustomBg && state.bgIndex == i)
                          ? AyatColors.goldBright
                          : Colors.white.withValues(alpha: 0.05),
                      width:
                          (!state.useCustomBg && state.bgIndex == i) ? 2 : 1,
                    ),
                  ),
                  alignment: Alignment.bottomRight,
                  padding: const EdgeInsets.all(8),
                  child: Text('خلفية ${i + 1}',
                      style: const TextStyle(
                          fontSize: 11, color: AyatColors.parchmentDim)),
                ),
              ),
          ],
        ),
        // PATCH_S29_BG_ANIMATION_TOGGLE: on/off switch for the S28 animated sheen -- only
        // meaningful for the preset gradients above, so it's placed
        // right under them.
        const SizedBox(height: 10),
        ToggleRow(
          label: 'خلفية متحركة',
          value: state.bgAnimated,
          onChanged: (v) => state.update(() => state.bgAnimated = v),
        ),
        // PATCH_S40_MULTI_BG_CYCLE
        const Divider(height: 32, color: AyatColors.hairline),
        ToggleRow(
          label: 'خلفيات متعددة (تبديل تلقائي أثناء التصدير)',
          value: state.multiBgEnabled,
          onChanged: (v) => state.update(() => state.multiBgEnabled = v),
        ),
        if (state.multiBgEnabled) ...[
          const SizedBox(height: 6),
          Text(
            'اضغط على خلفيتين أو أكثر بالترتيب الذي تريد التبديل بينه؛ الرقم على كل خلفية مختارة هو ترتيبها في الدورة. يظهر التبديل في الفيديو المُصدَّر فقط — المعاينة المباشرة تعرض الخلفية المحددة أعلاه. الخلفيات المخصصة/فن الذكاء الاصطناعي تبقى خلفية واحدة.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AyatColors.goldBright),
          ),
          const SizedBox(height: 10),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 11,
            crossAxisSpacing: 11,
            childAspectRatio: 9 / 13,
            children: [
              for (var i = 0; i < kBackgrounds.length; i++)
                GestureDetector(
                  onTap: () => state.update(() {
                    if (state.multiBgIndexes.contains(i)) {
                      state.multiBgIndexes.remove(i);
                    } else {
                      state.multiBgIndexes.add(i);
                    }
                  }),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: kBackgrounds[i].gradient,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: state.multiBgIndexes.contains(i)
                            ? AyatColors.goldBright
                            : Colors.white.withValues(alpha: 0.05),
                        width: state.multiBgIndexes.contains(i) ? 2 : 1,
                      ),
                    ),
                    alignment: Alignment.topLeft,
                    padding: const EdgeInsets.all(8),
                    child: state.multiBgIndexes.contains(i)
                        ? CircleAvatar(
                            radius: 11,
                            backgroundColor: AyatColors.goldBright,
                            child: Text(
                              '${state.multiBgIndexes.indexOf(i) + 1}',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ),
            ],
          ),
          if (state.multiBgIndexes.length < 2) ...[
            const SizedBox(height: 6),
            Text('اختر خلفيتين على الأقل ليعمل التبديل.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AyatColors.parchmentDim)),
          ],
          const SizedBox(height: 12),
          _fieldLabel('التبديل'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kBgSwitchTriggers)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: state.bgSwitchTrigger == entry.$1,
                  onSelected: (_) =>
                      state.update(() => state.bgSwitchTrigger = entry.$1),
                ),
            ],
          ),
          if (state.bgSwitchTrigger == BgSwitchTrigger.ayahs) ...[
            const SizedBox(height: 8),
            _fieldLabel(
                'كل ${state.bgSwitchAyahs} آية/آيات (يتطلب مزامنة تلقائية، وإلا يُستخدم التبديل بالثواني)'),
            Slider(
              value: state.bgSwitchAyahs.toDouble(),
              min: 1,
              max: 10,
              divisions: 9,
              onChanged: (v) =>
                  state.update(() => state.bgSwitchAyahs = v.round()),
            ),
          ] else ...[
            const SizedBox(height: 8),
            _fieldLabel('كل ${state.bgSwitchSeconds} ثانية'),
            Slider(
              value: state.bgSwitchSeconds.toDouble(),
              min: 3,
              max: 30,
              divisions: 27,
              onChanged: (v) =>
                  state.update(() => state.bgSwitchSeconds = v.round()),
            ),
          ],
          const SizedBox(height: 8),
          _fieldLabel('طريقة الانتقال'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kBgTransitionStyles)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: state.bgTransitionStyle == entry.$1,
                  onSelected: (_) =>
                      state.update(() => state.bgTransitionStyle = entry.$1),
                ),
            ],
          ),
          // PATCH_S70_MORE_TRANSITIONS: every non-hardCut style now uses the same
          // duration/overlap slider via xfade, not just crossfade specifically.
          if (state.bgTransitionStyle != BgTransitionStyle.hardCut) ...[
            const SizedBox(height: 8),
            _fieldLabel(
                'مدة الانتقال: ${state.bgCrossfadeDuration.toStringAsFixed(1)} ثانية'),
            Slider(
              value: state.bgCrossfadeDuration,
              min: 0.2,
              max: 3.0,
              divisions: 28,
              onChanged: (v) =>
                  state.update(() => state.bgCrossfadeDuration = v),
            ),
          ],
        ],
        // PATCH_S32_AI_ART_NANO_BANANA
        const Divider(height: 32, color: AyatColors.hairline),
        ToggleRow(
          label: 'فن الذكاء الاصطناعي لكل آية',
          value: state.aiArtEnabled,
          onChanged: (v) => state.update(() => state.aiArtEnabled = v),
        ),
        if (state.aiArtEnabled) ...[
          const SizedBox(height: 6),
          Text(
            // PATCH_S84_AI_ART_MODEL_CHAIN + PATCH_S84_AI_ART_FOLLOWS_PLAYBACK
            'تُنشأ خلفية بأسلوب خطوط متوهجة أحادية اللون لكل آية تُكتشف تلقائيًا، بلا وجوه بشرية أبدًا؛ إن ذُكر نبي في الآية يظهر عمود نور واسمه بخط عربي بدل أي شخصية. '
            'يختار التطبيق تلقائيًا أفضل نموذج مجاني متاح، ومع المزامنة التلقائية يتبدّل الفن مع كل آية أثناء التلاوة (في التلاوات الصوتية أو مع الكروم).',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AyatColors.goldBright),
          ),
          // PATCH_S87_AI_ART_ONE_TAP_FLOW: the API-key field used to sit in
          // plain view and read like a requirement to use the feature at
          // all -- it's optional (S80 made generation fully keyless), so
          // it now lives behind a collapsed "خيارات متقدمة" expander.
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('خيارات متقدمة',
                  style: TextStyle(fontSize: 13, color: AyatColors.parchmentDim)),
              children: [
                TextField(
                  controller: TextEditingController(text: state.pollinationsApiKey)
                    ..selection = TextSelection.collapsed(
                        offset: state.pollinationsApiKey.length),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'مفتاح Pollinations (اختياري)',
                    helperText: 'التوليد يعمل بدون مفتاح -- اتركه فارغًا. أدخل مفتاحك الشخصي فقط لرفع الحد لاحقًا',
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                  onChanged: (v) => state.update(() {
                    state.pollinationsApiKey = v.trim();
                    AiArtService.apiKey = state.pollinationsApiKey;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (state.aiArtError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                state.aiArtError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.redAccent),
              ),
            ),
          // PATCH_S87_AI_ART_ONE_TAP_FLOW: one obvious flow instead of three
          // half-explained states. With an auto-sync timeline active this
          // batch-generates + caches art for the segment's ayat (up to 6)
          // in one tap with live progress; without one it falls back to
          // the single current-ayah path (previous behavior, unchanged).
          if (state.aiArtBatchBusy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text(state.aiArtBatchProgress ?? 'جارٍ توليد الفن...')),
              ]),
            )
          else if (state.aiArtBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('جارٍ توليد الفن...'),
              ]),
            )
          else ...[
            if (state.aiArtBatchProgress != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(state.aiArtBatchProgress!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AyatColors.goldBright)),
              ),
            ElevatedButton.icon(
              onPressed: () => state.timelineActive
                  ? state.generateArtForTimelineBatch()
                  : state.generateAiArtNow(),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(state.timelineActive
                  ? 'توليد الفن لآيات المقطع (حتى 6 آيات)'
                  : 'توليد فن للآية الحالية'),
            ),
            if (state.hasAiArt) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => state.regenerateAiArt(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة توليد فن هذه الآية'),
              ),
              const SizedBox(height: 6),
              // PATCH_S51_AI_ART_DELETE: distinct from regenerate -- wipes
              // the cached image from disk and drops back to the preset
              // background instead of making a new one.
              OutlinedButton.icon(
                onPressed: () => state.deleteAiArt(),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('حذف الفن المولّد لهذه الآية'),
              ),
            ],
          ],
        ],
        const SizedBox(height: 10),
        // PATCH_S82_CUSTOM_BG_LIBRARY: the old single numbered slot
        // (kBackgrounds.length + 1) only made sense for exactly one custom
        // background. Now that every upload is kept, they're shown as their
        // own scrollable gallery instead -- tap to use, long-press to
        // remove from the library (storage itself is uncapped).
        if (state.customBgLibrary.isNotEmpty) ...[
          Text('خلفياتك المرفوعة (${state.customBgLibrary.length})',
              style: const TextStyle(fontSize: 11, color: AyatColors.parchmentDim)),
          const SizedBox(height: 8),
          SizedBox(
            height: 92,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.customBgLibrary.length,
              itemBuilder: (context, i) {
                final path = state.customBgLibrary[i];
                final isActive =
                    state.useCustomBg && state.customBgPath == path;
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: GestureDetector(
                    onTap: () => state.update(() {
                      state.useCustomBg = true;
                      state.customBgPath = path;
                    }),
                    onLongPress: () => state.update(() {
                      state.customBgLibrary.removeAt(i);
                      if (state.customBgPath == path) {
                        state.useCustomBg = false;
                        state.customBgPath = null;
                      }
                    }),
                    child: Container(
                      width: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isActive
                              ? AyatColors.goldBright
                              : Colors.white.withValues(alpha: 0.08),
                          width: isActive ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: File(path).existsSync()
                          ? Image.file(File(path),
                              fit: BoxFit.cover, cacheWidth: 160)
                          : Container(
                              color: Colors.white.withValues(alpha: 0.05)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Text('اضغط مطولًا على أي صورة لحذفها من المكتبة',
              style: TextStyle(
                  fontSize: 10,
                  color: AyatColors.parchmentDim.withValues(alpha: 0.7))),
          const SizedBox(height: 10),
        ],
        ElevatedButton.icon(
          onPressed: _pickCustomBg,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: const Text('ارفع خلفية جديدة'),
        ),
        if (state.useCustomBg) ...[
          const SizedBox(height: 10),
          Text(
            'تذكير: هذه الخلفية ستظهر خلف آيات القرآن — يُستحسن اختيار صور تليق بالمحتوى القرآني (زخارف، خطوط، تدرّجات، مناظر طبيعية مجرّدة)، وتجنّب صور الأشخاص أو أي مشهد لا يناسب تلاوة الآيات.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AyatColors.goldBright),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: () => state.update(() {
              state.useCustomBg = false;
              state.customBgPath = null;
            }),
            child: const Text('إلغاء التفعيل والعودة للخلفيات الجاهزة'),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------------ tab: كروم

  Widget _chromaPanel() {
    Widget colorDot(Color c, {String? label}) {
      final selected = state.chromaColor.toARGB32() == c.toARGB32();
      return GestureDetector(
        onTap: () => state.update(() => state.chromaColor = c),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(
                color: selected ? AyatColors.goldBright : AyatColors.hairline,
                width: selected ? 2.5 : 1),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('الكروم (خلفية خضراء)',
            'فعّل هذا الخيار إذا كان الفيديو المرفوع مصوّرًا أمام خلفية بلون موحّد (أخضر أو أزرق أو غيره)، ليتم استبدالها بالخلفية المختارة عند التصدير.'),
        ToggleRow(
          label: 'تفعيل إزالة الخلفية',
          value: state.chromaEnabled,
          onChanged: (v) => state.update(() => state.chromaEnabled = v),
        ),
        _fieldLabel('لون الشاشة الملوّنة'),
        Row(
          children: [
            GestureDetector(
              onTap: () async {
                final c = await showAyatColorPicker(context, state.chromaColor);
                if (c != null) state.update(() => state.chromaColor = c);
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: state.chromaColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AyatColors.goldBright),
                ),
                child: const Icon(Icons.colorize,
                    size: 15, color: Colors.black54),
              ),
            ),
            const SizedBox(width: 10),
            colorDot(const Color(0xFF00FF00)),
            const SizedBox(width: 8),
            colorDot(const Color(0xFF0000FF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text('اختر نفس لون الشاشة التي صوّرت أمامها',
                  style: Theme.of(context).textTheme.bodyMedium),
            ),
          ],
        ),
        _fieldLabel('قوة إزالة اللون'),
        Slider(
          value: state.chromaThreshold.toDouble(),
          min: 40,
          max: 140,
          onChanged: (v) =>
              state.update(() => state.chromaThreshold = v.round()),
        ),
        _fieldLabel('نعومة حواف القص'),
        Slider(
          value: state.chromaSoftness.toDouble(),
          min: 10,
          max: 90,
          onChanged: (v) =>
              state.update(() => state.chromaSoftness = v.round()),
        ),
        const SizedBox(height: 6),
        Text(
          'تتم إزالة اللون فعليًا على جهازك أثناء التصدير (بمحرك ffmpeg)، ويعمل مع أي لون شاشة تختاره وليس الأخضر فقط. اضبط «القوة» إذا بقيت بقايا من لون الخلفية، و«النعومة» إذا ظهرت حواف حادة حول الشخص. الجودة النهائية تعتمد أيضًا على إضاءة التصوير الأصلية.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  // ------------------------------------------------------------ tab: قرّاء

  Widget _recitersPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('مقاطع صوتية للقرّاء',
            'أرفق تلاوة لكل قارئ ثم اختره لإضافة تلاوته إلى المقطع المُصدَّر. لا يضم التطبيق أي تلاوات مسجّلة مسبقًا — أرفق ملفات مرخّصة لديك.'),
        for (var i = 0; i < kReciters.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: state.reciterIndex == i
                  ? AyatColors.surface3
                  : AyatColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: state.reciterIndex == i
                      ? AyatColors.gold
                      : AyatColors.hairline),
            ),
            child: InkWell(
              onTap: () {
                state.update(() => state.reciterIndex = i);
                _toast('تم اختيار قارئ: ${kReciters[i]}');
              },
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: AyatColors.emerald,
                    child: Text(kReciters[i].characters.first,
                        style: const TextStyle(
                            fontSize: 13, color: AyatColors.goldBright)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kReciters[i],
                            style: Theme.of(context).textTheme.bodyLarge),
                        GestureDetector(
                          onTap: () => _pickReciterAudio(i),
                          child: Text(
                            state.reciterAudioPaths[i] == null
                                ? 'إرفاق تلاوة صوتية'
                                : '✓ ${state.reciterAudioPaths[i]!.split('/').last}',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: state.reciterAudioPaths[i] == null
                                  ? AyatColors.parchmentDim
                                  : AyatColors.goldDim,
                              decoration: TextDecoration.underline,
                              decorationColor: AyatColors.parchmentDim,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _toggleReciterPreview(i),
                    icon: Icon(
                      _previewingReciter == i
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      color: AyatColors.goldBright,
                    ),
                    tooltip: 'تشغيل/إيقاف',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------ tab: قوالب

  Widget _templatesPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('قوالب جاهزة', 'كل قالب يضبط الموضع والخط واللون دفعة واحدة.'),
        for (var i = 0; i < kTemplates.length; i++)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick(); // PATCH_S83_SYNC_QOL
              state.applyTemplate(i);
              _toast('تم تطبيق قالب: ${kTemplates[i].name}');
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: state.templateIndex == i
                    ? AyatColors.surface3
                    : AyatColors.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: state.templateIndex == i
                        ? AyatColors.gold
                        : AyatColors.hairline),
              ),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 52,
                    decoration: BoxDecoration(
                      color: AyatColors.ink,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AyatColors.hairline),
                    ),
                    child: Align(
                      alignment: switch (kTemplates[i].pos) {
                        AyahTextPosition.top => const Alignment(0, -0.7),
                        AyahTextPosition.center => Alignment.center,
                        AyahTextPosition.bottom => const Alignment(0, 0.7),
                      },
                      child: Container(
                          width: 22, height: 3, color: kTemplates[i].color),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(kTemplates[i].name,
                            style: Theme.of(context).textTheme.bodyLarge),
                        Text(kTemplates[i].desc,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------------- tab: النص

  Widget _textPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('تنسيق النص'),
        _fieldLabel('خط الآية'),
        // PATCH_S46_DEFAULT_FONT_AND_GLOW: default fallback is now the bundled elgharib font.
        DropdownButton<String>(
          isExpanded: true,
          value: state.allFonts.any((f) => f.key == state.fontKey)
              ? state.fontKey
              : 'elgharib',
          items: [
            for (final f in state.allFonts)
              DropdownMenuItem(value: f.key, child: Text(f.label)),
          ],
          onChanged: (v) => state.update(() => state.fontKey = v ?? 'elgharib'),
        ),
        const SizedBox(height: 6),
        ElevatedButton.icon(
          onPressed: _pickCustomFont,
          icon: const Icon(Icons.font_download_outlined, size: 18),
          label: const Text('رفع خط مخصص (TTF/OTF)'),
        ),
        const SizedBox(height: 6),
        // PATCH_S39_PERSISTENT_FONTS
        Text(
          'الخطوط المرفوعة تُحفظ داخل التطبيق وتبقى متاحة ومحددة بعد إغلاقه — ارفع خط المصحف المفضل لديك (مثل الغريب نون حفص) مرة واحدة فقط.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        // PATCH_S46_DEFAULT_FONT_AND_GLOW: glow on/off + intensity (plan 2.2)
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('توهّج النص'),
          value: state.glowEnabled,
          onChanged: (v) => state.update(() => state.glowEnabled = v),
        ),
        if (state.glowEnabled) ...[
          _fieldLabel('شدة التوهّج'),
          Slider(
            value: state.glowIntensity,
            min: 0,
            max: 1.5,
            onChanged: (v) => state.update(() => state.glowIntensity = v),
          ),
        ],
        // PATCH_S51_KARAOKE_TOGGLE: on by default; off shows each ayah
        // part as plain static text instead of lighting up word-by-word
        // in step with الشيخ's recitation.
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('تظليل الكلمات مع التلاوة (كاريوكي)'),
          subtitle: const Text(
              'عند الإيقاف: تُعرض الآية كاملة دون إضاءة كل كلمة على حدة'),
          value: state.karaokeEnabled,
          onChanged: (v) => state.update(() => state.karaokeEnabled = v),
        ),
        // PATCH_S48_TEXT_SPACING_TOGGLES
        _fieldLabel('تباعد الأحرف'),
        Slider(
          value: state.letterSpacing,
          min: -1,
          max: 3,
          onChanged: (v) => state.update(() => state.letterSpacing = v),
        ),
        _fieldLabel('تباعد الأسطر'),
        Slider(
          value: state.lineHeightMultiplier,
          min: 1.2,
          max: 2.2,
          onChanged: (v) => state.update(() => state.lineHeightMultiplier = v),
        ),
        _fieldLabel('حجم خط الآية'),
        Slider(
          value: state.ayahFontSize,
          min: 14,
          max: 30,
          onChanged: (v) => state.update(() => state.ayahFontSize = v),
        ),
        _fieldLabel('حجم خط ترجمة المعاني'),
        Slider(
          value: state.transFontSize,
          min: 9,
          max: 18,
          onChanged: (v) => state.update(() => state.transFontSize = v),
        ),
        // PATCH_S50_DRAGGABLE_TEXT: sliders above stay as the fine-tune/reset-to-default
        // controls; drag the ayah text directly on the preview above to
        // reposition, pinch it to resize, or double-tap it to snap back.
        if (state.textOffset != Offset.zero || state.textUserScale != 1.0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: OutlinedButton.icon(
              onPressed: () => state.update(() {
                state.textOffset = Offset.zero;
                state.textUserScale = 1.0;
              }),
              icon: const Icon(Icons.restart_alt, size: 16),
              label: const Text('إعادة موضع/حجم النص للوضع الافتراضي'),
            ),
          ),
        _fieldLabel('لون النص'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final c in kTextColors)
              GestureDetector(
                onTap: () => state.update(() => state.textColor = c),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: state.textColor.toARGB32() == c.toARGB32()
                            ? AyatColors.goldBright
                            : AyatColors.hairline,
                        width:
                            state.textColor.toARGB32() == c.toARGB32() ? 2.5 : 1),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () async {
                final c = await showAyatColorPicker(context, state.textColor);
                if (c != null) state.update(() => state.textColor = c);
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: state.textColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: AyatColors.goldBright),
                ),
                child:
                    const Icon(Icons.colorize, size: 13, color: Colors.black54),
              ),
            ),
          ],
        ),
        _fieldLabel('موضع النص على الشاشة'),
        DropdownButton<AyahTextPosition>(
          isExpanded: true,
          value: state.textPosition,
          items: const [
            DropdownMenuItem(
                value: AyahTextPosition.top, child: Text('أعلى الشاشة')),
            DropdownMenuItem(
                value: AyahTextPosition.center, child: Text('منتصف الشاشة')),
            DropdownMenuItem(
                value: AyahTextPosition.bottom, child: Text('أسفل الشاشة')),
          ],
          onChanged: (v) => state
              .update(() => state.textPosition = v ?? AyahTextPosition.bottom),
        ),
        ToggleRow(
          label: 'إظهار ترجمة المعاني',
          value: state.showTranslation,
          onChanged: (v) => state.update(() => state.showTranslation = v),
        ),
      ],
    );
  }

  Widget _staticDurationRow() {
    return Row(
      children: [
        Expanded(
          child: Text('مدة التصدير بدون فيديو (ثانية)',
              style: Theme.of(context).textTheme.bodyLarge),
        ),
        SizedBox(
          width: 70,
          child: TextField(
            controller: _staticDurCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(isDense: true),
            onChanged: (v) =>
                state.staticDurationSec = (int.tryParse(v) ?? 6).clamp(2, 60),
          ),
        ),
      ],
    );
  }
}
