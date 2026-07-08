#!/usr/bin/env python3
"""
patch_s44_confidence_retranscribe.py

PLAN PART 1, item 1.3 -- confidence-weighted re-transcription pass.

TimelineBuilder.build() commits a segment off a single window once it
clears `highConfidence` (0.55), but a segment that only ever reached
somewhere between `minConfidence` (0.32) and `highConfidence` stays in the
timeline exactly as first transcribed -- from the original coarse 6s scan
window, which often straddles part of the previous/next ayah too. Once
normalizeTimeline()/_refineBoundaries() have snapped that segment's real
start/end to the reciter's actual breath pauses (already computed, just not
reused for a second look), a tight, single-ayah-sized re-transcription of
exactly that window frequently comes back cleaner than the original guess
and can push a borderline match to a confident one -- or correct it to a
neighbouring ayah entirely.

This does NOT touch the main per-window scan loop or its thresholds (that's
item 1.2, adaptive windowing -- a separate, larger patch). This is a
strictly additive second pass at the end of build(): it only ever replaces
a segment with a strictly higher-confidence result, so it can only improve
the timeline, never make a confident match worse.

Changes:
  lib/services/timeline_builder.dart
    - new constant `reTranscribeBelowConfidence`
    - new method `_reTranscribeWeakSegments()`, called once after
      `_refineBoundaries()` inside `build()`

Usage:
  python3 patch_s44_confidence_retranscribe.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S44_CONFIDENCE_RETRANSCRIBE"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S44 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_timeline_builder(project_dir):
    target = project_dir / "lib" / "services" / "timeline_builder.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    # 1. New threshold constant, next to the existing confidence thresholds.
    text = replace_once(
        text,
        "  static const double minConfidence = 0.32;\n"
        "  static const double highConfidence = 0.55; // commit off a single window\n",
        "  static const double minConfidence = 0.32;\n"
        "  static const double highConfidence = 0.55; // commit off a single window\n"
        f"  // {MARKER}: segments that committed but stayed below this bar get a\n"
        "  // focused second look once their real (refined) boundaries are known --\n"
        "  // a tight, single-ayah-sized window often transcribes more cleanly than\n"
        "  // the original coarse 6s scan window did.\n"
        "  static const double reTranscribeBelowConfidence = 0.45;\n",
        "TimelineBuilder thresholds -- add reTranscribeBelowConfidence",
    )

    # 2. Call the new pass right after boundary refinement, before the wav/
    #    temp-dir cleanup in the `finally` block.
    text = replace_once(
        text,
        "      // PATCH_S35_SMARTER_DETECTION: resolve overlaps/small gaps and snap\n"
        "      // ayah boundaries to the reciter's breath pauses.\n"
        "      normalizeTimeline(timeline, totalSec);\n"
        "      _refineBoundaries(timeline, pcm);\n"
        "    } finally {\n",
        "      // PATCH_S35_SMARTER_DETECTION: resolve overlaps/small gaps and snap\n"
        "      // ayah boundaries to the reciter's breath pauses.\n"
        "      normalizeTimeline(timeline, totalSec);\n"
        "      _refineBoundaries(timeline, pcm);\n"
        f"      // {MARKER}: give low-confidence segments one more focused look now\n"
        "      // that their real boundaries are known.\n"
        "      await _reTranscribeWeakSegments(timeline, pcm, matcher, tempDir,\n"
        "          onStatus: onStatus);\n"
        "    } finally {\n",
        "build() -- call _reTranscribeWeakSegments after boundary refinement",
    )

    # 3. The new method itself, inserted right after build() returns and
    #    before _expectedNext().
    text = replace_once(
        text,
        "    return timeline;\n"
        "  }\n"
        "\n"
        "  // PATCH_S35_SMARTER_DETECTION: the ayat mushaf order predicts after\n"
        "  // [anchor]: the anchor itself (still being recited) and the next two.\n"
        "  static List<Ayah> _expectedNext(List<Ayah> ayaat, Ayah anchor) {\n",
        "    return timeline;\n"
        "  }\n"
        "\n"
        f"  // {MARKER}: re-transcribes each committed segment that stayed below\n"
        "  // [reTranscribeBelowConfidence], using its own refined (tight,\n"
        "  // single-ayah-sized) boundaries instead of the original coarse scan\n"
        "  // window. Replaces the segment in place only if the new pass scores\n"
        "  // strictly higher -- never makes a confident match worse, and any\n"
        "  // failure on an individual segment (transcription error, empty text,\n"
        "  // no better candidate) just leaves that segment exactly as it was.\n"
        "  static Future<void> _reTranscribeWeakSegments(\n"
        "    List<TimelineSegment> timeline,\n"
        "    Int16List pcm,\n"
        "    AyahMatcher matcher,\n"
        "    Directory tempDir, {\n"
        "    void Function(String status)? onStatus,\n"
        "  }) async {\n"
        "    for (var i = 0; i < timeline.length; i++) {\n"
        "      if (_cancelRequested) return;\n"
        "      final seg = timeline[i];\n"
        "      if (seg.confidence >= reTranscribeBelowConfidence) continue;\n"
        "      final durSec = seg.end - seg.start;\n"
        "      if (durSec < 0.6) continue; // too short to bother re-transcribing\n"
        "\n"
        "      final startSample =\n"
        "          (seg.start * sampleRate).floor().clamp(0, pcm.length);\n"
        "      final endSample =\n"
        "          (seg.end * sampleRate).floor().clamp(startSample, pcm.length);\n"
        "      if (endSample - startSample < (sampleRate * 0.5).round()) continue;\n"
        "\n"
        "      onStatus?.call(\n"
        "          'تحسين دقة آية ذات ثقة منخفضة (${i + 1}/${timeline.length})…');\n"
        "      final slice = Int16List.sublistView(pcm, startSample, endSample);\n"
        "      final chunkPath = '${tempDir.path}/retrans_$i.wav';\n"
        "      String text;\n"
        "      try {\n"
        "        _writeWavMono16(chunkPath, slice);\n"
        "        text = await WhisperService.transcribeWav(chunkPath);\n"
        "      } catch (_) {\n"
        "        continue; // a failed re-pass just keeps the original segment\n"
        "      } finally {\n"
        "        File(chunkPath).delete().ignore();\n"
        "      }\n"
        "      if (text.trim().isEmpty) continue;\n"
        "\n"
        "      // Prefer testing against the mushaf-order neighbourhood first (same\n"
        "      // prior used during the main scan) -- a weak match is often just a\n"
        "      // slightly-off boundary on the SAME or an ADJACENT ayah, not a wild\n"
        "      // miss -- falling back to a corpus-wide search so a genuinely\n"
        "      // different ayah can still win if the neighbourhood check fails.\n"
        "      final neighbours = _expectedNext(matcher.ayaat, seg.ayah);\n"
        "      var candidate = matcher.matchAmong(text, neighbours,\n"
        "          minConfidence: contextMinConfidence);\n"
        "      candidate ??= matcher.match(text, minConfidence: minConfidence);\n"
        "      if (candidate != null && candidate.confidence > seg.confidence) {\n"
        "        timeline[i] = TimelineSegment(\n"
        "          start: seg.start,\n"
        "          end: seg.end,\n"
        "          ayah: candidate.ayah,\n"
        "          confidence: candidate.confidence,\n"
        "        );\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "\n"
        "  // PATCH_S35_SMARTER_DETECTION: the ayat mushaf order predicts after\n"
        "  // [anchor]: the anchor itself (still being recited) and the next two.\n"
        "  static List<Ayah> _expectedNext(List<Ayah> ayaat, Ayah anchor) {\n",
        "insert _reTranscribeWeakSegments() method",
    )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

    applied = patch_timeline_builder(project_dir)

    if applied:
        print("OK  lib/services/timeline_builder.dart: applied [S44 -- confidence-weighted re-transcription pass]")
    else:
        print("OK  lib/services/timeline_builder.dart: S44 already applied, skipping.")

    print()
    print(f"Applied: {1 if applied else 0}   Skipped(already applied): {0 if applied else 1}   Failed: 0")
    print()
    print("OK  S44 applied.")
    print()
    print("NOTE: this adds one extra short transcription per low-confidence")
    print("      segment at the END of a scan (not per scan window), so total")
    print("      scan time only grows with how many segments actually stayed")
    print("      weak -- a clean recitation with few weak segments sees almost")
    print("      no slowdown.")
    print()
    print("  git add lib/services/timeline_builder.dart")
    print('  git commit -m "S44: confidence-weighted re-transcription pass for weak timeline segments"')
    print("  git push")


if __name__ == "__main__":
    main()
