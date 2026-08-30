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
    show HapticFeedback, rootBundle; // PATCH_S83_SYNC_QOL tactile feedback + PATCH_S107 curated bg assets
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
import '../services/reciter_audio_service.dart'; // PATCH_S104_RECITER_LIBRARY_DOWNLOAD
import '../services/settings_service.dart'; // PATCH_S37_PERSISTENT_SETTINGS
import '../services/stage_effects.dart'; // PATCH_S34_STAGE_EFFECTS
import '../services/subtitle_service.dart'; // PATCH_S125_SUBTITLES
import '../data/text_transitions.dart'; // PATCH_S126_TEXT_TRANSITIONS
import '../services/stage_effects_library.dart'; // PATCH_S125_EFFECTS_LIBRARY
import '../services/overlay_renderer.dart';
import '../services/speech_service.dart';
import '../services/timeline_builder.dart';
import '../services/whisper_service.dart';
import '../services/app_settings.dart'; // PATCH_S123_I18N
import '../theme/ayat_fonts.dart'; // PATCH_S106_FIX_AYAHTEXTSTYLE_IMPORT
import '../theme/ayat_theme.dart';
import '../widgets/ayat_info_dialog.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/gold_switch.dart';
import '../widgets/motion.dart'; // PATCH_S123_MOTION
import '../widgets/quran_entry_button.dart'; // PATCH_S123_QURAN_ENTRY
import '../widgets/stage_preview.dart';
import '../i18n/app_strings.dart';
import '../widgets/first_run_tour.dart';
import '../widgets/text_editor_pro.dart';
import '../widgets/timeline_ribbon.dart'; // PATCH_S83_SYNC_QOL
import 'mushaf_screen.dart'; // PATCH_S62_MUSHAF_READER
import 'sequence_screen.dart'; // PATCH_S125_SEQUENCE
import '../widgets/autoseg_wizard.dart'; // PATCH_S134_AUTOSEG_WIZARD
import 'settings_screen.dart'; // PATCH_S123_SETTINGS_SCREEN

// PATCH_S144_UNIFIED_TEXT_CARD: the three kinds of text a project can
// carry -- the single Quran-matched ayah slot, the single caption
// slot, and the (now unbounded) list of free layers from S143. One
// enum so the add/edit sheet, the row list, and the sheet's own kind
// chips all agree on what "kind" means.
enum _TextKind { ayah, caption, layer }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with WidgetsBindingObserver {
  // PATCH_S128: rebuild when language changes
  // (AppSettings notifies; home already rebuilds via setState from settings return) // PATCH_S91_RELABEL_KARAOKE_AND_SAVE_ON_CLOSE
  final StudioState state = StudioState();

  VideoPlayerController? _video;
  VideoPlayerController? _reciterPreview;
  int? _previewingReciter;
  int? _downloadingReciter; // PATCH_S104_RECITER_LIBRARY_DOWNLOAD
  double? _downloadProgress; // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: 0..1, null = indeterminate

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
  // PATCH_S132_GAUNTLET_LOOP: classic<->grouped have different tab
  // counts (8 vs 5) -- clamp so a stale index can't be out of range.
  int get _safeSelectedTab => _selectedTab.clamp(0, _tabs.length - 1);
  int _selectedSurah = 1;
  // PATCH_S113_AYAH_DROPDOWN_SELECTION_STATE: the "الآية" dropdown's value
  // was hardcoded to null, so it never reflected the chosen ayah and reset
  // to the hint on every rebuild -- looked like the selection wasn't being
  // applied even though it was. This is the missing tracked selection.
  int? _selectedAyahIdx;
  // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: last ayah picked from the dropdown below,
  // so the partial-ayah word-range section knows what to slice from.
  Ayah? _partialSourceAyah;
  int _partialFromWord = 0;
  int _partialToWord = 0;

  // PATCH_S83_SYNC_QOL: playback aids for reviewing a detected timeline.
  static const _speeds = [1.0, 1.25, 1.5, 0.75];
  double _playbackSpeed = 1.0;
  bool _loopAyah = false;
  TimelineSegment? _loopSeg; // the ayah the loop control snaps back to

  // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX: "مراجعة الآيات
  // المرصودة" renders above the ayah panel, but every action that adds a
  // segment to it lives scrolled down inside that panel -- so the card
  // appearing was invisible in practice. This lets code scroll back to
  // it instead of just telling the user to do it themselves in a toast.
  final _scrollCtrl = ScrollController();
  final _customArCtrl = TextEditingController();
  final _customEnCtrl = TextEditingController();
  // PATCH_S143_TEXT_LAYERS: separate from the ayah-matching controllers
  // above -- this box never tries to match the Quran, it just adds a
  // new stacked text layer verbatim.
  final _newLayerCtrl = TextEditingController();
  AyahTextPosition _newLayerPosition = AyahTextPosition.top;
  // PATCH_S144_UNIFIED_TEXT_CARD: which kind the add/edit sheet is
  // currently showing, whether that sheet is editing an existing
  // element (locks the kind chips) or adding a fresh one, and -- only
  // for the layer kind, which is a list rather than a single slot --
  // which index is being edited.
  _TextKind _sheetKind = _TextKind.layer;
  bool _sheetIsEdit = false;
  int? _editingLayerIndex;
  // ---- PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION ----
  final _captionCtrl = TextEditingController();
  final _textStartCtrl = TextEditingController();
  final _textEndCtrl = TextEditingController();
  // PATCH_S125_CUSTOM_ASPECT
  late final _customWCtrl =
      TextEditingController(text: '${state.customAspectW}');
  late final _customHCtrl =
      TextEditingController(text: '${state.customAspectH}');
  // PATCH_S123_WATERMARK
  late final _watermarkCtrl =
      TextEditingController(text: state.watermarkText);
  late final _outroCtrl = TextEditingController(text: state.outroText);
  late final _staticDurCtrl =
      TextEditingController(text: '${state.staticDurationSec}');

  // PATCH_S123_I18N: the tab strip is the app's main navigation, so it is
  // localized even though the deeper panel copy is still Arabic-only.
  // A getter, not a const list, because the language can change at runtime.
  // PATCH_S129_WIRE_AND_SIMPLIFY_UI: five clear groups instead of an 8-tab 4×2 grid.
  // Content (which words) stays in الآيات; look (fonts/border/…) in النص.
  List<(IconData, String)> get _tabs =>
      AppSettings.instance.classicTabs ? _classicTabs : _groupedTabs;

  // PATCH_S132_GAUNTLET_LOOP: was hardcoded Arabic -- the old 8-tab strip
  // was localized via _t(), this one silently wasn't. Fixed.
  List<(IconData, String)> get _groupedTabs => [
        (Icons.menu_book_outlined, _t('studio.group.ayat')),
        (Icons.text_fields, _t('studio.tab.text')),
        (Icons.auto_awesome_outlined, _t('studio.group.shape')),
        (Icons.perm_media_outlined, _t('studio.group.media')),
        (Icons.more_horiz, _t('studio.group.more')),
      ];

  // PATCH_S132_GAUNTLET_LOOP: pre-S129 8-tab grid, recovered verbatim from
  // repo history (commit 62eca15) behind a settings toggle instead of the
  // 5 grouped tabs -- for people who want the old layout back.
  List<(IconData, String)> get _classicTabs => [
        (Icons.menu_book_outlined, _t('studio.tab.ayah')),
        (Icons.dark_mode_outlined, _t('studio.tab.backgrounds')),
        (Icons.water_drop_outlined, _t('studio.tab.effects')),
        (Icons.filter_hdr_outlined, _t('studio.tab.chroma')),
        (Icons.graphic_eq, _t('studio.tab.reciters')),
        (Icons.grid_view_outlined, _t('studio.tab.templates')),
        (Icons.text_fields, _t('studio.tab.text')),
        (Icons.video_settings_outlined, _t('studio.tab.export')),
      ];

  /// Shorthand for a localized string in this screen's chrome.
  String _t(String key) => AppSettings.instance.strings.t(key);

  // PATCH_S123_QURAN_ENTRY: an ayah chosen while reading the mushaf comes
  // straight back here as the studio's current ayah -- same path a manual
  // dropdown pick takes, so AI art, karaoke and the partial-ayah slicer all
  // see it exactly as if it had been picked from the list.
  void _useAyahFromMushaf(Ayah a) {
    final idx = state.ayaat.indexWhere(
        (x) => x.surahNum == a.surahNum && x.num == a.num);
    _liveOverlay.value = null;
    state.setAyah(a.ar, a.en, 'من المصحف: سورة ${a.surah} — آية ${a.num}',
        surahNum: a.surahNum, ayahNum: a.num);
    final words =
        a.ar.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    setState(() {
      _selectedSurah = a.surahNum;
      if (idx >= 0) _selectedAyahIdx = idx;
      _partialSourceAyah = a;
      _partialFromWord = 0;
      _partialToWord = words.isEmpty ? 0 : words.length - 1;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_t('mushaf.ayahAdded'))),
    );
  }

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
      _watermarkCtrl.text = state.watermarkText; // PATCH_S123_WATERMARK
      _customWCtrl.text = '${state.customAspectW}'; // PATCH_S125_CUSTOM_ASPECT
      _customHCtrl.text = '${state.customAspectH}';
    });
    state.addListener(_schedulePersist);
    // PATCH_S91_RELABEL_KARAOKE_AND_SAVE_ON_CLOSE: dispose() only fires when
    // Flutter tears this widget down, not when Android backgrounds the app
    // (home button, app-switch, later process kill) -- which is how this
    // app actually "closes" on a phone almost every time. Without this
    // observer nothing saves at that moment at all.
    WidgetsBinding.instance.addObserver(this);
    // PATCH_S128: one-time 3-step tour
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // PATCH_S132_GAUNTLET_LOOP: WelcomeScreen (shown before this screen)
      // already introduces the app's features -- this second, in-app tour
      // was redundant. Left first_run_tour.dart in place (harmless if
      // re-enabled later) but stopped calling it.
      // if (mounted) FirstRunTour.maybeShow(context);
    });
  }

  // PATCH_S37_PERSISTENT_SETTINGS
  void _schedulePersist() {
    if (!_settingsRestored) return; // don't overwrite saved prefs with defaults
    _persistDebounce?.cancel();
    _persistDebounce = Timer(const Duration(milliseconds: 800), () {
      SettingsService.persist(state);
    });
  }

  // PATCH_S91_RELABEL_KARAOKE_AND_SAVE_ON_CLOSE: paused is the last
  // reliable checkpoint before Android may kill the process outright --
  // flush immediately instead of hoping the 800ms debounce already fired.
  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.paused && _settingsRestored) {
      _persistDebounce?.cancel();
      SettingsService.persist(state);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance
        .removeObserver(this); // PATCH_S91_RELABEL_KARAOKE_AND_SAVE_ON_CLOSE
    state.removeListener(_schedulePersist); // PATCH_S37_PERSISTENT_SETTINGS
    // PATCH_S91_RELABEL_KARAOKE_AND_SAVE_ON_CLOSE: flush, don't just drop,
    // whatever change was still waiting on the debounce.
    _persistDebounce?.cancel();
    // PATCH_S123_QOL: the 10Hz auto-sync ticker was started in initState and
    // never cancelled -- it kept firing _tickAutoSync() against a disposed
    // State (and a disposed VideoPlayerController) after leaving the studio.
    _syncTimer?.cancel();
    if (_settingsRestored) SettingsService.persist(state);
    _video?.dispose();
    _reciterPreview?.dispose();
    _liveOverlay.dispose();
    _scrollCtrl.dispose(); // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX
    _customArCtrl.dispose();
    _customEnCtrl.dispose();
    _newLayerCtrl.dispose(); // PATCH_S143_TEXT_LAYERS
    // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION
    _captionCtrl.dispose();
    _textStartCtrl.dispose();
    _textEndCtrl.dispose();
    _customWCtrl.dispose(); // PATCH_S125_CUSTOM_ASPECT
    _customHCtrl.dispose();
    _watermarkCtrl.dispose(); // PATCH_S123_WATERMARK
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
        // PATCH_S128: prefer i18n when available
        state.corpusStatus =
            AppStrings(AppSettings.instance.lang).t('studio.loaded') + ' ✓'; // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
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

  // PATCH_S125_SEQUENCE: builds a multi-clip sequence in its own screen and
  // adopts the rendered file as the studio's working clip. Everything
  // downstream keeps seeing a single source, so nothing else had to change.
  Future<void> _openSequence() async {
    final (fw, fh) = state.frameSize;
    final merged = await openSequenceBuilder(
      context,
      initialClipPath: state.videoPath,
      frameWidth: fw,
      frameHeight: fh,
    );
    if (merged == null || !mounted) return;
    // A new source invalidates any timeline detected against the old one --
    // setVideo already clears it, which is exactly what's wanted here.
    await _video?.dispose();
    _liveOverlay.value = null;
    _playbackSpeed = 1.0;
    _loopAyah = false;
    _loopSeg = null;
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
      // The rendered sequence should always be a valid mp4, but a preview
      // player refusing it must not lose the render.
    }
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('تم تركيب المقاطع — شغّلي المزامنة التلقائية من جديد')),
    );
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
      final decodeWarning = result.decodeWarning; // PATCH_S97_DECODE_MISMATCH_WARNING
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
            '$qualityWarning'
            // PATCH_S97_DECODE_MISMATCH_WARNING
            '${decodeWarning != null ? '\n$decodeWarning' : ''}';
        state.detectedLabel = 'مزامنة تلقائية مفعّلة — التصدير سيستخدم نفس التوقيت';
      });
      HapticFeedback.mediumImpact(); // PATCH_S83_SYNC_QOL
      // PATCH_S97_DECODE_MISMATCH_WARNING: a different, more specific kind of
      // problem than "detected N ayat" -- worth its own toast, not just a
      // line buried inside the longer summary text.
      if (decodeWarning != null) _toast(decodeWarning);
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

  // PATCH_S107_CURATED_NATURE_BACKGROUNDS: bundled photos are Flutter
  // assets, not files, so the first tap on each copies it once into the
  // app's documents dir and reuses the existing useCustomBg/customBgPath
  // rendering path from then on -- preview, export, and chroma key all
  // already just read customBgPath as a normal file.
  final Map<String, String> _curatedBgResolvedPaths = {};

  Future<void> _useCuratedBg(CuratedBg c) async {
    var path = _curatedBgResolvedPaths[c.asset];
    if (path == null) {
      final docsDir = await getApplicationDocumentsDirectory();
      final bgDir = Directory('${docsDir.path}/curated_bg');
      if (!bgDir.existsSync()) bgDir.createSync(recursive: true);
      final destFile = File('${bgDir.path}/${c.asset.split('/').last}');
      if (!destFile.existsSync()) {
        final data = await rootBundle.load(c.asset);
        await destFile.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      }
      path = destFile.path;
      _curatedBgResolvedPaths[c.asset] = path;
    }
    state.update(() {
      state.useCustomBg = true;
      state.customBgPath = path;
    });
  }

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

  // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: second way to fill a reciter
  // slot -- download the real recitation instead of attaching a file.
  // Reuses state.reciterAudioPaths[i], so playback/export are unchanged.
  Future<void> _downloadReciterAudio(int i) async {
    final name = kReciters[i];
    final surahNum = await _pickSurahForDownload();
    if (surahNum == null || !mounted) return;
    setState(() {
      _downloadingReciter = i;
      _downloadProgress = null;
    });
    try {
      final path = await ReciterAudioService.downloadSurah(
        displayName: name,
        surahNum: surahNum,
        onProgress: (p) {
          if (mounted) setState(() => _downloadProgress = p);
        },
      );
      if (!mounted) return;
      state.update(() => state.reciterAudioPaths[i] = path);
      _toast('تم تنزيل تلاوة $name ✓');
    } on ReciterAudioException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('تعذّر تنزيل الملف الصوتي');
    } finally {
      if (mounted) {
        setState(() {
          _downloadingReciter = null;
          _downloadProgress = null;
        });
      }
    }
  }

  // Surah picker built from the already-loaded Quran corpus (state.matcher)
  // rather than a separately maintained list of 114 surah names.
  Future<int?> _pickSurahForDownload() async {
    final matcher = state.matcher;
    final surahs = <int, String>{};
    if (matcher != null) {
      for (final a in matcher.ayaat) {
        surahs[a.surahNum] = a.surah;
      }
    }
    final entries = surahs.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AyatColors.surface2,
        title: const Text('اختر السورة للتنزيل'),
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: entries.isEmpty
              ? const Center(
                  child: Text('انتظر تحميل بيانات القرآن ثم أعد المحاولة'))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (c, idx) {
                    final e = entries[idx];
                    return ListTile(
                      title: Text('${e.key}. ${e.value}'),
                      onTap: () => Navigator.pop(ctx, e.key),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
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
        title: Text(_t('app.name')),
        actions: [
          // PATCH_S56_UNDO_REDO: tester-requested step back / step forward
          ListenableBuilder(
            listenable: state,
            builder: (context, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: state.canUndo ? state.undoStep : null,
                  icon: const Icon(Icons.undo),
                  tooltip: _t('studio.undo'),
                ),
                IconButton(
                  onPressed: state.canRedo ? state.redoStep : null,
                  icon: const Icon(Icons.redo),
                  tooltip: _t('studio.redo'),
                ),
              ],
            ),
          ),
          // PATCH_S123_SETTINGS_SCREEN: language, animations and the reader's
          // light mode live one tap from anywhere in the studio.
          IconButton(
            onPressed: () => Navigator.of(context)
                .push(AppMotion.route(const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
            tooltip: _t('settings.title'),
          ),
          IconButton(
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
            tooltip: _t('studio.info'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: state,
          builder: (context, _) => SingleChildScrollView(
            controller: _scrollCtrl, // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX
            // PATCH_S145_SCROLL_WORDCOLOR_FONTS_GLOW: EdgeInsets.all(16)
            // gave the same 16px at the bottom as everywhere else, which
            // was never enough clearance past the last card (usually
            // "نطاق آيات متعدد") on gesture-nav phones -- SafeArea alone
            // doesn't add scroll-content padding, so the card's own
            // bottom edge sat right against the screen edge even at max
            // scroll. Extra bottom padding on top of the device's own
            // inset now.
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.of(context).padding.bottom + 40),
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
                _simpleTopTabs(), // PATCH_S128: 5 grouped tabs (آيات/نص/شكل/وسائط/مزيد)
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
            // PATCH_S37_CANCEL_LONG_JOBS: abort export / auto-sync scan.
            // PATCH_S57_RESUMABLE_MODEL_DOWNLOAD: now shown for EVERY busy
            // job — tester feedback: a hung model download used to keep the
            // whole app (including the export button) locked forever. With
            // no job-specific cancel, this releases the UI; a partially
            // downloaded model resumes from where it stopped next time.
            const SizedBox(height: 6),
            TextButton.icon(
              onPressed: () {
                final action = _busyCancelAction;
                if (action != null) {
                  action();
                  setState(() => _busyCancelAction = null);
                  _setBusyStatus('جارٍ الإلغاء…');
                } else {
                  setState(() {
                    _busy = false;
                    _busyStatus = '';
                    _busyProgress = null;
                  });
                  _toast('تم تحرير الواجهة — لو كان تنزيل النموذج جاريًا فسيُستأنف من حيث توقف عند المحاولة القادمة');
                }
              },
              icon: const Icon(Icons.cancel_outlined,
                  size: 16, color: AyatColors.parchmentDim),
              label: const Text('إلغاء العملية',
                  style: TextStyle(
                      fontSize: 12, color: AyatColors.parchmentDim)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ratioToggle() {
    // PATCH_S53_LANDSCAPE_EXPORT: renders all shapes from kAspectRatios instead of
    // two hardcoded chips.
    // PATCH_S125_CUSTOM_ASPECT: plus a custom size, for the platforms and
    // print sizes no preset covers.
    final (fw, fh) = state.frameSize;
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in kAspectRatios)
              ChoiceChip(
                label: Text(AppStrings(AppSettings.instance.lang).t('aspect.${entry.$1.name}')), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
                selected: state.aspectRatio == entry.$1,
                onSelected: (_) =>
                    state.update(() => state.aspectRatio = entry.$1),
              ),
          ],
        ),
        if (state.aspectRatio == AyatAspectRatio.custom) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customWCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'العرض', isDense: true),
                  onChanged: (v) => state.update(() =>
                      state.customAspectW = int.tryParse(v) ?? state.customAspectW),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text('×'),
              ),
              Expanded(
                child: TextField(
                  controller: _customHCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'الارتفاع', isDense: true),
                  onChanged: (v) => state.update(() =>
                      state.customAspectH = int.tryParse(v) ?? state.customAspectH),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            // Both are forced even and clamped, so say what will actually be
            // encoded rather than what was typed -- H.264 cannot encode an
            // odd dimension and libx264 fails outright on one.
            'سيتم التصدير بمقاس $fw × $fh بكسل (يُقرَّب لأقرب رقم زوجي، بين 240 و3840).',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
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
        // PATCH_S125_SEQUENCE: S79's merge is two clips, whole, butted
        // together. This is the general case -- any number of clips, each
        // trimmed, reordered, joined with a real transition.
        OutlinedButton.icon(
          onPressed: _busy ? null : _openSequence,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('تركيب عدة مقاطع (قصّ وترتيب وانتقالات)'),
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
              ? AppStrings(AppSettings.instance.lang).t('autosync.btnRescan')
              : AppStrings(AppSettings.instance.lang).t('autosync.btn')), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
        ),
        // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: set expectations before they tap it --
        // it does the job well on roughly half the video; the rest may
        // need a manual touch-up from the review card above.
        const SizedBox(height: 6),
        Text(
          AppStrings(AppSettings.instance.lang).t('autosync.hint'), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AyatColors.goldDim),
        ),
      ],
    );
  }

  // PATCH_S134_AUTOSEG_WIZARD: guided multi-step entry point (the
  // reference "Auto-Segmentation Wizard"). The wizard lives in its
  // own file; everything it changes flows through existing
  // StudioState APIs (addManualSegment / whisperModelSize), same as
  // every other dialog in this file.
  Widget _autoSegWizardCard() {
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          const Icon(Icons.auto_awesome_outlined,
              color: AyatColors.gold, size: 20),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_t('wizard.title'),
                  style: Theme.of(context).textTheme.titleSmall)),
        ]),
        const SizedBox(height: 4),
        Text(_t('wizard.subtitle'),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AyatColors.goldDim)),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _openAutoSegWizard,
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: Text(_t('wizard.launch')),
        ),
      ],
    ));
  }

  // PATCH_S134_AUTOSEG_WIZARD: opens the wizard and surfaces its result
  // through the existing toast/timeline-card plumbing.
  Future<void> _openAutoSegWizard() async {
    final res = await showAutoSegWizard(
      context: context,
      state: state,
      audioPath: _video?.dataSource,
    );
    if (res == null) return;
    if (res.importedSegments > 0) {
      _revealTimelineCard();
      _toast('${_t('wizard.imported')}: ${res.importedSegments} \u2713');
    } else if (res.tierApplied) {
      _toast(_t('wizard.localNote'));
    } else if (res.cloudChosen) {
      _toast(_t('wizard.cloudNote'));
    }
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
                  // PATCH_S128: AyahBlocksEditor can replace the ribbon:
                  // AyahBlocksEditor(segs: _segVMs(), durationSec: _clipDur(),
                  //     onChanged: () => state.pushHistory()),
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

  // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX: "مراجعة الآيات
  // المرصودة" sits above the panel/tabs -- animate back up to it after a
  // segment is added so it's actually seen instead of scrolled past.
  void _revealTimelineCard() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        0,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
      );
    });
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
                        _revealTimelineCard(); // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX
                        _toast(wasEmpty
                            ? 'أُضيفت الآية الأولى ✓ — إلى \'مراجعة الآيات المرصودة\' أعلى الشاشة'
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
                            // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: mark
                            // segments that only carry part of the ayah so
                            // they're not mistaken for the full ayah at a
                            // glance in the review list.
                            'سورة ${seg.ayah.surah} — آية ${seg.ayah.num}'
                            '${seg.textOverride != null ? ' (جزء)' : ''}',
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
                child: Text(AppStrings(AppSettings.instance.lang).t('trim.label'), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
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
            '${StageEffect.values.length - 1} تأثيرًا فوق الفيديو أو الخلفية — يظهر التأثير في المعاينة مباشرة ويُدمج في الفيديو المُصدَّر بنفس الشكل.'),
        // PATCH_S125_EFFECTS_LIBRARY: 74 effects in one flat Wrap is a wall of
        // chips nobody reads to the end of. Grouped by category, with the
        // group holding the current selection expanded, it stays a menu.
        _EffectPicker(
          selected: state.effect,
          onSelected: (e) => state.update(
              () => state.effect = state.effect == e ? StageEffect.none : e),
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
        // PATCH_S100_FONTS_SPINSTAR_TINT: quick blue/gold presets plus a full
        // color picker (showAyatColorPicker), so any color works, not just
        // the two swatches.
        _fieldLabel('تدرّج بلون مخصص (أزرق / ذهبي / أي لون)'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: () => state.update(() => state.tintColor = null),
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: state.tintColor == null
                          ? AyatColors.goldBright
                          : AyatColors.hairline,
                      width: state.tintColor == null ? 2.5 : 1),
                ),
                child: const Icon(Icons.block, size: 16, color: AyatColors.parchmentDim),
              ),
            ),
            for (final preset in const [
              (Color(0xFF2A6FDB), 'أزرق'),
              (Color(0xFFD4A017), 'ذهبي'),
            ])
              GestureDetector(
                onTap: () => state.update(() => state.tintColor = preset.$1),
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: preset.$1,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: state.tintColor?.toARGB32() ==
                                preset.$1.toARGB32()
                            ? AyatColors.goldBright
                            : AyatColors.hairline,
                        width: state.tintColor?.toARGB32() ==
                                preset.$1.toARGB32()
                            ? 2.5
                            : 1),
                  ),
                ),
              ),
            GestureDetector(
              onTap: () async {
                final c = await showAyatColorPicker(
                    context, state.tintColor ?? AyatColors.gold);
                if (c != null) state.update(() => state.tintColor = c);
              },
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: state.tintColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AyatColors.goldBright),
                ),
                child: const Icon(Icons.colorize, size: 15, color: Colors.black54),
              ),
            ),
          ],
        ),
        if (state.tintColor != null)
          Slider(
            value: state.tintIntensity.toDouble(),
            min: 0,
            max: 100,
            onChanged: (v) => state.update(() => state.tintIntensity = v.round()),
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
  // PATCH_S129_WIRE_AND_SIMPLIFY_UI: one horizontal row of 5 equal chips — easy to scan.
  Widget _tabChips() {
    // PATCH_S132_GAUNTLET_LOOP: classic mode uses the original fixed
    // 4-column grid (8 tabs never fit a single Row); grouped mode keeps
    // the current 5-wide Row unchanged.
    if (AppSettings.instance.classicTabs) {
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
    return Row(
      children: [
        for (var i = 0; i < _tabs.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : 4,
                right: i == _tabs.length - 1 ? 0 : 4,
              ),
              child: _tabButton(i),
            ),
          ),
      ],
    );
  }

  // PATCH_S129_WIRE_AND_SIMPLIFY_UI: compact chip — icon + short label, works in a 5-wide row.
  Widget _tabButton(int i) {
    final selected = _selectedTab == i;
    return Material(
      color: selected ? AyatColors.goldBright : AyatColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _selectedTab = i);
        },
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
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
              const SizedBox(height: 2),
              Text(_tabs[i].$2,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected ? AyatColors.ink : AyatColors.parchment,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  // PATCH_S129_WIRE_AND_SIMPLIFY_UI: case map matches the 5-group bar.
  // النص (1) finally mounts TextEditorPro instead of the old plain panel.
  Widget _panelCard() {
    return _card(
      child: AppSettings.instance.classicTabs
          ? switch (_selectedTab) {
              0 => _ayahPanel(),
              1 => _bgPanel(),
              2 => _effectsPanel(),
              3 => _chromaPanel(),
              4 => _recitersPanel(),
              5 => _templatesPanel(),
              6 => _textEditorProPanel(),
              _ => _exportPanel(),
            }
          : switch (_selectedTab) {
              0 => _ayahPanel(),
              1 => _textEditorProPanel(),
              2 => _shapePanel(),   // effects + templates
              3 => _mediaPanel(),   // backgrounds + chroma + reciters
              _ => _exportPanel(),
            },
    );
  }

  // PATCH_S129_WIRE_AND_SIMPLIFY_UI: "الشكل" — visual look (particles + ready templates).
  Widget _shapePanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _effectsPanel(),
        const Divider(height: 28, color: AyatColors.hairline),
        _templatesPanel(),
      ],
    );
  }

  // PATCH_S129_WIRE_AND_SIMPLIFY_UI: "الوسائط" — backgrounds, chroma, reciter audio.
  Widget _mediaPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _bgPanel(),
        const Divider(height: 28, color: AyatColors.hairline),
        _chromaPanel(),
        const Divider(height: 28, color: AyatColors.hairline),
        _recitersPanel(),
      ],
    );
  }

  // ------------------------------------------------------------ tab: تصدير
  // PATCH_S54_PRO_EXPORT_CONTROLS

  Widget _exportPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _panelTitle('إعدادات التصدير',
            'تحكّم احترافي في الإخراج النهائي — بلا أي شعار للتطبيق، ولا علامة مائية إلا التي تضيفينها بنفسك.'),
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
        // PATCH_S123_AUDIO_MIX: attaching a reciter used to silence the clip
        // outright. This keeps the original underneath at a chosen level.
        if (state.selectedReciterAudio != null && state.hasVideo) ...[
          _fieldLabel(
              '${_t('audio.originalUnder')}: ${(state.originalAudioMix * 100).round()}٪'),
          Slider(
            value: state.originalAudioMix,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: (v) => state.update(() => state.originalAudioMix = v),
          ),
          Text(_t('audio.originalUnderHint'),
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 6),
        ],
        ToggleRow(
          label: _t('audio.muteAll'),
          value: state.muteAudio,
          onChanged: (v) => state.update(() => state.muteAudio = v),
        ),
        const SizedBox(height: 6),
        Text(
          'تُطبَّق هذه الإعدادات على المسار الصوتي المُصدَّر أيًّا كان مصدره (تلاوة مرفقة أو صوت الفيديو نفسه) — التلاوة نفسها لا تُسرَّع ولا تُبطَّأ أبدًا.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const Divider(height: 32, color: AyatColors.hairline),
        _musicBedSection(),
        const Divider(height: 32, color: AyatColors.hairline),
        _speedSection(),
        const Divider(height: 32, color: AyatColors.hairline),
        _subtitleSection(),
        const Divider(height: 32, color: AyatColors.hairline),
        _watermarkSection(),
      ],
    );
  }

  // PATCH_S126_TEXT_TRANSITIONS: how the ayah text arrives and leaves.
  // Split in/out, because "rise in, fade out" is the pairing most people
  // actually want and forcing one setting for both makes it unreachable.
  Widget _textTransitionSection() {
    Widget picker({
      required String label,
      required TextTransition current,
      required ValueChanged<TextTransition> onPick,
    }) {
      final plain = TextTransition.values.where((t) => !t.isReveal).toList();
      final reveals = TextTransition.values.where((t) => t.isReveal).toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fieldLabel(label),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in plain)
                ChoiceChip(
                  label: Text(t.labelAr),
                  selected: current == t,
                  onSelected: (_) => onPick(t),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text('كشف تدريجي',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AyatColors.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in reveals)
                ChoiceChip(
                  label: Text(t.labelAr),
                  selected: current == t,
                  onSelected: (_) => onPick(t),
                ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ظهور النص واختفاؤه',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          '${TextTransition.values.length} أسلوبًا لدخول النص وخروجه. المعاينة '
          'أعلاه تعرض الأسلوب نفسه الذي سيُدمج في الفيديو تمامًا.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        picker(
          label: 'أسلوب الدخول',
          current: state.textInTransition,
          onPick: (t) => state.update(() => state.textInTransition = t),
        ),
        const SizedBox(height: 14),
        picker(
          label: 'أسلوب الخروج',
          current: state.textOutTransition,
          onPick: (t) => state.update(() => state.textOutTransition = t),
        ),
        const SizedBox(height: 14),
        _fieldLabel('مدة الحركة: ${state.textTransitionMs} مللي ثانية'),
        Slider(
          value: state.textTransitionMs
              .toDouble()
              .clamp(kMinTextTransitionMs.toDouble(),
                  kMaxTextTransitionMs.toDouble()),
          min: kMinTextTransitionMs.toDouble(),
          max: kMaxTextTransitionMs.toDouble(),
          divisions: (kMaxTextTransitionMs - kMinTextTransitionMs) ~/ 50,
          onChanged: (v) =>
              state.update(() => state.textTransitionMs = v.round()),
        ),
        Text(
          'الأطول أهدأ وأنعم. تُرسم الحركة بـ ${ExportService.overlayFps} إطارًا '
          'في الثانية عند التصدير، فلا يظهر أي تقطيع.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  // PATCH_S127_MUSIC_BED: an ambience/nasheed track UNDER everything else.
  // Distinct from the reciter mix above, which only rebalances the two tracks
  // that were already in the clip.
  Widget _musicBedSection() {
    final path = state.musicBedPath;
    final name = path == null ? null : path.split(Platform.pathSeparator).last;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('خلفية موسيقية / أجواء',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'مسار صوتي هادئ يُمزج تحت التلاوة وصوت المقطع. يُكرَّر تلقائيًا إذا '
          'كان أقصر من الفيديو ويُقصّ إذا كان أطول، فلا حاجة لمطابقة المدة.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickMusicBed,
                icon: const Icon(Icons.library_music_outlined),
                label: Text(path == null ? 'اختيار ملف صوتي' : 'تغيير الملف'),
              ),
            ),
            if (path != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'إزالة الخلفية الموسيقية',
                onPressed: () => state.update(() => state.musicBedPath = null),
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
        if (name != null) ...[
          const SizedBox(height: 6),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AyatColors.gold)),
          const SizedBox(height: 10),
          _fieldLabel(
              'مستوى الخلفية: ${(state.musicBedVolume * 100).round()}٪'),
          Slider(
            value: state.musicBedVolume,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            onChanged: (v) => state.update(() => state.musicBedVolume = v),
          ),
          ToggleRow(
            label: 'دخول وخروج تدريجي للخلفية',
            value: state.musicBedFade,
            onChanged: (v) => state.update(() => state.musicBedFade = v),
          ),
          if (state.muteAudio)
            Text('الصوت مكتوم بالكامل حاليًا — أوقف الكتم لتسمع الخلفية.',
                style: Theme.of(context).textTheme.bodyMedium),
        ],
      ],
    );
  }

  Future<void> _pickMusicBed() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = res?.files.single.path;
    if (path == null) return;
    state.update(() => state.musicBedPath = path);
    _toast('تمت إضافة خلفية موسيقية ✓');
  }

  // PATCH_S125_SPEED: constant-rate speed change, applied to the finished
  // composite so picture, synced text and particles all move together.
  Widget _speedSection() {
    const presets = [0.25, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0];
    final hasReciter = state.selectedReciterAudio != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('سرعة المقطع', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'أقل من ١× حركة بطيئة، وأكثر تسريع. تُطبَّق على الصورة وعلى نص الآية '
          'المتزامن معًا، فلا ينفصل أحدهما عن الآخر.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final sp in presets)
              ChoiceChip(
                label: Text(sp == 1.0 ? 'عادي ١×' : '${sp}×'),
                selected: (state.playbackSpeed - sp).abs() < 0.005,
                onSelected: (_) =>
                    state.update(() => state.playbackSpeed = sp),
              ),
          ],
        ),
        if (state.hasSpeedChange) ...[
          const SizedBox(height: 8),
          Text(
            hasReciter
                ? 'تلاوة القارئ المرفقة لا تُسرَّع ولا تُبطَّأ إطلاقًا — تبقى بطبقة '
                    'صوتها الأصلية. السرعة تُطبَّق على الصورة وصوت المقطع فقط.'
                : 'صوت المقطع الأصلي يتغيّر مع الصورة للحفاظ على التزامن.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AyatColors.goldBright),
          ),
        ],
      ],
    );
  }

  // PATCH_S125_SUBTITLES: the auto-sync timeline already knows which ayah was
  // recited between which two seconds -- that IS a subtitle track, it just
  // had nowhere to go. Burned-in text can't be switched off, translated or
  // read by a screen reader; a sidecar file can.
  Widget _subtitleSection() {
    final cues = SubtitleService.cueCount(state.timeline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('ملف الترجمة (SRT / VTT)',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'يُحفظ ملف ترجمة بجانب الفيديو في مجلد التنزيلات، مبنيًّا على توقيت '
          'الآيات المرصودة. مفيد ليوتيوب وللمشاهدين الذين يحتاجون نصًا يمكن '
          'إيقافه أو ترجمته — بخلاف النص المحروق في الصورة.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        ToggleRow(
          label: 'تصدير ملف ترجمة مع الفيديو',
          value: state.exportSubtitles,
          onChanged: (v) => state.update(() => state.exportSubtitles = v),
        ),
        if (state.exportSubtitles) ...[
          const SizedBox(height: 8),
          if (state.timeline.isEmpty)
            Text(
              'لا توجد آيات مرصودة بعد — شغّلي «المزامنة التلقائية» أو أضيفي '
              'آيات للخط الزمني يدويًا، وإلا فلن يحتوي الملف على شيء.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AyatColors.goldBright),
            )
          else
            Text('سيحتوي الملف على $cues مقطعًا نصيًا.',
                style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          _fieldLabel('الصيغة'),
          Wrap(
            spacing: 8,
            children: [
              for (final f in SubtitleFormat.values)
                ChoiceChip(
                  label: Text(f.labelAr),
                  selected: state.subtitleFormat == f,
                  onSelected: (_) =>
                      state.update(() => state.subtitleFormat = f),
                ),
            ],
          ),
          _fieldLabel('المحتوى'),
          Wrap(
            spacing: 8,
            children: [
              for (final c in SubtitleContent.values)
                ChoiceChip(
                  label: Text(switch (c) {
                    SubtitleContent.arabic => 'الآية بالعربية',
                    SubtitleContent.translation => 'ترجمة المعاني',
                    SubtitleContent.both => 'الاثنان معًا',
                  }),
                  selected: state.subtitleContent == c,
                  onSelected: (_) =>
                      state.update(() => state.subtitleContent = c),
                ),
            ],
          ),
        ],
      ],
    );
  }

  // PATCH_S123_WATERMARK: opt-in, and visibly so. The app adds nothing to an
  // export by default and never asks for money to remove a mark it put there
  // itself -- this exists so a channel can sign its OWN work.
  Widget _watermarkSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_t('wm.section'),
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(_t('wm.hint'), style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 8),
        ToggleRow(
          label: _t('wm.enable'),
          value: state.watermarkEnabled,
          onChanged: (v) => state.update(() => state.watermarkEnabled = v),
        ),
        if (state.watermarkEnabled) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _watermarkCtrl,
            decoration: InputDecoration(
              labelText: _t('wm.text'),
              hintText: 'مثال: قناة نور',
            ),
            onChanged: (v) => state.update(() => state.watermarkText = v),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickWatermarkImage,
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: Text(state.watermarkImagePath == null
                      ? _t('wm.pickImage')
                      : _t('wm.image')),
                ),
              ),
              if (state.watermarkImagePath != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: _t('wm.clearImage'),
                  onPressed: () =>
                      state.update(() => state.watermarkImagePath = null),
                  icon: const Icon(Icons.close, color: AyatColors.gold),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            state.watermarkImagePath == null
                ? 'بدون صورة ستُستخدم الكتابة أعلاه.'
                : 'الصورة تحلّ محل النص. أزيليها للعودة إلى الكتابة.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 10),
          _fieldLabel(_t('wm.position')),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final entry in kWatermarkCorners)
                ChoiceChip(
                  label: Text(entry.$2),
                  selected: state.watermarkCorner == entry.$1,
                  onSelected: (_) =>
                      state.update(() => state.watermarkCorner = entry.$1),
                ),
            ],
          ),
          _fieldLabel(
              '${_t('wm.size')}: ${(state.watermarkScale * 100).round()}٪'),
          Slider(
            value: state.watermarkScale,
            min: 0.08,
            max: 0.45,
            divisions: 37,
            onChanged: (v) => state.update(() => state.watermarkScale = v),
          ),
          _fieldLabel(
              '${_t('wm.opacity')}: ${(state.watermarkOpacity * 100).round()}٪'),
          Slider(
            value: state.watermarkOpacity,
            min: 0.15,
            max: 1.0,
            divisions: 17,
            onChanged: (v) => state.update(() => state.watermarkOpacity = v),
          ),
        ],
      ],
    );
  }

  // PATCH_S123_WATERMARK: copied into app storage like the background
  // uploads (S64) -- a picked file's original path can be a temporary
  // content:// cache entry that no longer resolves on the next launch.
  Future<void> _pickWatermarkImage() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final src = res?.files.single.path;
    if (src == null) return;
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/watermark');
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final ext = src.contains('.') ? src.split('.').last : 'png';
      final dst =
          '${dir.path}/wm_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await File(src).copy(dst);
      state.update(() {
        state.watermarkImagePath = dst;
        state.watermarkEnabled = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('تعذّر استخدام هذه الصورة: $e')));
    }
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

  // PATCH_S128: tabbed pro text editor
  // PATCH_S132_GAUNTLET_LOOP: the 30-style transitions section
  // (_textTransitionSection, PATCH_S126) never got ported into
  // TextEditorPro when S128 replaced the old _textPanel() -- it still
  // works exactly as before, it was just orphaned. Mounted alongside
  // the tabbed editor instead of duplicating 30 already-correct entries.
  Widget _textEditorProPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextEditorPro(
            state: state,
            segmentTexts: state.unifiedTexts,
            canvasWidth: 1080,
            onPickCustomFont: _pickCustomFont,
          ),
          const Divider(height: 32, color: AyatColors.hairline),
          _textTransitionSection(),
        ],
      );

  // PATCH_S128_FIX1_BUILD_ERRORS: bridge only -- PATCH_S128 called this but never
  // defined it. This just restores the old tab strip so the app
  // builds. TODO: replace with the real 5 grouped tabs
  // (آيات/نص/شكل/وسائط/مزيد) described in the PATCH_S128 comment.
  Widget _simpleTopTabs() => _tabChips();

  // PATCH_S120_ADVANCED_OPTIONS_CLEANUP: shared header for every optional
  // section below the ayah picker (partial-ayah, red words, manual
  // timing, caption, multi-ayah range, intro/outro cards). badgeNum
  // reuses the same gold ayahNumberBadge size/style as the السورة/الآية
  // dropdown above (size: 22, fontSize: 10) instead of each section
  // picking its own -- that mismatch was the "floating circle" mess.
  // The long explanation moves into a tap-to-open popup instead of
  // sitting permanently inline under the title.
  Widget _sectionHeader(String title, String infoText, {int? badgeNum}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (badgeNum != null) ...[
          ayahNumberBadge(badgeNum, size: 22, fontSize: 10),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.info_outline,
              size: 19, color: AyatColors.goldDim),
          tooltip: 'توضيح',
          onPressed: () => _showSectionInfo(title, infoText),
        ),
      ],
    );
  }

  Future<void> _showSectionInfo(String title, String text) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AyatColors.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        content: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  // One consistent bordered surface for every optional section instead
  // of the previous mix of bare SizedBox/Divider spacers between them.
  Widget _sectionCard(Widget child) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AyatColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AyatColors.hairline),
      ),
      child: child,
    );
  }

  // ------------------------------------------------------------ tab: الآية

  // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: lets you use only part of the
  // currently-picked ayah (e.g. the first half) as the on-screen text,
  // instead of always the whole ayah. Purely a text-slicing UI -- the
  // result still goes through the normal state.setAyah() path, so
  // AI-art/karaoke/export don't need to know the difference.
  Widget _partialAyahSection() {
    final a = _partialSourceAyah;
    if (a == null) return const SizedBox.shrink();
    final words = a.ar.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2) return const SizedBox.shrink();
    final from = _partialFromWord.clamp(0, words.length - 1);
    final to = _partialToWord.clamp(from, words.length - 1);
    final partialText = words.sublist(from, to + 1).join(' ');
    final isFull = from == 0 && to == words.length - 1;
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          _t('partial.use'), // PATCH_S134_AUTOSEG_WIZARD
          'اختاري من أي كلمة إلى أي كلمة من الآية المحددة أعلاه -- مفيد لعرض '
          'نصفها فقط مثلاً بدل الآية كاملة، أو لإضافتها كمقطع مستقل في الخط '
          'الزمني أدناه. مثال: لو اخترتِ من الكلمة الأولى إلى الثالثة فقط '
          'يظهر هذا الجزء بمفرده -- إمّا كنص الآية نفسه، أو كمقطع منفصل عبر '
          '"إضافة هذا الجزء إلى الخط الزمني" أسفل الصفحة.',
          badgeNum: a.num,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                decoration: InputDecoration(labelText: _t('partial.fromWord')), // PATCH_S134_AUTOSEG_WIZARD
                initialValue: from,
                items: [
                  for (var i = 0; i < words.length; i++)
                    DropdownMenuItem(
                      value: i,
                      // PATCH_S107_WORD_DROPDOWN_FONT: match the ayah font
                      // picked under 'خط الآية', same fix S105 already did
                      // for the preview box below.
                      child: Text('${i + 1}. ${words[i]}',
                          style: ayahTextStyle(state.fontKey, fontSize: 15)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _partialFromWord = v ?? 0;
                  if (_partialToWord < _partialFromWord) {
                    _partialToWord = _partialFromWord;
                  }
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                decoration: InputDecoration(labelText: _t('partial.toWord')), // PATCH_S134_AUTOSEG_WIZARD
                initialValue: to,
                items: [
                  for (var i = 0; i < words.length; i++)
                    DropdownMenuItem(
                      value: i,
                      // PATCH_S107_WORD_DROPDOWN_FONT: match the ayah font
                      // picked under 'خط الآية', same fix S105 already did
                      // for the preview box below.
                      child: Text('${i + 1}. ${words[i]}',
                          style: ayahTextStyle(state.fontKey, fontSize: 15)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _partialToWord = v ?? (words.length - 1);
                  if (_partialFromWord > _partialToWord) {
                    _partialFromWord = _partialToWord;
                  }
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: more breathing room around
        // the preview text itself (was a tight EdgeInsets.all(10)).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            border: Border.all(color: AyatColors.hairline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(partialText,
              textAlign: TextAlign.center,
              // PATCH_S105_DEFAULT_FONT_PREVIEW: use the ayah font the user
              // actually picked under 'خط الآية' (state.fontKey) instead of
              // the generic UI text style, so this preview matches what
              // will actually be exported.
              style: ayahTextStyle(state.fontKey,
                  fontSize: 20, color: AyatColors.parchment)),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: isFull
              ? null
              : () {
                  _liveOverlay.value = null;
                  state.setAyah(
                    partialText,
                    a.en,
                    'جزء من: سورة ${a.surah} — آية ${a.num}',
                    surahNum: a.surahNum,
                    ayahNum: a.num,
                  );
                  _toast(_t('partial.usedToast')); // PATCH_S134_AUTOSEG_WIZARD
                },
          child: Text(_t(isFull ? 'partial.full' : 'partial.useThis')), // PATCH_S134_AUTOSEG_WIZARD
        ),
        const SizedBox(height: 8),
        // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: the missing link between
        // this picker and "نطاق آيات متعدد" -- adds the sliced words as a
        // real timeline segment (chained after the last one, like the
        // full-ayah manual-add dialog), which makes timelineActive true
        // and brings up "مراجعة الآيات المرصودة" immediately. No video or
        // audio required, same as adding a full ayah manually.
        // PATCH_S119_TIMELINE_VISIBILITY_AND_ENABLE_FIX: this was disabled
        // whenever the picked range equalled the full ayah (isFull), but
        // that's the default selection AND the only possible selection
        // for any 2-word ayah -- adding a *whole* ayah to the timeline is
        // completely valid (it's what the full-ayah dialog already does
        // with no such restriction), so this button no longer checks
        // isFull at all.
        OutlinedButton.icon(
          onPressed: () {
            final start =
                state.timeline.isNotEmpty ? state.timeline.last.end : 0.0;
            final end = start + 4;
            state.addManualSegment(a, start, end, textOverride: partialText);
            _revealTimelineCard();
            _toast(_t('partial.addedToast')); // PATCH_S134_AUTOSEG_WIZARD
          },
          icon: const Icon(Icons.playlist_add, size: 18),
          label: Text(_t('partial.addToTimeline')), // PATCH_S134_AUTOSEG_WIZARD
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: tap a word of the currently
  // displayed ayah to color just that word red in the exported video.
  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION / PATCH_S146_FINISH_WORDCOLORS:
  // "تلوين كلمات بالأحمر" and "توقيت ظهور النص يدويًا" used to be two
  // separate boxes stacked back-to-back, even though both are the same
  // job -- extra control over how the on-screen ayah text stands out --
  // and coloring a word used to only ever mean red, applied instantly
  // with no other option. Now one card: pick a color (red by default,
  // same as before, or any color via the picker), tap words to
  // paint/unpaint them with it, and set when the whole ayah text
  // (colored words included) appears/disappears -- one place instead
  // of two.
  Widget _manualTimingSection() {
    final words = state.ayahText
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'تلوين الكلمات وتوقيت ظهورها (اختياري)',
          'اختاري لونًا ثم اضغطي على أي كلمة لتلوينها به في الفيديو '
          'المُصدَّر -- مفيدة لتمييز اسم الجلالة أو كلمة محورية. اضغطي '
          'الكلمة مجددًا لإزالة لونها. حدّدي أيضًا بالثواني متى يظهر نص '
          'الآية ومتى يختفي؛ اتركي الحقلين فارغين ليظهر طوال المقطع '
          'كالمعتاد.',
        ),
        if (words.isNotEmpty) ...[
          const SizedBox(height: 10),
          // PATCH_S145/S146: the color the next tap applies -- defaults to
          // red so tapping a word behaves exactly like before unless a
          // different color is chosen first.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final c in const [
                Color(0xFFE53935), // red -- the old, only option
                Color(0xFFECC875), // gold
                Color(0xFFFFFFFF), // white
                Color(0xFF4CAF50), // green
                Color(0xFF2A6FDB), // blue
              ])
                GestureDetector(
                  onTap: () => state.update(() => state.activeWordColor = c),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: state.activeWordColor.toARGB32() ==
                                  c.toARGB32()
                              ? AyatColors.goldBright
                              : Colors.black26,
                          width: state.activeWordColor.toARGB32() ==
                                  c.toARGB32()
                              ? 2.5
                              : 1),
                    ),
                  ),
                ),
              GestureDetector(
                onTap: () async {
                  final c = await showAyatColorPicker(
                      context, state.activeWordColor);
                  if (c != null) {
                    state.update(() => state.activeWordColor = c);
                  }
                },
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: state.activeWordColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AyatColors.goldBright),
                  ),
                  child: const Icon(Icons.colorize,
                      size: 14, color: Colors.black54),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < words.length; i++)
                FilterChip(
                  label: Text(words[i],
                      style: ayahTextStyle(state.fontKey, fontSize: 14)),
                  selected: state.wordColors.containsKey(i),
                  selectedColor:
                      (state.wordColors[i] ?? state.activeWordColor)
                          .withValues(alpha: 0.35),
                  onSelected: (sel) => state.update(() {
                    if (sel) {
                      state.wordColors[i] = state.activeWordColor;
                    } else {
                      state.wordColors.remove(i);
                    }
                  }),
                ),
            ],
          ),
        ],
        const Divider(height: 28, color: AyatColors.hairline),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textStartCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'يبدأ عند (ثانية)'),
                onChanged: (v) => state.update(
                    () => state.textTimeStartOverride = double.tryParse(v)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _textEndCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ينتهي عند (ثانية)'),
                onChanged: (v) => state.update(
                    () => state.textTimeEndOverride = double.tryParse(v)),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'مسح التوقيت اليدوي',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _textStartCtrl.clear();
                _textEndCtrl.clear();
                state.update(() {
                  state.textTimeStartOverride = null;
                  state.textTimeEndOverride = null;
                });
              }),
            ),
          ],
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: free-text caption (reciter
  // name, ayah-range label, ...) shown near the top or bottom of the frame.
  Widget _captionSection() {
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'نص إضافي (اسم الشيخ، نطاق الآيات...)',
          'مثال: "من آية ١٦ إلى ١٨" أو اسم القارئ -- يظهر كسطر صغير أعلى أو '
          'أسفل الفيديو، بمعزل تمامًا عن نص الآية نفسه، ويمكن اختيار مكانه '
          '(أعلى أو أسفل) من الخيارين تحت الحقل.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _captionCtrl,
          decoration: const InputDecoration(
              hintText: 'مثال: الشيخ عبد الباسط عبد الصمد'),
          onChanged: (v) => state.update(() => state.captionText = v),
        ),
        const SizedBox(height: 4),
        // PATCH_S123_QOL: RadioListTile's own groupValue/onChanged are
        // deprecated -- the group is declared once by the RadioGroup
        // ancestor now, and each tile only carries its own value.
        RadioGroup<CaptionPosition>(
          groupValue: state.captionPosition,
          onChanged: (v) => state.update(
              () => state.captionPosition = v ?? CaptionPosition.bottom),
          child: Row(
            children: [
              for (final pos in CaptionPosition.values)
                Expanded(
                  child: RadioListTile<CaptionPosition>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(pos == CaptionPosition.top ? 'أعلى' : 'أسفل'),
                    value: pos,
                  ),
                ),
            ],
          ),
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }

  // -------------------------------------------------------------------
  // PATCH_S144_UNIFIED_TEXT_CARD
  //
  // Before this patch, "text on the video" was three separate cards in
  // the الآية tab: "اكتب نص الآية" (Quran-matched ayah text), "طبقات نص
  // ثابتة" (S143's stacked free layers), and a third card further down
  // the same tab for a small caption (reciter name / ayah range). Three
  // boxes for one job, each with its own explanation and its own
  // Add/Apply button, and no single place showing everything that's
  // actually on the video right now.
  //
  // This replaces all three with ONE card: a list of every text
  // element currently on the video (ayah, then caption, then every
  // layer, in that order) with one edit (pencil) and one delete (X)
  // action per row -- the same two-icon pattern InShot and every other
  // mainstream video editor uses for an on-canvas text element -- plus
  // a single "+ إضافة نص" button that opens one add/edit sheet shared
  // by all three kinds.
  //
  // Nothing about WHAT each kind does changes underneath: ayah text
  // still runs through the same Quran matcher (_applyCustomText),
  // captions still write state.captionText/captionPosition, layers
  // still go through state.addTextLayer/updateTextLayerAt/
  // removeTextLayerAt exactly as PATCH_S143 left them. This patch only
  // changes how you reach those three actions -- one door instead of
  // three.
  // -------------------------------------------------------------------

  Widget _unifiedTextCard() {
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'النص على الفيديو',
          'مكان واحد لكل نص يظهر على الفيديو — نص الآية، تسمية توضيحية '
          '(مثل اسم القارئ)، وأي عدد تريدينه من طبقات النص الحرة. لكل '
          'عنصر أدناه زر تعديل (✎) وزر حذف (✕)، وتظهر كل العناصر معًا '
          'فوق الفيديو دون أن يستبدل أحدها الآخر.',
        ),
        const SizedBox(height: 10),
        _textElementsList(),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () => _openTextSheet(),
          icon: const Icon(Icons.add, size: 20),
          label: const Text('إضافة نص'),
        ),
      ],
    ));
  }

  // One row per element currently on the video, in a fixed order
  // (ayah, then caption, then layers) so the list doesn't reshuffle
  // as you edit things. Empty state explains what the button below
  // does instead of just showing a blank card.
  Widget _textElementsList() {
    final rows = <Widget>[];
    if (state.hasAyah) {
      rows.add(_textElementRow(
        icon: Icons.menu_book_outlined,
        kindLabel: 'آية',
        preview: state.ayahText,
        onEdit: () => _openTextSheet(kind: _TextKind.ayah),
        onDelete: () => state.setAyah('', '', ''),
      ));
    }
    if (state.captionText.isNotEmpty) {
      rows.add(_textElementRow(
        icon: Icons.label_outline,
        kindLabel: 'تسمية',
        preview: state.captionText,
        onEdit: () => _openTextSheet(kind: _TextKind.caption),
        onDelete: () {
          state.update(() => state.captionText = '');
          _captionCtrl.clear();
        },
      ));
    }
    for (var i = 0; i < state.textLayers.length; i++) {
      final layer = state.textLayers[i];
      rows.add(_textElementRow(
        icon: Icons.layers_outlined,
        kindLabel: 'طبقة',
        preview: layer.text,
        onEdit: () => _openTextSheet(kind: _TextKind.layer, layerIndex: i),
        onDelete: () => state.removeTextLayerAt(i),
      ));
    }
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          border: Border.all(color: AyatColors.hairline),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(children: [
          const Icon(Icons.text_fields,
              size: 24, color: AyatColors.parchmentDim),
          const SizedBox(height: 6),
          Text('لا يوجد أي نص على الفيديو بعد',
              style: Theme.of(context).textTheme.bodyMedium),
        ]),
      );
    }
    return Column(children: [
      for (final r in rows)
        Padding(padding: const EdgeInsets.only(bottom: 6), child: r),
    ]);
  }

  // Same bordered-row look S143 introduced for layers, now shared by
  // all three kinds, with a small gold kind badge (آية/تسمية/طبقة) so
  // the mixed list still reads clearly at a glance -- plus the
  // edit-pencil that S143's layer rows never had.
  Widget _textElementRow({
    required IconData icon,
    required String kindLabel,
    required String preview,
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: AyatColors.hairline),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Icon(icon, size: 17, color: AyatColors.goldDim),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: AyatColors.surface,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(kindLabel,
              style:
                  const TextStyle(fontSize: 10, color: AyatColors.goldDim)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            preview,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textDirection: TextDirection.rtl,
          ),
        ),
        IconButton(
          tooltip: 'تعديل',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: onEdit,
        ),
        IconButton(
          tooltip: 'حذف',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
          icon: const Icon(Icons.cancel, size: 18, color: Colors.redAccent),
          onPressed: onDelete,
        ),
      ]),
    );
  }

  String _textKindTitle(_TextKind k, bool isEdit) => switch (k) {
        _TextKind.ayah => isEdit ? 'تعديل نص الآية' : 'كتابة نص الآية',
        _TextKind.caption =>
          isEdit ? 'تعديل التسمية التوضيحية' : 'تسمية توضيحية جديدة',
        _TextKind.layer => isEdit ? 'تعديل طبقة النص' : 'طبقة نص جديدة',
      };

  // The single entry point for every "add" or "edit" of text on the
  // video. Called with no args from the "+ إضافة نص" button (fresh add,
  // starts on the "نص حر" kind); called with a kind (+ layerIndex for
  // layers) from a row's own edit pencil, which also locks the kind
  // chips so an in-progress edit can't accidentally turn into adding a
  // different kind of element.
  void _openTextSheet({_TextKind? kind, int? layerIndex}) {
    _sheetIsEdit = kind != null;
    _editingLayerIndex = layerIndex;
    if (kind == _TextKind.ayah) {
      _customArCtrl.text = state.ayahText;
      _customEnCtrl.text = state.translationText;
      _sheetKind = _TextKind.ayah;
    } else if (kind == _TextKind.caption) {
      _captionCtrl.text = state.captionText;
      _sheetKind = _TextKind.caption;
    } else if (kind == _TextKind.layer && layerIndex != null) {
      final l = state.textLayers[layerIndex];
      _newLayerCtrl.text = l.text;
      _newLayerPosition = l.position;
      _sheetKind = _TextKind.layer;
    } else {
      _newLayerCtrl.clear();
      _newLayerPosition = AyahTextPosition.top;
      _sheetKind = _TextKind.layer;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AyatColors.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 18,
            right: 18,
            top: 14,
            bottom: MediaQuery.of(context).viewInsets.bottom + 18,
          ),
          // PATCH_S147_TEXT_SHEET_SCROLL_FIX: the sheet's content
          // (title + kind chips + fields + buttons) doesn't fit above
          // the keyboard once it opens -- scroll instead of clipping
          // the bottom (which used to cut off the Apply/Save buttons).
          child: SingleChildScrollView(
            child: _textSheetBody(context, setSheetState),
          ),
        ),
      ),
    );
  }

  Widget _textSheetBody(BuildContext context, StateSetter setSheetState) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: Text(_textKindTitle(_sheetKind, _sheetIsEdit),
                style: Theme.of(context).textTheme.headlineMedium),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ]),
        // Kind chips only show when adding fresh -- editing an existing
        // element keeps its kind fixed, same as you can't turn a
        // caption into a layer by fiddling with it after the fact.
        if (!_sheetIsEdit) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 8, children: [
            for (final k in _TextKind.values)
              ChoiceChip(
                label: Text(switch (k) {
                  _TextKind.ayah => 'آية قرآنية',
                  _TextKind.caption => 'تسمية توضيحية',
                  _TextKind.layer => 'نص حر',
                }),
                selected: _sheetKind == k,
                onSelected: (_) => setSheetState(() {
                  _sheetKind = k;
                  // ayah/caption are single slots -- switching to them
                  // from the fresh-add flow should show what's already
                  // there (if anything) instead of a misleadingly
                  // blank field.
                  if (k == _TextKind.ayah) {
                    _customArCtrl.text = state.ayahText;
                    _customEnCtrl.text = state.translationText;
                  } else if (k == _TextKind.caption) {
                    _captionCtrl.text = state.captionText;
                  } else {
                    _newLayerCtrl.clear();
                    _newLayerPosition = AyahTextPosition.top;
                  }
                }),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        switch (_sheetKind) {
          _TextKind.ayah => _ayahSheetFields(context),
          _TextKind.caption => _captionSheetFields(context, setSheetState),
          _TextKind.layer => _layerSheetFields(context, setSheetState),
        },
        const SizedBox(height: 8),
      ],
    );
  }

  // Same matcher flow _applyCustomText() always ran -- only the field
  // now lives in the sheet instead of its own card. Both actions close
  // the sheet first, then run the (possibly async, possibly
  // dialog-showing) existing method on the main screen underneath.
  Widget _ayahSheetFields(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'اكتبي الآية أو أي نص عربي — سيُطابَق تلقائيًا مع القرآن إن '
          'أمكن، وإلا يُستخدم كما كتبتِه.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customArCtrl,
          maxLines: 3,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            hintText: 'اكتب الآية أو أي نص عربي…',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _customEnCtrl,
          decoration:
              const InputDecoration(hintText: 'ترجمة المعاني (اختياري)'),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _applyCustomText();
              },
              child: const Text('تطبيق على الفيديو'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _saveTypedTextToTimeline();
              },
              icon: const Icon(Icons.timeline, size: 18),
              label: const Text('حفظ في الخط الزمني'))),
        ]),
      ],
    );
  }

  Widget _captionSheetFields(
      BuildContext context, StateSetter setSheetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _captionCtrl,
          decoration: const InputDecoration(
              hintText: 'مثال: الشيخ عبد الباسط عبد الصمد'),
          onChanged: (v) => state.update(() => state.captionText = v),
        ),
        const SizedBox(height: 4),
        RadioGroup<CaptionPosition>(
          groupValue: state.captionPosition,
          onChanged: (v) => setSheetState(() => state.update(
              () => state.captionPosition = v ?? CaptionPosition.bottom)),
          child: Row(
            children: [
              for (final pos in CaptionPosition.values)
                Expanded(
                  child: RadioListTile<CaptionPosition>(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text(pos == CaptionPosition.top ? 'أعلى' : 'أسفل'),
                    value: pos,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('تم'),
        ),
      ],
    );
  }

  Widget _layerSheetFields(BuildContext context, StateSetter setSheetState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _newLayerCtrl,
          maxLines: 2,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            hintText: 'اكتب أي نص… (اسم القناة، تعليق، عنوان، ...)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          const Text('الموضع:'),
          const SizedBox(width: 10),
          DropdownButton<AyahTextPosition>(
            value: _newLayerPosition,
            items: const [
              DropdownMenuItem(
                  value: AyahTextPosition.top, child: Text('أعلى الشاشة')),
              DropdownMenuItem(
                  value: AyahTextPosition.center,
                  child: Text('منتصف الشاشة')),
              DropdownMenuItem(
                  value: AyahTextPosition.bottom,
                  child: Text('أسفل الشاشة')),
            ],
            onChanged: (v) => setSheetState(
                () => _newLayerPosition = v ?? AyahTextPosition.top),
          ),
        ]),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: () {
            final txt = _newLayerCtrl.text.trim();
            if (txt.isEmpty) {
              _toast('اكتبي نصًا أولًا');
              return;
            }
            if (_editingLayerIndex != null) {
              // Preserve whatever fontSize/color the layer already had
              // -- there's no per-layer style control yet (S144 doesn't
              // add one), so this only ever carries S143's own
              // defaults today, but won't silently reset a real custom
              // value if a future patch adds that control.
              final orig = state.textLayers[_editingLayerIndex!];
              state.updateTextLayerAt(
                  _editingLayerIndex!,
                  TextLayer(
                      text: txt,
                      position: _newLayerPosition,
                      fontSize: orig.fontSize,
                      color: orig.color));
            } else {
              state.addTextLayer(
                  TextLayer(text: txt, position: _newLayerPosition));
            }
            _newLayerCtrl.clear();
            Navigator.pop(context);
          },
          icon: Icon(
              _editingLayerIndex != null
                  ? Icons.check
                  : Icons.add_box_outlined,
              size: 18),
          label: Text(
              _editingLayerIndex != null ? 'حفظ التعديل' : 'إضافة الطبقة'),
        ),
      ],
    );
  }

  Future<void> _saveTypedTextToTimeline() async {
    final ar = _customArCtrl.text.trim();
    if (ar.isEmpty) {
      _toast('اكتب النص أولًا');
      return;
    }
    final en = _customEnCtrl.text.trim();
    final m = state.matcher?.match(ar);
    final ayah = m?.ayah ??
        Ayah(surahNum: 0, surah: 'نص مخصص', num: 0, ar: ar, en: en);
    final range = await _pickTextTimeRange();
    if (range == null) return;
    state.addManualSegment(ayah, range.$1, range.$2, textOverride: ar);
    _revealTimelineCard();
    _toast('حُفظ النص في الخط الزمني ✓ — سيظهر من ${_fmtSec(range.$1)} '
        'إلى ${_fmtSec(range.$2)}');
  }

  Future<(double, double)?> _pickTextTimeRange() {
    final sCtrl = TextEditingController(text: '0');
    final eCtrl = TextEditingController(text: '5');
    return showDialog<(double, double)>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, setS) {
        void chip(double a, double b) => setS(() {
          sCtrl.text = a.toStringAsFixed(0);
          eCtrl.text = b.toStringAsFixed(0);
        });
        final dur = state.videoDurationSec;
        return AlertDialog(
          backgroundColor: AyatColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AyatColors.hairline)),
          title: const Text('متى يظهر هذا النص؟'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final r in const [
                  (0.0, 5.0), (5.0, 10.0), (10.0, 15.0), (15.0, 20.0)
                ])
                  ActionChip(
                    label: Text('${r.$1.toInt()}–${r.$2.toInt()} ث'),
                    onPressed: () => chip(r.$1, r.$2)),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(child: TextField(
                  controller: sCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'من (ث)'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(
                  controller: eCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'إلى (ث)'))),
              ]),
              if (dur > 0) ...[
                const SizedBox(height: 6),
                Text('مدة الفيديو: ${_fmtSec(dur)}',
                  style: const TextStyle(
                      fontSize: 11, color: AyatColors.parchmentDim)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء')),
            FilledButton(onPressed: () {
              final s = double.tryParse(sCtrl.text) ?? 0;
              var e = double.tryParse(eCtrl.text) ?? (s + 5);
              if (dur > 0) e = e.clamp(0, dur);
              if (e <= s) {
                _toast('النهاية يجب أن تكون بعد البداية');
                return;
              }
              Navigator.pop(context, (s.clamp(0, 9999), e));
            }, child: const Text('حفظ')),
          ],
        );
      }),
    );
  }

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
        // PATCH_S144_UNIFIED_TEXT_CARD: the ayah-matching card, S143's
        // "طبقات نص ثابتة" layers card, and the caption card further
        // down this tab used to be three separate boxes for one job
        // (text on the video). They're now one list + one add/edit
        // sheet -- see _unifiedTextCard() and its supporting methods
        // below. _captionSection() is left defined but uncalled --
        // nothing else references it, kept only so a future patch
        // can resurrect the standalone caption box without redoing it
        // from scratch.
        _unifiedTextCard(),
        // PATCH_S62_MUSHAF_READER: standalone full-mushaf browser, separate from
        // the single-ayah picker below it -- reuses state.ayaat, no extra load.
        // PATCH_S123_QURAN_ENTRY: was a bare OutlinedButton -- the plainest
        // control on the screen for the app's most meaningful destination.
        // Now the ornamented card, and it hands the chosen ayah straight back
        // into the editor instead of being a read-only detour.
        QuranEntryButton(
          title: _t('mushaf.open'),
          subtitle: _t('mushaf.openHint'),
          onTap: () => Navigator.push(
            context,
            AppMotion.route( // PATCH_S63_MUSHAF_FONT_FIX: pass the user's selected ayah font
              MushafScreen(
                ayaat: state.ayaat,
                fontKey: state.fontKey,
                initialSurah: _selectedSurah,
                onUseAyah: _useAyahFromMushaf,
              ),
            ),
          ),
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
          onChanged: (v) => setState(() {
            _selectedSurah = v ?? 1;
            // PATCH_S113_AYAH_DROPDOWN_SELECTION_STATE: old index belonged
            // to the previous surah's ayah list -- drop it instead of
            // pointing at the wrong ayah (or a now out-of-range index).
            _selectedAyahIdx = null;
          }),
        ),
        _fieldLabel('الآية'),
        DropdownButton<int>(
          isExpanded: true,
          value: _selectedAyahIdx,
          hint: const Text('اختر الآية'),
          items: [
            for (final e in ayatOfSurah)
              // PATCH_S105_GOLD_AYAH_BADGE: gold-circle number badge instead
              // of plain "آية N" text, matching the mushaf reader's style.
              DropdownMenuItem(
                value: e.$1,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ayahNumberBadge(e.$2.num, size: 22, fontSize: 10),
                    const SizedBox(width: 8),
                    Text('آية ${e.$2.num}'),
                  ],
                ),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            final a = state.ayaat[v];
            _liveOverlay.value = null;
            state.setAyah(a.ar, a.en,
                'تم الاختيار يدويًا: سورة ${a.surah} — آية ${a.num}',
                surahNum: a.surahNum, ayahNum: a.num); // PATCH_S32_AI_ART_NANO_BANANA
            // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH
            final words = a.ar.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
            setState(() {
              // PATCH_S113_AYAH_DROPDOWN_SELECTION_STATE: actually remember
              // the picked index so the dropdown shows it instead of
              // snapping back to the 'اختر الآية' hint.
              _selectedAyahIdx = v;
              _partialSourceAyah = a;
              _partialFromWord = 0;
              _partialToWord = words.isEmpty ? 0 : words.length - 1;
            });
          },
        ),
        if (_partialSourceAyah != null) _partialAyahSection(),
        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION / PATCH_S146_FINISH_WORDCOLORS
        _manualTimingSection(),
        // PATCH_S144_UNIFIED_TEXT_CARD: caption is now one of the rows
        // in _unifiedTextCard() above, not its own card down here.
        _autoSegWizardCard(), // PATCH_S134_AUTOSEG_WIZARD
        // PATCH_S57_MANUAL_MULTI_AYAH_ENTRY: the dropdown above sets ONE static ayah. For a
        // recitation that moves through several ayat, build a manual
        // timeline instead -- this opens the same add-a-segment dialog
        // used by the auto-sync review card, so the first ayah added
        // here becomes the start of a full multi-ayah timeline you can
        // keep extending from the card that appears above once it's
        // no longer empty.
        // PATCH_S120_ADVANCED_OPTIONS_CLEANUP: card replaces the old bare
        // Divider(height: 32) that used to separate this from the field
        // above -- the card's own border/margin does that job now.
        _sectionCard(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(
              AppStrings(AppSettings.instance.lang).t('multi.range'), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
              'لتلاوة تمر بعدة آيات، أضيفي كل آية بتوقيتها الخاص. ستظهر '
              'بطاقة \'مراجعة الآيات المرصودة\' أعلى الشاشة بعد أول آية '
              'لإكمال الباقي أو تعديل التوقيت -- يمكنك إضافة آية كاملة من '
              'هنا، أو جزء من آية فقط عبر قسم "استخدام جزء من الآية فقط" '
              'أعلاه.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addManualSegmentDialog,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('إضافة آية إلى خط زمني متعدد'),
            ),
          ],
        )),
        _sectionCard(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(
              'بطاقات افتتاحية وختامية',
              'تظهر البسملة والخاتمة كشاشتين مستقلتين قبل/بعد المقطع فقط — '
              'لا تُدمجان أبدًا فوق الفيديو أو أي موسيقى. عطّلي أيًا منهما '
              'إن لم ترغبي بها، ويمكنك تخصيص نص الخاتمة بعد تفعيلها.',
            ),
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
                onChanged: (v) => state.outroText =
                    v.trim().isEmpty ? kDefaultOutro : v.trim(),
              ),
          ],
        )),
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
        // PATCH_S107_CURATED_NATURE_BACKGROUNDS
        Text('خلفيات طبيعية جاهزة',
            style: const TextStyle(fontSize: 11, color: AyatColors.parchmentDim)),
        const SizedBox(height: 8),
        SizedBox(
          height: 92,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: kCuratedBackgrounds.length,
            itemBuilder: (context, i) {
              final c = kCuratedBackgrounds[i];
              final isActive = state.useCustomBg &&
                  state.customBgPath == _curatedBgResolvedPaths[c.asset];
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: GestureDetector(
                  onTap: () => _useCuratedBg(c),
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
                    child: Image.asset(c.asset, fit: BoxFit.cover, cacheWidth: 160),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text('اضغط على أي صورة لاستخدامها كخلفية مباشرة',
            style: TextStyle(
                fontSize: 10,
                color: AyatColors.parchmentDim.withValues(alpha: 0.7))),
        const SizedBox(height: 10),
        ElevatedButton.icon(
          onPressed: _pickCustomBg,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: const Text('ارفع خلفية جديدة'),
        ),
        if (state.useCustomBg) ...[
          const SizedBox(height: 10),
          Text(
            AppStrings(AppSettings.instance.lang).t('bg.customNote'), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
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
          label: AppStrings(AppSettings.instance.lang).t('chroma.enable'), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
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
            // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: no longer true that the app
            // can only use manually-attached files -- it can fetch real
            // recitations from mp3quran.net now.
            'اختر قارئًا ثم إمّا نزّل تلاوته لسورة معيّنة من الإنترنت، أو أرفق ملف تلاوة خاص بك.'),
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
                  // PATCH_S104_RECITER_LIBRARY_DOWNLOAD: download this
                  // reciter's audio for a chosen سورة straight from the
                  // internet instead of attaching a file.
                  _downloadingReciter == i
                      ? SizedBox(
                          width: 40,
                          height: 40,
                          child: Padding(
                            padding: const EdgeInsets.all(9),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              value: _downloadProgress,
                              color: AyatColors.goldBright,
                            ),
                          ),
                        )
                      : IconButton(
                          onPressed: () => _downloadReciterAudio(i),
                          icon: const Icon(
                            Icons.cloud_download_outlined,
                            color: AyatColors.goldBright,
                          ),
                          tooltip: 'تنزيل من الإنترنت',
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
        // PATCH_S126_TEXT_TRANSITIONS
        _textTransitionSection(),
        const Divider(height: 32, color: AyatColors.hairline),
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

// PATCH_S125_EFFECTS_LIBRARY: category-grouped effect picker. One category is
// open at a time (the one holding the current selection, so reopening the
// panel lands you where you left off), and "بدون تأثير" is always reachable
// at the top rather than buried inside a group.
class _EffectPicker extends StatefulWidget {
  final StageEffect selected;
  final ValueChanged<StageEffect> onSelected;
  const _EffectPicker({required this.selected, required this.onSelected});

  @override
  State<_EffectPicker> createState() => _EffectPickerState();
}

class _EffectPickerState extends State<_EffectPicker> {
  late EffectCategory _open = widget.selected == StageEffect.none
      ? EffectCategory.nature
      : widget.selected.category;

  @override
  void didUpdateWidget(covariant _EffectPicker old) {
    super.didUpdateWidget(old);
    if (widget.selected != old.selected &&
        widget.selected != StageEffect.none) {
      _open = widget.selected.category;
    }
  }

  @override
  Widget build(BuildContext context) {
    final byCategory = <EffectCategory, List<StageEffect>>{};
    for (final e in StageEffect.values) {
      if (e == StageEffect.none) continue;
      byCategory.putIfAbsent(e.category, () => []).add(e);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ChoiceChip(
            avatar: const Icon(Icons.block, size: 15),
            label: Text(StageEffect.none.label),
            selected: widget.selected == StageEffect.none,
            onSelected: (_) => widget.onSelected(StageEffect.none),
          ),
        ),
        const SizedBox(height: 10),
        for (final cat in EffectCategory.values)
          if ((byCategory[cat] ?? const []).isNotEmpty) ...[
            InkWell(
              onTap: () => setState(() => _open = cat),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Icon(cat.icon,
                        size: 16,
                        color: _open == cat
                            ? AyatColors.goldBright
                            : AyatColors.parchmentDim),
                    const SizedBox(width: 8),
                    Text(
                      cat.labelAr,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _open == cat
                            ? AyatColors.goldBright
                            : AyatColors.parchmentDim,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text('(${byCategory[cat]!.length})',
                        style: const TextStyle(
                            fontSize: 11, color: AyatColors.parchmentDim)),
                    const Spacer(),
                    Icon(
                      _open == cat ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AyatColors.gold,
                    ),
                  ],
                ),
              ),
            ),
            if (_open == cat)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final e in byCategory[cat]!)
                      ChoiceChip(
                        avatar: Icon(e.icon,
                            size: 15,
                            color: widget.selected == e
                                ? AyatColors.goldBright
                                : AyatColors.parchmentDim),
                        label: Text(e.label),
                        selected: widget.selected == e,
                        onSelected: (_) => widget.onSelected(e),
                      ),
                  ],
                ),
              ),
            const Divider(height: 1, color: AyatColors.hairline),
          ],
      ],
    );
  }
}
