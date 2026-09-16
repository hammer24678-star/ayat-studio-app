#!/usr/bin/env python3
"""
patch_s162_cue_gate_and_undo_fix.py
====================================

Two independent, verified bugs from the S161 gauntlet-loop scan. Both
anchors below were checked with `view`/`grep` against the real repo
(post-S161) before being written into this script.

BUG A -- committed text-time-cues silently dropped from export
----------------------------------------------------------------
lib/services/export_service.dart: the branch that renders textTimeCues is
gated `state.hasAyah && (state.textTimeCues.isNotEmpty || ...)`. A
committed TextTimeCue already carries its own text/translation snapshot
(commitTextTimeCue() copies ayahText/translationText into it at commit
time) -- it does not need a live, non-empty state.ayahText to render.
Clearing the typed-text field after committing one or more cues (a normal
"done, type the next one" motion) makes hasAyah false, which skips this
branch AND both branches after it (they all require hasAyah too), so the
export ships with NO text overlay at all despite valid cues sitting in
state.textTimeCues. Same failure family as the S160/S161 "second text
never shows" report, just gated on a different field. Fix: only the
still-being-typed override half of the condition needs hasAyah (it reads
ayahText/translationText live); textTimeCues.isNotEmpty stands alone.

BUG B -- undo/redo blind to an entire generation of text features
--------------------------------------------------------------------
lib/models/studio_state.dart: _capture()/_apply() (the undo/redo snapshot)
never picked up textTimeCues, textTimeStartOverride/EndOverride,
textLayers, wordColors, activeWordColor, captionText, captionPosition,
textInTransition/textOutTransition when S129/S143/S145/S160 added them --
unlike same-vintage watermark (S123) and music-bed (S127) fields, which
did get added. Concretely: remove a committed cue and hit Undo -- it does
not come back (the snapshot has no textTimeCues key, so _apply() never
touches the field). Separately, addTextLayer/updateTextLayerAt/
removeTextLayerAt are called directly (never wrapped in state.update())
and never call pushHistory() themselves, so adding/editing/removing a
free text layer is invisible to undo/redo, not merely unrestorable. Fix:
add the missing fields to _capture()/_apply() (lists/maps copied by
value, same reasoning as the existing `timeline` entry -- capturing the
live reference would let later mutations bleed into the "old" snapshot),
and add pushHistory() to the three text-layer mutators.
(translationFontSize/Color/Opacity/OffsetY were checked too -- they are
only ever set from persisted app settings in settings_service.dart, never
from an in-editor undo-relevant control, so they're intentionally left
out of this fix.)

NOTE ON IDEMPOTENCY: S161's replace_once() checked a single global
MARKER string against the whole file before applying each edit. That's
fine when every edit lands in a different file (as in S161), but this
patch makes five edits to the SAME file (studio_state.dart) -- with a
global marker, edit #2 would see the marker edit #1 just wrote and skip
itself even though its own anchor was never touched. So replace_once()
here checks "is `new` already in the file" per edit instead of a shared
marker -- self-contained, still idempotent, no cross-edit false skips.

Marker-gated (per-edit), idempotent, safe to re-run.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

EXPORT_SERVICE = "lib/services/export_service.dart"
STUDIO_STATE = "lib/models/studio_state.dart"
PUBSPEC = "pubspec.yaml"
APP_INFO = "lib/app_info.dart"

OLD_VERSION, NEW_VERSION = "1.7.3", "1.7.4"
OLD_BUILD, NEW_BUILD = 10, 11


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


def replace_once(path, old, new, label):
    p = ROOT / path
    if not p.exists():
        _log(label, "SKIPPED-NOT-FOUND")
        return False
    text = p.read_text(encoding="utf-8")
    if new in text:
        _log(label, "SKIPPED-ALREADY")
        return False
    count = text.count(old)
    if count == 0:
        _log(label, "SKIPPED-ANCHOR-NOT-FOUND")
        return False
    if count > 1:
        _log(label, f"SKIPPED-ANCHOR-AMBIGUOUS({count})")
        return False
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "OK")
    return True


# ---------------------------------------------------------------------
# BUG A -- export_service.dart: don't gate committed cues on hasAyah
# ---------------------------------------------------------------------

replace_once(
    EXPORT_SERVICE,
    "      } else if (state.hasAyah &&\n"
    "          (state.textTimeCues.isNotEmpty ||\n"
    "              (state.textTimeStartOverride != null &&\n"
    "                  state.textTimeEndOverride != null))) {",
    "      } else if (state.textTimeCues.isNotEmpty ||\n"
    "          (state.hasAyah &&\n"
    "              state.textTimeStartOverride != null &&\n"
    "              state.textTimeEndOverride != null)) {\n"
    "        // PATCH_S162_CUE_GATE_AND_UNDO_FIX: a committed TextTimeCue already\n"
    "        // carries its own text/translation snapshot (commitTextTimeCue()\n"
    "        // copies state.ayahText/translationText into it at commit time), so\n"
    "        // it doesn't need a live, non-empty state.ayahText to render. The\n"
    "        // previous `state.hasAyah && (...)` gate put hasAyah in front of\n"
    "        // BOTH halves of the condition -- clearing the typed-text field\n"
    "        // after committing one or more cues (a normal \"done, type the next\n"
    "        // one\" motion) made hasAyah false and every branch below fall\n"
    "        // through with nothing rendered, silently dropping every committed\n"
    "        // cue from the export. Only the still-being-typed override half\n"
    "        // genuinely needs hasAyah, since it reads ayahText/translationText\n"
    "        // live rather than from a snapshot.",
    "export_service.dart: stop gating committed textTimeCues on hasAyah",
)

# ---------------------------------------------------------------------
# BUG B -- studio_state.dart: undo/redo snapshot + text-layer history
# ---------------------------------------------------------------------

replace_once(
    STUDIO_STATE,
    "        'musicBedPath': musicBedPath,\n"
    "        'musicBedVolume': musicBedVolume,\n"
    "        'musicBedFade': musicBedFade,\n"
    "      };",
    "        'musicBedPath': musicBedPath,\n"
    "        'musicBedVolume': musicBedVolume,\n"
    "        'musicBedFade': musicBedFade,\n"
    "        // PATCH_S162_CUE_GATE_AND_UNDO_FIX: these were never added when\n"
    "        // each feature landed (S129/S143/S145/S160), unlike same-vintage\n"
    "        // watermark/music-bed fields just above -- removing a committed\n"
    "        // text-time-cue and hitting Undo did not bring it back, and\n"
    "        // editing a caption/word-color/transition choice was not\n"
    "        // undoable at all. Lists/maps are copied by value here, same\n"
    "        // reasoning as the `timeline` entry above: capturing the live\n"
    "        // List/Map reference would let later mutations bleed into this\n"
    "        // \"old\" snapshot and undo would silently do nothing.\n"
    "        'textTimeCues': [\n"
    "          for (final c in textTimeCues)\n"
    "            TextTimeCue(\n"
    "                text: c.text,\n"
    "                translation: c.translation,\n"
    "                start: c.start,\n"
    "                end: c.end),\n"
    "        ],\n"
    "        'textTimeStartOverride': textTimeStartOverride,\n"
    "        'textTimeEndOverride': textTimeEndOverride,\n"
    "        'textLayers': [\n"
    "          for (final l in textLayers)\n"
    "            TextLayer(\n"
    "                text: l.text,\n"
    "                position: l.position,\n"
    "                fontSize: l.fontSize,\n"
    "                color: l.color),\n"
    "        ],\n"
    "        'wordColors': Map<int, Color>.from(wordColors),\n"
    "        'activeWordColor': activeWordColor,\n"
    "        'captionText': captionText,\n"
    "        'captionPosition': captionPosition,\n"
    "        'textInTransition': textInTransition,\n"
    "        'textOutTransition': textOutTransition,\n"
    "      };",
    "studio_state.dart: capture textTimeCues/textLayers/captions/wordColors/transitions in undo snapshot",
)

replace_once(
    STUDIO_STATE,
    "    musicBedPath = s['musicBedPath'] as String?;\n"
    "    musicBedVolume = s['musicBedVolume'] as double;\n"
    "    musicBedFade = s['musicBedFade'] as bool;\n"
    "  }",
    "    musicBedPath = s['musicBedPath'] as String?;\n"
    "    musicBedVolume = s['musicBedVolume'] as double;\n"
    "    musicBedFade = s['musicBedFade'] as bool;\n"
    "    // PATCH_S162_CUE_GATE_AND_UNDO_FIX: restore the fields captured above.\n"
    "    textTimeCues = (s['textTimeCues'] as List).cast<TextTimeCue>();\n"
    "    textTimeStartOverride = s['textTimeStartOverride'] as double?;\n"
    "    textTimeEndOverride = s['textTimeEndOverride'] as double?;\n"
    "    textLayers = (s['textLayers'] as List).cast<TextLayer>();\n"
    "    wordColors = (s['wordColors'] as Map).cast<int, Color>();\n"
    "    activeWordColor = s['activeWordColor'] as Color;\n"
    "    captionText = s['captionText'] as String;\n"
    "    captionPosition = s['captionPosition'] as CaptionPosition;\n"
    "    textInTransition = s['textInTransition'] as TextTransition;\n"
    "    textOutTransition = s['textOutTransition'] as TextTransition;\n"
    "  }",
    "studio_state.dart: restore the newly-captured fields in _apply()",
)

replace_once(
    STUDIO_STATE,
    "  void addTextLayer(TextLayer layer) {\n"
    "    textLayers = [...textLayers, layer];\n"
    "    notifyListeners();\n"
    "  }",
    "  void addTextLayer(TextLayer layer) {\n"
    "    // PATCH_S162_CUE_GATE_AND_UNDO_FIX: called directly (never wrapped in\n"
    "    // state.update()) everywhere in the UI, and this method never pushed\n"
    "    // its own history entry -- adding a text layer was invisible to\n"
    "    // undo/redo, not merely unrestorable. Paired with the textLayers\n"
    "    // entry added to _capture()/_apply() above.\n"
    "    pushHistory();\n"
    "    textLayers = [...textLayers, layer];\n"
    "    notifyListeners();\n"
    "  }",
    "studio_state.dart: addTextLayer() now pushes undo history",
)

replace_once(
    STUDIO_STATE,
    "  void updateTextLayerAt(int index, TextLayer layer) {\n"
    "    if (index < 0 || index >= textLayers.length) return;\n"
    "    final next = [...textLayers];\n"
    "    next[index] = layer;\n"
    "    textLayers = next;\n"
    "    notifyListeners();\n"
    "  }",
    "  void updateTextLayerAt(int index, TextLayer layer) {\n"
    "    if (index < 0 || index >= textLayers.length) return;\n"
    "    // PATCH_S162_CUE_GATE_AND_UNDO_FIX: see addTextLayer() above.\n"
    "    pushHistory();\n"
    "    final next = [...textLayers];\n"
    "    next[index] = layer;\n"
    "    textLayers = next;\n"
    "    notifyListeners();\n"
    "  }",
    "studio_state.dart: updateTextLayerAt() now pushes undo history",
)

replace_once(
    STUDIO_STATE,
    "  void removeTextLayerAt(int index) {\n"
    "    if (index < 0 || index >= textLayers.length) return;\n"
    "    final next = [...textLayers]..removeAt(index);\n"
    "    textLayers = next;\n"
    "    notifyListeners();\n"
    "  }",
    "  void removeTextLayerAt(int index) {\n"
    "    if (index < 0 || index >= textLayers.length) return;\n"
    "    // PATCH_S162_CUE_GATE_AND_UNDO_FIX: see addTextLayer() above.\n"
    "    pushHistory();\n"
    "    final next = [...textLayers]..removeAt(index);\n"
    "    textLayers = next;\n"
    "    notifyListeners();\n"
    "  }",
    "studio_state.dart: removeTextLayerAt() now pushes undo history",
)

# ---------------------------------------------------------------------
# version bump -- pubspec.yaml + lib/app_info.dart, together
# (S158/S159 lesson: bump both in the same script or they drift)
# ---------------------------------------------------------------------


def bump_version(path, old, new, label):
    p = ROOT / path
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
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "OK")
    return True


bump_version(
    PUBSPEC,
    f"version: {OLD_VERSION}+{OLD_BUILD}",
    f"version: {NEW_VERSION}+{NEW_BUILD}",
    f"pubspec.yaml: version {OLD_VERSION}+{OLD_BUILD} -> {NEW_VERSION}+{NEW_BUILD}",
)

bump_version(
    APP_INFO,
    f"const String kAppVersion = '{OLD_VERSION}';",
    f"const String kAppVersion = '{NEW_VERSION}';",
    f"app_info.dart: kAppVersion {OLD_VERSION} -> {NEW_VERSION}",
)

bump_version(
    APP_INFO,
    f"const int kAppBuildNumber = {OLD_BUILD};",
    f"const int kAppBuildNumber = {NEW_BUILD};",
    f"app_info.dart: kAppBuildNumber {OLD_BUILD} -> {NEW_BUILD}",
)


def main():
    print("=" * 70)
    print("S162 -- export no longer drops committed cues on empty ayahText;")
    print("        undo/redo now covers cues/layers/captions/wordColors/transitions")
    print("=" * 70)
    print()
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok} fix(es) applied.")
    print("=" * 70)
    if any(s.startswith("SKIPPED-ANCHOR") for _, s in LEDGER):
        print(
            """
An anchor didn't match -- most likely one of the two target files has
shifted since this dump. Check the failed label above against the
current source before hand-applying; don't assume the others still
apply cleanly if one anchor moved.
"""
        )
    else:
        print(
            """
Next:
  1. flutter analyze
  2. flutter test
  3. Manual test -- BUG A repro:
       a. Pick an ayah, set 1s-13s, tap "+" to commit a cue.
       b. Clear the typed-text field (don't type a replacement).
       c. Export. Confirm the committed cue still shows at 1-13s instead
          of the export having no text overlay at all.
  4. Manual test -- BUG B repro:
       a. Add a free text layer (S143 "unified text" card). Hit Undo.
          Confirm the layer disappears (previously: nothing happened).
       b. Commit a text-time-cue, then remove it. Hit Undo. Confirm the
          cue comes back (previously: stayed removed).
       c. Tap a word to color it, then Undo. Confirm the color reverts.
  5. git add -A && git commit -m "S162: stop dropping committed text-cues when ayahText is empty; cover cues/layers/captions/wordColors/transitions in undo-redo"
  6. git push
"""
        )


if __name__ == "__main__":
    main()
