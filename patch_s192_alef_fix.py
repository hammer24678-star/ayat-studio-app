#!/usr/bin/env python3
"""
patch_s192_alef_fix.py - Ayat Studio S192 (run from repo root, after S191)

Fixes the one red CI test (quran_text_sheet_test: mid-ayah fragment) and the
real bug behind it: typing العالمين / الكتاب / هذا with a normal alef found
nothing, because the corpus writes those sounds as a small dagger alef that
the normalizer drops. Search now retries ignoring alefs when the exact pass
finds nothing (existing behaviour untouched), and keeps whole letters at the
edges so the completion in «كتابة بالقرآن» starts and ends cleanly.
Adds a test for it.

Idempotent; every anchor is verified before anything is written.
"""
import os, sys
MARK = 'PATCH_S192_ALEF'
if not os.path.exists('lib/services/quran_search.dart'):
    sys.exit('Run from the repo root (missing lib/services/quran_search.dart).')

FILES = {
  'lib/services/quran_search.dart': [
    ('alefless fallback', '      results.sort((a, b) {\n        final c = a.rank.compareTo(b.rank);\n        return c != 0 ? c : a.corpusIndex.compareTo(b.corpusIndex);\n      });\n    }\n\n    return results.length > limit ? results.sublist(0, limit) : results;\n  }\n', "      results.sort((a, b) {\n        final c = a.rank.compareTo(b.rank);\n        return c != 0 ? c : a.corpusIndex.compareTo(b.corpusIndex);\n      });\n      // PATCH_S192_ALEF: nothing matched as typed -> try again ignoring alefs.\n      if (results.isEmpty) {\n        results.addAll(_alefless(q, ayaat, norm, offsets, limit));\n      }\n    }\n\n    return results.length > limit ? results.sublist(0, limit) : results;\n  }\n\n  /// The corpus writes many long-aa sounds as a small dagger alef above the\n  /// letter (العٰلمين, الكتٰب, هٰذا) which the normalizer drops, while people\n  /// type a full alef (العالمين, الكتاب, هذا). So when the exact pass finds\n  /// nothing, both sides are compared with every alef removed. The reported\n  /// range is widened by a leading / trailing alef the user typed, so a\n  /// completion still starts and ends on whole letters.\n  static List<AyahSearchResult> _alefless(String q, List<Ayah> ayaat,\n      List<String> norm, List<List<int>> offsets, int limit) {\n    final qs = q.replaceAll('ا', '');\n    if (qs.length < 2) return const [];\n    final out = <AyahSearchResult>[];\n    for (var i = 0; i < norm.length && i < ayaat.length; i++) {\n      final n = norm[i];\n      final sb = StringBuffer();\n      final back = <int>[];\n      for (var k = 0; k < n.length; k++) {\n        if (n[k] == 'ا') continue;\n        sb.write(n[k]);\n        back.add(k);\n      }\n      final sk = sb.toString();\n      final at = sk.indexOf(qs);\n      if (at < 0) continue;\n      final map = offsets[i];\n      var nStart = back[at];\n      var nEnd = back[at + qs.length - 1];\n      if (q.startsWith('ا') && nStart > 0 && n[nStart - 1] == 'ا') nStart--;\n      if (q.endsWith('ا') && nEnd + 1 < n.length && n[nEnd + 1] == 'ا') nEnd++;\n      final start = nStart < map.length ? map[nStart] : -1;\n      final end = nEnd < map.length ? map[nEnd] : -1;\n      out.add(AyahSearchResult(\n        corpusIndex: i,\n        ayah: ayaat[i],\n        matchStart: start,\n        matchLength: (start >= 0 && end >= start) ? end - start + 1 : 0,\n        rank: at == 0 ? 0 : (sk[at - 1] == ' ' ? 1 : 2) + at / 10000.0,\n      ));\n      if (out.length >= limit * 3) break;\n    }\n    out.sort((a, b) {\n      final c = a.rank.compareTo(b.rank);\n      return c != 0 ? c : a.corpusIndex.compareTo(b.corpusIndex);\n    });\n    return out;\n  }\n"),
  ],
  'test/quran_text_sheet_test.dart': [
    ('alef test', "  test('non-Quran text finds nothing', () {\n    expect(QuranSearch.search('مرحبا بكم', corpus), isEmpty);\n  });\n}\n", "  test('non-Quran text finds nothing', () {\n    expect(QuranSearch.search('مرحبا بكم', corpus), isEmpty);\n  });\n\n  // PATCH_S192_ALEF\n  test('a full alef still finds dagger-alef text, whole letters at the edges',\n      () {\n    final r = QuranSearch.search('العالمين', corpus);\n    expect(r, isNotEmpty);\n    expect(r.first.ayah.num, 2);\n    final out = quranCompleteFrom(r.first.ayah.ar, r.first.matchStart);\n    expect(out.startsWith('ٱ'), isTrue);\n    expect(out.endsWith('ٱلْعَـٰلَمِينَ'), isTrue);\n  });\n}\n"),
  ],
}

def read(p):
    return open(p, encoding='utf-8').read()

if all(MARK in read(p) for p in FILES if os.path.exists(p)):
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
if bad:
    sys.exit('Anchor check failed, nothing written:\n  ' + '\n  '.join(bad))

for path, edits in FILES.items():
    t = texts[path]
    for label, old, new in edits:
        t = t.replace(old, new, 1)
        print('  PATCHED %s - %s' % (path, label))
    open(path, 'w', encoding='utf-8').write(t)
print('S192 applied. Next: git add -A && git commit -m "S192: alef-tolerant Quran search" && git push')
