// استوديو الآيات — the full native studio screen, feature-matched to the
// HTML prototype: ayah selection (manual / typed / mic / from-video-audio /
// auto-sync timeline), backgrounds, chroma settings, reciters, templates,
// text formatting, ayah-boundary trim and real MP4 export.
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data' show ByteData;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../data/quran_repository.dart';
import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import '../services/ayah_matcher.dart';
import '../services/export_service.dart';
import '../services/media_service.dart';
import '../services/overlay_renderer.dart';
import '../services/speech_service.dart';
import '../services/timeline_builder.dart';
import '../services/whisper_service.dart';
import '../theme/ayat_theme.dart';
import '../widgets/ayat_info_dialog.dart';
import '../widgets/color_picker_dialog.dart';
import '../widgets/gold_switch.dart';
import '../widgets/stage_preview.dart';

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
  bool _listening = false;

  int _selectedTab = 0;
  int _customFontCounter = 0;
  int _selectedSurah = 1;

  final _customArCtrl = TextEditingController();
  final _customEnCtrl = TextEditingController();
  late final _outroCtrl = TextEditingController(text: state.outroText);
  late final _staticDurCtrl =
      TextEditingController(text: '${state.staticDurationSec}');

  static const _tabs = [
    (Icons.menu_book_outlined, 'الآية'),
    (Icons.dark_mode_outlined, 'خلفيات'),
    (Icons.filter_hdr_outlined, 'كروم'),
    (Icons.graphic_eq, 'قرّاء'),
    (Icons.grid_view_outlined, 'قوالب'),
    (Icons.text_fields, 'النص'),
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
  }

  @override
  void dispose() {
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

  Future<T?> _withBusy<T>(Future<T> Function() job) async {
    if (_busy) return null;
    setState(() {
      _busy = true;
      _busyProgress = null;
    });
    try {
      return await job();
    } catch (e) {
      _toast('$e'.replaceFirst('Exception: ', ''));
      return null;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyStatus = '';
          _busyProgress = null;
        });
      }
    }
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
    final controller = VideoPlayerController.file(File(path));
    _video = controller;
    state.setVideo(path);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
    } catch (_) {
      // audio-only files still work for detection/auto-sync even if the
      // preview player refuses them
    }
    if (mounted) setState(() {});
    _toast('تم رفع الملف ✓');
  }

  Future<void> _detectFromVideo() async {
    final matcher = state.matcher;
    if (!state.hasVideo || matcher == null) {
      _toast('ارفع فيديو أولًا');
      return;
    }
    await _withBusy(() async {
      _setBusyStatus('جارٍ استخراج الصوت…');
      final wav = await MediaService.extractWav16kMono(state.videoPath!);
      final text = await WhisperService.transcribeWav(wav,
          onStatus: (s) => _setBusyStatus(s));
      File(wav).delete().ignore();
      if (text.isEmpty) {
        _toast('لم يتم استخراج أي كلام واضح من الفيديو');
        return;
      }
      final match = matcher.match(text);
      if (match != null) {
        _liveOverlay.value = null;
        state.setAyah(
          match.ayah.ar,
          match.ayah.en,
          'تم التعرف: سورة ${match.ayah.surah} — آية ${match.ayah.num}',
          confidenceText:
              'نسبة التطابق: ${(match.confidence * 100).round()}٪ — النص المسموع: "$text"',
        );
      } else {
        _toast('تم تفريغ الصوت لكن لم تُطابق أي آية بثقة كافية');
      }
    });
  }

  Future<void> _autoSync() async {
    final matcher = state.matcher;
    if (!state.hasVideo || matcher == null) {
      _toast('ارفع فيديو أولًا');
      return;
    }
    // pause the preview so the decoder isn't fighting the analysis pass
    await _video?.pause();
    await _withBusy(() async {
      final timeline = await TimelineBuilder.build(
        mediaPath: state.videoPath!,
        matcher: matcher,
        onStatus: (s) => _setBusyStatus(s),
        onProgress: (f) => setState(() => _busyProgress = f),
      );
      if (timeline.isEmpty) {
        state.setTimeline([]);
        _toast('لم يتم رصد أي آية معروفة بثقة كافية في هذا الفيديو');
        return;
      }
      state.setTimeline(timeline);
      state.update(() {
        state.matchConfidenceText =
            'تم رصد ${timeline.length} آية على طول الفيديو — شغّله لعرضها تلقائيًا بالكتابة الحيّة';
        state.detectedLabel = 'مزامنة تلقائية مفعّلة — التصدير سيستخدم نفس التوقيت';
      });
      _toast('تم رصد ${timeline.length} آية ✓ — التصدير سيستخدم نفس التوقيت تلقائيًا');
      await _video?.play();
    });
  }

  /// 10x/sec: while an auto-sync timeline is active, type the current ayah
  /// out in the preview in step with the playing recitation.
  void _tickAutoSync() {
    final controller = _video;
    if (!state.timelineActive ||
        controller == null ||
        !controller.value.isInitialized) {
      return;
    }
    final t = controller.value.position.inMilliseconds / 1000.0;
    TimelineSegment? seg;
    for (final s in state.timeline) {
      if (t >= s.start && t < s.end) {
        seg = s;
        break;
      }
    }
    if (seg == null) return; // keep the last ayah on screen between segments
    final frac =
        min(1.0, (t - seg.start) * 1000 / ExportService.typingRevealMs);
    final chars = (seg.ayah.ar.length * frac).round();
    final typed = seg.ayah.ar.substring(0, chars);
    final trans = frac >= 1 ? seg.ayah.en : '';
    // PATCH_S27_FADE_TEXT_ANIMATIONS: stable per-ayah key so StagePreview only fades when
    // the segment actually changes, not on every typed character.
    final segmentKey = '${seg.ayah.surahNum}:${seg.ayah.num}';
    final current = _liveOverlay.value;
    if (current == null ||
        current.text != typed ||
        current.translation != trans) {
      _liveOverlay.value = StageOverlayText(typed, trans, segmentKey);
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
        );
      } else {
        _toast('لم يتم العثور على آية مطابقة بثقة كافية — حاول التلاوة بوضوح أكبر');
      }
    } catch (e) {
      _toast('$e'.replaceFirst('Exception: ', ''));
    } finally {
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
    final path = await _withBusy(() async {
      _setBusyStatus('جارٍ تجهيز التصدير…', 0);
      return ExportService.export(
        state: state,
        onStatus: (s) => _setBusyStatus(s),
        onProgress: (f) => setState(() => _busyProgress = f),
      );
    });
    if (path == null || !mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AyatColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: AyatColors.hairline),
        ),
        title: const Text('التصدير جاهز ✓'),
        content: Text('تم حفظ المقطع بصيغة MP4:\n$path',
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
    final path = res?.files.single.path;
    if (path == null) return;
    state.update(() {
      state.useCustomBg = true;
      state.customBgPath = path;
    });
    _toast('تم رفع الخلفية ✓');
  }

  Future<void> _pickCustomFont() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['ttf', 'otf']);
    final file = res?.files.single;
    if (file?.path == null) return;
    try {
      final bytes = await File(file!.path!).readAsBytes();
      _customFontCounter++;
      final family = 'CustomAyahFont$_customFontCounter';
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      state.update(() {
        state.customFonts.add(AyahFontChoice(family, 'خط مخصص: ${file.name}'));
        state.fontKey = family;
      });
      _toast('تم رفع الخط وتطبيقه على الآية ✓');
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

  void _applyCustomText() {
    final matcher = state.matcher;
    final ar = _customArCtrl.text.trim();
    final en = _customEnCtrl.text.trim();
    if (ar.isEmpty) {
      _toast('اكتب نص الآية أولًا');
      return;
    }
    _liveOverlay.value = null;
    final match = matcher?.match(ar, minConfidence: 0.28);
    if (match != null) {
      state.setAyah(match.ayah.ar, en.isNotEmpty ? en : match.ayah.en,
          'تم التعرّف: سورة ${match.ayah.surah} — آية ${match.ayah.num}');
      _toast('تم العثور على الآية ✓ (سورة ${match.ayah.surah}:${match.ayah.num})');
    } else {
      state.setAyah(ar, en, 'نص مخصص (لم يتم العثور على تطابق في القرآن)');
      _toast('لم يتم العثور على تطابق دقيق — تم استخدام النص كما هو');
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
                  label: const Text('تصدير المقطع (MP4 — حتى 1080p / 120 ثانية)'),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _busyProgress,
                minHeight: 6,
                backgroundColor: AyatColors.surface3,
                valueColor: const AlwaysStoppedAnimation(AyatColors.gold),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _ratioToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('9:16 قصة'),
          selected: !state.squareRatio,
          onSelected: (_) => state.update(() => state.squareRatio = false),
        ),
        const SizedBox(width: 8),
        ChoiceChip(
          label: const Text('1:1 مربع'),
          selected: state.squareRatio,
          onSelected: (_) => state.update(() => state.squareRatio = true),
        ),
      ],
    );
  }

  Widget _mediaButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: _busy ? null : _pickVideo,
          icon: const Icon(Icons.upload_file, size: 18),
          label: const Text('رفع فيديو أو تلاوة صوتية'),
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
          label: const Text('مزامنة تلقائية: اكتب كل آية أثناء التلاوة'),
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

  Widget _tabChips() {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.center,
      children: [
        for (var i = 0; i < _tabs.length; i++)
          ChoiceChip(
            avatar: Icon(_tabs[i].$1,
                size: 15,
                color: _selectedTab == i
                    ? AyatColors.goldBright
                    : AyatColors.parchmentDim),
            label: Text(_tabs[i].$2),
            selected: _selectedTab == i,
            onSelected: (_) => setState(() => _selectedTab = i),
          ),
      ],
    );
  }

  Widget _panelCard() {
    return _card(
      child: switch (_selectedTab) {
        0 => _ayahPanel(),
        1 => _bgPanel(),
        2 => _chromaPanel(),
        3 => _recitersPanel(),
        4 => _templatesPanel(),
        _ => _textPanel(),
      },
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
                'تم الاختيار يدويًا: سورة ${a.surah} — آية ${a.num}');
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
        const Divider(height: 32, color: AyatColors.hairline),
        ElevatedButton.icon(
          onPressed: _pickCustomBg,
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: const Text('أو ارفع خلفية خاصة بك'),
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
            child: const Text('إزالة الخلفية المخصصة والعودة للخلفيات الجاهزة'),
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
        DropdownButton<String>(
          isExpanded: true,
          value: state.allFonts.any((f) => f.key == state.fontKey)
              ? state.fontKey
              : 'amiri',
          items: [
            for (final f in state.allFonts)
              DropdownMenuItem(value: f.key, child: Text(f.label)),
          ],
          onChanged: (v) => state.update(() => state.fontKey = v ?? 'amiri'),
        ),
        const SizedBox(height: 6),
        ElevatedButton.icon(
          onPressed: _pickCustomFont,
          icon: const Icon(Icons.font_download_outlined, size: 18),
          label: const Text('رفع خط مخصص (TTF/OTF)'),
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
