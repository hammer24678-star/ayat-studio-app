#!/usr/bin/env python3
"""
patch_s69b_hardcode_pollinations_key.py

Sets a default value for `pollinationsApiKey` in studio_state.dart so the
Settings field S69 added is pre-filled on first run instead of starting
empty -- no more pasting it in by hand.

SECURITY NOTE (stating this once, plainly, then doing what was asked):
this bakes a live secret key into a file that gets committed to git --
it will sit in your repo's commit history permanently (recoverable even
if you later remove it in a new commit), visible to anyone with read
access to the repo now or in the future, and also visible in plain text
to anyone who decompiles the built APK (same as if it were typed into
the Settings field, just also now in git history on top of that). If
this repo is ever made public, forked, or a CI log echoes the file, the
key goes with it. You said that's acceptable for this key -- proceeding
on that basis. If you ever want this reversed later, rotate/revoke this
key on the Pollinations dashboard and generate a fresh one; the old
value will still exist in old commits even after this file is edited
again.

WHAT THIS PATCH DOES:
  lib/models/studio_state.dart
    - `String pollinationsApiKey = '';` -> defaults to the given key
    - the Settings field (added by S69) still shows/edits this value and
      persists overrides via SharedPreferences as before; this only
      changes what a fresh install starts with before any override

Usage:
  python3 patch_s69b_hardcode_pollinations_key.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S69B_HARDCODE_POLLINATIONS_KEY"
API_KEY = "sk_7WOpFiSmdUD4TtS2Zk07bBLfoxYeVaTr"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S69b was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_studio_state(project_dir):
    target = project_dir / "lib" / "models" / "studio_state.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False
    if "pollinationsApiKey" not in text:
        die(f"{target} has no pollinationsApiKey field -- run patch_s69_ai_art_fix.py first.")

    old = (
        "  // Free pk_ key from https://enter.pollinations.ai -- current\n"
        "  // Pollinations API requires this even for free-tier image gen.\n"
        "  String pollinationsApiKey = '';\n"
    )
    new = (
        f"  // {MARKER}: hardcoded default so a fresh install doesn't start\n"
        "  // with an empty key -- see this patch's module docstring for the\n"
        "  // security tradeoff this accepts (committed to git history + baked\n"
        "  // into the compiled APK). Still overridable via Settings, which\n"
        "  // persists any change through SharedPreferences as before.\n"
        f"  String pollinationsApiKey = '{API_KEY}';\n"
    )
    text = replace_once(text, old, new, "studio_state pollinationsApiKey default")

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    changed = patch_studio_state(project_dir)
    print(f"{'OK: patched' if changed else 'SKIP: already applied'} lib/models/studio_state.dart")

    print()
    print("Next steps:")
    print("  git add lib/models/studio_state.dart")
    print("  git commit -m 'S69b: default Pollinations API key'")
    print("  git push")
    print()
    print("HOW TO VERIFY: fresh install (or clear app data) -> خلفيات tab -> enable")
    print("AI art -- the 'مفتاح Pollinations' field should already show the key, and")
    print("art generation should work without typing anything in.")


if __name__ == "__main__":
    main()
