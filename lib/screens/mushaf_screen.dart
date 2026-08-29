// PATCH_S123_MUSHAF_REBUILD: the reader used to be a surah dropdown over one
// long scroll of text. It is now an actual mushaf:
//
//   • real Madani pages — all 604 of them, swipeable, numbered, with the juz
//     shown alongside (page/juz data in lib/data/mushaf_meta.dart)
//   • a surah index you can search, instead of a 114-row dropdown
//   • ayah search: type any run of words, with or without tashkeel, and land
//     on the ayah — or type "2:255" and go straight there
//   • تفسير for every single ayah, from several works, cached on-device
//   • light mode, for the reader only
//   • motion everywhere, all of it under the one animations switch
//
// The whole screen is written against [MushafPalette] rather than
// AyatColors, which is what lets light mode be a real mode and not a hack.
import 'dart:io'; // PATCH_S138_IMPORTS: File for the downloaded/cached mp3
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart'; // PATCH_S138_IMPORTS

import '../data/mushaf_meta.dart';
import '../data/studio_presets.dart'; // PATCH_S138_IMPORTS: kReciters
import '../i18n/app_strings.dart';
import '../services/app_settings.dart';
import '../services/ayah_matcher.dart';
import '../services/quran_search.dart';
import '../services/reciter_audio_service.dart'; // PATCH_S138_IMPORTS
import '../services/tafsir_service.dart';
import '../theme/ayat_fonts.dart';
import '../theme/mushaf_theme.dart';
import '../widgets/motion.dart';

// PATCH_S108_MUSHAF_AYAH_ORNAMENT_REDESIGN: Eastern Arabic-Indic digits
// (٠١٢٣٤٥٦٧٨٩) for the ayah-end ornament, matching printed mushaf
// convention instead of Western digits.
const _kEasternArabicDigits = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
String easternArabicNumeral(int n) {
  // PATCH_S128: guard negative input
  if (n < 0) n = 0;
  return n.toString().split('')
      .map((d) => _kEasternArabicDigits[int.parse(d)]).join();
}

// PATCH_S112_MUSHAF_AYAH_ROSETTE_FIX: matches a real printed-mushaf
// ayah-stop -- a single thin scalloped ring (one continuous outline, not
// a cluster of filled circles), left UNFILLED so the digit sits directly
// on the page and stays legible.
// PATCH_S123_MUSHAF_REBUILD: takes the palette so it stays gold-on-paper in
// light mode instead of a dark-mode ornament stamped onto a light page.
Widget ayahRosetteOrnament(int num, MushafPalette palette, {double size = 26}) {
  return SizedBox(
    width: size,
    height: size,
    child: Stack(
      alignment: Alignment.center,
      children: [
        CustomPaint(
          size: Size(size, size),
          painter: _AyahRosettePainter(palette),
        ),
        // PATCH_S114_REDWORDS_AND_ROSETTE_CENTERING: Noto Kufi Arabic has
        // plain, evenly-spaced digit metrics, and the strut pins the line
        // height to the font size so nothing pushes the digit off-centre.
        // PATCH_S117_MULTI_DIGIT_AYAH_NUMBERS: FittedBox shrinks 3-digit ayah
        // numbers to fit instead of letting them disappear.
        SizedBox(
          width: size * 0.62,
          height: size * 0.62,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              easternArabicNumeral(num),
              textAlign: TextAlign.center,
              strutStyle: const StrutStyle(
                fontSize: 12,
                height: 1.0,
                forceStrutHeight: true,
              ),
              style: GoogleFonts.notoKufiArabic(
                textStyle: TextStyle(
                  color: palette.goldBright,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class _AyahRosettePainter extends CustomPainter {
  final MushafPalette palette;
  const _AyahRosettePainter(this.palette);

  static const _teeth = 10;

  Path _scallopedRing(Offset center, double baseR, double bumpR) {
    final path = Path();
    const step = 2 * pi / _teeth;
    for (var i = 0; i <= _teeth; i++) {
      final angle = i * step;
      final midAngle = angle - step / 2;
      final outerPt = center + Offset(cos(angle), sin(angle)) * baseR;
      final bumpPt = center + Offset(cos(midAngle), sin(midAngle)) * bumpR;
      if (i == 0) {
        path.moveTo(outerPt.dx, outerPt.dy);
      } else {
        path.quadraticBezierTo(bumpPt.dx, bumpPt.dy, outerPt.dx, outerPt.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final baseR = size.width * 0.30;
    final bumpR = size.width * 0.5;

    canvas.drawPath(
      _scallopedRing(center, baseR, bumpR),
      Paint()
        ..color = palette.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      center,
      baseR * 0.82,
      Paint()
        ..color = palette.goldDim.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6,
    );
  }

  @override
  bool shouldRepaint(covariant _AyahRosettePainter old) =>
      old.palette.gold != palette.gold;
}

class MushafScreen extends StatefulWidget {
  final List<Ayah> ayaat;

  /// The ayah font chosen in the studio — the reader honours it so the two
  /// never disagree about what the user's mushaf looks like.
  final String fontKey;
  final int initialSurah;

  /// Global ayah id (1-based) to open on, overriding [initialSurah].
  final int? initialAyahId;

  /// When provided, every ayah gets a "use this ayah in the studio" action
  /// that hands it back to the editor and closes the reader.
  final void Function(Ayah ayah)? onUseAyah;

  const MushafScreen({
    super.key,
    required this.ayaat,
    required this.fontKey,
    this.initialSurah = 1,
    this.initialAyahId,
    this.onUseAyah,
  });

  @override
  State<MushafScreen> createState() => _MushafScreenState();
}

class _MushafScreenState extends State<MushafScreen>
    with TickerProviderStateMixin {
  // Both controllers are created in initState rather than as lazy `late final`
  // initializers: the "corpus not ready yet" branch of build() never touches
  // the TabController, so dispose() would be its first use -- and building a
  // ticker against an already-deactivated element throws.
  late final TabController _tabs;
  late PageController _pageCtrl;

  /// 1..604
  int _page = 1;

  /// Global ayah id currently selected (drives the tafsir tab + highlight).
  int? _selectedAyahId;

  /// Surah shown in "whole surah" mode.
  int _surah = 1;

  final _surahScrollCtrl = ScrollController();
  final _settings = AppSettings.instance;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    final startId = widget.initialAyahId ??
        globalAyahId(widget.initialSurah.clamp(1, 114), 1);
    if (startId > 0) {
      _selectedAyahId = widget.initialAyahId;
      _page = pageOfAyahId(startId);
      _surah = _surahOfId(startId);
    }
    _pageCtrl = PageController(initialPage: _page - 1);
    _settings.addListener(_onSettings);
    // PATCH_S132_GAUNTLET_LOOP: PageController.initialPage can settle a
    // frame later than _page once the PageView's real viewport size is
    // known (this sits 3 layouts deep inside a TabBarView) -- the footer
    // is built straight from _page with no layout dependency, so it can
    // briefly disagree with what's actually painted. Re-assert once real
    // layout lands.
    // PATCH_S136_SURAH_TAP_HEADER_FOOTER_DESYNC: one-shot only -- do NOT
    // keep listening. An ongoing listener here fought _goToAyah's
    // animated jump, repeatedly overwriting _page/_surah mid-flight with
    // the controller's transient, not-yet-settled position. That's how
    // tapping a surah could leave the header on the previous surah while
    // the footer already showed the target page.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _syncPageFromController());
  }

  void _syncPageFromController() {
    if (!mounted || !_pageCtrl.hasClients) return;
    final raw = _pageCtrl.page;
    if (raw == null) return;
    final resolved = raw.round() + 1;
    if (resolved != _page) {
      setState(() {
        _page = resolved;
        _surah = _surahOfId(ayahRangeOfPage(_page).$1);
      });
    }
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    _tabs.dispose();
    _pageCtrl.dispose();
    _surahScrollCtrl.dispose();
    super.dispose();
  }

  /// Which view mode the current [_pageCtrl] was built for — see [_onSettings].
  late MushafViewMode _ctrlBuiltFor = _settings.mushafView;

  void _onSettings() {
    if (!mounted) return;
    // A PageController's initialPage is read once, when the PageView first
    // attaches. Switching to "whole surah" and back would therefore drop the
    // reader onto whatever page the controller was CREATED with, not the one
    // being read. Rebuild it with the current page instead.
    if (_settings.mushafView != _ctrlBuiltFor) {
      _ctrlBuiltFor = _settings.mushafView;
      if (_settings.mushafView == MushafViewMode.page) {
        _pageCtrl.dispose();
        _pageCtrl = PageController(initialPage: _page - 1);
      }
    }
    setState(() {});
  }

  int _surahOfId(int id) {
    for (final m in kSurahMeta) {
      if (id >= m.firstAyahId && id <= m.lastAyahId) return m.num;
    }
    return 1;
  }

  AppStrings get _s => _settings.strings;
  MushafPalette get _p => MushafPalette.of(_settings.mushafLight);

  // ---- navigation -------------------------------------------------------

  void _goToAyah(int globalId, {bool select = true}) {
    if (globalId < 1 || globalId > kTotalAyat) return;
    final targetPage = pageOfAyahId(globalId);
    // PATCH_S136_SURAH_TAP_HEADER_FOOTER_DESYNC: in paged mode, don't set
    // _page/_surah here -- the header is painted straight from the
    // PageView's own index, so setting them ahead of the actual jump is
    // what let the footer race ahead of what was on screen. Let
    // onPageChanged own both once the view genuinely gets there, exactly
    // like _stepPage already does (that path never showed this bug).
    // Whole-surah mode has no PageView to fire onPageChanged, so it still
    // needs to be set directly.
    if (_settings.mushafView == MushafViewMode.surah) {
      setState(() {
        if (select) _selectedAyahId = globalId;
        _page = targetPage;
        _surah = _surahOfId(globalId);
      });
    } else if (select) {
      setState(() => _selectedAyahId = globalId);
    }
    _settings.setLastReadAyahId(globalId);
    _tabs.animateTo(1);
    if (_settings.mushafView == MushafViewMode.surah) return;
    void jump() {
      if (!mounted || !_pageCtrl.hasClients) return;
      if (AppMotion.on) {
        _pageCtrl.animateToPage(targetPage - 1,
            duration: AppMotion.medium, curve: Curves.easeOutCubic);
      } else {
        _pageCtrl.jumpToPage(targetPage - 1);
      }
    }
    // The PageView may not be attached yet on the very first frame after a
    // tab switch -- retry once more on the following frame if so.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageCtrl.hasClients) {
        jump();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) => jump());
      }
    });
  }

  void _goToSurah(int surahNum) => _goToAyah(globalAyahId(surahNum, 1),
      select: false);

  void _stepPage(int delta) {
    final next = (_page + delta).clamp(1, kTotalPages);
    if (next == _page) return;
    if (_pageCtrl.hasClients) {
      if (AppMotion.on) {
        _pageCtrl.animateToPage(next - 1,
            duration: AppMotion.fast, curve: Curves.easeOut);
      } else {
        _pageCtrl.jumpToPage(next - 1);
      }
    } else {
      setState(() => _page = next);
    }
  }

  void _stepSurah(int delta) {
    final next = (_surah + delta).clamp(1, 114);
    if (next == _surah) return;
    setState(() => _surah = next);
    if (_surahScrollCtrl.hasClients) _surahScrollCtrl.jumpTo(0);
  }

  // ---- sheets -----------------------------------------------------------

  Future<void> _openSearch() async {
    final id = await Navigator.of(context).push<int>(
      AppMotion.route(_AyahSearchScreen(
        ayaat: widget.ayaat,
        palette: _p,
        strings: _s,
        fontKey: widget.fontKey,
      )),
    );
    if (id != null) _goToAyah(id);
  }

  void _openViewOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _p.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Directionality(
        textDirection: _settings.textDirection,
        child: _ReaderOptionsSheet(palette: _p, strings: _s),
      ),
    );
  }

  void _openAyahActions(int corpusIndex) {
    final ayah = widget.ayaat[corpusIndex];
    final id = corpusIndex + 1;
    HapticFeedback.selectionClick(); // same tactile language as the studio
    setState(() => _selectedAyahId = id);
    _settings.setLastReadAyahId(id);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _p.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    ayahRosetteOrnament(ayah.num, _p, size: 30),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'سورة ${ayah.surah} — ${_s.t('mushaf.page')} ${pageOfAyahId(id)}'
                        ' · ${_s.t('mushaf.juz')} ${juzOfAyahId(id)}',
                        style: GoogleFonts.tajawal(
                            color: _p.textDim, fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  ayah.ar,
                  textAlign: TextAlign.center,
                  style: ayahTextStyle(widget.fontKey,
                      fontSize: 20, height: 1.9, color: _p.text),
                ),
                if (ayah.en.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    ayah.en,
                    textAlign: TextAlign.center,
                    textDirection: TextDirection.ltr,
                    style: GoogleFonts.tajawal(
                        color: _p.textDim, fontSize: 12.5, height: 1.6),
                  ),
                ],
                const SizedBox(height: 16),
                _SheetAction(
                  palette: _p,
                  icon: Icons.menu_book_outlined,
                  label: _s.t('mushaf.tafsir'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _tabs.animateTo(2);
                  },
                ),
                // PATCH_S138_LISTEN_ACTION: hear a reciter or cache one for
                // offline reading, without leaving المصحف.
                _SheetAction(
                  palette: _p,
                  icon: Icons.graphic_eq,
                  label: 'استماع',
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _openReciterSheet(ayah);
                  },
                ),
                _SheetAction(
                  palette: _p,
                  icon: Icons.ios_share_outlined,
                  label: _s.t('common.share'),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    // The reference travels with the text -- an ayah pasted
                    // into a chat without one is a quote nobody can check.
                    SharePlus.instance.share(ShareParams(
                      text: '${ayah.ar}\n\n[سورة ${ayah.surah}: ${ayah.num}]',
                    ));
                  },
                ),
                _SheetAction(
                  palette: _p,
                  icon: Icons.copy_all_outlined,
                  label: _s.t('common.copy'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(
                        text: '${ayah.ar}\n[${ayah.surah}: ${ayah.num}]'));
                    if (!sheetCtx.mounted || !mounted) return;
                    Navigator.pop(sheetCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(_s.t('common.copied'))),
                    );
                  },
                ),
                if (widget.onUseAyah != null)
                  _SheetAction(
                    palette: _p,
                    icon: Icons.movie_creation_outlined,
                    label: _s.t('mushaf.useInStudio'),
                    highlighted: true,
                    onTap: () {
                      Navigator.pop(sheetCtx);
                      widget.onUseAyah!(ayah);
                      Navigator.of(context).maybePop();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // PATCH_S138_OPEN_SHEET: reciter list for one ayah's surah -- streaming and
  // offline-download live in the sheet widget itself (below), so this
  // screen's state doesn't grow a second set of download/playback fields.
  void _openReciterSheet(Ayah ayah) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _p.surface,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: _ReciterListenSheet(
          palette: _p,
          surahNum: ayah.surahNum,
          surahName: ayah.surah,
        ),
      ),
    );
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = _p;
    // PATCH_S123_MUSHAF_REBUILD: the studio hands this screen its corpus,
    // which loads asynchronously at startup -- opening the reader in that
    // window used to hand every page-layout path an empty list and index
    // straight off the end of it. The reader needs the WHOLE mushaf (page
    // ranges are absolute ayah ids), so anything short of it is "not ready".
    if (widget.ayaat.length < kTotalAyat) {
      return Theme(
        data: palette.toTheme(Theme.of(context)),
        child: Directionality(
          textDirection: _settings.textDirection,
          child: Scaffold(
            backgroundColor: palette.background,
            appBar: AppBar(
              backgroundColor: palette.background,
              foregroundColor: palette.text,
              iconTheme: IconThemeData(color: palette.gold),
              title: Text(_s.t('mushaf.title')),
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(
                      color: palette.goldBright, strokeWidth: 2.4),
                  const SizedBox(height: 16),
                  Text(_s.t('common.loading'),
                      style: GoogleFonts.tajawal(
                          color: palette.textDim, fontSize: 13)),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return Theme(
      data: palette.toTheme(Theme.of(context)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: palette.background,
          appBar: AppBar(
            backgroundColor: palette.background,
            foregroundColor: palette.text,
            title: Text(_s.t('mushaf.title'),
                style: GoogleFonts.arefRuqaa(
                    color: palette.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
            iconTheme: IconThemeData(color: palette.gold),
            actionsIconTheme: IconThemeData(color: palette.gold),
            actions: [
              IconButton(
                tooltip: _s.t('common.search'),
                icon: const Icon(Icons.search),
                onPressed: _openSearch,
              ),
              IconButton(
                tooltip: _s.t('mushaf.lightMode'),
                icon: Icon(palette.isLight
                    ? Icons.dark_mode_outlined
                    : Icons.light_mode_outlined),
                onPressed: () => _settings.setMushafLight(!palette.isLight),
              ),
              IconButton(
                tooltip: _s.t('mushaf.viewMode'),
                icon: const Icon(Icons.tune),
                onPressed: _openViewOptions,
              ),
            ],
            bottom: TabBar(
              controller: _tabs,
              labelColor: palette.goldBright,
              unselectedLabelColor: palette.textDim,
              indicatorColor: palette.gold,
              dividerColor: palette.hairline,
              labelStyle:
                  GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 13),
              tabs: [
                Tab(text: _s.t('mushaf.surahs')),
                Tab(text: _s.t('mushaf.read')),
                Tab(text: _s.t('mushaf.tafsir')),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _SurahIndexTab(
                ayaat: widget.ayaat,
                palette: palette,
                strings: _s,
                onOpenSurah: _goToSurah,
                onContinue: _settings.lastReadAyahId > 0
                    ? () => _goToAyah(_settings.lastReadAyahId)
                    : null,
                lastReadAyahId: _settings.lastReadAyahId,
              ),
              _buildReader(palette),
              _TafsirTab(
                key: ValueKey(_selectedAyahId),
                ayaat: widget.ayaat,
                globalAyahId: _selectedAyahId,
                palette: palette,
                strings: _s,
                fontKey: widget.fontKey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReader(MushafPalette palette) {
    if (_settings.mushafView == MushafViewMode.surah) {
      return _buildSurahReader(palette);
    }
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: kTotalPages,
            onPageChanged: (i) {
              setState(() {
                _page = i + 1;
                _surah = _surahOfId(ayahRangeOfPage(_page).$1);
              });
              _settings.setLastReadAyahId(ayahRangeOfPage(_page).$1);
            },
            itemBuilder: (context, i) => _MushafPageBody(
              page: i + 1,
              ayaat: widget.ayaat,
              palette: palette,
              strings: _s,
              fontKey: widget.fontKey,
              fontSize: _settings.mushafFontSize,
              showTranslation: _settings.readerTranslation,
              selectedAyahId: _selectedAyahId,
              onTapAyah: _openAyahActions,
            ),
          ),
        ),
        _PageFooter(
          palette: palette,
          strings: _s,
          page: _page,
          onPrev: _page > 1 ? () => _stepPage(-1) : null,
          onNext: _page < kTotalPages ? () => _stepPage(1) : null,
          onJump: _promptGoToPage,
        ),
      ],
    );
  }

  Widget _buildSurahReader(MushafPalette palette) {
    final meta = kSurahMeta[_surah - 1];
    final items = <int>[
      for (var id = meta.firstAyahId; id <= meta.lastAyahId; id++) id - 1,
    ];
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            controller: _surahScrollCtrl,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SurahHeader(
                  palette: palette,
                  strings: _s,
                  meta: meta,
                  arabicName: widget.ayaat[meta.firstAyahId - 1].surah,
                ),
                const SizedBox(height: 14),
                if (_surah != 1 && _surah != 9)
                  _BismillahLine(palette: palette, fontKey: widget.fontKey),
                _AyahParagraph(
                  corpusIndexes: items,
                  ayaat: widget.ayaat,
                  palette: palette,
                  fontKey: widget.fontKey,
                  fontSize: _settings.mushafFontSize,
                  selectedAyahId: _selectedAyahId,
                  onTapAyah: _openAyahActions,
                ),
                if (_settings.readerTranslation) ...[
                  const SizedBox(height: 16),
                  _TranslationBlock(
                      corpusIndexes: items,
                      ayaat: widget.ayaat,
                      palette: palette),
                ],
              ],
            ),
          ),
        ),
        _SurahFooter(
          palette: palette,
          strings: _s,
          label: 'سورة ${widget.ayaat[meta.firstAyahId - 1].surah}',
          onPrev: _surah > 1 ? () => _stepSurah(-1) : null,
          onNext: _surah < 114 ? () => _stepSurah(1) : null,
        ),
      ],
    );
  }

  Future<void> _promptGoToPage() async {
    final ctrl = TextEditingController(text: '$_page');
    final palette = _p;
    final target = await showDialog<int>(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: _settings.textDirection,
        child: AlertDialog(
          backgroundColor: palette.surface,
          title: Text(_s.t('mushaf.goToPage'),
              style: TextStyle(color: palette.text, fontSize: 16)),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: TextStyle(color: palette.text),
            decoration: InputDecoration(
              hintText: '1 – $kTotalPages',
              hintStyle: TextStyle(color: palette.textDim),
              enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: palette.hairline)),
              focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: palette.gold)),
            ),
            onSubmitted: (v) =>
                Navigator.pop(dialogCtx, int.tryParse(v.trim())),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(_s.t('common.cancel'),
                  style: TextStyle(color: palette.textDim)),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogCtx, int.tryParse(ctrl.text.trim())),
              child: Text(_s.t('common.done'),
                  style: TextStyle(color: palette.goldBright)),
            ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final clamped = target.clamp(1, kTotalPages);
    _goToAyah(ayahRangeOfPage(clamped).$1, select: false);
  }
}

// ---------------------------------------------------------------------------
// Reader body
// ---------------------------------------------------------------------------

/// One printed page: every surah that starts on it gets its header and
/// bismillah, and the ayat flow as one justified block, exactly like the
/// printed mushaf.
class _MushafPageBody extends StatelessWidget {
  final int page;
  final List<Ayah> ayaat;
  final MushafPalette palette;
  final AppStrings strings;
  final String fontKey;
  final double fontSize;
  final bool showTranslation;
  final int? selectedAyahId;
  final void Function(int corpusIndex) onTapAyah;

  const _MushafPageBody({
    required this.page,
    required this.ayaat,
    required this.palette,
    required this.strings,
    required this.fontKey,
    required this.fontSize,
    required this.showTranslation,
    required this.selectedAyahId,
    required this.onTapAyah,
  });

  @override
  Widget build(BuildContext context) {
    final (firstId, lastId) = ayahRangeOfPage(page);
    if (firstId > ayaat.length) {
      return Center(
        child: Text(strings.t('mushaf.loadFailed'),
            style: TextStyle(color: palette.textDim)),
      );
    }
    final last = min(lastId, ayaat.length);

    // Split the page into per-surah runs so a page that turns over into the
    // next surah gets that surah's header in the right place mid-page.
    final runs = <List<int>>[];
    var currentSurah = -1;
    for (var id = firstId; id <= last; id++) {
      final a = ayaat[id - 1];
      if (a.surahNum != currentSurah) {
        currentSurah = a.surahNum;
        runs.add(<int>[]);
      }
      runs.last.add(id - 1);
    }

    final children = <Widget>[];
    for (final run in runs) {
      final first = ayaat[run.first];
      final meta = kSurahMeta[first.surahNum - 1];
      final startsSurah = run.first + 1 == meta.firstAyahId;
      if (startsSurah) {
        children.add(_SurahHeader(
          palette: palette,
          strings: strings,
          meta: meta,
          arabicName: first.surah,
        ));
        children.add(const SizedBox(height: 10));
        if (first.surahNum != 1 && first.surahNum != 9) {
          children.add(_BismillahLine(palette: palette, fontKey: fontKey));
        }
      }
      children.add(_AyahParagraph(
        corpusIndexes: run,
        ayaat: ayaat,
        palette: palette,
        fontKey: fontKey,
        fontSize: fontSize,
        selectedAyahId: selectedAyahId,
        onTapAyah: onTapAyah,
      ));
      if (showTranslation) {
        children.add(const SizedBox(height: 14));
        children.add(_TranslationBlock(
            corpusIndexes: run, ayaat: ayaat, palette: palette));
      }
      children.add(const SizedBox(height: 16));
    }

    return SingleChildScrollView(
      key: PageStorageKey('mushaf_page_$page'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      child: FadeSlideIn(
        duration: AppMotion.fast,
        from: const Offset(0, 8),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          decoration: BoxDecoration(
            color: palette.paper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: palette.hairline),
            boxShadow: palette.isLight
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

/// The justified run of ayah text with a tappable span per ayah.
class _AyahParagraph extends StatefulWidget {
  final List<int> corpusIndexes;
  final List<Ayah> ayaat;
  final MushafPalette palette;
  final String fontKey;
  final double fontSize;
  final int? selectedAyahId;
  final void Function(int corpusIndex) onTapAyah;

  const _AyahParagraph({
    required this.corpusIndexes,
    required this.ayaat,
    required this.palette,
    required this.fontKey,
    required this.fontSize,
    required this.selectedAyahId,
    required this.onTapAyah,
  });

  @override
  State<_AyahParagraph> createState() => _AyahParagraphState();
}

class _AyahParagraphState extends State<_AyahParagraph> {
  // Gesture recognizers attached to TextSpans are NOT owned by the span and
  // must be disposed by whoever made them, so they're built once per ayah
  // list here rather than inside build().
  List<TapGestureRecognizer> _recognizers = const [];

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  @override
  void didUpdateWidget(covariant _AyahParagraph old) {
    super.didUpdateWidget(old);
    if (old.corpusIndexes.length != widget.corpusIndexes.length ||
        (old.corpusIndexes.isNotEmpty &&
            old.corpusIndexes.first != widget.corpusIndexes.first)) {
      _rebuild();
    }
  }

  void _rebuild() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers = [
      for (var i = 0; i < widget.corpusIndexes.length; i++)
        TapGestureRecognizer()
          ..onTap = () {
            if (i < widget.corpusIndexes.length) {
              widget.onTapAyah(widget.corpusIndexes[i]);
            }
          },
    ];
  }

  @override
  void dispose() {
    for (final r in _recognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final base = ayahTextStyle(
      widget.fontKey,
      fontSize: widget.fontSize,
      height: 2.05,
      color: p.text,
    ).copyWith(letterSpacing: 0.2);

    final spans = <InlineSpan>[];
    for (var i = 0; i < widget.corpusIndexes.length; i++) {
      final idx = widget.corpusIndexes[i];
      final a = widget.ayaat[idx];
      final id = idx + 1;
      final selected = widget.selectedAyahId == id;
      spans.add(TextSpan(
        text: '${a.ar} ',
        recognizer: i < _recognizers.length ? _recognizers[i] : null,
        style: selected
            ? base.copyWith(
                backgroundColor: p.highlight, color: p.goldBright)
            : base,
      ));
      if (hasSajda(id)) {
        spans.add(TextSpan(
          text: '۩ ',
          style: base.copyWith(color: p.gold, fontSize: widget.fontSize * 0.9),
        ));
      }
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 5),
          child: ayahRosetteOrnament(a.num, p,
              size: (widget.fontSize * 1.12).clamp(22.0, 40.0)),
        ),
      ));
      spans.add(const TextSpan(text: '  '));
    }

    return Text.rich(
      TextSpan(children: spans),
      textAlign: TextAlign.justify,
      textDirection: TextDirection.rtl,
    );
  }
}

/// The English meaning of a run of ayat, shown under the Arabic when the
/// reader's translation switch is on.
class _TranslationBlock extends StatelessWidget {
  final List<int> corpusIndexes;
  final List<Ayah> ayaat;
  final MushafPalette palette;
  const _TranslationBlock({
    required this.corpusIndexes,
    required this.ayaat,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      for (final i in corpusIndexes)
        if (ayaat[i].en.trim().isNotEmpty) i,
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: palette.isLight ? 0.7 : 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.hairline),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final i in items) ...[
              Text(
                '${ayaat[i].num}. ${ayaat[i].en}',
                style: GoogleFonts.tajawal(
                    color: palette.textDim, fontSize: 12.5, height: 1.6),
              ),
              if (i != items.last) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

/// The framed surah title, with its own facts (juz, ayah count, where it was
/// revealed) so the page reads like a printed mushaf's header band.
class _SurahHeader extends StatelessWidget {
  final MushafPalette palette;
  final AppStrings strings;
  final SurahMeta meta;
  final String arabicName;
  const _SurahHeader({
    required this.palette,
    required this.strings,
    required this.meta,
    required this.arabicName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.gold.withValues(alpha: palette.isLight ? 0.14 : 0.20),
            palette.gold.withValues(alpha: 0.04),
            palette.gold.withValues(alpha: palette.isLight ? 0.14 : 0.20),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.gold.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          Text(
            'سورة $arabicName',
            textAlign: TextAlign.center,
            style: GoogleFonts.arefRuqaa(
              color: palette.text,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${meta.meccan ? strings.t('mushaf.meccan') : strings.t('mushaf.medinan')}'
            ' · ${strings.f('mushaf.ayahCount', [meta.ayahCount])}'
            ' · ${strings.t('mushaf.juz')} ${juzOfAyahId(meta.firstAyahId)}',
            textAlign: TextAlign.center,
            style: GoogleFonts.tajawal(color: palette.textDim, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _BismillahLine extends StatelessWidget {
  final MushafPalette palette;
  final String fontKey;
  const _BismillahLine({required this.palette, required this.fontKey});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 4),
        child: Text(
          'بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ',
          textAlign: TextAlign.center,
          style: ayahTextStyle(fontKey,
              fontSize: 19, height: 1.8, color: palette.gold),
        ),
      );
}

/// Page number + juz + the two page arrows.
class _PageFooter extends StatelessWidget {
  final MushafPalette palette;
  final AppStrings strings;
  final int page;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  final VoidCallback onJump;

  const _PageFooter({
    required this.palette,
    required this.strings,
    required this.page,
    required this.onPrev,
    required this.onNext,
    required this.onJump,
  });

  @override
  Widget build(BuildContext context) {
    final (firstId, _) = ayahRangeOfPage(page);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            IconButton(
              tooltip: strings.t('mushaf.prevPage'),
              icon: const Icon(Icons.chevron_right),
              color: palette.gold,
              onPressed: onPrev,
            ),
            Expanded(
              child: PressableScale(
                onTap: onJump,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      // Page number in the mushaf's own numerals — this is a
                      // page of Quran, not a UI list index.
                      Text(
                        '${strings.t('mushaf.page')} ${easternArabicNumeral(page)}'
                        '  ·  ${strings.t('mushaf.juz')} ${easternArabicNumeral(juzOfAyahId(firstId))}',
                        style: GoogleFonts.tajawal(
                          color: palette.goldBright,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // A hairline progress bar: how far through the mushaf
                      // this page sits. Reading 604 pages needs a sense of
                      // place, and a bare number doesn't give one.
                      SizedBox(
                        height: 3,
                        child: LayoutBuilder(
                          builder: (context, c) => Stack(
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: palette.hairline,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                              AnimatedContainer(
                                duration: AppMotion.d(AppMotion.medium),
                                curve: Curves.easeOut,
                                width: c.maxWidth * (page / kTotalPages),
                                decoration: BoxDecoration(
                                  color: palette.gold,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: strings.t('mushaf.nextPage'),
              icon: const Icon(Icons.chevron_left),
              color: palette.gold,
              onPressed: onNext,
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahFooter extends StatelessWidget {
  final MushafPalette palette;
  final AppStrings strings;
  final String label;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;
  const _SurahFooter({
    required this.palette,
    required this.strings,
    required this.label,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border(top: BorderSide(color: palette.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              IconButton(
                tooltip: strings.t('mushaf.prevSurah'),
                icon: const Icon(Icons.chevron_right),
                color: palette.gold,
                onPressed: onPrev,
              ),
              Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.tajawal(
                      color: palette.goldBright,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: strings.t('mushaf.nextSurah'),
                icon: const Icon(Icons.chevron_left),
                color: palette.gold,
                onPressed: onNext,
              ),
            ],
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Surah index tab
// ---------------------------------------------------------------------------

class _SurahIndexTab extends StatefulWidget {
  final List<Ayah> ayaat;
  final MushafPalette palette;
  final AppStrings strings;
  final void Function(int surahNum) onOpenSurah;
  final VoidCallback? onContinue;
  final int lastReadAyahId;

  const _SurahIndexTab({
    required this.ayaat,
    required this.palette,
    required this.strings,
    required this.onOpenSurah,
    required this.onContinue,
    required this.lastReadAyahId,
  });

  @override
  State<_SurahIndexTab> createState() => _SurahIndexTabState();
}

class _SurahIndexTabState extends State<_SurahIndexTab> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.strings;
    final arabicNames = <int, String>{};
    for (final a in widget.ayaat) {
      arabicNames.putIfAbsent(a.surahNum, () => a.surah);
    }
    final visible = _query.trim().isEmpty
        ? kSurahMeta
        : [
            for (final n
                in QuranSearch.matchingSurahs(_query, widget.ayaat))
              kSurahMeta[n - 1],
          ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: TextField(
            controller: _ctrl,
            onChanged: (v) => setState(() => _query = v),
            style: TextStyle(color: p.text, fontSize: 14),
            decoration: InputDecoration(
              isDense: true,
              hintText: s.t('mushaf.searchSurahPlaceholder'),
              hintStyle: GoogleFonts.tajawal(color: p.textDim, fontSize: 13),
              prefixIcon: Icon(Icons.search, color: p.gold, size: 20),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, color: p.textDim, size: 18),
                      onPressed: () {
                        _ctrl.clear();
                        setState(() => _query = '');
                      },
                    ),
              filled: true,
              fillColor: p.surface,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.hairline),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.hairline),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.gold),
              ),
            ),
          ),
        ),
        if (widget.onContinue != null && _query.trim().isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: FadeSlideIn(
              child: PressableScale(
                onTap: widget.onContinue,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: p.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: p.gold.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bookmark_outline, color: p.goldBright, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.t('mushaf.continueReading'),
                              style: GoogleFonts.tajawal(
                                  color: p.goldBright,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700),
                            ),
                            Text(
                              '${widget.ayaat[widget.lastReadAyahId - 1].surah}'
                              ' · ${s.t('mushaf.page')} ${pageOfAyahId(widget.lastReadAyahId)}',
                              style: GoogleFonts.tajawal(
                                  color: p.textDim, fontSize: 11.5),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_left, color: p.gold),
                    ],
                  ),
                ),
              ),
            ),
          ),
        Expanded(
          child: visible.isEmpty
              ? Center(
                  child: Text(s.t('mushaf.searchNoResults'),
                      style: TextStyle(color: p.textDim)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 2, 14, 24),
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final m = visible[i];
                    final row = _SurahRow(
                      palette: p,
                      strings: s,
                      meta: m,
                      arabicName: arabicNames[m.num] ?? '',
                      onTap: () => widget.onOpenSurah(m.num),
                    );
                    // Stagger only the first screenful; animating row 90 that
                    // the user scrolls to later would feel like lag, not polish.
                    return i < 10
                        ? FadeSlideIn(
                            delay: Duration(milliseconds: 28 * i), child: row)
                        : row;
                  },
                ),
        ),
      ],
    );
  }
}

class _SurahRow extends StatelessWidget {
  final MushafPalette palette;
  final AppStrings strings;
  final SurahMeta meta;
  final String arabicName;
  final VoidCallback onTap;
  const _SurahRow({
    required this.palette,
    required this.strings,
    required this.meta,
    required this.arabicName,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.hairline),
          ),
          child: Row(
            children: [
              // Surah number in a diamond, the way a mushaf index prints it.
              Transform.rotate(
                angle: pi / 4,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    border: Border.all(color: p.gold.withValues(alpha: 0.7)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: Transform.rotate(
                      angle: -pi / 4,
                      child: Text(
                        easternArabicNumeral(meta.num),
                        style: GoogleFonts.notoKufiArabic(
                          textStyle: TextStyle(
                              color: p.goldBright,
                              fontSize: 11,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      arabicName,
                      style: GoogleFonts.arefRuqaa(
                          color: p.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${meta.transliteration} · ${meta.englishName}',
                      textDirection: TextDirection.ltr,
                      style: GoogleFonts.tajawal(
                          color: p.textDim, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    strings.f('mushaf.ayahCount', [meta.ayahCount]),
                    style:
                        GoogleFonts.tajawal(color: p.textDim, fontSize: 11),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${strings.t('mushaf.page')} ${pageOfAyahId(meta.firstAyahId)}',
                    style: GoogleFonts.tajawal(
                        color: p.gold.withValues(alpha: 0.9), fontSize: 10.5),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tafsir tab
// ---------------------------------------------------------------------------

class _TafsirTab extends StatefulWidget {
  final List<Ayah> ayaat;
  final int? globalAyahId;
  final MushafPalette palette;
  final AppStrings strings;
  final String fontKey;

  const _TafsirTab({
    super.key,
    required this.ayaat,
    required this.globalAyahId,
    required this.palette,
    required this.strings,
    required this.fontKey,
  });

  @override
  State<_TafsirTab> createState() => _TafsirTabState();
}

class _TafsirTabState extends State<_TafsirTab> {
  String? _text;
  String? _error;
  bool _loading = false;
  bool _fromCache = false;

  /// Guards against a slow request for an ayah the user has already left.
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _TafsirTab old) {
    super.didUpdateWidget(old);
    if (old.globalAyahId != widget.globalAyahId) _load();
  }

  Future<void> _load() async {
    final id = widget.globalAyahId;
    if (id == null || id < 1 || id > widget.ayaat.length) {
      setState(() {
        _text = null;
        _error = null;
        _loading = false;
      });
      return;
    }
    final ayah = widget.ayaat[id - 1];
    final token = ++_requestToken;
    setState(() {
      _loading = true;
      _error = null;
      _text = null;
    });
    try {
      final res = await TafsirService.fetch(
        slug: AppSettings.instance.tafsirEdition,
        surah: ayah.surahNum,
        ayah: ayah.num,
      );
      if (!mounted || token != _requestToken) return;
      setState(() {
        _text = res.text;
        _fromCache = res.fromCache;
        _loading = false;
      });
    } on TafsirException catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = AppSettings.instance.lang == AppLang.ar
            ? e.messageAr
            : e.messageEn;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = '${widget.strings.t('mushaf.tafsirFailed')} — $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.strings;
    final id = widget.globalAyahId;
    if (id == null || id < 1 || id > widget.ayaat.length) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.menu_book_outlined, color: p.goldDim, size: 42),
              const SizedBox(height: 14),
              Text(
                s.t('mushaf.tafsirPick'),
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(color: p.textDim, fontSize: 13.5),
              ),
            ],
          ),
        ),
      );
    }
    final ayah = widget.ayaat[id - 1];
    final edition = editionBySlug(AppSettings.instance.tafsirEdition);
    final isArabicText = edition.textLang == 'ar';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 30),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
          decoration: BoxDecoration(
            color: p.paper,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ayahRosetteOrnament(ayah.num, p, size: 26),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'سورة ${ayah.surah}',
                      style: GoogleFonts.arefRuqaa(
                          color: p.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                ayah.ar,
                textAlign: TextAlign.center,
                style: ayahTextStyle(widget.fontKey,
                    fontSize: 20, height: 1.95, color: p.text),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _EditionPicker(
          palette: p,
          strings: s,
          onChanged: (slug) {
            AppSettings.instance.setTafsirEdition(slug);
            _load();
          },
        ),
        const SizedBox(height: 14),
        AnimatedSwitcher(
          duration: AppMotion.d(AppMotion.medium),
          child: _body(p, s, isArabicText),
        ),
      ],
    );
  }

  Widget _body(MushafPalette p, AppStrings s, bool isArabicText) {
    if (_loading) {
      return Column(
        key: const ValueKey('loading'),
        children: [
          const SizedBox(height: 20),
          CircularProgressIndicator(color: p.gold, strokeWidth: 2.4),
          const SizedBox(height: 14),
          Text(s.t('mushaf.tafsirLoading'),
              style: GoogleFonts.tajawal(color: p.textDim, fontSize: 12.5)),
        ],
      );
    }
    if (_error != null) {
      return Column(
        key: const ValueKey('error'),
        children: [
          Icon(Icons.cloud_off_outlined, color: p.goldDim, size: 34),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(color: p.textDim, fontSize: 12.5)),
          const SizedBox(height: 8),
          Text(s.t('mushaf.tafsirOffline'),
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                  color: p.textDim.withValues(alpha: 0.75), fontSize: 11.5)),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _load,
            style: OutlinedButton.styleFrom(
              foregroundColor: p.goldBright,
              side: BorderSide(color: p.gold),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(s.t('common.retry')),
          ),
        ],
      );
    }
    final text = _text;
    if (text == null) return const SizedBox.shrink(key: ValueKey('empty'));
    return Container(
      key: const ValueKey('text'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_fromCache)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.offline_pin_outlined, size: 14, color: p.goldDim),
                  const SizedBox(width: 6),
                  Text(s.t('mushaf.tafsirCached'),
                      style: GoogleFonts.tajawal(
                          color: p.textDim, fontSize: 10.5)),
                ],
              ),
            ),
          Directionality(
            textDirection:
                isArabicText ? TextDirection.rtl : TextDirection.ltr,
            child: SelectableText(
              text,
              textAlign: TextAlign.start,
              style: GoogleFonts.tajawal(
                  color: p.text, fontSize: 14, height: 1.95),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditionPicker extends StatelessWidget {
  final MushafPalette palette;
  final AppStrings strings;
  final ValueChanged<String> onChanged;
  const _EditionPicker({
    required this.palette,
    required this.strings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final current = editionBySlug(AppSettings.instance.tafsirEdition);
    final arabicUi = AppSettings.instance.lang == AppLang.ar;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              isExpanded: true,
              value: current.slug,
              dropdownColor: p.surface,
              iconEnabledColor: p.gold,
              style: TextStyle(color: p.text),
              items: [
                for (final e in kTafsirEditions)
                  DropdownMenuItem(
                    value: e.slug,
                    child: Text(arabicUi ? e.nameAr : e.nameEn,
                        style: GoogleFonts.tajawal(
                            color: p.text, fontSize: 13.5)),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10, top: 2),
            child: Text(
              arabicUi ? current.noteAr : current.noteEn,
              style: GoogleFonts.tajawal(color: p.textDim, fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search
// ---------------------------------------------------------------------------

/// Full-screen ayah search. Pops the chosen ayah's global id.
class _AyahSearchScreen extends StatefulWidget {
  final List<Ayah> ayaat;
  final MushafPalette palette;
  final AppStrings strings;
  final String fontKey;
  const _AyahSearchScreen({
    required this.ayaat,
    required this.palette,
    required this.strings,
    required this.fontKey,
  });

  @override
  State<_AyahSearchScreen> createState() => _AyahSearchScreenState();
}

class _AyahSearchScreenState extends State<_AyahSearchScreen> {
  final _ctrl = TextEditingController();
  List<AyahSearchResult> _results = const [];
  List<int> _surahHits = const [];
  bool _searched = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _run(String q) {
    setState(() {
      _searched = q.trim().isNotEmpty;
      _results = QuranSearch.search(q, widget.ayaat);
      _surahHits = q.trim().isEmpty
          ? const []
          : QuranSearch.matchingSurahs(q, widget.ayaat);
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.strings;
    return Theme(
      data: p.toTheme(Theme.of(context)),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: p.background,
          appBar: AppBar(
            backgroundColor: p.background,
            foregroundColor: p.text,
            iconTheme: IconThemeData(color: p.gold),
            title: TextField(
              controller: _ctrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onChanged: _run,
              style: TextStyle(color: p.text, fontSize: 15),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: s.t('mushaf.searchPlaceholder'),
                hintStyle:
                    GoogleFonts.tajawal(color: p.textDim, fontSize: 13.5),
              ),
            ),
            actions: [
              if (_ctrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _ctrl.clear();
                    _run('');
                  },
                ),
            ],
          ),
          body: _body(p, s),
        ),
      ),
    );
  }

  Widget _body(MushafPalette p, AppStrings s) {
    if (!_searched) {
      return Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.travel_explore_outlined, color: p.goldDim, size: 44),
            const SizedBox(height: 16),
            Text(
              s.t('mushaf.searchHint'),
              textAlign: TextAlign.center,
              style: GoogleFonts.tajawal(
                  color: p.textDim, fontSize: 13, height: 1.8),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final example in const [
                  'إن مع العسر يسرا',
                  'الله لا إله إلا هو الحي القيوم',
                  '2:255',
                  'الكهف',
                ])
                  PressableScale(
                    borderRadius: BorderRadius.circular(20),
                    onTap: () {
                      _ctrl.text = example;
                      _run(example);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: p.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.hairline),
                      ),
                      child: Text(example,
                          style: GoogleFonts.tajawal(
                              color: p.textDim, fontSize: 12)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    }
    if (_results.isEmpty && _surahHits.isEmpty) {
      return Center(
        child: Text(s.t('mushaf.searchNoResults'),
            style: GoogleFonts.tajawal(color: p.textDim, fontSize: 14)),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
      children: [
        if (_surahHits.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(s.t('mushaf.surahs'),
                style: GoogleFonts.tajawal(
                    color: p.gold, fontSize: 12, fontWeight: FontWeight.w700)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final n in _surahHits)
                PressableScale(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.pop(
                      context, kSurahMeta[n - 1].firstAyahId),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: p.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: p.hairline),
                    ),
                    child: Text(
                      widget.ayaat[kSurahMeta[n - 1].firstAyahId - 1].surah,
                      style: GoogleFonts.tajawal(
                          color: p.text, fontSize: 12.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (_results.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              s.f('mushaf.searchResults', [_results.length]),
              style: GoogleFonts.tajawal(
                  color: p.gold, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
        for (var i = 0; i < _results.length; i++)
          _SearchResultRow(
            result: _results[i],
            palette: p,
            strings: s,
            fontKey: widget.fontKey,
            onTap: () =>
                Navigator.pop(context, _results[i].globalAyahId),
          ),
      ],
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  final AyahSearchResult result;
  final MushafPalette palette;
  final AppStrings strings;
  final String fontKey;
  final VoidCallback onTap;
  const _SearchResultRow({
    required this.result,
    required this.palette,
    required this.strings,
    required this.fontKey,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final a = result.ayah;
    final base =
        ayahTextStyle(fontKey, fontSize: 17, height: 1.9, color: p.text);
    // Highlight exactly the matched run inside the real, vocalized text.
    final spans = <TextSpan>[];
    if (result.matchStart >= 0 && result.matchLength > 0) {
      final start = result.matchStart.clamp(0, a.ar.length);
      final end = (start + result.matchLength).clamp(start, a.ar.length);
      if (start > 0) spans.add(TextSpan(text: a.ar.substring(0, start)));
      spans.add(TextSpan(
        text: a.ar.substring(start, end),
        style: base.copyWith(
            color: p.goldBright,
            backgroundColor: p.highlight,
            fontWeight: FontWeight.w700),
      ));
      if (end < a.ar.length) spans.add(TextSpan(text: a.ar.substring(end)));
    } else {
      spans.add(TextSpan(text: a.ar));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 12),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  ayahRosetteOrnament(a.num, p, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سورة ${a.surah}  ·  ${strings.t('mushaf.page')} ${result.page}'
                      '  ·  ${strings.t('mushaf.juz')} ${juzOfAyahId(result.globalAyahId)}',
                      style: GoogleFonts.tajawal(
                          color: p.textDim, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(style: base, children: spans),
                textDirection: TextDirection.rtl,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Options sheet + small pieces
// ---------------------------------------------------------------------------

class _ReaderOptionsSheet extends StatefulWidget {
  final MushafPalette palette;
  final AppStrings strings;
  const _ReaderOptionsSheet({required this.palette, required this.strings});

  @override
  State<_ReaderOptionsSheet> createState() => _ReaderOptionsSheetState();
}

class _ReaderOptionsSheetState extends State<_ReaderOptionsSheet> {
  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final s = widget.strings;
    final settings = AppSettings.instance;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 2, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.t('mushaf.viewMode'),
                style: GoogleFonts.tajawal(
                    color: p.gold, fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            SegmentedButton<MushafViewMode>(
              segments: [
                ButtonSegment(
                  value: MushafViewMode.page,
                  icon: const Icon(Icons.auto_stories_outlined, size: 17),
                  label: Text(s.t('mushaf.viewPage')),
                ),
                ButtonSegment(
                  value: MushafViewMode.surah,
                  icon: const Icon(Icons.list_alt_outlined, size: 17),
                  label: Text(s.t('mushaf.viewSurah')),
                ),
              ],
              selected: {settings.mushafView},
              showSelectedIcon: false,
              style: ButtonStyle(
                textStyle: WidgetStatePropertyAll(
                    GoogleFonts.tajawal(fontSize: 12)),
                foregroundColor: WidgetStatePropertyAll(p.text),
                side: WidgetStatePropertyAll(BorderSide(color: p.hairline)),
              ),
              onSelectionChanged: (v) =>
                  setState(() => settings.setMushafView(v.first)),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Text(s.t('mushaf.fontSize'),
                    style: GoogleFonts.tajawal(
                        color: p.gold,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('${settings.mushafFontSize.round()}',
                    style:
                        GoogleFonts.tajawal(color: p.textDim, fontSize: 12)),
              ],
            ),
            Slider(
              min: 16,
              max: 40,
              divisions: 24,
              value: settings.mushafFontSize,
              activeColor: p.gold,
              inactiveColor: p.hairline,
              onChanged: (v) => setState(() => settings.setMushafFontSize(v)),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.mushafLight,
              activeThumbColor: p.gold,
              title: Text(s.t('mushaf.lightMode'),
                  style: GoogleFonts.tajawal(color: p.text, fontSize: 13.5)),
              subtitle: Text(s.t('mushaf.lightModeHint'),
                  style:
                      GoogleFonts.tajawal(color: p.textDim, fontSize: 11.5)),
              onChanged: (v) => setState(() => settings.setMushafLight(v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.readerTranslation,
              activeThumbColor: p.gold,
              title: Text(s.t('mushaf.showTranslation'),
                  style: GoogleFonts.tajawal(color: p.text, fontSize: 13.5)),
              onChanged: (v) =>
                  setState(() => settings.setReaderTranslation(v)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final MushafPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;
  const _SheetAction({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: PressableScale(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: highlighted
                ? p.gold.withValues(alpha: 0.14)
                : p.surfaceRaised,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: highlighted
                    ? p.gold.withValues(alpha: 0.6)
                    : p.hairline),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 19, color: highlighted ? p.goldBright : p.gold),
              const SizedBox(width: 12),
              Text(label,
                  style: GoogleFonts.tajawal(
                      color: highlighted ? p.goldBright : p.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// PATCH_S138_RECITER_SHEET: reciter list for a single surah, opened from the ayah
// actions sheet. Self-contained -- owns its own search text, per-reciter
// download progress, and the one active player -- so nothing needs
// adding to _MushafScreenState, and the sheet's state simply goes away
// when it's closed (its dispose() stops playback and frees the player).
//
// Downloads are tracked in a Map<int, double?> keyed by reciter index
// rather than a single `int? downloading` -- unlike the studio's own
// reciter panel (S104), that means starting reciter B's download does
// not have to wait for reciter A's to finish; each entry in the map
// updates independently as ReciterAudioService reports progress.
// ReciterAudioService itself already caches to disk permanently, so a
// completed download here IS the offline copy -- nothing extra to do
// to make the surah available without a connection afterwards.
class _ReciterListenSheet extends StatefulWidget {
  final MushafPalette palette;
  final int surahNum;
  final String surahName;

  const _ReciterListenSheet({
    required this.palette,
    required this.surahNum,
    required this.surahName,
  });

  @override
  State<_ReciterListenSheet> createState() => _ReciterListenSheetState();
}

class _ReciterListenSheetState extends State<_ReciterListenSheet> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  // One entry per reciter currently downloading; absent = idle. Several
  // reciters can be present at once -- see the class comment above.
  final Map<int, double?> _progress = {};
  final Set<int> _cached = {};
  int? _playingIndex;
  VideoPlayerController? _player;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _player?.dispose();
    super.dispose();
  }

  Future<void> _stopPlayer() async {
    final old = _player;
    _player = null;
    if (old != null) {
      await old.pause();
      await old.dispose();
    }
  }

  Future<void> _togglePlay(int i) async {
    if (_playingIndex == i) {
      await _stopPlayer();
      if (mounted) setState(() => _playingIndex = null);
      return;
    }
    await _stopPlayer();
    if (!mounted) return;
    setState(() {
      _playingIndex = i;
      if (!_cached.contains(i)) _progress[i] = null;
    });
    try {
      final path = await ReciterAudioService.downloadSurah(
        displayName: kReciters[i],
        surahNum: widget.surahNum,
        onProgress: (p) {
          if (mounted) setState(() => _progress[i] = p);
        },
      );
      if (!mounted) return;
      final c = VideoPlayerController.file(File(path));
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      c.addListener(() {
        if (!mounted || _player != c) return;
        final v = c.value;
        if (!v.isPlaying &&
            v.duration > Duration.zero &&
            v.position >= v.duration) {
          setState(() => _playingIndex = null);
        }
      });
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _player = c;
        _cached.add(i);
        _progress.remove(i);
      });
    } on ReciterAudioException catch (e) {
      if (!mounted) return;
      setState(() {
        _progress.remove(i);
        if (_playingIndex == i) _playingIndex = null;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _progress.remove(i);
        if (_playingIndex == i) _playingIndex = null;
      });
    }
  }

  Future<void> _downloadOnly(int i) async {
    if (_progress.containsKey(i) || _cached.contains(i)) return;
    setState(() => _progress[i] = null);
    try {
      await ReciterAudioService.downloadSurah(
        displayName: kReciters[i],
        surahNum: widget.surahNum,
        onProgress: (p) {
          if (mounted) setState(() => _progress[i] = p);
        },
      );
      if (!mounted) return;
      setState(() {
        _progress.remove(i);
        _cached.add(i);
      });
    } on ReciterAudioException catch (e) {
      if (!mounted) return;
      setState(() => _progress.remove(i));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _progress.remove(i));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    final names = kReciters;
    final q = _query.trim();
    final shown = [
      for (var i = 0; i < names.length; i++)
        if (q.isEmpty || names[i].contains(q)) i,
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('سورة ${widget.surahName} — استماع وتنزيل',
                textAlign: TextAlign.center,
                style: GoogleFonts.tajawal(
                    color: p.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('التشغيل والتنزيل لكامل السورة',
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.tajawal(color: p.textDim, fontSize: 11.5)),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: GoogleFonts.tajawal(color: p.text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'ابحث عن قارئ',
                hintStyle:
                    GoogleFonts.tajawal(color: p.textDim, fontSize: 13),
                prefixIcon: Icon(Icons.search, color: p.textDim, size: 19),
                isDense: true,
                filled: true,
                fillColor: p.surfaceRaised,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: p.hairline)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 340,
              child: shown.isEmpty
                  ? Center(
                      child: Text('لا يوجد قارئ بهذا الاسم',
                          style: GoogleFonts.tajawal(
                              color: p.textDim, fontSize: 12.5)))
                  : ListView.separated(
                      itemCount: shown.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (c, idx) {
                        final i = shown[idx];
                        final downloading = _progress.containsKey(i);
                        final progress = _progress[i];
                        final playing = _playingIndex == i;
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: playing
                                ? p.gold.withValues(alpha: 0.12)
                                : p.surfaceRaised,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: playing
                                    ? p.gold.withValues(alpha: 0.6)
                                    : p.hairline),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(names[i],
                                    style: GoogleFonts.tajawal(
                                        color: p.text,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600)),
                              ),
                              if (downloading)
                                SizedBox(
                                  width: 34,
                                  height: 34,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        value: progress,
                                        color: p.goldBright),
                                  ),
                                )
                              else ...[
                                IconButton(
                                  tooltip: 'تنزيل للقراءة بلا إنترنت',
                                  icon: Icon(
                                      _cached.contains(i)
                                          ? Icons.check_circle
                                          : Icons.download_outlined,
                                      color: _cached.contains(i)
                                          ? const Color(0xFF43A047)
                                          : p.gold,
                                      size: 20),
                                  onPressed: _cached.contains(i)
                                      ? null
                                      : () => _downloadOnly(i),
                                ),
                                IconButton(
                                  tooltip: playing ? 'إيقاف' : 'تشغيل',
                                  icon: Icon(
                                      playing
                                          ? Icons.pause_circle_outline
                                          : Icons.play_circle_outline,
                                      color: p.goldBright,
                                      size: 24),
                                  onPressed: () => _togglePlay(i),
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
