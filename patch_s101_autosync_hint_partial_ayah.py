#!/usr/bin/env python3
"""
PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH
=======================================

Two independent additions to lib/screens/home_screen.dart:

1. AUTO-SYNC EXPECTATION HINT -- a short line under the auto-sync
   button so people know, before they tap it, what it actually does
   today: it scans and writes ayat for roughly half the video well,
   and the rest may need manual review/adjustment via the timeline
   card. No behavior change, just honest labeling up front instead of
   people discovering it mid-export.

2. PARTIAL-AYAH SELECTION -- in the الآية tab's single-ayah picker,
   once a surah+ayah is chosen from the dropdowns, a word-range picker
   appears letting you use just part of it (e.g. the first half) as
   the on-screen text instead of the full ayah. Backed entirely by
   the existing state.setAyah() -- a partial string is just text, and
   setAyah doesn't care how it was assembled -- so AI-art/karaoke/
   export all keep working unchanged. surahNum/ayahNum are still
   passed through so AI-art scene generation still has a real anchor.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s101_autosync_hint_partial_ayah.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH"


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")

    if new.strip() in text:
        print(f"  SKIP  ({label}): already applied")
        return False

    count = text.count(old)
    if count == 0:
        raise SystemExit(
            f"ERROR ({label}): expected old text not found in {path}. "
            f"File may have drifted since this patch was written -- "
            f"aborting instead of guessing."
        )
    if count > 1:
        raise SystemExit(
            f"ERROR ({label}): old text found {count} times in {path}, "
            f"expected exactly 1 -- refusing to guess which one."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  OK    ({label}): patched")
    return True


# ---------------------------------------------------------------------
# 1. lib/screens/home_screen.dart -- auto-sync hint text
# ---------------------------------------------------------------------

_AUTOSYNC_OLD = """        ElevatedButton.icon(
          onPressed: _busy ? null : _autoSync,
          style: ElevatedButton.styleFrom(
            side: const BorderSide(color: AyatColors.gold),
          ),
          icon: const Icon(Icons.auto_awesome, size: 18),
          // PATCH_S83_SYNC_QOL: make it clear a re-run replaces the current scan
          label: Text(state.timelineActive
              ? 'إعادة المزامنة التلقائية (تستبدل الرصد الحالي)'
              : 'مزامنة تلقائية: اكتب كل آية أثناء التلاوة'),
        ),
      ],
    );
  }"""

_AUTOSYNC_NEW = """        ElevatedButton.icon(
          onPressed: _busy ? null : _autoSync,
          style: ElevatedButton.styleFrom(
            side: const BorderSide(color: AyatColors.gold),
          ),
          icon: const Icon(Icons.auto_awesome, size: 18),
          // PATCH_S83_SYNC_QOL: make it clear a re-run replaces the current scan
          label: Text(state.timelineActive
              ? 'إعادة المزامنة التلقائية (تستبدل الرصد الحالي)'
              : 'مزامنة تلقائية: اكتب كل آية أثناء التلاوة'),
        ),
        // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: set expectations before they tap it --
        // it does the job well on roughly half the video; the rest may
        // need a manual touch-up from the review card above.
        const SizedBox(height: 6),
        Text(
          'تعمل جيدًا في نحو نصف الفيديو غالبًا؛ راجعي/عدّلي الباقي من '
          'بطاقة \\'مراجعة الآيات المرصودة\\' بعد التشغيل.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AyatColors.goldDim),
        ),
      ],
    );
  }"""


def patch_home_screen_hint(root: pathlib.Path) -> bool:
    path = root / "lib" / "screens" / "home_screen.dart"
    return replace_once(path, _AUTOSYNC_OLD, _AUTOSYNC_NEW,
                         "home_screen.dart: auto-sync expectation hint")


# ---------------------------------------------------------------------
# 2. lib/screens/home_screen.dart -- partial-ayah word-range picker
# ---------------------------------------------------------------------

# Track which ayah is currently picked (the old dropdown always shows
# `value: null` / resets visually on purpose -- we don't touch that,
# we just also remember the index privately so the new section below
# knows what to slice).
_STATE_FIELD_OLD = """  int _selectedTab = 0;
  int _selectedSurah = 1;"""

_STATE_FIELD_NEW = """  int _selectedTab = 0;
  int _selectedSurah = 1;
  // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: last ayah picked from the dropdown below,
  // so the partial-ayah word-range section knows what to slice from.
  Ayah? _partialSourceAyah;
  int _partialFromWord = 0;
  int _partialToWord = 0;"""

_DROPDOWN_OLD = """          onChanged: (v) {
            if (v == null) return;
            final a = state.ayaat[v];
            _liveOverlay.value = null;
            state.setAyah(a.ar, a.en,
                'تم الاختيار يدويًا: سورة ${a.surah} — آية ${a.num}',
                surahNum: a.surahNum, ayahNum: a.num); // PATCH_S32_AI_ART_NANO_BANANA
          },
        ),"""

_DROPDOWN_NEW = """          onChanged: (v) {
            if (v == null) return;
            final a = state.ayaat[v];
            _liveOverlay.value = null;
            state.setAyah(a.ar, a.en,
                'تم الاختيار يدويًا: سورة ${a.surah} — آية ${a.num}',
                surahNum: a.surahNum, ayahNum: a.num); // PATCH_S32_AI_ART_NANO_BANANA
            // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH
            final words = a.ar.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
            setState(() {
              _partialSourceAyah = a;
              _partialFromWord = 0;
              _partialToWord = words.isEmpty ? 0 : words.length - 1;
            });
          },
        ),
        if (_partialSourceAyah != null) _partialAyahSection(),"""

_PANEL_METHOD_ANCHOR_OLD = """  // ------------------------------------------------------------ tab: الآية

  Widget _ayahPanel() {"""

_PARTIAL_SECTION_METHOD = """  // ------------------------------------------------------------ tab: الآية

  // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: lets you use only part of the
  // currently-picked ayah (e.g. the first half) as the on-screen text,
  // instead of always the whole ayah. Purely a text-slicing UI -- the
  // result still goes through the normal state.setAyah() path, so
  // AI-art/karaoke/export don't need to know the difference.
  Widget _partialAyahSection() {
    final a = _partialSourceAyah;
    if (a == null) return const SizedBox.shrink();
    final words = a.ar.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2) return const SizedBox.shrink();
    final from = _partialFromWord.clamp(0, words.length - 1);
    final to = _partialToWord.clamp(from, words.length - 1);
    final partialText = words.sublist(from, to + 1).join(' ');
    final isFull = from == 0 && to == words.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text('استخدام جزء من الآية فقط',
            style: Theme.of(context).textTheme.headlineMedium),
        Text(
          'اختاري من أي كلمة إلى أي كلمة من الآية المحددة أعلاه -- مفيد لعرض نصفها '
          'فقط مثلاً بدل الآية كاملة.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'من كلمة'),
                value: from,
                items: [
                  for (var i = 0; i < words.length; i++)
                    DropdownMenuItem(value: i, child: Text('${i + 1}. ${words[i]}')),
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
                decoration: const InputDecoration(labelText: 'إلى كلمة'),
                value: to,
                items: [
                  for (var i = 0; i < words.length; i++)
                    DropdownMenuItem(value: i, child: Text('${i + 1}. ${words[i]}')),
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
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: AyatColors.hairline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(partialText,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge),
        ),
        const SizedBox(height: 8),
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
                  _toast('تم استخدام جزء من الآية');
                },
          child: Text(isFull ? 'الآية كاملة محددة بالفعل' : 'استخدام هذا الجزء فقط'),
        ),
      ],
    );
  }

  Widget _ayahPanel() {"""


def patch_home_screen_partial(root: pathlib.Path) -> bool:
    path = root / "lib" / "screens" / "home_screen.dart"
    a = replace_once(path, _STATE_FIELD_OLD, _STATE_FIELD_NEW,
                      "home_screen.dart: add _partialSourceAyah/_partialFromWord/_partialToWord fields")
    b = replace_once(path, _DROPDOWN_OLD, _DROPDOWN_NEW,
                      "home_screen.dart: track picked ayah + show partial-ayah section")
    c = replace_once(path, _PANEL_METHOD_ANCHOR_OLD, _PARTIAL_SECTION_METHOD,
                      "home_screen.dart: insert _partialAyahSection()")
    return a or b or c


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 patch_s101_autosync_hint_partial_ayah.py <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    if not root.exists():
        raise SystemExit(f"ERROR: project root not found: {root}")

    print(f"Patching under: {root}\n")

    print("-- auto-sync expectation hint --")
    patch_home_screen_hint(root)

    print("\n-- partial-ayah word-range picker --")
    patch_home_screen_partial(root)

    print(f"\nDone. {MARKER} applied (or already present).")
    print("\nSanity-check next:")
    print("  1. dart analyze")
    print("  2. Auto-sync button (الآية tab, upload panel) should show a small")
    print("     gold-dim line under it about ~half accuracy + review card.")
    print("  3. الآية tab: pick a surah+ayah from the two dropdowns -- a new")
    print("     'استخدام جزء من الآية فقط' section should appear with two")
    print("     word dropdowns (من كلمة / إلى كلمة), a live preview box of the")
    print("     selected slice, and an apply button (disabled when the full")
    print("     ayah is selected).")
    print("  4. Applying a partial slice should update the live stage text")
    print("     and detectedLabel ('جزء من: سورة ... — آية ...') same as any")
    print("     other manual pick; AI-art (if enabled) should still fire since")
    print("     surahNum/ayahNum are still passed through.")


if __name__ == "__main__":
    main()
