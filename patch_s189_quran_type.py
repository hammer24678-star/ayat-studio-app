#!/usr/bin/env python3
"""
patch_s189_quran_type.py - Ayat Studio S189 (run from repo root, after S188)

Typing text with the Quran finishing it.

  * Main clip bar, right after the Whisper buttons: «كتابة بالقرآن». Opens a
    sheet; type any part of an ayah (any spelling, with or without tashkeel)
    and the matching ayat are listed live from the bundled corpus.
    Tap a row = completes what you typed to the end of that ayah (real
    vocalized text); the book icon = the whole ayah. Anything that is not
    Quran stays exactly as typed. The text lands as a 4 s text block at the
    playhead, selected.
  * «تعديل النص» on a selected text block uses the same sheet.
  * Translation is kept only while the text is still the one it belongs to.

Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S189_QURAN_TYPE'
if not os.path.exists('lib/screens/home_screen.dart'):
    sys.exit('Run from the repo root (missing lib/screens/home_screen.dart).')

NEW_FILES = {
'lib/widgets/quran_text_sheet.dart': r'''// PATCH_S189_QURAN_TYPE: type a text and let the Quran finish it.
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
''',
'test/quran_text_sheet_test.dart': r'''// PATCH_S189_QURAN_TYPE: completing a half-typed ayah from the corpus.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/services/ayah_matcher.dart';
import 'package:ayat_studio_app/services/quran_search.dart';
import 'package:ayat_studio_app/widgets/quran_text_sheet.dart';

Ayah ayah(int s, String name, int n, String ar) =>
    Ayah(surahNum: s, surah: name, num: n, ar: ar, en: '');

void main() {
  final corpus = [
    ayah(1, 'الفاتحة', 2, 'ٱلْحَمْدُ لِلَّهِ رَبِّ ٱلْعَـٰلَمِينَ'),
    ayah(1, 'الفاتحة', 3, 'ٱلرَّحْمَـٰنِ ٱلرَّحِيمِ'),
  ];

  setUp(QuranSearch.resetIndex);

  test('unvocalized fragment finds the ayah and completes from the match', () {
    final r = QuranSearch.search('الحمد لله رب', corpus);
    expect(r, isNotEmpty);
    expect(r.first.ayah.num, 2);
    final full = quranCompleteFrom(r.first.ayah.ar, r.first.matchStart);
    expect(full.endsWith('ٱلْعَـٰلَمِينَ'), isTrue);
  });

  test('mid-ayah fragment completes to the end, not from the start', () {
    final r = QuranSearch.search('رب العالمين', corpus);
    expect(r, isNotEmpty);
    final out = quranCompleteFrom(r.first.ayah.ar, r.first.matchStart);
    expect(out.length < r.first.ayah.ar.length, isTrue);
    expect(out.endsWith('ٱلْعَـٰلَمِينَ'), isTrue);
  });

  test('no match offset gives the whole ayah', () {
    expect(quranCompleteFrom('abc', -1), 'abc');
    expect(quranCompleteFrom('abc', 0), 'abc');
  });

  test('non-Quran text finds nothing', () {
    expect(QuranSearch.search('مرحبا بكم', corpus), isEmpty);
  });
}
''',
}

FILES = {
  'lib/screens/home_screen.dart': [
    ('import', "import '../services/ayah_matcher.dart';\n", "import '../services/ayah_matcher.dart';\nimport '../widgets/quran_text_sheet.dart'; // PATCH_S189_QURAN_TYPE\n"),
    ('main bar', "        (Icons.manage_search, 'تعرّف من الصوت', () { if (!_busy) _detectFromVideo(); }, false),\n", "        (Icons.manage_search, 'تعرّف من الصوت', () { if (!_busy) _detectFromVideo(); }, false),\n        (Icons.spellcheck, 'كتابة بالقرآن', _addQuranText, false), // PATCH_S189_QURAN_TYPE\n"),
    ('add + edit text', "  Future<void> _cueEditText(int i) async {\n    if (i < 0 || i >= state.textTimeCues.length) return;\n    final cue = state.textTimeCues[i];\n    final ctrl = TextEditingController(text: cue.text);\n    final result = await showDialog<String>(\n      context: context,\n      builder: (ctx) => AlertDialog(\n        backgroundColor: AyatColors.surface,\n        title: const Text('تعديل النص'),\n        content: TextField(\n          controller: ctrl,\n          autofocus: true,\n          maxLines: 4,\n          textAlign: TextAlign.right,\n          textDirection: TextDirection.rtl,\n        ),\n        actions: [\n          TextButton(\n              onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),\n          TextButton(\n              onPressed: () => Navigator.pop(ctx, ctrl.text),\n              child: const Text('حفظ')),\n        ],\n      ),\n    );\n    ctrl.dispose();\n    if (result == null || result.trim().isEmpty) return;\n    state.update(() => cue.text = result.trim());\n  }\n", "  // PATCH_S189_QURAN_TYPE: typing a text, the Quran finishes it.\n  Future<void> _addQuranText() async {\n    final main = _video;\n    if (!state.hasVideo || main == null || !main.value.isInitialized) {\n      _toast('ارفع فيديو أولًا');\n      return;\n    }\n    final r = await showQuranTextSheet(context,\n        ayaat: state.ayaat, title: 'نص جديد');\n    if (r == null || !mounted) return;\n    final total = main.value.duration.inMilliseconds / 1000.0;\n    var s = _playheadSec;\n    var e = s + 4.0;\n    if (e > total) {\n      e = total;\n      s = max(0.0, total - 4.0);\n    }\n    if (e - s < 0.3) {\n      _toast('المقطع الأساسي قصير جدًّا');\n      return;\n    }\n    state.update(() {\n      state.textTimeCues = [\n        ...state.textTimeCues,\n        TextTimeCue(\n            text: r.text, translation: r.translation, start: s, end: e),\n      ];\n    });\n    HapticFeedback.mediumImpact();\n    setState(() {\n      _selCue = state.textTimeCues.length - 1;\n      _selSeg = -1;\n      _selMain = false;\n    });\n    _toast('أُضيف النص');\n  }\n\n  Future<void> _cueEditText(int i) async {\n    if (i < 0 || i >= state.textTimeCues.length) return;\n    final cue = state.textTimeCues[i];\n    final r = await showQuranTextSheet(context,\n        ayaat: state.ayaat,\n        title: 'تعديل النص',\n        initial: cue.text,\n        initialTranslation: cue.translation);\n    if (r == null || !mounted) return;\n    if (i >= state.textTimeCues.length) return;\n    state.update(() {\n      cue.text = r.text;\n      cue.translation = r.translation;\n    });\n  }\n"),
  ],
}

def read(p):
    return open(p, encoding='utf-8').read()

if all(os.path.exists(p) for p in NEW_FILES) and MARK in read('lib/screens/home_screen.dart'):
    print('  OK      already applied'); sys.exit(0)

bad = []
texts = {}
for path, edits in FILES.items():
    if not os.path.exists(path):
        bad.append('%s (file missing)' % path); continue
    t = read(path)
    if MARK in t:
        bad.append('%s (already contains %s - restore it with git checkout first)' % (path, MARK)); continue
    for label, old, new in edits:
        n = t.count(old)
        if n != 1:
            bad.append('%s - %s (found %d)' % (path, label, n))
    texts[path] = t
for p in NEW_FILES:
    if os.path.exists(p):
        bad.append('%s already exists' % p)
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for path, edits in FILES.items():
    t = texts[path]
    for label, old, new in edits:
        t = t.replace(old, new, 1)
        print('  PATCHED %s - %s' % (path, label))
    open(path, 'w', encoding='utf-8').write(t)
for p, body in NEW_FILES.items():
    os.makedirs(os.path.dirname(p) or '.', exist_ok=True)
    open(p, 'w', encoding='utf-8').write(body)
    print('  CREATED %s' % p)
print('S189 applied. Next: git add -A && git commit -m "S189: Quran-assisted text typing" && git push')
