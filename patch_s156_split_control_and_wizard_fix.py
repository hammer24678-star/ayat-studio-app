# patch_s156_split_control_and_wizard_fix.py
#
# Two independent fixes, both in the auto-segmentation area:
#
# 1) "A full ayah gets cut into parts if it's big" -- this is
#    lib/services/karaoke.dart's kKaraokeMaxWordsPerChunk (12 words):
#    ayahs longer than that are ALWAYS split into 2-3+ sequential on-screen
#    parts, in both the live preview (home_screen._tickAutoSync) and the
#    exporter (export_service._renderKaraokeSequence). The existing
#    "karaoke toggle" (StudioState.karaokeEnabled) does NOT turn this off --
#    it only disables the per-word lighting animation; the ayah is still
#    shown one chunk at a time (see karaoke.dart's own comment: "falls back
#    to showing each ayah part as plain static text" -- still a *part*).
#
#    Fix: two new independently-controllable StudioState fields --
#    splitLongAyahsEnabled (on/off) and maxWordsPerChunk (the threshold,
#    default unchanged at 12) -- wired into buildKaraokeChunks via a new
#    optional parameter, both call sites, settings persistence, undo
#    capture/restore, and a new pair of controls in the Text editor's Glow
#    card right under the existing karaoke toggle.
#
# 2) The auto-segmentation wizard (لصق -> "فتح المعالج الموجّه") genuinely
#    does nothing when run with its own defaults: "Cloud" is both the
#    pre-selected runtime AND the one marked RECOMMENDED, but this build has
#    no cloud backend (autoseg_wizard.dart says so directly in its own
#    comments) -- picking it and tapping "Start segmentation" just closes
#    the dialog and shows a small toast explaining cloud isn't available
#    here. The "Local" runtime is real, but even that only saved the model
#    tier and told the user, via ANOTHER toast, to go find the separate
#    auto-sync button themselves -- so even the one working path never
#    actually ran anything from inside the wizard.
#
#    Fix: default to Local (the runtime that's actually real in this
#    build) and move the RECOMMENDED badge onto it; and make choosing
#    Local + Start actually run the same auto-sync scan the standalone
#    button runs, instead of just saving a setting and telling the user to
#    go do it themselves.
#
# Also bumps the version: 1.5.0+5 -> 1.6.0+6.
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


KARAOKE = "lib/services/karaoke.dart"
STUDIO_STATE = "lib/models/studio_state.dart"
SETTINGS_SERVICE = "lib/services/settings_service.dart"
APP_STRINGS = "lib/i18n/app_strings.dart"
TEXT_EDITOR_PRO = "lib/widgets/text_editor_pro.dart"
HOME_SCREEN = "lib/screens/home_screen.dart"
EXPORT_SERVICE = "lib/services/export_service.dart"
AUTOSEG_WIZARD = "lib/widgets/autoseg_wizard.dart"
KARAOKE_TEST = "test/karaoke_test.dart"
PUBSPEC = "pubspec.yaml"
APP_INFO = "lib/app_info.dart"


# ---------------------------------------------------------------------
# 1) karaoke.dart: the split threshold becomes a parameter instead of
#    always reading the hardcoded constant directly.
# ---------------------------------------------------------------------
def patch_karaoke():
    apply_literal(
        KARAOKE,
        "import 'dart:math';\n"
        "\n"
        "import '../models/studio_state.dart';\n",
        "// PATCH_S156_LONG_AYAH_SPLIT_CONTROL: the split is no longer forced.\n"
        "// StudioState.splitLongAyahsEnabled can turn it off entirely (the whole\n"
        "// ayah stays one on-screen piece no matter how long), and\n"
        "// StudioState.maxWordsPerChunk controls the threshold when splitting is\n"
        "// on -- see buildKaraokeChunks's maxWordsPerChunk parameter below.\n"
        "import 'dart:math';\n"
        "\n"
        "import '../models/studio_state.dart';\n",
        "karaoke.dart: note the split is now controllable (S156)",
        skip_if="PATCH_S156_LONG_AYAH_SPLIT_CONTROL",
    )
    apply_literal(
        KARAOKE,
        "List<KaraokeChunk> buildKaraokeChunks(TimelineSegment seg) {\n"
        "  // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: a segment added from the\n"
        "  // partial-ayah picker carries just the sliced words as textOverride --\n"
        "  // karaoke chunking (and therefore export) reads that instead of the\n"
        "  // full ayah when it's set.\n"
        "  final words = (seg.textOverride ?? seg.ayah.ar).trim().split(RegExp(r'\\s+'));\n"
        "  final total = words.length;\n"
        "  final parts = max(1, (total / kKaraokeMaxWordsPerChunk).ceil());\n",
        "List<KaraokeChunk> buildKaraokeChunks(TimelineSegment seg,\n"
        "    {int maxWordsPerChunk = kKaraokeMaxWordsPerChunk}) {\n"
        "  // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: a segment added from the\n"
        "  // partial-ayah picker carries just the sliced words as textOverride --\n"
        "  // karaoke chunking (and therefore export) reads that instead of the\n"
        "  // full ayah when it's set.\n"
        "  // PATCH_S156_LONG_AYAH_SPLIT_CONTROL: [maxWordsPerChunk] defaults to the\n"
        "  // same constant as always, but callers can now pass a huge value (the\n"
        "  // whole ayah simply never crosses it, so parts stays 1) to keep a long\n"
        "  // ayah as one piece, or a smaller one to split more aggressively.\n"
        "  final words = (seg.textOverride ?? seg.ayah.ar).trim().split(RegExp(r'\\s+'));\n"
        "  final total = words.length;\n"
        "  final parts = max(1, (total / maxWordsPerChunk).ceil());\n",
        "karaoke.dart: buildKaraokeChunks takes a maxWordsPerChunk parameter (S156)",
    )


# ---------------------------------------------------------------------
# 2) studio_state.dart: the two new settings, plus undo capture/restore.
# ---------------------------------------------------------------------
def patch_studio_state():
    apply_literal(
        STUDIO_STATE,
        "  // PATCH_S51_KARAOKE_TOGGLE: word-by-word highlight while الشيخ recites,\n"
        "  // on by default (matches previous always-on behavior). Off falls back\n"
        "  // to showing each ayah part as plain static text.\n"
        "  bool karaokeEnabled = true;\n",
        "  // PATCH_S51_KARAOKE_TOGGLE: word-by-word highlight while الشيخ recites,\n"
        "  // on by default (matches previous always-on behavior). Off falls back\n"
        "  // to showing each ayah part as plain static text.\n"
        "  bool karaokeEnabled = true;\n"
        "  // PATCH_S156_LONG_AYAH_SPLIT_CONTROL: whether long ayat get split into\n"
        "  // sequential on-screen parts at all. On by default (matches previous\n"
        "  // always-split behavior). This is independent of karaokeEnabled above,\n"
        "  // which only ever controlled the per-word lighting, not the splitting.\n"
        "  bool splitLongAyahsEnabled = true;\n"
        "  // PATCH_S156_LONG_AYAH_SPLIT_CONTROL: word-count threshold above which\n"
        "  // an ayah is split, when splitLongAyahsEnabled is on. 12 matches\n"
        "  // karaoke.dart's kKaraokeMaxWordsPerChunk, the previous fixed value.\n"
        "  int maxWordsPerChunk = 12;\n",
        "studio_state.dart: splitLongAyahsEnabled + maxWordsPerChunk fields (S156)",
        skip_if="splitLongAyahsEnabled",
    )
    apply_literal(
        STUDIO_STATE,
        "        'karaokeEnabled': karaokeEnabled,\n",
        "        'karaokeEnabled': karaokeEnabled,\n"
        "        'splitLongAyahsEnabled': splitLongAyahsEnabled,\n"
        "        'maxWordsPerChunk': maxWordsPerChunk,\n",
        "studio_state.dart: capture splitLongAyahsEnabled/maxWordsPerChunk for undo (S156)",
        skip_if="'splitLongAyahsEnabled': splitLongAyahsEnabled",
    )
    apply_literal(
        STUDIO_STATE,
        "    karaokeEnabled = s['karaokeEnabled'] as bool;\n",
        "    karaokeEnabled = s['karaokeEnabled'] as bool;\n"
        "    splitLongAyahsEnabled = s['splitLongAyahsEnabled'] as bool;\n"
        "    maxWordsPerChunk = s['maxWordsPerChunk'] as int;\n",
        "studio_state.dart: restore splitLongAyahsEnabled/maxWordsPerChunk on undo (S156)",
        skip_if="splitLongAyahsEnabled = s['splitLongAyahsEnabled']",
    )


# ---------------------------------------------------------------------
# 3) settings_service.dart: persist the two new settings like every
#    other studio setting (read on load, write on save).
# ---------------------------------------------------------------------
def patch_settings_service():
    apply_literal(
        SETTINGS_SERVICE,
        "      // PATCH_S51_KARAOKE_TOGGLE\n"
        "      state.karaokeEnabled =\n"
        "          read<bool>('karaokeEnabled') ?? state.karaokeEnabled;\n",
        "      // PATCH_S51_KARAOKE_TOGGLE\n"
        "      state.karaokeEnabled =\n"
        "          read<bool>('karaokeEnabled') ?? state.karaokeEnabled;\n"
        "      // PATCH_S156_LONG_AYAH_SPLIT_CONTROL\n"
        "      state.splitLongAyahsEnabled =\n"
        "          read<bool>('splitLongAyahsEnabled') ?? state.splitLongAyahsEnabled;\n"
        "      state.maxWordsPerChunk =\n"
        "          (read<int>('maxWordsPerChunk') ?? state.maxWordsPerChunk)\n"
        "              .clamp(4, 40);\n",
        "settings_service.dart: restore split-control settings (S156)",
        skip_if="state.splitLongAyahsEnabled =",
    )
    apply_literal(
        SETTINGS_SERVICE,
        "      // PATCH_S51_KARAOKE_TOGGLE\n"
        "      p.setBool('${_prefix}karaokeEnabled', state.karaokeEnabled),\n",
        "      // PATCH_S51_KARAOKE_TOGGLE\n"
        "      p.setBool('${_prefix}karaokeEnabled', state.karaokeEnabled),\n"
        "      // PATCH_S156_LONG_AYAH_SPLIT_CONTROL\n"
        "      p.setBool('${_prefix}splitLongAyahsEnabled', state.splitLongAyahsEnabled),\n"
        "      p.setInt('${_prefix}maxWordsPerChunk', state.maxWordsPerChunk),\n",
        "settings_service.dart: persist split-control settings (S156)",
        skip_if="'${_prefix}splitLongAyahsEnabled'",
    )


# ---------------------------------------------------------------------
# 4) app_strings.dart: new i18n keys for the two new controls, and a
#    corrected karaokeToggleSubtitle (it used to claim the OFF state
#    shows "the whole ayah" -- it never did; it showed the current part
#    as static text, same as ON, just without the word-by-word lighting).
# ---------------------------------------------------------------------
def patch_app_strings():
    apply_literal(
        APP_STRINGS,
        "  'textEditorPro.karaokeToggleSubtitle': ['عند الإيقاف: تُعرض الآية كاملة دون إضاءة كل كلمة على حدة', 'When off: the whole ayah shows without lighting up word by word', 'When off: the whole ayah shows without lighting up word by word', 'When off: the whole ayah shows without lighting up word by word', 'When off: the whole ayah shows without lighting up word by word'],\n",
        "  // PATCH_S156_LONG_AYAH_SPLIT_CONTROL: corrected -- this toggle only ever\n"
        "  // controlled the per-word lighting, never whether a long ayah gets\n"
        "  // split into parts (that's the new toggle right below).\n"
        "  'textEditorPro.karaokeToggleSubtitle': ['عند الإيقاف: يُعرض كل جزء من الآية كنص ثابت دون إضاءة كلماته — للتحكم في تقسيم الآيات الطويلة نفسه استخدمي الخيار أدناه', 'When off: each part of the ayah shows as static text without word lighting — to control whether long ayat get split at all, use the option below', 'When off: each part of the ayah shows as static text without word lighting — to control whether long ayat get split at all, use the option below', 'When off: each part of the ayah shows as static text without word lighting — to control whether long ayat get split at all, use the option below', 'When off: each part of the ayah shows as static text without word lighting — to control whether long ayat get split at all, use the option below'],\n"
        "  'textEditorPro.splitLongAyahsToggleTitle': ['تقسيم الآيات الطويلة إلى أجزاء متتالية', 'Split long ayat into sequential parts', 'Split long ayat into sequential parts', 'Split long ayat into sequential parts', 'Split long ayat into sequential parts'],\n"
        "  'textEditorPro.splitLongAyahsToggleSubtitle': ['عند الإيقاف: تبقى الآية قطعة واحدة على الشاشة مهما طال طولها', 'When off: the ayah stays on screen as one piece no matter how long', 'When off: the ayah stays on screen as one piece no matter how long', 'When off: the ayah stays on screen as one piece no matter how long', 'When off: the ayah stays on screen as one piece no matter how long'],\n"
        "  'textEditorPro.maxWordsPerChunkLabel': ['أقصى كلمات/جزء', 'Max words/part', 'Max words/part', 'Max words/part', 'Max words/part'],\n",
        "app_strings.dart: split-control i18n keys + corrected karaoke subtitle (S156)",
        skip_if="textEditorPro.splitLongAyahsToggleTitle",
    )


# ---------------------------------------------------------------------
# 5) text_editor_pro.dart: the new controls, right under the existing
#    karaoke toggle in the Glow card. The word-count slider only shows
#    while splitting itself is on -- the threshold is meaningless
#    otherwise.
# ---------------------------------------------------------------------
def patch_text_editor_pro():
    apply_literal(
        TEXT_EDITOR_PRO,
        "    SwitchListTile(\n"
        "      contentPadding: EdgeInsets.zero,\n"
        "      title: Text(_t('textEditorPro.karaokeToggleTitle'),\n"
        "          style: const TextStyle(fontSize: 13)),\n"
        "      subtitle: Text(\n"
        "          _t('textEditorPro.karaokeToggleSubtitle'),\n"
        "          style: const TextStyle(fontSize: 11)),\n"
        "      value: s.karaokeEnabled,\n"
        "      activeColor: AyatColors.gold,\n"
        "      onChanged: (v) => s.update(() => s.karaokeEnabled = v),\n"
        "    ),\n"
        "  ]);\n",
        "    SwitchListTile(\n"
        "      contentPadding: EdgeInsets.zero,\n"
        "      title: Text(_t('textEditorPro.karaokeToggleTitle'),\n"
        "          style: const TextStyle(fontSize: 13)),\n"
        "      subtitle: Text(\n"
        "          _t('textEditorPro.karaokeToggleSubtitle'),\n"
        "          style: const TextStyle(fontSize: 11)),\n"
        "      value: s.karaokeEnabled,\n"
        "      activeColor: AyatColors.gold,\n"
        "      onChanged: (v) => s.update(() => s.karaokeEnabled = v),\n"
        "    ),\n"
        "    const SizedBox(height: 6),\n"
        "    // PATCH_S156_LONG_AYAH_SPLIT_CONTROL: separate from the toggle above --\n"
        "    // this one controls whether a long ayah gets cut into parts at all.\n"
        "    SwitchListTile(\n"
        "      contentPadding: EdgeInsets.zero,\n"
        "      title: Text(_t('textEditorPro.splitLongAyahsToggleTitle'),\n"
        "          style: const TextStyle(fontSize: 13)),\n"
        "      subtitle: Text(\n"
        "          _t('textEditorPro.splitLongAyahsToggleSubtitle'),\n"
        "          style: const TextStyle(fontSize: 11)),\n"
        "      value: s.splitLongAyahsEnabled,\n"
        "      activeColor: AyatColors.gold,\n"
        "      onChanged: (v) => s.update(() => s.splitLongAyahsEnabled = v),\n"
        "    ),\n"
        "    if (s.splitLongAyahsEnabled)\n"
        "      _slider(_t('textEditorPro.maxWordsPerChunkLabel'),\n"
        "          s.maxWordsPerChunk.toDouble(), 4, 40, 0,\n"
        "          (v) => s.update(() => s.maxWordsPerChunk = v.round())),\n"
        "  ]);\n",
        "text_editor_pro.dart: split-control toggle + threshold slider (S156)",
        skip_if="splitLongAyahsToggleTitle",
    )


# ---------------------------------------------------------------------
# 6) home_screen.dart: the live preview reads the new settings, AND the
#    wizard's "Local" result now actually runs the scan.
# ---------------------------------------------------------------------
def patch_home_screen():
    apply_literal(
        HOME_SCREEN,
        "    final cue = karaokeCueAt(buildKaraokeChunks(seg), t);\n",
        "    // PATCH_S156_LONG_AYAH_SPLIT_CONTROL: an effectively-infinite\n"
        "    // threshold when splitting is off keeps the whole ayah as one chunk\n"
        "    // no matter its word count, instead of always cutting long ayat into\n"
        "    // parts.\n"
        "    final cue = karaokeCueAt(\n"
        "        buildKaraokeChunks(seg,\n"
        "            maxWordsPerChunk:\n"
        "                state.splitLongAyahsEnabled ? state.maxWordsPerChunk : 1 << 30),\n"
        "        t);\n",
        "home_screen.dart: _tickAutoSync respects split-control settings (S156)",
        skip_if="maxWordsPerChunk:\n"
                 "                state.splitLongAyahsEnabled ? state.maxWordsPerChunk : 1 << 30",
    )
    apply_literal(
        HOME_SCREEN,
        "    if (res == null) return;\n"
        "    if (res.importedSegments > 0) {\n"
        "      _revealTimelineCard();\n"
        "      _toast('${_t('wizard.imported')}: ${res.importedSegments} \\u2713');\n"
        "    } else if (res.tierApplied) {\n"
        "      _toast(_t('wizard.localNote'));\n"
        "    } else if (res.cloudChosen) {\n"
        "      _toast(_t('wizard.cloudNote'));\n"
        "    }\n"
        "  }\n",
        "    if (res == null) return;\n"
        "    if (res.importedSegments > 0) {\n"
        "      _revealTimelineCard();\n"
        "      _toast('${_t('wizard.imported')}: ${res.importedSegments} \\u2713');\n"
        "    } else if (res.tierApplied) {\n"
        "      // PATCH_S156_WIZARD_LOCAL_RUNS: the wizard used to just save the\n"
        "      // model tier and tell the user, in a toast, to go find the\n"
        "      // separate auto-sync button themselves -- so tapping the wizard's\n"
        "      // own \"Start segmentation\" button visibly did nothing. Local has\n"
        "      // no reason to stop short of actually running the scan it just\n"
        "      // configured, so it does now -- the same real TimelineBuilder\n"
        "      // pass the standalone button triggers.\n"
        "      if (state.hasVideo) {\n"
        "        await _autoSync();\n"
        "      } else {\n"
        "        _toast(_t('wizard.localNote'));\n"
        "      }\n"
        "    } else if (res.cloudChosen) {\n"
        "      _toast(_t('wizard.cloudNote'));\n"
        "    }\n"
        "  }\n",
        "home_screen.dart: wizard Local result actually runs auto-sync (S156)",
        skip_if="PATCH_S156_WIZARD_LOCAL_RUNS",
    )


# ---------------------------------------------------------------------
# 7) export_service.dart: burned-in captions must match what the live
#    preview showed (Preview = Export rule, same as everywhere else in
#    this codebase).
# ---------------------------------------------------------------------
def patch_export_service():
    apply_literal(
        EXPORT_SERVICE,
        "        final cue =\n"
        "            karaokeCueAt(chunkCache[seg] ??= buildKaraokeChunks(seg), videoT);\n",
        "        // PATCH_S156_LONG_AYAH_SPLIT_CONTROL: same effectively-infinite\n"
        "        // threshold trick as the live preview, so what gets burned into\n"
        "        // the exported video matches what auto-sync playback showed.\n"
        "        final cue = karaokeCueAt(\n"
        "            chunkCache[seg] ??= buildKaraokeChunks(seg,\n"
        "                maxWordsPerChunk: state.splitLongAyahsEnabled\n"
        "                    ? state.maxWordsPerChunk\n"
        "                    : 1 << 30),\n"
        "            videoT);\n",
        "export_service.dart: exporter respects split-control settings (S156)",
        skip_if="state.splitLongAyahsEnabled\n                    ? state.maxWordsPerChunk",
    )


# ---------------------------------------------------------------------
# 8) autoseg_wizard.dart: default to Local (the runtime that actually
#    works standalone), move the RECOMMENDED badge onto it.
# ---------------------------------------------------------------------
def patch_autoseg_wizard():
    apply_literal(
        AUTOSEG_WIZARD,
        "  _Step _step = _Step.version;\n"
        "  bool _v2 = true;\n"
        "  _Runtime _runtime = _Runtime.cloud;\n",
        "  _Step _step = _Step.version;\n"
        "  bool _v2 = true;\n"
        "  // PATCH_S156_WIZARD_LOCAL_DEFAULT: default to the runtime that\n"
        "  // actually works standalone in this build (see the runtime step\n"
        "  // widget below for why Cloud shouldn't be the default).\n"
        "  _Runtime _runtime = _Runtime.local;\n",
        "autoseg_wizard.dart: default runtime is Local, not Cloud (S156)",
        skip_if="PATCH_S156_WIZARD_LOCAL_DEFAULT",
    )
    apply_literal(
        AUTOSEG_WIZARD,
        "      case _Step.runtime:\n"
        "        return Column(children: [\n"
        "          _card(\n"
        "              selected: _runtime == _Runtime.cloud,\n"
        "              onTap: () => setState(() => _runtime = _Runtime.cloud),\n"
        "              child: Row(children: [\n"
        "                Expanded(child: _title(_s.t('wizard.cloud'), _s.t('wizard.cloudDesc'))),\n"
        "                _badge(),\n"
        "              ])),\n"
        "          if (_runtime == _Runtime.cloud) ...[\n"
        "            const SizedBox(height: 6),\n"
        "            Text(_s.t('wizard.cloudNote'),\n"
        "                style: Theme.of(context)\n"
        "                    .textTheme\n"
        "                    .bodySmall\n"
        "                    ?.copyWith(color: AyatColors.goldDim)),\n"
        "          ],\n"
        "          const SizedBox(height: 10),\n"
        "          _card(\n"
        "              selected: _runtime == _Runtime.local,\n"
        "              onTap: () => setState(() => _runtime = _Runtime.local),\n"
        "              child: _title(_s.t('wizard.local'), _s.t('wizard.localDesc'))),\n"
        "          const SizedBox(height: 10),\n",
        "      case _Step.runtime:\n"
        "        return Column(children: [\n"
        "          // PATCH_S156_WIZARD_LOCAL_DEFAULT: Local moved first and now\n"
        "          // carries the \"recommended\" badge. Cloud has no backend in this\n"
        "          // build (see wizard.cloudNote below) but used to sit here,\n"
        "          // marked recommended, as the default selection -- so hitting\n"
        "          // Start with the wizard's own defaults did nothing at all.\n"
        "          // Local is the one runtime that genuinely works with one tap.\n"
        "          _card(\n"
        "              selected: _runtime == _Runtime.local,\n"
        "              onTap: () => setState(() => _runtime = _Runtime.local),\n"
        "              child: Row(children: [\n"
        "                Expanded(child: _title(_s.t('wizard.local'), _s.t('wizard.localDesc'))),\n"
        "                _badge(),\n"
        "              ])),\n"
        "          const SizedBox(height: 10),\n"
        "          _card(\n"
        "              selected: _runtime == _Runtime.cloud,\n"
        "              onTap: () => setState(() => _runtime = _Runtime.cloud),\n"
        "              child: _title(_s.t('wizard.cloud'), _s.t('wizard.cloudDesc'))),\n"
        "          if (_runtime == _Runtime.cloud) ...[\n"
        "            const SizedBox(height: 6),\n"
        "            Text(_s.t('wizard.cloudNote'),\n"
        "                style: Theme.of(context)\n"
        "                    .textTheme\n"
        "                    .bodySmall\n"
        "                    ?.copyWith(color: AyatColors.goldDim)),\n"
        "          ],\n"
        "          const SizedBox(height: 10),\n",
        "autoseg_wizard.dart: Local card first + badge, Cloud loses the badge (S156)",
        skip_if="PATCH_S156_WIZARD_LOCAL_DEFAULT: Local moved first",
    )


# ---------------------------------------------------------------------
# 9) test/karaoke_test.dart: cover the new parameter.
# ---------------------------------------------------------------------
def patch_karaoke_test():
    apply_literal(
        KARAOKE_TEST,
        "  test('long ayahs split into 2-3 parts above 12 words', () {\n"
        "    expect(buildKaraokeChunks(seg(words(12), '', 0, 10)).length, 1);\n"
        "    expect(buildKaraokeChunks(seg(words(13), '', 0, 10)).length, 2);\n"
        "    expect(buildKaraokeChunks(seg(words(24), '', 0, 10)).length, 2);\n"
        "    expect(buildKaraokeChunks(seg(words(30), '', 0, 10)).length, 3);\n"
        "  });\n",
        "  test('long ayahs split into 2-3 parts above 12 words', () {\n"
        "    expect(buildKaraokeChunks(seg(words(12), '', 0, 10)).length, 1);\n"
        "    expect(buildKaraokeChunks(seg(words(13), '', 0, 10)).length, 2);\n"
        "    expect(buildKaraokeChunks(seg(words(24), '', 0, 10)).length, 2);\n"
        "    expect(buildKaraokeChunks(seg(words(30), '', 0, 10)).length, 3);\n"
        "  });\n"
        "\n"
        "  // PATCH_S156_LONG_AYAH_SPLIT_CONTROL\n"
        "  test('maxWordsPerChunk overrides the default split threshold', () {\n"
        "    // same 30-word ayah that splits into 3 parts by default (test above)\n"
        "    // stays as one chunk when the caller raises the threshold -- this is\n"
        "    // exactly what StudioState.splitLongAyahsEnabled == false does via an\n"
        "    // effectively-infinite maxWordsPerChunk.\n"
        "    expect(\n"
        "        buildKaraokeChunks(seg(words(30), '', 0, 10), maxWordsPerChunk: 1000)\n"
        "            .length,\n"
        "        1);\n"
        "    // and a lower threshold splits an ayah the 12-word default would not\n"
        "    expect(\n"
        "        buildKaraokeChunks(seg(words(8), '', 0, 10), maxWordsPerChunk: 4)\n"
        "            .length,\n"
        "        2);\n"
        "  });\n",
        "karaoke_test.dart: test for the new maxWordsPerChunk parameter (S156)",
        skip_if="maxWordsPerChunk overrides the default split threshold",
    )


# ---------------------------------------------------------------------
# 10) Version bump: 1.5.0+5 -> 1.6.0+6.
# ---------------------------------------------------------------------
def patch_pubspec():
    apply_literal(
        PUBSPEC,
        "version: 1.5.0+5",
        "version: 1.6.0+6",
        "pubspec.yaml: bump version to 1.6.0+6 (S156)",
        skip_if="version: 1.6.0+6",
    )


def patch_app_info():
    apply_literal(
        APP_INFO,
        "const String kAppVersion = '1.5.0';\nconst int kAppBuildNumber = 5;",
        "const String kAppVersion = '1.6.0';\nconst int kAppBuildNumber = 6;",
        "lib/app_info.dart: bump kAppVersion/kAppBuildNumber to 1.6.0/6 (S156)",
        skip_if="kAppVersion = '1.6.0'",
    )


def main():
    patch_karaoke()
    patch_studio_state()
    patch_settings_service()
    patch_app_strings()
    patch_text_editor_pro()
    patch_home_screen()
    patch_export_service()
    patch_autoseg_wizard()
    patch_karaoke_test()
    patch_pubspec()
    patch_app_info()

    print("\n=== S156 split-control-and-wizard-fix ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================================\n")


if __name__ == "__main__":
    main()
