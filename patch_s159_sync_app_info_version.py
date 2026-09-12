#!/usr/bin/env python3
"""
patch_s159_sync_app_info_version.py
=============================================

BUG: patch_s158_partial_translation_slice.py bumped pubspec.yaml's
`version:` to 1.7.1+8 but never touched lib/app_info.dart's
kAppVersion/kAppBuildNumber constants (its own header comment says to
bump both together, but the script itself only edited PUBSPEC). They
were left at 1.7.0/7, so test/app_info_test.dart's
"kAppVersion and kAppBuildNumber match pubspec.yaml" check fails --
that's the ❌ in the CI output.

FIX: bump app_info.dart's constants to match pubspec.yaml's actual
1.7.1+8. Marker-gated, idempotent, safe to re-run.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

APP_INFO = "lib/app_info.dart"
OLD_VERSION, NEW_VERSION = "1.7.0", "1.7.1"
OLD_BUILD, NEW_BUILD = 7, 8


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


def edit(rel, old, new, label):
    p = ROOT / rel
    if not p.exists():
        _log(label, "SKIPPED-NOT-FOUND")
        return False
    text = p.read_text(encoding="utf-8")
    if old not in text:
        if new in text:
            _log(label, "SKIPPED-ALREADY")
        else:
            _log(label, "SKIPPED-NOT-FOUND")
        return False
    text = text.replace(old, new, 1)
    p.write_text(text, encoding="utf-8")
    _log(label, "OK")
    return True


def main():
    print("=" * 70)
    print(f"S159 — sync app_info.dart to pubspec's {NEW_VERSION}+{NEW_BUILD}")
    print("=" * 70)

    edit(APP_INFO,
         f"const String kAppVersion = '{OLD_VERSION}';",
         f"const String kAppVersion = '{NEW_VERSION}';",
         f"app_info.dart: kAppVersion {OLD_VERSION} -> {NEW_VERSION}")

    edit(APP_INFO,
         f"const int kAppBuildNumber = {OLD_BUILD};",
         f"const int kAppBuildNumber = {NEW_BUILD};",
         f"app_info.dart: kAppBuildNumber {OLD_BUILD} -> {NEW_BUILD}")

    print()
    print("=" * 70)
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok} fix(es) applied.")
    print("=" * 70)
    print("""
Next:
  1. flutter test test/app_info_test.dart   (should be green now)
  2. git add -A && git commit -m "S159: sync app_info.dart version with pubspec (1.7.1+8)"
  3. git push
""")


if __name__ == "__main__":
    main()
