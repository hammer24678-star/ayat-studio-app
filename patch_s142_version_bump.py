# patch_s142_version_bump.py
#
# Bumps the app's code/build version from 1.2.0+3 to 1.2.0+4.
#
# Per the repo's own convention (see PATCH_S123_APP_INFO note in
# lib/app_info.dart, and the checklist in the project notes):
# pubspec.yaml's `version: x.y.z+n` is the single source of truth,
# and lib/app_info.dart's kAppVersion/kAppBuildNumber are kept beside
# it by hand rather than pulled in via package_info_plus. Both must
# be bumped together or test/app_info_test.dart's drift check fails.
#
# This patch bumps only the build number (+3 -> +4); the semantic
# version (1.2.0) is unchanged. If a version-string bump is wanted
# instead, edit VERSION_NAME below and re-run.
#
# Run from the project root.

from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

VERSION_NAME = "1.2.0"
OLD_BUILD = 3
NEW_BUILD = 4


def _log(label, status):
    LEDGER.append((label, status))


def apply_literal(rel_path, old, new, label, skip_if=None):
    p = ROOT / rel_path
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel_path} not found under {ROOT}")
    text = p.read_text(encoding="utf-8")
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


PUBSPEC = "pubspec.yaml"
APP_INFO = "lib/app_info.dart"


def bump_pubspec():
    apply_literal(
        PUBSPEC,
        f"version: {VERSION_NAME}+{OLD_BUILD}\n",
        f"version: {VERSION_NAME}+{NEW_BUILD}\n",
        f"pubspec.yaml: version {VERSION_NAME}+{OLD_BUILD} -> {VERSION_NAME}+{NEW_BUILD}",
        skip_if=f"version: {VERSION_NAME}+{NEW_BUILD}\n",
    )


def bump_app_info():
    apply_literal(
        APP_INFO,
        f"const int kAppBuildNumber = {OLD_BUILD};\n",
        f"const int kAppBuildNumber = {NEW_BUILD};\n",
        f"app_info.dart: kAppBuildNumber {OLD_BUILD} -> {NEW_BUILD}",
        skip_if=f"const int kAppBuildNumber = {NEW_BUILD};\n",
    )


def main():
    bump_pubspec()
    bump_app_info()

    print("\n=== S142 gauntlet loop ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================\n")


if __name__ == "__main__":
    main()
