#!/usr/bin/env python3
"""
PATCH_S157b — hotfix for the S157 CI break

Two mistakes left by S157:

1. karaoke.dart signature became
       {int maxWordsPerChunk = maxWordsPerChunk}
   because the body rewrite also rewrote the default value.
   Restore the constant:
       {int maxWordsPerChunk = kKaraokeMaxWordsPerChunk}

2. app_info.dart: kAppVersion is 1.7.0 but kAppBuildNumber is still 6
   (S157 only did a string replace of "1.6.0"/"+6", not the bare int).
   Bump to 7 so app_info_test matches pubspec 1.7.0+7.

Run:  python3 patch_s157b_fix_maxwords_default.py <project_root>
"""

from __future__ import annotations

import pathlib
import sys

MARKER = "PATCH_S157B_FIX_MAXWORDS_DEFAULT"
LEDGER: list[tuple[str, str]] = []


def _log(label: str, status: str) -> None:
    LEDGER.append((label, status))
    print(f"  [{status:22}] {label}")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(
            f"Usage: python3 {pathlib.Path(__file__).name} <project_root>"
        )
    root = pathlib.Path(sys.argv[1]).resolve()
    print(f"Applying {MARKER} to {root}\n")

    # ── 1. karaoke.dart signature default ──────────────────────────────
    p = root / "lib/services/karaoke.dart"
    if not p.exists():
        _log("karaoke.dart", "MISSING (file absent)")
    else:
        text = p.read_text(encoding="utf-8")
        broken = "{int maxWordsPerChunk = maxWordsPerChunk}"
        fixed = "{int maxWordsPerChunk = kKaraokeMaxWordsPerChunk}"
        if fixed in text and broken not in text:
            _log("karaoke.dart: default = kKaraokeMaxWordsPerChunk", "SKIP (already fixed)")
        elif broken in text:
            text = text.replace(broken, fixed, 1)
            p.write_text(text, encoding="utf-8")
            _log("karaoke.dart: default = kKaraokeMaxWordsPerChunk", "OK")
        else:
            # tolerant of whitespace
            import re
            pat = re.compile(
                r"\{\s*int\s+maxWordsPerChunk\s*=\s*maxWordsPerChunk\s*\}"
            )
            if pat.search(text):
                text = pat.sub(
                    "{int maxWordsPerChunk = kKaraokeMaxWordsPerChunk}",
                    text,
                    count=1,
                )
                p.write_text(text, encoding="utf-8")
                _log("karaoke.dart: default = kKaraokeMaxWordsPerChunk", "OK")
            else:
                _log(
                    "karaoke.dart: default = kKaraokeMaxWordsPerChunk",
                    "MISSING (broken form not found)",
                )

    # ── 2. app_info.dart build number ──────────────────────────────────
    p = root / "lib/app_info.dart"
    if not p.exists():
        _log("app_info.dart: kAppBuildNumber", "MISSING (file absent)")
    else:
        text = p.read_text(encoding="utf-8")
        if "kAppBuildNumber = 7" in text or "kAppBuildNumber=7" in text:
            _log("app_info.dart: kAppBuildNumber = 7", "SKIP (already 7)")
        elif "kAppBuildNumber = 6" in text:
            text = text.replace("kAppBuildNumber = 6", "kAppBuildNumber = 7", 1)
            p.write_text(text, encoding="utf-8")
            _log("app_info.dart: kAppBuildNumber = 7", "OK")
        else:
            import re
            m = re.search(r"kAppBuildNumber\s*=\s*(\d+)", text)
            if m and m.group(1) != "7":
                text = text[: m.start()] + "kAppBuildNumber = 7" + text[m.end() :]
                p.write_text(text, encoding="utf-8")
                _log(f"app_info.dart: kAppBuildNumber {m.group(1)} → 7", "OK")
            else:
                _log("app_info.dart: kAppBuildNumber", "MISSING (no match)")

    print("\n==================================")
    print(f"=== {MARKER} ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================")
    print(
        """
Next:
  dart format lib
  flutter analyze
  flutter test test/karaoke_test.dart test/app_info_test.dart
  git add lib/services/karaoke.dart lib/app_info.dart
  git commit -m "S157b: restore kKaraokeMaxWordsPerChunk default + build number 7"
  git push
"""
    )


if __name__ == "__main__":
    main()
