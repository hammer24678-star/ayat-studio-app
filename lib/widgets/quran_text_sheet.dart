// PATCH_S189_QURAN_TYPE: type a text and let the Quran finish it.
//
// A bottom sheet with one text box. While you type (any spelling, with or
// without tashkeel, from anywhere inside the ayah) the bundled corpus is
// searched live and the closest ayat are listed under the box:
//   - tap a row            -> your fragment is completed, from where you started
//                             to the end of that ayah, in the real vocalized text
//   - tap the book icon    -> the whole ayah
// Typing something that is not Quran works too; it is kept as written.
// Runs entirely on the bundled corpus - no network.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/ayah_matcher.dart';
import '../services/quran_search.dart';
import '../theme/ayat_theme.dart';

class QuranTextResult {
  final String text;
  final String translation;
  const QuranTextResult(this.text, this.translation);
}

/// The vocalized text of [ar] from the match onward (the whole ayah when
/// there is no usable match offset).
String quranCompleteFrom(String ar, int matchStart) {
  if (matchStart <= 0 || matchStart >= ar.length) return ar;
  return ar.substring(matchStart);
}

Future<QuranTextResult?> showQuranTextSheet(
  BuildContext context, {
  required List<Ayah> ayaat,
  required String title,
  String initial = '',
  String initialTranslation = '',
}) {
  return showModalBottomSheet<QuranTextResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AyatColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _QuranTextSheet(
      ayaat: ayaat,
      title: title,
      initial: initial,
      initialTranslation: initialTranslation,
    ),
  );
}

class _QuranTextSheet extends StatefulWidget {
  final List<Ayah> ayaat;
  final String title;
  final String initial;
  final String initialTranslation;
  const _QuranTextSheet({
    required this.ayaat,
    required this.title,
    required this.initial,
    required this.initialTranslation,
  });

  @override
  State<_QuranTextSheet> createState() => _QuranTextSheetState();
}

class _QuranTextSheetState extends State<_QuranTextSheet> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  Timer? _debounce;
  List<AyahSearchResult> _hits = const [];
  String _translation = '';
  String _translationFor = '';

  @override
  void initState() {
    super.initState();
    _translation = widget.initialTranslation;
    _translationFor = widget.initial;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      setState(() {
        _hits = QuranSearch.search(v, widget.ayaat, limit: 12);
      });
    });
  }

  void _set(String text, String translation) {
    _ctrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _translation = translation;
    _translationFor = text;
    setState(() {
      _hits = QuranSearch.search(text, widget.ayaat, limit: 12);
    });
  }

  void _done() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    // A translation only stays when the text is still the one it belongs to.
    final keep = _translation.isNotEmpty && _translationFor.trim() == t;
    Navigator.pop(context, QuranTextResult(t, keep ? _translation : ''));
  }

  Widget _row(AyahSearchResult r) {
    final ar = r.ayah.ar;
    final hasMatch = r.matchStart >= 0 &&
        r.matchLength > 0 &&
        r.matchStart + r.matchLength <= ar.length;
    final base = GoogleFonts.amiri(
        fontSize: 17, height: 1.7, color: AyatColors.parchment);
    final span = hasMatch
        ? TextSpan(style: base, children: [
            TextSpan(text: ar.substring(0, r.matchStart)),
            TextSpan(
              text: ar.substring(r.matchStart, r.matchStart + r.matchLength),
              style: base.copyWith(
                  color: AyatColors.goldBright, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: ar.substring(r.matchStart + r.matchLength)),
          ])
        : TextSpan(text: ar, style: base);
    return InkWell(
      onTap: () => _set(quranCompleteFrom(ar, r.matchStart), ''),
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AyatColors.hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${r.ayah.surah}  ${r.ayah.num}',
                      style: GoogleFonts.tajawal(
                          fontSize: 11.5, color: AyatColors.gold)),
                  RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.rtl,
                    text: span,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'الآية كاملة',
              icon: const Icon(Icons.menu_book_outlined,
                  color: AyatColors.gold, size: 22),
              onPressed: () => _set(ar, r.ayah.en),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final typed = _ctrl.text.trim();
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: GoogleFonts.arefRuqaa(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AyatColors.parchment)),
              const SizedBox(height: 10),
              TextField(
                controller: _ctrl,
                autofocus: true,
                autocorrect: false, // PATCH_S197_DETAILS
                minLines: 1,
                maxLines: 4,
                textAlign: TextAlign.right,
                textDirection: TextDirection.rtl,
                onChanged: _onChanged,
                style: GoogleFonts.amiri(
                    fontSize: 19, height: 1.7, color: AyatColors.parchment),
                decoration: InputDecoration(
                  hintText: 'اكتب أي جزء من آية وسيكملها القرآن',
                  suffixIcon: typed.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => _set('', ''),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Flexible(
                child: _hits.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Text(
                          typed.length < 2
                              ? 'اكتب كلمتين على الأقل لتظهر الاقتراحات'
                              : 'لا توجد آية مطابقة — يُستخدم نصك كما كتبته',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.tajawal(
                              fontSize: 12.5, color: AyatColors.parchmentDim),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [for (final r in _hits) _row(r)],
                      ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: typed.isEmpty ? null : _done,
                      child: const Text('تم'),
                    ),
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
