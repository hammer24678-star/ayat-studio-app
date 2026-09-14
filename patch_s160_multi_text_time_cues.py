#!/usr/bin/env python3
"""
patch_s160_multi_text_time_cues.py
=============================================

BUG (reported): typing ayah-part-1 with a manual "starts at / ends at"
window of 1-13s works fine. Typing ayah-part-2 with a window of 13-17s
never shows -- the 1-13s text just keeps showing (or the screen goes
blank) instead of switching to the new text at 13s.

ROOT CAUSE: in the no-video / single-ayah export path,
`textTimeStartOverride` / `textTimeEndOverride` (PATCH_S109) are a
SINGLE pair of fields shared by the whole ayah text, and
`export_service.dart` bakes exactly ONE static overlay.png gated by
exactly ONE `enable='between(t,start,end)'` window (see
lib/services/export_service.dart, the `else if (overlayPng != null)`
branch). Typing a second piece of text and a second window doesn't
ADD a second timed text -- it just overwrites the one and only
start/end pair (and the one and only `ayahText`) that existed before.
There was never a way to have two different texts each on their own
timer in this mode; the multi-segment timeline (auto-sync / "add ayah
manually") is the only place that ever supported that, and it
requires an uploaded video.

FIX: add a real list of independently-timed text cues
(`StudioState.textTimeCues`, a `List<TextTimeCue>`). The existing
start/end fields become "the entry currently being edited"; a new
"add to list" button commits them as their own cue instead of
overwriting the previous one. The exporter now renders one overlay
PNG per cue and chains one `overlay=...:enable=between(...)` filter
per cue, so each text only ever appears in its own window -- multiple
texts, multiple windows, in the same export.

Marker-gated, idempotent, safe to re-run.
"""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

STUDIO_STATE = "lib/models/studio_state.dart"
HOME_SCREEN = "lib/screens/home_screen.dart"
EXPORT_SERVICE = "lib/services/export_service.dart"
PUBSPEC = "pubspec.yaml"
APP_INFO = "lib/app_info.dart"

MARKER = "PATCH_S160_MULTI_TEXT_TIME_CUES"

# PATCH_S158/S159 lesson: pubspec.yaml's version and app_info.dart's
# kAppVersion/kAppBuildNumber drifted apart last time because only one of
# the two got bumped -- bump both here, together, in the same script.
OLD_VERSION, NEW_VERSION = "1.7.1", "1.7.2"
OLD_BUILD, NEW_BUILD = 8, 9


def _log(label, status):
    LEDGER.append((label, status))
    print(f"  {status:20s} {label}")


def replace_once(path, old, new, label):
    p = ROOT / path
    if not p.exists():
        _log(label, "SKIPPED-NOT-FOUND")
        return False
    text = p.read_text(encoding="utf-8")
    if MARKER in text and new.strip() and new in text:
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
# 1. lib/models/studio_state.dart -- TextTimeCue class + list + methods
# ---------------------------------------------------------------------

_CLASS_ANCHOR = "class StudioState extends ChangeNotifier {\n  // ---- corpus ----"

_CLASS_NEW = f"""// {MARKER}: one independently-timed piece of ayah text. The old
// PATCH_S109 textTimeStartOverride/textTimeEndOverride pair could only
// ever describe ONE text's window -- a second typed text just overwrote
// it. StudioState.textTimeCues below is a real list of these instead.
class TextTimeCue {{
  String text;
  String translation;
  double start;
  double end;
  TextTimeCue({{
    required this.text,
    this.translation = '',
    required this.start,
    required this.end,
  }});
}}

class StudioState extends ChangeNotifier {{
  // ---- corpus ----"""

replace_once(STUDIO_STATE, _CLASS_ANCHOR, _CLASS_NEW,
             "studio_state.dart: add TextTimeCue class")

_FIELDS_OLD = """  // ---- PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION ----
  // Manual override for when the ayah text overlay appears/disappears in
  // the exported clip (seconds, relative to the exported clip's own start).
  // Both null (the default) means "shown for the whole clip", same as before.
  double? textTimeStartOverride;
  double? textTimeEndOverride;"""

_FIELDS_NEW = _FIELDS_OLD + f"""
  // ---- {MARKER} ----
  // Committed timed texts -- each keeps its own independent [start, end)
  // window. textTimeStartOverride/textTimeEndOverride above are now just
  // "the entry currently being typed/edited"; commitTextTimeCue() below
  // is what actually locks it in as its own cue instead of silently
  // replacing whatever text+window was set before it.
  List<TextTimeCue> textTimeCues = [];

  void commitTextTimeCue() {{
    if (textTimeStartOverride == null || textTimeEndOverride == null) return;
    if (textTimeEndOverride! <= textTimeStartOverride!) return;
    if (ayahText.trim().isEmpty) return;
    textTimeCues = [
      ...textTimeCues,
      TextTimeCue(
        text: ayahText,
        translation: translationText,
        start: textTimeStartOverride!,
        end: textTimeEndOverride!,
      ),
    ];
    textTimeStartOverride = null;
    textTimeEndOverride = null;
    notifyListeners();
  }}

  void removeTextTimeCueAt(int index) {{
    if (index < 0 || index >= textTimeCues.length) return;
    final next = [...textTimeCues]..removeAt(index);
    textTimeCues = next;
    notifyListeners();
  }}"""

replace_once(STUDIO_STATE, _FIELDS_OLD, _FIELDS_NEW,
             "studio_state.dart: textTimeCues list + commit/remove methods")

# ---------------------------------------------------------------------
# 2. lib/screens/home_screen.dart -- "add to list" button + cues list UI
# ---------------------------------------------------------------------

_UI_OLD = """            const SizedBox(width: 6),
            IconButton(
              tooltip: 'مسح التوقيت اليدوي',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _textStartCtrl.clear();
                _textEndCtrl.clear();
                state.update(() {
                  state.textTimeStartOverride = null;
                  state.textTimeEndOverride = null;
                });
              }),
            ),
          ],
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: free-text caption (reciter"""

_UI_NEW = f"""            const SizedBox(width: 6),
            IconButton(
              tooltip: 'مسح التوقيت اليدوي',
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {{
                _textStartCtrl.clear();
                _textEndCtrl.clear();
                state.update(() {{
                  state.textTimeStartOverride = null;
                  state.textTimeEndOverride = null;
                }});
              }}),
            ),
            const SizedBox(width: 6),
            // {MARKER}: commits the text+window above as its OWN cue
            // instead of it getting silently overwritten by the next text
            // you type -- this is what actually lets two different texts
            // each appear in their own time window.
            IconButton(
              tooltip: 'إضافة كنص مستقل بتوقيته الخاص',
              icon: const Icon(Icons.playlist_add),
              onPressed: (state.textTimeStartOverride == null ||
                      state.textTimeEndOverride == null ||
                      state.ayahText.trim().isEmpty)
                  ? null
                  : () => setState(() {{
                        state.update(() => state.commitTextTimeCue());
                        _textStartCtrl.clear();
                        _textEndCtrl.clear();
                        _toast('أُضيف النص إلى القائمة ✓');
                      }}),
            ),
          ],
        ),
        if (state.textTimeCues.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (var _cueIdx = 0; _cueIdx < state.textTimeCues.length; _cueIdx++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${{state.textTimeCues[_cueIdx].text}}  ·  '
                      '${{_fmtSec(state.textTimeCues[_cueIdx].start)}}'
                      '–${{_fmtSec(state.textTimeCues[_cueIdx].end)}}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: ayahTextStyle(state.fontKey, fontSize: 13),
                    ),
                  ),
                  IconButton(
                    tooltip: 'حذف',
                    icon: const Icon(Icons.delete_outline, size: 18),
                    onPressed: () =>
                        state.update(() => state.removeTextTimeCueAt(_cueIdx)),
                  ),
                ],
              ),
            ),
        ],
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }}

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: free-text caption (reciter"""

replace_once(HOME_SCREEN, _UI_OLD, _UI_NEW,
             "home_screen.dart: add-to-list button + timed-cues list UI")

# ---------------------------------------------------------------------
# 3. lib/services/export_service.dart -- render + gate one overlay per cue
# ---------------------------------------------------------------------

_DECL_OLD = """      String? overlaySeqPattern;
      String? overlayPng;"""

_DECL_NEW = f"""      String? overlaySeqPattern;
      String? overlayPng;
      // {MARKER}: one rendered PNG + its own [start, end) window per
      // committed text cue, so several different texts can each show up
      // only during their own slice of the export instead of one baked
      // PNG (and one shared window) for the whole clip.
      List<({{String path, double start, double end}})>? overlayPngCues;"""

replace_once(EXPORT_SERVICE, _DECL_OLD, _DECL_NEW,
             "export_service.dart: declare overlayPngCues")

_RENDER_OLD = """      } else if (state.hasAyah) {
        overlayPng = '${work.path}/overlay.png';
        await File(overlayPng)
            .writeAsBytes(await OverlayRenderer.renderTextOverlayPng(
          w: w,
          h: h,
          text: state.ayahText,
          translation: state.translationText,
          style: style,
        ));
      }"""

_RENDER_NEW = f"""      }} else if (state.hasAyah) {{
        // {MARKER}: state.textTimeCues (plus whatever's still sitting in
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
        if (cues.isEmpty) {{
          overlayPng = '${{work.path}}/overlay.png';
          await File(overlayPng)
              .writeAsBytes(await OverlayRenderer.renderTextOverlayPng(
            w: w,
            h: h,
            text: state.ayahText,
            translation: state.translationText,
            style: style,
          ));
        }} else {{
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
        }}
      }}"""

replace_once(EXPORT_SERVICE, _RENDER_OLD, _RENDER_NEW,
             "export_service.dart: render one PNG per text cue")

_GATE_OLD = """    if (overlaySeqPattern != null) {
      inputs.write(
          '-framerate $overlayFps -start_number 0 -i "$overlaySeqPattern" ');
      final ovIdx = idx++;
      filters.add('[$ovIdx:v]format=rgba[ovf]');
      filters.add('[$base][ovf]overlay=0:0[outv]');
    } else if (overlayPng != null) {
      inputs.write('-loop 1 -i "$overlayPng" ');
      final ovIdx = idx++;
      // gentle fade-in so the static text appears like the preview reveal;
      // PATCH_S27_FADE_TEXT_ANIMATIONS: and fade back out near the end instead of a hard cut.
      final fadeOutStart = (duration - 0.6).clamp(0.0, double.infinity);
      final fadeOutFilter = duration > 1.3
          ? ',fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=0.6:alpha=1'
          : '';
      filters.add('[$ovIdx:v]format=rgba,fade=t=in:st=0:d=0.6:alpha=1$fadeOutFilter[ovf]');
      // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: if the user picked an
      // explicit start/stop second for the ayah text, gate the overlay to
      // that window instead of showing it for the whole clip.
      var enableClause = '';
      if (state.textTimeStartOverride != null &&
          state.textTimeEndOverride != null) {
        final ws =
            (state.textTimeStartOverride! - clipStart).clamp(0.0, duration);
        final we =
            (state.textTimeEndOverride! - clipStart).clamp(ws, duration);
        enableClause =
            ":enable='between(t,${ws.toStringAsFixed(3)},${we.toStringAsFixed(3)})'";
      }
      filters.add('[$base][ovf]overlay=0:0:shortest=1$enableClause[outv]');
    } else {
      filters.add('[$base]null[outv]');
    }"""

_GATE_NEW = f"""    if (overlaySeqPattern != null) {{
      inputs.write(
          '-framerate $overlayFps -start_number 0 -i "$overlaySeqPattern" ');
      final ovIdx = idx++;
      filters.add('[$ovIdx:v]format=rgba[ovf]');
      filters.add('[$base][ovf]overlay=0:0[outv]');
    }} else if (overlayPngCues != null && overlayPngCues!.isNotEmpty) {{
      // {MARKER}: chain one overlay per cue, each gated to ONLY its own
      // window -- this is the actual fix for "the second text never
      // shows": before this, there was only ever one overlay and one
      // window, so a second typed text simply had nowhere to go.
      for (var i = 0; i < overlayPngCues!.length; i++) {{
        final cue = overlayPngCues![i];
        inputs.write('-loop 1 -i "${{cue.path}}" ');
        final ovIdx = idx++;
        final ws = (cue.start - clipStart).clamp(0.0, duration);
        final we = (cue.end - clipStart).clamp(ws, duration);
        final fadeOutStart = (we - 0.6).clamp(ws, we);
        final fadeOutFilter = (we - ws) > 1.3
            ? ',fade=t=out:st=${{fadeOutStart.toStringAsFixed(3)}}:d=0.6:alpha=1'
            : '';
        filters.add('[$ovIdx:v]format=rgba,'
            'fade=t=in:st=${{ws.toStringAsFixed(3)}}:d=0.6:alpha=1'
            '$fadeOutFilter[ov$i]');
        final outLabel = i == overlayPngCues!.length - 1 ? 'outv' : 'ovbase$i';
        filters.add("[$base][ov$i]overlay=0:0:shortest=1:"
            "enable='between(t,${{ws.toStringAsFixed(3)}},"
            "${{we.toStringAsFixed(3)}})'[$outLabel]");
        base = outLabel;
      }}
    }} else if (overlayPng != null) {{
      inputs.write('-loop 1 -i "$overlayPng" ');
      final ovIdx = idx++;
      // gentle fade-in so the static text appears like the preview reveal;
      // PATCH_S27_FADE_TEXT_ANIMATIONS: and fade back out near the end instead of a hard cut.
      final fadeOutStart = (duration - 0.6).clamp(0.0, double.infinity);
      final fadeOutFilter = duration > 1.3
          ? ',fade=t=out:st=${{fadeOutStart.toStringAsFixed(3)}}:d=0.6:alpha=1'
          : '';
      filters.add('[$ovIdx:v]format=rgba,fade=t=in:st=0:d=0.6:alpha=1$fadeOutFilter[ovf]');
      filters.add('[$base][ovf]overlay=0:0:shortest=1[outv]');
    }} else {{
      filters.add('[$base]null[outv]');
    }}"""

replace_once(EXPORT_SERVICE, _GATE_OLD, _GATE_NEW,
             "export_service.dart: chain one gated overlay per cue")

# ---------------------------------------------------------------------
# 4. version bump -- pubspec.yaml + lib/app_info.dart, together
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
    print("S160 — multiple independently-timed ayah texts (real bug fix)")
    print("=" * 70)
    print()
    print("=" * 70)
    ok = sum(1 for _, s in LEDGER if s == "OK")
    print(f"{ok} fix(es) applied.")
    print("=" * 70)
    print("""
Next:
  1. flutter analyze
  2. Test: pick ayah, set 1s-13s, tap the new "+" (playlist_add) button
     next to the clear (X) button -- it should appear in the list below.
     Then set 13s-17s for the second text and tap "+" again. Export and
     confirm both texts show up, each only in its own window.
  3. git add -A && git commit -m "S160: support multiple independently-timed ayah texts (fixes 2nd text never showing)"
  4. git push
""")


if __name__ == "__main__":
    main()
