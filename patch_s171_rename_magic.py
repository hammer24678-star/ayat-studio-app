#!/usr/bin/env python3
"""
patch_s171_rename_magic.py - Ayat Studio S171 (run from repo root, after S170)

Pure rename of the S170 card's user-facing names (no logic changes):
  سحر الآية        -> ظلال الآية      (card title)
  مزاج الآية: X    -> روح الآية: X    (mood row)
  طبّق المزاج      -> طبّق روح الآية  (button)
  طُبِّق مزاج «X»   -> اكتست الآية روح «X»  (toast)
  اقتراح اللحظة    -> آية اللحظة      (moment suggestion)
Studio lamp (سراج الاستوديو) is unchanged.
Idempotent; anchor-checked: nothing is written unless every anchor exists.
"""
import os, sys

P = 'lib/widgets/magic_card.dart'
if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
if not os.path.exists(P):
    sys.exit('missing ' + P + ' (apply S170 first)')
src = open(P, encoding='utf-8').read()

R = [
    ("'سحر الآية'", "'ظلال الآية'"),
    ('"سحر الآية": Ayah Mood', '"ظلال الآية": Ayah Mood'),
    ("'مزاج الآية: ${r.labelAr}'", "'روح الآية: ${r.labelAr}'"),
    ("'طبّق المزاج'", "'طبّق روح الآية'"),
    ("'طُبِّق مزاج «${r.labelAr}» ${r.emoji}'", "'اكتست الآية روح «${r.labelAr}» ${r.emoji}'"),
    ("'اقتراح اللحظة'", "'آية اللحظة'"),
    ("'اقتراح اللحظة: سورة", "'آية اللحظة: سورة"),
]
if all(new in src for _, new in R) and not any(old in src for old, _ in R):
    print('  OK      already applied'); sys.exit(0)
missing = [old for old, new in R if old not in src and new not in src]
if missing:
    print('  NOTHING WRITTEN. Missing anchors:')
    for m in missing: print('   -', m)
    sys.exit(1)
for old, new in R:
    src = src.replace(old, new)
open(P, 'w', encoding='utf-8').write(src)
print('  PATCHED', P)
print('Done. Next: git add -A && git commit -m "S171: rename magic card" && git push')
