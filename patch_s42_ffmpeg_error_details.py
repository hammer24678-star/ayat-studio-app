#!/usr/bin/env python3
"""
patch_s42_ffmpeg_error_details.py

"تعذّر استخراج الصوت من الملف (ffmpeg rc=1)" tells us NOTHING about why --
rc=1 is ffmpeg's generic catch-all failure code, covering everything from
"not a real media file" to "codec not found" to "path doesn't exist" to a
Storage-Access-Framework content:// URI ffmpeg can't open directly. We
can't fix what we can't see, so this patch makes the error self-diagnosing
instead of guessing at a root cause blind:

  1. Before invoking ffmpeg at all, check the input path actually exists
     as a real file. FilePicker normally returns a real cached path, but
     if this ever fires it's an instant, specific Arabic message instead
     of a generic ffmpeg rc=1 three seconds later.
  2. On ffmpeg failure, append ffmpeg's own console output (the real
     "Unknown encoder", "Invalid data found", "No such file or directory",
     etc.) to the thrown exception, tail-truncated so a long log doesn't
     blow up the error banner. This is what actually lets us root-cause
     the NEXT time this fires, instead of staring at "rc=1" again.

Usage:
  python3 patch_s42_ffmpeg_error_details.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S42_FFMPEG_ERROR_DETAILS"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S42 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_media_service(project_dir):
    target = project_dir / "lib" / "services" / "media_service.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    old = (
        "import 'package:path_provider/path_provider.dart';\n"
        "import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';\n"
        "import 'package:ffmpeg_kit_flutter_new/return_code.dart';\n"
        "\n"
        "class MediaService {\n"
        "  /// Extracts mono 16kHz PCM WAV from any video/audio file — exactly the\n"
        "  /// format Whisper wants. Real ffmpeg decode, so none of the browser's\n"
        "  /// decodeAudioData container-strictness issues apply here.\n"
        "  static Future<String> extractWav16kMono(String inputPath) async {\n"
        "    final dir = await getTemporaryDirectory();\n"
        "    final outPath = '${dir.path}/asr_${DateTime.now().millisecondsSinceEpoch}.wav';\n"
        "    final cmd = '-y -i \"$inputPath\" -vn -ac 1 -ar 16000 -f wav \"$outPath\"';\n"
        "    final session = await FFmpegKit.execute(cmd);\n"
        "    final rc = await session.getReturnCode();\n"
        "    if (!ReturnCode.isSuccess(rc)) {\n"
        "      throw Exception('تعذّر استخراج الصوت من الملف (ffmpeg rc=$rc)');\n"
        "    }\n"
        "    return outPath;\n"
        "  }\n"
        "}\n"
    )
    new = (
        "import 'dart:io';\n"
        "\n"
        "import 'package:path_provider/path_provider.dart';\n"
        "import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';\n"
        "import 'package:ffmpeg_kit_flutter_new/return_code.dart';\n"
        "\n"
        "class MediaService {\n"
        "  /// Extracts mono 16kHz PCM WAV from any video/audio file — exactly the\n"
        "  /// format Whisper wants. Real ffmpeg decode, so none of the browser's\n"
        "  /// decodeAudioData container-strictness issues apply here.\n"
        "  static Future<String> extractWav16kMono(String inputPath) async {\n"
        f"    // {MARKER}: a plain \"ffmpeg rc=1\" told us nothing about *why* it\n"
        "    // failed -- catch the one common cause we CAN diagnose upfront\n"
        "    // (path doesn't actually resolve to a real file -- e.g. a\n"
        "    // content:// SAF uri ffmpeg's file protocol can't open directly)\n"
        "    // with a specific message, before ever shelling out to ffmpeg.\n"
        "    if (!File(inputPath).existsSync()) {\n"
        "      throw Exception('تعذّر الوصول إلى الملف المحدد — قد يكون مسارًا غير مباشر (SAF) أو تم حذف/نقل الملف بعد اختياره.\\n$inputPath');\n"
        "    }\n"
        "    final dir = await getTemporaryDirectory();\n"
        "    final outPath = '${dir.path}/asr_${DateTime.now().millisecondsSinceEpoch}.wav';\n"
        "    final cmd = '-y -i \"$inputPath\" -vn -ac 1 -ar 16000 -f wav \"$outPath\"';\n"
        "    final session = await FFmpegKit.execute(cmd);\n"
        "    final rc = await session.getReturnCode();\n"
        "    if (!ReturnCode.isSuccess(rc)) {\n"
        f"      // {MARKER}: surface ffmpeg's OWN console output -- the actual\n"
        "      // \"Unknown encoder\", \"Invalid data found when processing input\",\n"
        "      // \"No such file or directory\", etc. -- instead of a bare return\n"
        "      // code that tells us nothing about the real cause. Tail-truncated\n"
        "      // so a noisy log doesn't blow up the error banner.\n"
        "      final rawLog = (await session.getOutput()) ?? '';\n"
        "      final log = rawLog.length > 900 ? rawLog.substring(rawLog.length - 900) : rawLog;\n"
        "      throw Exception('تعذّر استخراج الصوت من الملف (ffmpeg rc=$rc)\\n$log');\n"
        "    }\n"
        "    return outPath;\n"
        "  }\n"
        "}\n"
    )
    text = replace_once(text, old, new, "extractWav16kMono -- add existence check + real ffmpeg log on failure")
    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")

    applied = patch_media_service(project_dir)

    if applied:
        print("OK  lib/services/media_service.dart: applied [S42 -- surface real ffmpeg failure reason]")
    else:
        print("OK  lib/services/media_service.dart: S42 already applied, skipping.")

    print()
    print(f"Applied: {1 if applied else 0}   Skipped(already applied): {0 if applied else 1}   Failed: 0")
    print()
    print("OK  S42 applied.")
    print()
    print("Next time the extraction fails, the error banner will show ffmpeg's")
    print("own log tail (or the specific 'file not accessible' message) instead")
    print("of a bare rc=1 -- screenshot/paste that text and it tells us the real")
    print("cause directly instead of guessing.")
    print()
    print("  git add lib/services/media_service.dart")
    print('  git commit -m "S42: surface real ffmpeg failure reason instead of bare rc=1"')
    print("  git push")


if __name__ == "__main__":
    main()
