#!/usr/bin/env python3
"""
PATCH_S88_AUTOSYNC_HONEST_FIX
==============================

Problem
-------
The deepest remaining structural flaw in auto-sync: ANY single scan window
that scored above `minConfidence` (0.32) got committed to the timeline
as-is. Recitation always follows mushaf order, but the old pipeline never
used that -- one garbled window that happened to resemble some other ayah
became one wrong ayah in the results, with no cross-check against the
ayat around it. On top of that, a shaky scan (mostly low-confidence
matches) rendered the exact same "تم رصد N آية ✓" success summary as a
solid one, so there was no signal telling you to distrust the timing.

Fix
---
  1. lib/services/timeline_builder.dart: new `_enforceMushafOrderChain()`,
     called right after the first `repairTimeline()` pass (before
     gap-rescue/inference, so a wrong ayah here can't go on to anchor
     wrong inferences or rescue matches around it). Finds the
     maximum-weight (duration × confidence) subsequence of the committed
     timeline whose ayat are in strictly increasing mushaf order, and
     drops everything outside that chain UNLESS it's individually strong
     enough (`chainKeepConfidence` = 0.5) to stand on its own -- so a
     clearly-heard deliberate repeat still survives even though a repeat
     necessarily breaks strict order.
  2. lib/models/studio_state.dart: new `timelineAverageConfidence()`.
  3. lib/screens/home_screen.dart: the post-scan summary now appends a
     plain warning when average confidence is low, and tells you what
     helps -- raise the دقة التعرف (Whisper model) tier, or use a
     clearer/quieter recording -- instead of presenting a shaky timeline
     as an unqualified success.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s88_autosync_honest_fix.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S88_AUTOSYNC_HONEST_FIX"


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
        raise SystemExit("Usage: python3 patch_s88_autosync_honest_fix.py <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    timeline_builder = root / "lib" / "services" / "timeline_builder.dart"
    studio_state = root / "lib" / "models" / "studio_state.dart"
    home_screen = root / "lib" / "screens" / "home_screen.dart"

    for f in (timeline_builder, studio_state, home_screen):
        if not f.exists():
            raise SystemExit(f"ERROR: expected file not found: {f}")

    print(f"Patching under: {root}\n")

    # ------------------------------------------------------------------
    # 1a) timeline_builder.dart -- call the chain filter right after the
    #     first repairTimeline() pass, before gap-rescue/inference.
    # ------------------------------------------------------------------
    old_1a = """      repairTimeline(timeline);
      await _rescanGaps(
        timeline: timeline,
        pcm: pcm,
        matcher: matcher,
        tempDir: tempDir,
        silenceGate: silenceGate,"""

    new_1a = """      repairTimeline(timeline);
      // PATCH_S88_AUTOSYNC_HONEST_FIX: drop out-of-mushaf-order weak
      // detections before anything downstream can build on them.
      _enforceMushafOrderChain(timeline);
      await _rescanGaps(
        timeline: timeline,
        pcm: pcm,
        matcher: matcher,
        tempDir: tempDir,
        silenceGate: silenceGate,"""

    replace_once(timeline_builder, old_1a, new_1a,
                 "timeline_builder.dart: call _enforceMushafOrderChain")

    # ------------------------------------------------------------------
    # 1b) timeline_builder.dart -- the chain-filter method itself
    # ------------------------------------------------------------------
    anchor_1b = """  // PATCH_S44_CONFIDENCE_RETRANSCRIBE: re-transcribes each committed segment that stayed below
  // [reTranscribeBelowConfidence], using its own refined (tight,"""

    chain_method = """  // PATCH_S88_AUTOSYNC_HONEST_FIX: a detection strong enough to stand on
  // its own outside the chain -- a clearly-heard deliberate repeat, or a
  // genuinely correct out-of-order match -- without needing chain support.
  static const double chainKeepConfidence = 0.5;

  /// PATCH_S88_AUTOSYNC_HONEST_FIX: the deepest structural flaw in the old
  /// pipeline was that ANY single scan window scoring above [minConfidence]
  /// got committed to the timeline as-is, so one garbled window = one wrong
  /// ayah in the results. Recitation follows mushaf order, so this finds
  /// the maximum-weight (duration × confidence) subsequence of [timeline]
  /// whose ayat are in strictly increasing mushaf order (surah, then ayah
  /// number) and drops everything outside that chain UNLESS it's
  /// individually strong enough ([chainKeepConfidence]+) to survive on its
  /// own -- a clearly-heard deliberate repeat necessarily breaks strict
  /// order, so it has to earn its place by confidence rather than by chain
  /// membership. Runs before the gap-rescue/inference passes so a wrong
  /// ayah here can't go on to anchor wrong inferences or wrong rescue
  /// matches around it.
  static void _enforceMushafOrderChain(List<TimelineSegment> timeline) {
    final n = timeline.length;
    if (n < 2) return;

    int key(TimelineSegment s) => s.ayah.surahNum * 10000 + s.ayah.num;
    final weight = [
      for (final s in timeline) (s.end - s.start) * s.confidence
    ];

    // dp[i] = best total weight of an in-order chain ending at segment i.
    final dp = List<double>.filled(n, 0);
    final prev = List<int>.filled(n, -1);
    for (var i = 0; i < n; i++) {
      dp[i] = weight[i];
      for (var j = 0; j < i; j++) {
        if (key(timeline[j]) < key(timeline[i]) &&
            dp[j] + weight[i] > dp[i]) {
          dp[i] = dp[j] + weight[i];
          prev[i] = j;
        }
      }
    }

    var bestEnd = 0;
    for (var i = 1; i < n; i++) {
      if (dp[i] > dp[bestEnd]) bestEnd = i;
    }

    final inChain = List<bool>.filled(n, false);
    for (var cur = bestEnd; cur != -1; cur = prev[cur]) {
      inChain[cur] = true;
    }

    final kept = <TimelineSegment>[
      for (var i = 0; i < n; i++)
        if (inChain[i] || timeline[i].confidence >= chainKeepConfidence)
          timeline[i],
    ];
    if (kept.length == timeline.length) return; // nothing to drop
    timeline
      ..clear()
      ..addAll(kept);
  }

"""

    replace_once(timeline_builder, anchor_1b, chain_method + anchor_1b,
                 "timeline_builder.dart: _enforceMushafOrderChain() method")

    # ------------------------------------------------------------------
    # 2) studio_state.dart -- timelineAverageConfidence()
    # ------------------------------------------------------------------
    anchor_2 = """  double timelineCoverageFraction() {
    if (timeline.isEmpty) return 0;
    final total = videoDurationSec > 0 ? videoDurationSec : timeline.last.end;
    if (total <= 0) return 0;
    var covered = 0.0;
    for (final s in timeline) {
      covered += s.end - s.start;
    }
    return (covered / total).clamp(0.0, 1.0);
  }
"""

    avg_conf_method = """
  // PATCH_S88_AUTOSYNC_HONEST_FIX: mean confidence across the detected
  // timeline -- surfaced in the post-scan summary so a shaky scan reads
  // as shaky instead of a plain, encouraging-looking list of ayat.
  double timelineAverageConfidence() {
    if (timeline.isEmpty) return 0;
    final total = timeline.fold<double>(0, (sum, s) => sum + s.confidence);
    return total / timeline.length;
  }
"""

    replace_once(studio_state, anchor_2, anchor_2 + avg_conf_method,
                 "studio_state.dart: timelineAverageConfidence()")

    # ------------------------------------------------------------------
    # 3) home_screen.dart -- low-confidence warning in the post-scan summary
    # ------------------------------------------------------------------
    old_3 = """      state.update(() {
        state.matchConfidenceText =
            'تم رصد ${timeline.length} آية ($range) تغطي $coverage٪ من المقطع'
            '${inferredCount > 0 ? ' — منها $inferredCount مستنتجة من تسلسل المصحف، راجعها في «مراجعة الآيات المرصودة»' : ''}';
        state.detectedLabel = 'مزامنة تلقائية مفعّلة — التصدير سيستخدم نفس التوقيت';
      });"""

    new_3 = """      // PATCH_S88_AUTOSYNC_HONEST_FIX: a low-confidence scan used to render
      // as the exact same success summary as a solid one -- say so plainly
      // instead, and point at what actually helps.
      final avgConfidence = state.timelineAverageConfidence();
      const lowConfidenceWarnBar = 0.5;
      final qualityWarning = avgConfidence < lowConfidenceWarnBar
          ? '\\n⚠️ متوسط الثقة منخفض (${(avgConfidence * 100).round()}٪) — '
              'التوقيت قد يكون غير دقيق. '
              '${state.whisperModelSize == WhisperModelSize.quranTuned ? 'جرّب مقطعًا أوضح صوتًا وأقل ضجيجًا.' : 'ارفع دقة التعرف (حجم النموذج) من الإعدادات إلى النموذج المخصص للقرآن للحصول على نتيجة أدق.'}'
          : '';
      state.update(() {
        state.matchConfidenceText =
            'تم رصد ${timeline.length} آية ($range) تغطي $coverage٪ من المقطع'
            '${inferredCount > 0 ? ' — منها $inferredCount مستنتجة من تسلسل المصحف، راجعها في «مراجعة الآيات المرصودة»' : ''}'
            '$qualityWarning';
        state.detectedLabel = 'مزامنة تلقائية مفعّلة — التصدير سيستخدم نفس التوقيت';
      });"""

    replace_once(home_screen, old_3, new_3,
                 "home_screen.dart: low-confidence summary warning")

    print("\nDone. PATCH_S88 applied (or already present).")
    print("\nSanity-check next:")
    print("  1. dart analyze lib/services/timeline_builder.dart lib/models/studio_state.dart lib/screens/home_screen.dart")
    print("  2. dart run tool/matcher_test.dart")
    print("  3. Re-run auto-sync on the 3 test recitation files and compare")
    print("     the reported ayah boundaries + summary text by ear.")


if __name__ == "__main__":
    main()
