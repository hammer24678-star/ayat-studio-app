#!/usr/bin/env python3
"""
PATCH_S87_AI_ART_ONE_TAP_FLOW
==============================

Problem
-------
The AI-art panel had three half-explained states stacked on top of each
other: a "generate now" button that only ever did ONE ayah (the currently
displayed one), a separate regenerate/delete pair, and an API-key field
sitting in plain view that read like a requirement even though generation
has been fully keyless since S80. None of it told you what tapping it
would actually do, and it had no idea an auto-sync timeline (up to 6
detected ayat) even existed.

Fix
---
  1. lib/models/studio_state.dart: new `generateArtForTimelineBatch()` --
     one call generates + caches art for the first 6 unique ayat of the
     active auto-sync timeline (in timeline order), switches the
     background to the first one, and leaves the existing S84
     `ensureArtForPlayback` playback path to swap each ayah's art in from
     the now-warm cache as the reciter reaches it. `AiArtService.artFor()`
     is itself cache-checked, so re-running this after a partial failure
     only retries what didn't finish. New `aiArtBatchBusy` /
     `aiArtBatchProgress` fields track it independently of the existing
     single-ayah `aiArtBusy` spinner.
  2. lib/screens/home_screen.dart: the API-key field moves behind a
     collapsed "خيارات متقدمة" expander, and the three old buttons become
     ONE button whose label and action depend on whether an auto-sync
     timeline is active:
       - timeline active:  "توليد الفن لآيات المقطع (حتى 6 آيات)"
                            -> generateArtForTimelineBatch()
       - no timeline yet:  "توليد فن للآية الحالية"
                            -> generateAiArtNow() (previous single-ayah path)
     A live "الآية N من 6..." progress line shows during the batch.
     Regenerate/delete for the currently displayed ayah stay available
     underneath once art exists, unchanged from before.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s87_ai_art_one_tap_flow.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S87_AI_ART_ONE_TAP_FLOW"


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")

    if MARKER in text and new.strip() in text:
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


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 patch_s87_ai_art_one_tap_flow.py <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    studio_state = root / "lib" / "models" / "studio_state.dart"
    home_screen = root / "lib" / "screens" / "home_screen.dart"

    for f in (studio_state, home_screen):
        if not f.exists():
            raise SystemExit(f"ERROR: expected file not found: {f}")

    print(f"Patching under: {root}\n")

    # ------------------------------------------------------------------
    # 1) studio_state.dart -- new batch-tracking fields
    # ------------------------------------------------------------------
    old_1 = """  bool aiArtEnabled = false;
  bool aiArtBusy = false;"""

    new_1 = """  bool aiArtEnabled = false;
  bool aiArtBusy = false;
  // PATCH_S87_AI_ART_ONE_TAP_FLOW: batch generation for the whole
  // auto-sync segment, tracked separately from the single-ayah
  // aiArtBusy above so the two flows never fight over one spinner.
  bool aiArtBatchBusy = false;
  String? aiArtBatchProgress;"""

    replace_once(studio_state, old_1, new_1, "studio_state.dart: batch fields")

    # ------------------------------------------------------------------
    # 2) studio_state.dart -- generateArtForTimelineBatch()
    # ------------------------------------------------------------------
    anchor_2 = """  Future<void> generateAiArtNow() async {
    if (_lastMatchedSurah == null ||
        _lastMatchedAyahNum == null ||
        _lastMatchedAyahText == null) {
      aiArtError = 'اختر آية أولًا (بالتعرف التلقائي أو من المصحف) قبل توليد الفن';
      notifyListeners();
      return;
    }
    _aiArtSeedOffset = 0;
    await _generateAiArt(
        _lastMatchedSurah!, _lastMatchedAyahNum!, _lastMatchedAyahText!);
  }
"""

    batch_method = """
  // PATCH_S87_AI_ART_ONE_TAP_FLOW: one tap generates + caches art for the
  // first [_aiArtBatchMax] unique ayat of the active auto-sync timeline
  // (in timeline order), switches the background to the first one, and
  // leaves aiArtEnabled on so the existing playback path (S84) swaps each
  // ayah's art in from the now-warm cache as the reciter reaches it --
  // no separate "follow-along" flag needed, ensureArtForPlayback already
  // does that whenever aiArtEnabled is true. artFor() is itself
  // cache-checked, so re-running this after a partial success only retries
  // whatever didn't finish, and never re-hits the network for ayat that
  // already have art.
  static const int _aiArtBatchMax = 6;
  Future<void> generateArtForTimelineBatch() async {
    if (aiArtBatchBusy || aiArtBusy) return;
    if (timeline.isEmpty) {
      aiArtError = 'شغّل المزامنة التلقائية أولًا لرصد آيات المقطع';
      notifyListeners();
      return;
    }
    final seen = <String>{};
    final targets = <Ayah>[];
    for (final seg in timeline) {
      final key = '${seg.ayah.surahNum}:${seg.ayah.num}';
      if (seen.add(key)) {
        targets.add(seg.ayah);
        if (targets.length >= _aiArtBatchMax) break;
      }
    }

    aiArtBatchBusy = true;
    aiArtBatchProgress = null;
    aiArtError = null;
    notifyListeners();
    var ok = 0;
    try {
      for (var i = 0; i < targets.length; i++) {
        final ayah = targets[i];
        aiArtBatchProgress = 'الآية ${i + 1} من ${targets.length}…';
        notifyListeners();
        try {
          final path = await AiArtService.artFor(
            surahNum: ayah.surahNum,
            ayahNum: ayah.num,
            ayahArabic: ayah.ar,
          );
          if (path != null) {
            ok++;
            if (i == 0) {
              useCustomBg = true;
              customBgPath = path;
              _aiArtSurah = ayah.surahNum;
              _aiArtAyahNum = ayah.num;
              _aiArtAyahText = ayah.ar;
              _aiArtSeedOffset = 0;
            }
            _lastMatchedSurah = ayah.surahNum;
            _lastMatchedAyahNum = ayah.num;
            _lastMatchedAyahText = ayah.ar;
          }
        } on AiArtException catch (e) {
          aiArtError = e.message; // last error stays visible if all fail
        } catch (e) {
          aiArtError = 'تعذر توليد الفن: $e';
        }
      }
      if (ok == 0) {
        aiArtError ??= 'تعذر توليد الفن لأي من آيات المقطع';
        aiArtBatchProgress = null;
      } else if (ok < targets.length) {
        aiArtError = null;
        aiArtBatchProgress =
            'تم توليد فن $ok من ${targets.length} آيات — البقية ستُحاول تلقائيًا أثناء التشغيل';
      } else {
        aiArtError = null;
        aiArtBatchProgress = null;
      }
    } finally {
      aiArtBatchBusy = false;
      notifyListeners();
    }
  }
"""

    replace_once(studio_state, anchor_2, anchor_2 + batch_method,
                 "studio_state.dart: generateArtForTimelineBatch()")

    # ------------------------------------------------------------------
    # 3) home_screen.dart -- collapse the API key field + one obvious button
    # ------------------------------------------------------------------
    old_3 = """          // PATCH_S80_POLLINATIONS_KEYLESS_FLUX: generation now works with this
          // field left blank -- it's an optional advanced field only.
          const SizedBox(height: 8),
          TextField(
            controller: TextEditingController(text: state.pollinationsApiKey)
              ..selection = TextSelection.collapsed(
                  offset: state.pollinationsApiKey.length),
            style: const TextStyle(fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'مفتاح Pollinations (اختياري)',
              helperText: 'التوليد يعمل بدون مفتاح -- اتركه فارغًا. أدخل مفتاحك الشخصي فقط لرفع الحد لاحقًا',
              helperMaxLines: 2,
              isDense: true,
            ),
            onChanged: (v) => state.update(() {
              state.pollinationsApiKey = v.trim();
              AiArtService.apiKey = state.pollinationsApiKey;
            }),
          ),
          const SizedBox(height: 8),
          if (state.aiArtError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                state.aiArtError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.redAccent),
              ),
            ),
          if (state.aiArtBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('جارٍ توليد الفن...'),
              ]),
            )
          else if (state.hasAiArt) ...[
            OutlinedButton.icon(
              onPressed: () => state.regenerateAiArt(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('إعادة توليد فن هذه الآية'),
            ),
            const SizedBox(height: 6),
            // PATCH_S51_AI_ART_DELETE: distinct from regenerate -- wipes
            // the cached image from disk and drops back to the preset
            // background instead of making a new one.
            OutlinedButton.icon(
              onPressed: () => state.deleteAiArt(),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('حذف الفن المولّد لهذه الآية'),
            ),
          ] else
            // PATCH_S69_AI_ART_FIX: previously nothing rendered here at all when no
            // art existed yet -- this was the actual \"does nothing\" bug.
            ElevatedButton.icon(
              onPressed: () => state.generateAiArtNow(),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('توليد الآن'),
            ),
        ],
        const SizedBox(height: 10),"""

    new_3 = """          // PATCH_S87_AI_ART_ONE_TAP_FLOW: the API-key field used to sit in
          // plain view and read like a requirement to use the feature at
          // all -- it's optional (S80 made generation fully keyless), so
          // it now lives behind a collapsed "خيارات متقدمة" expander.
          const SizedBox(height: 8),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text('خيارات متقدمة',
                  style: TextStyle(fontSize: 13, color: AyatColors.parchmentDim)),
              children: [
                TextField(
                  controller: TextEditingController(text: state.pollinationsApiKey)
                    ..selection = TextSelection.collapsed(
                        offset: state.pollinationsApiKey.length),
                  style: const TextStyle(fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'مفتاح Pollinations (اختياري)',
                    helperText: 'التوليد يعمل بدون مفتاح -- اتركه فارغًا. أدخل مفتاحك الشخصي فقط لرفع الحد لاحقًا',
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                  onChanged: (v) => state.update(() {
                    state.pollinationsApiKey = v.trim();
                    AiArtService.apiKey = state.pollinationsApiKey;
                  }),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (state.aiArtError != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                state.aiArtError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.redAccent),
              ),
            ),
          // PATCH_S87_AI_ART_ONE_TAP_FLOW: one obvious flow instead of three
          // half-explained states. With an auto-sync timeline active this
          // batch-generates + caches art for the segment's ayat (up to 6)
          // in one tap with live progress; without one it falls back to
          // the single current-ayah path (previous behavior, unchanged).
          if (state.aiArtBatchBusy)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Expanded(
                    child:
                        Text(state.aiArtBatchProgress ?? 'جارٍ توليد الفن...')),
              ]),
            )
          else if (state.aiArtBusy)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 8),
                Text('جارٍ توليد الفن...'),
              ]),
            )
          else ...[
            if (state.aiArtBatchProgress != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(state.aiArtBatchProgress!,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AyatColors.goldBright)),
              ),
            ElevatedButton.icon(
              onPressed: () => state.timelineActive
                  ? state.generateArtForTimelineBatch()
                  : state.generateAiArtNow(),
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: Text(state.timelineActive
                  ? 'توليد الفن لآيات المقطع (حتى 6 آيات)'
                  : 'توليد فن للآية الحالية'),
            ),
            if (state.hasAiArt) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => state.regenerateAiArt(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('إعادة توليد فن هذه الآية'),
              ),
              const SizedBox(height: 6),
              // PATCH_S51_AI_ART_DELETE: distinct from regenerate -- wipes
              // the cached image from disk and drops back to the preset
              // background instead of making a new one.
              OutlinedButton.icon(
                onPressed: () => state.deleteAiArt(),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('حذف الفن المولّد لهذه الآية'),
              ),
            ],
          ],
        ],
        const SizedBox(height: 10),"""

    replace_once(home_screen, old_3, new_3, "home_screen.dart: one-tap AI art UI")

    print("\nDone. PATCH_S87 applied (or already present).")
    print("\nSanity-check next:")
    print("  1. dart analyze lib/models/studio_state.dart lib/screens/home_screen.dart")
    print("  2. flutter build (or run) and check: توليد بدون مزامنة يعمل كالسابق،")
    print("     وبعد المزامنة التلقائية يظهر زر «توليد الفن لآيات المقطع».")


if __name__ == "__main__":
    main()
