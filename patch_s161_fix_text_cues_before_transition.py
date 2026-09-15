#!/usr/bin/env python3
"""
patch_s161_fix_text_cues_before_transition.py
=============================================

BUG (reported): "it works until I turn off تظليل الكلمات (word
highlighting/karaoke) — it does the same bug [as before S160]." Typing
ayah-part-1 with a 1-13s window, committing it, then typing ayah-part-2
with a 13-17s window and committing it: the second text never shows,
exactly like the original S160 report.

ROOT CAUSE (the karaoke toggle was a red herring -- NOTE this clearly so
nobody chases it again): export_service.dart's overlay-selection
if/else-if chain has THREE branches gated on `state.hasAyah`:

    1. hasVideo && timelineActive && timeline.isNotEmpty  -> karaoke seq
    2. hasAyah && hasTextTransition                        -> ONE animated
       block of `state.ayahText` for the whole clip (PATCH_S126)
    3. hasAyah                                             -> the
       textTimeCues-aware multi-window branch S160 added

Branch 2 sits BEFORE branch 3, and `hasTextTransition` is:

    bool get hasTextTransition =>
        textInTransition != TextTransition.none ||
        textOutTransition != TextTransition.none;

`textInTransition` defaults to `TextTransition.riseFade` and
`textOutTransition` defaults to `TextTransition.fade` -- NEITHER is
`none` out of the box. So `hasTextTransition` is TRUE by default, which
means branch 2 wins by default on every export, and branch 2 has never
once looked at `state.textTimeCues` -- it renders `state.ayahText` for
the whole clip's duration and nothing else. Every text cue you commit
gets silently thrown away as long as text transitions are left on
(their default state). This is a branch-ordering bug, not anything to
do with karaokeEnabled, which none of these three branches or their
conditions reference at all -- karaokeEnabled only ever affects
per-word lighting inside branch 1 (see PATCH_S51). Whatever correlation
was observed with the karaoke toggle was incidental to how that export
happened to be set up, not a causal link in the code.

FIX: check "does this export have any committed-or-in-progress timed
cue" BEFORE checking `hasTextTransition`, so a timed cue always gets
its own window regardless of the transition settings. The plain
single-block/no-cues path (old branch 2, still used for the common
"just one ayah, no manual timing" case) and the old branch-3 PNG
rendering are otherwise untouched -- this is purely a reordering plus
dropping the now-dead "cues.isEmpty" fork from the old branch 3, since
that fork is only ever reached with genuinely empty cues now.

Marker-gated, idempotent, safe to re-run.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

EXPORT_SERVICE = "lib/services/export_service.dart"
PUBSPEC = "pubspec.yaml"
APP_INFO = "lib/app_info.dart"

MARKER = "PATCH_S161_TEXT_CUES_BEFORE_TRANSITION"

OLD_VERSION, NEW_VERSION = "1.7.2", "1.7.3"
OLD_BUILD, NEW_BUILD = 9, 10


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


def replace_once(path, old, new, label):
    p = ROOT / path
    if not p.exists():
        _log(label, "SKIPPED-NOT-FOUND")
        return False
    text = p.read_text(encoding="utf-8")
    if MARKER in text:
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
# export_service.dart -- reorder the branch chain so a committed/
# in-progress text cue always wins over the default-on transition branch
# ---------------------------------------------------------------------

_OLD = """      if (state.hasVideo && state.timelineActive && state.timeline.isNotEmpty) {
        final seqDir = Directory('${work.path}/seq')..createSync();
        await _renderKaraokeSequence(
          dir: seqDir.path,
          state: state,
          style: style,
          w: w,
          h: h,
          clipStart: clipStart,
          duration: duration,
          onStatus: onStatus,
        );
        overlaySeqPattern = '${seqDir.path}/ov_%05d.png';
      } else if (state.hasAyah && state.hasTextTransition) {
        // PATCH_S126_TEXT_TRANSITIONS: a single-ayah export used to be one
        // still PNG with an ffmpeg alpha fade bolted on — which can do a fade
        // and nothing else. Rendering it as a sequence too means one ayah
        // gets exactly the same transitions, and the same smoothness, as a
        // synced one. Frames outside the entrance and exit are identical, so
        // the dedupe+hard-link path below makes this nearly free.
        onStatus?.call('جارٍ رسم ظهور النص…');
        final seqDir = Directory('${work.path}/ov')..createSync();
        await _renderTextSequence(
          dir: seqDir.path,
          state: state,
          style: style,
          w: w,
          h: h,
          clipStart: clipStart,
          duration: duration,
          onStatus: onStatus,
        );
        overlaySeqPattern = '${seqDir.path}/ov_%05d.png';
      } else if (state.hasAyah) {
        // PATCH_S160_MULTI_TEXT_TIME_CUES: state.textTimeCues (plus whatever's still sitting in
        // the single-shot override fields, for anyone who only ever wants
        // one timed text) -- render each one as its own PNG instead of
        // collapsing them all into the single `state.ayahText` that used
        // to be the only thing this branch ever knew how to bake.
        final cues = <TextTimeCue>[
          ...state.textTimeCues,
          if (state.textTimeStartOverride != null &&
              state.textTimeEndOverride != null)
            TextTimeCue(
              text: state.ayahText,
              translation: state.translationText,
              start: state.textTimeStartOverride!,
              end: state.textTimeEndOverride!,
            ),
        ];
        if (cues.isEmpty) {
          overlayPng = '${work.path}/overlay.png';
          await File(overlayPng)
              .writeAsBytes(await OverlayRenderer.renderTextOverlayPng(
            w: w,
            h: h,
            text: state.ayahText,
            translation: state.translationText,
            style: style,
          ));
        } else {
          final rendered = <({String path, double start, double end})>[];
          for (var i = 0; i < cues.length; i++) {
            final cue = cues[i];
            final png = '${work.path}/overlay_$i.png';
            await File(png).writeAsBytes(
                await OverlayRenderer.renderTextOverlayPng(
              w: w,
              h: h,
              text: cue.text,
              translation: cue.translation,
              style: style,
            ));
            rendered.add((path: png, start: cue.start, end: cue.end));
          }
          overlayPngCues = rendered;
        }
      }"""

_NEW = f"""      if (state.hasVideo && state.timelineActive && state.timeline.isNotEmpty) {{
        final seqDir = Directory('${{work.path}}/seq')..createSync();
        await _renderKaraokeSequence(
          dir: seqDir.path,
          state: state,
          style: style,
          w: w,
          h: h,
          clipStart: clipStart,
          duration: duration,
          onStatus: onStatus,
        );
        overlaySeqPattern = '${{seqDir.path}}/ov_%05d.png';
      }} else if (state.hasAyah &&
          (state.textTimeCues.isNotEmpty ||
              (state.textTimeStartOverride != null &&
                  state.textTimeEndOverride != null))) {{
        // {MARKER}: this branch used to sit AFTER the `hasTextTransition`
        // branch below, so whenever text transitions were on (the
        // DEFAULT -- textInTransition defaults to riseFade,
        // textOutTransition to fade, neither is `none`) that branch
        // always won first and rendered nothing but `state.ayahText` for
        // the whole clip, discarding every committed textTimeCue
        // outright. That's the "second typed text never shows" report
        // coming back -- it never actually depended on the karaoke
        // toggle (karaokeEnabled isn't referenced by any of these branch
        // conditions; it only ever affects per-word lighting inside the
        // karaoke-sequence branch above). Checking for a committed (or
        // still-being-typed) cue FIRST means it always gets its own
        // window, regardless of the transition settings.
        final cues = <TextTimeCue>[
          ...state.textTimeCues,
          if (state.textTimeStartOverride != null &&
              state.textTimeEndOverride != null)
            TextTimeCue(
              text: state.ayahText,
              translation: state.translationText,
              start: state.textTimeStartOverride!,
              end: state.textTimeEndOverride!,
            ),
        ];
        final rendered = <({{String path, double start, double end}})>[];
        for (var i = 0; i < cues.length; i++) {{
          final cue = cues[i];
          final png = '${{work.path}}/overlay_$i.png';
          await File(png).writeAsBytes(
              await OverlayRenderer.renderTextOverlayPng(
            w: w,
            h: h,
            text: cue.text,
            translation: cue.translation,
            style: style,
          ));
          rendered.add((path: png, start: cue.start, end: cue.end));
        }}
        overlayPngCues = rendered;
      }} else if (state.hasAyah && state.hasTextTransition) {{
        // PATCH_S126_TEXT_TRANSITIONS: a single-ayah export used to be one
        // still PNG with an ffmpeg alpha fade bolted on — which can do a fade
        // and nothing else. Rendering it as a sequence too means one ayah
        // gets exactly the same transitions, and the same smoothness, as a
        // synced one. Frames outside the entrance and exit are identical, so
        // the dedupe+hard-link path below makes this nearly free.
        // ({MARKER}: only reached now when there are NO timed cues --
        // this is still the right choice for the plain "one ayah, no
        // manual timing" case, which is most exports.)
        onStatus?.call('جارٍ رسم ظهور النص…');
        final seqDir = Directory('${{work.path}}/ov')..createSync();
        await _renderTextSequence(
          dir: seqDir.path,
          state: state,
          style: style,
          w: w,
          h: h,
          clipStart: clipStart,
          duration: duration,
          onStatus: onStatus,
        );
        overlaySeqPattern = '${{seqDir.path}}/ov_%05d.png';
      }} else if (state.hasAyah) {{
        // {MARKER}: reached only when there are no committed/in-progress
        // timed cues AND text transitions are off -- always a single
        // static overlay for the whole clip. (Old branch-3's now-dead
        // "cues.isEmpty" fork folded in here, since cues is guaranteed
        // empty by this point.)
        overlayPng = '${{work.path}}/overlay.png';
        await File(overlayPng)
            .writeAsBytes(await OverlayRenderer.renderTextOverlayPng(
          w: w,
          h: h,
          text: state.ayahText,
          translation: state.translationText,
          style: style,
        ));
      }}"""

replace_once(EXPORT_SERVICE, _OLD, _NEW,
             "export_service.dart: check for timed text cues before the transition branch")

# ---------------------------------------------------------------------
# version bump -- pubspec.yaml + lib/app_info.dart, together
# (PATCH_S158/S159 lesson: bump both in the same script or they drift)
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


bump_version(PUBSPEC,
             f"version: {OLD_VERSION}+{OLD_BUILD}",
             f"version: {NEW_VERSION}+{NEW_BUILD}",
             f"pubspec.yaml: version {OLD_VERSION}+{OLD_BUILD} -> {NEW_VERSION}+{NEW_BUILD}")

bump_version(APP_INFO,
             f"const String kAppVersion = '{OLD_VERSION}';",
             f"const String kAppVersion = '{NEW_VERSION}';",
             f"app_info.dart: kAppVersion {OLD_VERSION} -> {NEW_VERSION}")

bump_version(APP_INFO,
             f"const int kAppBuildNumber = {OLD_BUILD};",
             f"const int kAppBuildNumber = {NEW_BUILD};",
             f"app_info.dart: kAppBuildNumber {OLD_BUILD} -> {NEW_BUILD}")


def main():
    print("=" * 70)
    print("S161 — timed text cues no longer discarded when transitions are on")
    print("=" * 70)
    print()
    print("=" * 70)
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok} fix(es) applied.")
    print("=" * 70)
    if any(s.startswith("SKIPPED-ANCHOR") for _, s in LEDGER):
        print("""
Anchor didn't match -- most likely export_service.dart's branch chain
has shifted since this dump. Open it and manually move the
`state.hasAyah` branch that builds `cues`/`overlayPngCues` so it is
checked BEFORE `else if (state.hasAyah && state.hasTextTransition)`,
using a condition like:
    state.textTimeCues.isNotEmpty ||
    (state.textTimeStartOverride != null && state.textTimeEndOverride != null)
""")
    else:
        print("""
Next:
  1. flutter analyze
  2. flutter test
  3. Manual test — the actual repro:
       a. Pick an ayah, LEAVE text transitions at their defaults (don't
          touch textInTransition/textOutTransition).
       b. Set 1s-13s, tap the "+" (playlist_add) button -- confirm it's
          added to the list below.
       c. Set 13s-17s, tap "+" again.
       d. Export. Confirm ayah-part-1 shows 1-13s AND ayah-part-2 shows
          13-17s, regardless of whether كاريوكي/تظليل الكلمات is on or off
          (that toggle only matters for hasVideo+timeline auto-sync
          exports and should have no bearing on this at all now).
  4. git add -A && git commit -m "S161: fix textTimeCues being discarded whenever text transitions are on (branch-order bug, unrelated to karaoke toggle)"
  5. git push
""")


if __name__ == "__main__":
    main()
