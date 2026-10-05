#!/usr/bin/env python3
"""
patch_s164_whisper_cpu_threads.py
=================================
Ayat Studio S164 - run from the repo root (after S163):

    python3 patch_s164_whisper_cpu_threads.py

whisper_ggml_plus on Android is CPU-only (its docs list Android acceleration as
"CPU (SIMD)"; Metal/CoreML are iOS/macOS only), so there is no GPU switch to
flip. What CAN be tuned is the thread count: phones are big.LITTLE, and
whisper.cpp syncs every thread at each layer, so the slow cores make the fast
ones wait. This patch runs Whisper on the fast cores only.

  1. reads each core's max frequency from sysfs and counts the fast cores
  2. falls back to a core-count heuristic when sysfs is unreadable
  3. computed once and cached, not on every transcribe call

Idempotent (marker PATCH_S164).
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S164'
path = os.path.join(ROOT, 'lib/services/whisper_service.dart')
if not os.path.exists(path):
    sys.exit('lib/services/whisper_service.dart missing')

s = open(path, encoding='utf-8').read()
if MARK in s:
    print('  OK      whisper_service.dart (already applied)')
    sys.exit(0)

OLD = ("  static int get _threads =>\n"
       "      math.max(2, math.min(8, Platform.numberOfProcessors - 1));")
if OLD not in s:
    sys.exit('  SKIP    anchor not found (S123 _threads getter) - nothing touched')

NEW = r"""  // PATCH_S164_BIG_CORE_THREADS: whisper_ggml_plus runs on the CPU only on
  // Android. On a big.LITTLE phone the slow cores finish each layer late and
  // every other thread waits for them, so "all cores" is slower than "fast
  // cores". Count the cores whose max frequency is within 70% of the fastest;
  // when sysfs can't be read (some Android builds block it) fall back to a
  // core-count heuristic. Computed once.
  static int? _threadsMemo;
  static int get _threads => _threadsMemo ??= _pickThreads();

  static int _pickThreads() {
    final total = Platform.numberOfProcessors;
    try {
      final freqs = <int>[];
      for (var i = 0; i < total; i++) {
        final f = File(
            '/sys/devices/system/cpu/cpu$i/cpufreq/cpuinfo_max_freq');
        if (!f.existsSync()) continue;
        final v = int.tryParse(f.readAsStringSync().trim());
        if (v != null && v > 0) freqs.add(v);
      }
      if (freqs.length == total && total >= 4) {
        final top = freqs.reduce(math.max);
        final fast = freqs.where((f) => f >= top * 0.7).length;
        return math.max(2, math.min(6, fast));
      }
    } catch (_) {
      // fall through to the heuristic
    }
    if (total >= 6) return 4; // typical 1+3+4 / 2+4 / 4+4 layouts
    return math.max(2, total - 1);
  }"""

s = s.replace(OLD, NEW)
open(path, 'w', encoding='utf-8').write(s)
t = re.sub(r"//[^\n]*", '', s)
bal = all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))
print('  PATCHED lib/services/whisper_service.dart - fast-core thread count')
print('  all balanced' if bal else '  !! UNBALANCED - check the file')
print('Next: git add -A && git commit -m "S164: Whisper threads on fast cores" && git push')
