#!/usr/bin/env python3
"""
patch_s178_fix_systemchrome.py - Ayat Studio S178 (run from repo root, after S177)

BUILD FIX (CI run #191): S176's fullscreen preview calls SystemChrome and
SystemUiMode, but home_screen.dart imports flutter/services.dart with
`show HapticFeedback, rootBundle`, so both names are undefined
(home_screen.dart:1700 and :1728) and screens_smoke_test fails to load.
Fix: add them to that `show` list. Nothing else changes.
Idempotent; anchor-checked.
"""
import os, sys
P = 'lib/screens/home_screen.dart'
if not os.path.exists('pubspec.yaml'):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
if not os.path.exists(P):
    sys.exit('missing ' + P)
s = open(P, encoding='utf-8').read()
OLD = "    show HapticFeedback, rootBundle; // PATCH_S83_SYNC_QOL"
NEW = "    show HapticFeedback, SystemChrome, SystemUiMode, rootBundle; // PATCH_S178_FIX + PATCH_S83_SYNC_QOL"
if 'SystemUiMode, rootBundle' in s:
    print('  OK      already applied'); sys.exit(0)
if s.count(OLD) != 1:
    sys.exit('  NOTHING WRITTEN. services import anchor missing or not unique.')
open(P, 'w', encoding='utf-8').write(s.replace(OLD, NEW, 1))
print('  PATCHED', P)
print('Done. Next: git add -A && git commit -m "S178: import SystemChrome" && git push')
