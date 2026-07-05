import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';
import '../data/quran_repository.dart';
import '../services/ayah_matcher.dart';
import '../services/media_service.dart';
import '../services/whisper_service.dart';
import '../theme/ayat_theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AyahMatcher? _matcher;
  String _status = 'جارٍ تحميل القرآن الكريم كاملاً…';
  String? _videoPath;
  AyahMatch? _lastMatch;
  bool _busy = false;
  double? _downloadProgress; // null when not downloading

  @override
  void initState() {
    super.initState();
    _loadCorpus();
  }

  Future<void> _loadCorpus() async {
    final ayaat = await QuranRepository.loadFullCorpus();
    setState(() {
      _matcher = AyahMatcher(ayaat);
      _status = 'تم تحميل القرآن الكريم كاملاً (${ayaat.length} آية) ✓';
    });
  }

  Future<void> _pickVideo() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.single.path == null) return;
    setState(() {
      _videoPath = res.files.single.path;
      _status = 'تم اختيار الفيديو ✓';
    });
  }

  Future<void> _detectFromVideo() async {
    if (_videoPath == null || _matcher == null) return;
    setState(() {
      _busy = true;
      _downloadProgress = null;
      _status = 'جارٍ استخراج الصوت…';
    });
    try {
      final wav = await MediaService.extractWav16kMono(_videoPath!);
      final text = await WhisperService.transcribeWav(
        wav,
        onStatus: (s) => setState(() => _status = s),
        onProgress: (f) => setState(() => _downloadProgress = f),
      );
      final match = _matcher!.match(text);
      setState(() {
        _lastMatch = match;
        _downloadProgress = null;
        _status = match != null
            ? 'تم التعرّف: سورة ${match.ayah.surah} — آية ${match.ayah.num} (${(match.confidence * 100).round()}٪)'
            : 'لم يتم العثور على آية مطابقة بثقة كافية';
      });
    } catch (e) {
      setState(() {
        _downloadProgress = null;
        _status = 'خطأ: $e';
      });
    } finally {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AyatColors.ink,
      appBar: AppBar(title: const Text('آيات ستوديو')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AyatColors.surface,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: AyatColors.hairline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _status,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.tajawal(
                        color: AyatColors.goldBright,
                        fontSize: 13,
                      ),
                    ),
                    if (_downloadProgress != null) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: _downloadProgress,
                          minHeight: 6,
                          backgroundColor: AyatColors.surface3,
                          valueColor: const AlwaysStoppedAnimation(AyatColors.gold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _busy ? null : _pickVideo,
                child: const Text('رفع فيديو'),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: (_busy || _videoPath == null) ? null : _detectFromVideo,
                child: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('تعرّف من صوت الفيديو المرفوع'),
              ),
              if (_lastMatch != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AyatColors.surface2,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: AyatColors.hairline),
                  ),
                  child: Column(
                    children: [
                      Text(
                        _lastMatch!.ayah.ar,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.amiriQuran(
                          color: AyatColors.parchment,
                          fontSize: 22,
                          height: 1.8,
                        ),
                      ),
                      if (_lastMatch!.ayah.en.isNotEmpty) ...[
                        const SizedBox(height: 11),
                        Text(
                          _lastMatch!.ayah.en,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tajawal(
                            color: AyatColors.parchmentDim,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
