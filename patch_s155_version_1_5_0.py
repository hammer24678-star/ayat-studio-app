# patch_s155_version_1_5_0.py
#
# Quick version bump: 1.2.0+4 -> 1.5.0+5
#
# Two places carry the version (per PATCH_S123's own note, and enforced by
# test/app_info_test.dart):
#   - pubspec.yaml        `version: x.y.z+n`   (what Play Console sees)
#   - lib/app_info.dart   kAppVersion / kAppBuildNumber (in-app Settings screen)
#
# Build number is bumped +1 (4 -> 5) since Play Console rejects a reused or
# non-increasing versionCode.
#
# Run from the project root.

from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []


def _log(label, status):
    LEDGER.append((label, status))


def apply_literal(rel_path, old, new, label, skip_if=None):
    p = ROOT / rel_path
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel_path} not found under {ROOT}")
    text = p.read_text(encoding="utf-8")
    if skip_if is not None and old not in text and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


PUBSPEC = 'pubspec.yaml'
APP_INFO = 'lib/app_info.dart'


def patch_pubspec():
    apply_literal(
        PUBSPEC,
        "version: 1.2.0+4",
        "version: 1.5.0+5",
        'pubspec.yaml: bump version to 1.5.0+5 (S155)',
        skip_if="version: 1.5.0+5",
    )


def patch_app_info():
    apply_literal(
        APP_INFO,
        "const String kAppVersion = '1.2.0';\nconst int kAppBuildNumber = 4;",
        "const String kAppVersion = '1.5.0';\nconst int kAppBuildNumber = 5;",
        'lib/app_info.dart: bump kAppVersion/kAppBuildNumber to 1.5.0/5 (S155)',
        skip_if="kAppVersion = '1.5.0'",
    )


def main():
    patch_pubspec()
    patch_app_info()

    print("\n=== S155 version-1.5.0 ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================\n")


if __name__ == "__main__":
    main()
