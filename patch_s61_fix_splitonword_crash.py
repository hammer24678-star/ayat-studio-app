#!/usr/bin/env python3
"""
patch_s61_fix_splitonword_crash.py

Crash seen on-device (upload/video sync flow, "سريع 148MB" model tier):

  تعذّر التعرّف على الكلام في كل مقاطع هذا الفيديو
  (Exception: [json.exception.type_error.302] type must be string, but is null)

Root cause: S55 passes splitOnWord: true to whisper_ggml_plus's
WhisperController.transcribe() to get per-word onsets for the karaoke
timing. whisper_ggml_plus's own docs flag word-split mode as a newer,
narrower code path (it force-disables VAD internally, unlike the normal
segment-level path) -- and in practice, for at least some inputs, the
underlying whisper.cpp JSON it parses comes back with a null word-token
field, which the plugin's nlohmann::json bridge reads as a string
unconditionally and throws on. Because every scan window takes the same
splitOnWord:true path, one bad response pattern fails 100% of windows for
the whole video, exactly as reported.

Fix: on a transcribe failure, retry that window once with
splitOnWord: false before giving up on it. _groupWords() already falls
back to whole-window text when no per-word timestamps come back (see its
own comment), so this only costs karaoke-onset precision for the
window(s) that hit the bug -- detection/matching keeps working instead of
the whole video failing outright.

  lib/screens/home_screen.dart (or wherever _detectTimeline's scan loop
  lives -- matched by anchor, not a fixed path)
    - transcribe try/catch now retries once without splitOnWord on failure.

Usage:
  python3 patch_s61_fix_splitonword_crash.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S61_SPLITONWORD_FALLBACK"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S61 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def find_target(project_dir):
    candidates = [
        project_dir / "lib" / "services" / "timeline_builder.dart",
        project_dir / "lib" / "screens" / "home_screen.dart",
    ]
    for c in candidates:
        if c.exists():
            try:
                if "splitOnWord: true, // PATCH_S55_WORD_TIMESTAMPS" in c.read_text():
                    return c
            except Exception:
                pass
    # fall back to scanning the whole lib/ tree
    for path in (project_dir / "lib").rglob("*.dart"):
        try:
            if "splitOnWord: true, // PATCH_S55_WORD_TIMESTAMPS" in path.read_text():
                return path
        except Exception:
            continue
    return None


def patch_file(target):
    text = target.read_text()
    if MARKER in text:
        return False

    old = (
        "        try {\n"
        "          final chunkPath = '${tempDir.path}/chunk_$chunkIndex.wav';\n"
        "          _writeWavMono16(chunkPath, slice);\n"
        "          transcript = await WhisperService.transcribeWavWithSegments(\n"
        "            chunkPath,\n"
        "            audioDurationSec: windowDurationSec,\n"
        "            splitOnWord: true, // PATCH_S55_WORD_TIMESTAMPS\n"
        "          );\n"
        "          File(chunkPath).delete().ignore();\n"
        "        } catch (e) {\n"
        "          windowsFailed++; // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES\n"
        "          lastTranscribeError = e; // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES\n"
        "          continue; // one failed window shouldn't kill the whole scan\n"
        "        }\n"
    )

    new = (
        "        final chunkPath = '${tempDir.path}/chunk_$chunkIndex.wav';\n"
        "        _writeWavMono16(chunkPath, slice);\n"
        "        try {\n"
        "          transcript = await WhisperService.transcribeWavWithSegments(\n"
        "            chunkPath,\n"
        "            audioDurationSec: windowDurationSec,\n"
        "            splitOnWord: true, // PATCH_S55_WORD_TIMESTAMPS\n"
        "          );\n"
        "        } catch (e) {\n"
        f"          // {MARKER}: whisper_ggml_plus's word-split path is narrower\n"
        "          // than its normal one (it force-disables VAD, per its own docs)\n"
        "          // and can throw a json.exception.type_error.302 for some inputs.\n"
        "          // Retry this window without word-splitting before giving up on\n"
        "          // it -- _groupWords() already falls back to whole-window text\n"
        "          // when no per-word timestamps come back, so this only costs\n"
        "          // karaoke-onset precision for the affected window(s), not the\n"
        "          // whole video's detection.\n"
        "          try {\n"
        "            transcript = await WhisperService.transcribeWavWithSegments(\n"
        "              chunkPath,\n"
        "              audioDurationSec: windowDurationSec,\n"
        "              splitOnWord: false,\n"
        "            );\n"
        "          } catch (e2) {\n"
        "            File(chunkPath).delete().ignore();\n"
        "            windowsFailed++; // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES\n"
        "            lastTranscribeError = e2; // PATCH_S56_SURFACE_TRANSCRIBE_FAILURES\n"
        "            continue; // one failed window shouldn't kill the whole scan\n"
        "          }\n"
        "        }\n"
        "        File(chunkPath).delete().ignore();\n"
    )

    text = replace_once(text, old, new, "transcribe try/catch -> splitOnWord fallback")
    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    target = find_target(project_dir)
    if target is None:
        die("could not locate the file containing the S55 splitOnWord scan loop under lib/ "
            "-- it may have moved or already been patched differently.")
    changed = patch_file(target)
    if changed:
        print(f"OK: patched {target}")
    else:
        print(f"SKIP: S61 marker already present in {target}, no changes made.")


if __name__ == "__main__":
    main()
