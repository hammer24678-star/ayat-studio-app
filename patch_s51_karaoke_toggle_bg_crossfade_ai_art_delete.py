#!/usr/bin/env python3
"""
patch_s51_karaoke_toggle_bg_crossfade_ai_art_delete.py

Four independent features, bundled together because they all came out of
the same "everything works, but..." review:

1. PATCH_S51_KARAOKE_TOGGLE -- a real on/off switch for the karaoke
   word-by-word highlight (it was always-on before, with no way to fall
   back to plain static ayah text while الشيخ recites). Off reuses the
   existing static-text render path (karaokeWords == null) rather than
   adding a second branch, so preview and export stay in lockstep exactly
   like they did for the always-on case.

2. PATCH_S51_BG_CROSSFADE -- the AI-art background was popping in with a
   hard cut in the LIVE PREVIEW every time a new ayah's art loaded, even
   though bgTransitionStyle/bgCrossfadeDuration already existed and were
   already respected by the export. This wires the same setting into the
   preview so what you see now matches what you'll export.

3. PATCH_S51_AI_ART_DELETE -- the existing "remove custom background"
   button only detached the path in memory; the file stayed cached on
   disk forever (by design, for reuse), and aiArtEnabled staying on meant
   the very next matched ayah could silently regenerate a background you
   thought you'd gotten rid of. This adds a real delete: wipes the cached
   file(s) for that ayah from disk and drops back to the preset gradient,
   without touching the aiArtEnabled switch itself.

4. PATCH_S51_MORE_EFFECTS -- adds a 4th stage effect ("sparkle": quick
   white twinkling glints, distinct from the slow golden dust) appended
   to the end of the StageEffect enum, so persisted effect indexes for
   existing users don't shift.

Every edit is attempted independently (same never-abort convention as
S50c); a failure on one is reported and we move on, so a partial anchor
mismatch doesn't take down the whole run.

Usage:
  python3 patch_s51_karaoke_toggle_bg_crossfade_ai_art_delete.py /path/to/ayat_studio_app
"""

import sys
import pathlib

STUDIO_STATE = "lib/models/studio_state.dart"
SETTINGS_SERVICE = "lib/services/settings_service.dart"
HOME_SCREEN = "lib/screens/home_screen.dart"
EXPORT_SERVICE = "lib/services/export_service.dart"
AI_ART_SERVICE = "lib/services/ai_art_service.dart"
STAGE_EFFECTS = "lib/services/stage_effects.dart"
STAGE_PREVIEW = "lib/widgets/stage_preview.dart"


def apply_literal(project_dir, rel_path, old, new, label, results):
    target = project_dir / rel_path
    if not target.exists():
        results[label] = f"ERROR: {target} not found"
        return
    text = target.read_text()
    if text.count(new) >= 1:
        results[label] = "already applied"
        return
    count = text.count(old)
    if count == 0:
        results[label] = "MISSING: anchor not found, and patched text isn't there either -- needs a manual look"
        return
    if count > 1:
        results[label] = f"MISSING: anchor not unique ({count} matches) -- refusing to guess"
        return
    target.write_text(text.replace(old, new, 1))
    results[label] = "applied"


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    results = {}

    # ================= 1. KARAOKE TOGGLE =================

    # 1a. studio_state.dart -- the field itself
    apply_literal(
        project_dir, STUDIO_STATE,
        "  // ---- auto-sync timeline ----\n"
        "  List<TimelineSegment> timeline = [];\n"
        "  bool timelineActive = false;\n",

        "  // ---- auto-sync timeline ----\n"
        "  List<TimelineSegment> timeline = [];\n"
        "  bool timelineActive = false;\n"
        "  // PATCH_S51_KARAOKE_TOGGLE: word-by-word highlight while الشيخ recites,\n"
        "  // on by default (matches previous always-on behavior). Off falls back\n"
        "  // to showing each ayah part as plain static text.\n"
        "  bool karaokeEnabled = true;\n",
        "studio_state.dart (karaokeEnabled field)", results,
    )

    # 1b. settings_service.dart -- restore()
    apply_literal(
        project_dir, SETTINGS_SERVICE,
        "      state.aiArtEnabled = read<bool>('aiArtEnabled') ?? state.aiArtEnabled;\n",

        "      state.aiArtEnabled = read<bool>('aiArtEnabled') ?? state.aiArtEnabled;\n"
        "      // PATCH_S51_KARAOKE_TOGGLE\n"
        "      state.karaokeEnabled =\n"
        "          read<bool>('karaokeEnabled') ?? state.karaokeEnabled;\n",
        "settings_service.dart (restore karaokeEnabled)", results,
    )

    # 1c. settings_service.dart -- persist()
    apply_literal(
        project_dir, SETTINGS_SERVICE,
        "      p.setBool('${_prefix}aiArtEnabled', state.aiArtEnabled),\n",

        "      p.setBool('${_prefix}aiArtEnabled', state.aiArtEnabled),\n"
        "      // PATCH_S51_KARAOKE_TOGGLE\n"
        "      p.setBool('${_prefix}karaokeEnabled', state.karaokeEnabled),\n",
        "settings_service.dart (persist karaokeEnabled)", results,
    )

    # 1d. home_screen.dart -- gate the live-preview ticker
    apply_literal(
        project_dir, HOME_SCREEN,
        "  void _tickAutoSync() {\n"
        "    final controller = _video;\n"
        "    if (!state.timelineActive ||\n"
        "        controller == null ||\n"
        "        !controller.value.isInitialized) {\n"
        "      return;\n"
        "    }\n"
        "    final t = controller.value.position.inMilliseconds / 1000.0;\n"
        "    TimelineSegment? seg;\n"
        "    for (final s in state.timeline) {\n"
        "      if (t >= s.start && t < s.end) {\n"
        "        seg = s;\n"
        "        break;\n"
        "      }\n"
        "    }\n"
        "    if (seg == null) return; // keep the last ayah on screen between segments\n"
        "    final cue = karaokeCueAt(buildKaraokeChunks(seg), t);\n"
        "    // PATCH_S27_FADE_TEXT_ANIMATIONS: stable per-part key so StagePreview only fades when\n"
        "    // the ayah part actually changes, not on every newly lit word.\n"
        "    final segmentKey =\n"
        "        '${seg.ayah.surahNum}:${seg.ayah.num}:${cue.chunk.index}';\n"
        "    final current = _liveOverlay.value;\n"
        "    if (current == null ||\n"
        "        current.segmentKey != segmentKey ||\n"
        "        current.litWords != cue.litWords) {\n"
        "      _liveOverlay.value = StageOverlayText(cue.chunk.text,\n"
        "          cue.chunk.translation, segmentKey, cue.chunk.words, cue.litWords);\n"
        "    }\n"
        "  }\n",

        "  void _tickAutoSync() {\n"
        "    final controller = _video;\n"
        "    if (!state.timelineActive ||\n"
        "        controller == null ||\n"
        "        !controller.value.isInitialized) {\n"
        "      return;\n"
        "    }\n"
        "    final t = controller.value.position.inMilliseconds / 1000.0;\n"
        "    TimelineSegment? seg;\n"
        "    for (final s in state.timeline) {\n"
        "      if (t >= s.start && t < s.end) {\n"
        "        seg = s;\n"
        "        break;\n"
        "      }\n"
        "    }\n"
        "    if (seg == null) return; // keep the last ayah on screen between segments\n"
        "    final cue = karaokeCueAt(buildKaraokeChunks(seg), t);\n"
        "    // PATCH_S27_FADE_TEXT_ANIMATIONS: stable per-part key so StagePreview only fades when\n"
        "    // the ayah part actually changes, not on every newly lit word.\n"
        "    final segmentKey =\n"
        "        '${seg.ayah.surahNum}:${seg.ayah.num}:${cue.chunk.index}';\n"
        "    // PATCH_S51_KARAOKE_TOGGLE: with the toggle off, drop the per-word\n"
        "    // list entirely -- StagePreview already falls back to plain static\n"
        "    // text whenever karaokeWords is null, so this reuses that path\n"
        "    // instead of adding a second rendering branch.\n"
        "    final words = state.karaokeEnabled ? cue.chunk.words : null;\n"
        "    final litWords = state.karaokeEnabled ? cue.litWords : 0;\n"
        "    final current = _liveOverlay.value;\n"
        "    if (current == null ||\n"
        "        current.segmentKey != segmentKey ||\n"
        "        current.litWords != litWords) {\n"
        "      _liveOverlay.value = StageOverlayText(\n"
        "          cue.chunk.text, cue.chunk.translation, segmentKey, words, litWords);\n"
        "    }\n"
        "  }\n",
        "home_screen.dart (_tickAutoSync karaoke gate)", results,
    )

    # 1e. home_screen.dart -- settings switch, right after the glow toggle
    apply_literal(
        project_dir, HOME_SCREEN,
        "        ),\n"
        "        // PATCH_S46_DEFAULT_FONT_AND_GLOW: glow on/off + intensity (plan 2.2)\n"
        "        SwitchListTile(\n"
        "          contentPadding: EdgeInsets.zero,\n"
        "          title: const Text('توهّج النص'),\n"
        "          value: state.glowEnabled,\n"
        "          onChanged: (v) => state.update(() => state.glowEnabled = v),\n"
        "        ),\n"
        "        if (state.glowEnabled) ...[\n"
        "          _fieldLabel('شدة التوهّج'),\n"
        "          Slider(\n"
        "            value: state.glowIntensity,\n"
        "            min: 0,\n"
        "            max: 1.5,\n"
        "            onChanged: (v) => state.update(() => state.glowIntensity = v),\n"
        "          ),\n"
        "        ],\n",

        "        ),\n"
        "        // PATCH_S46_DEFAULT_FONT_AND_GLOW: glow on/off + intensity (plan 2.2)\n"
        "        SwitchListTile(\n"
        "          contentPadding: EdgeInsets.zero,\n"
        "          title: const Text('توهّج النص'),\n"
        "          value: state.glowEnabled,\n"
        "          onChanged: (v) => state.update(() => state.glowEnabled = v),\n"
        "        ),\n"
        "        if (state.glowEnabled) ...[\n"
        "          _fieldLabel('شدة التوهّج'),\n"
        "          Slider(\n"
        "            value: state.glowIntensity,\n"
        "            min: 0,\n"
        "            max: 1.5,\n"
        "            onChanged: (v) => state.update(() => state.glowIntensity = v),\n"
        "          ),\n"
        "        ],\n"
        "        // PATCH_S51_KARAOKE_TOGGLE: on by default; off shows each ayah\n"
        "        // part as plain static text instead of lighting up word-by-word\n"
        "        // in step with الشيخ's recitation.\n"
        "        SwitchListTile(\n"
        "          contentPadding: EdgeInsets.zero,\n"
        "          title: const Text('تظليل الكلمات مع التلاوة (كاريوكي)'),\n"
        "          subtitle: const Text(\n"
        "              'عند الإيقاف: تُعرض الآية كاملة دون إضاءة كل كلمة على حدة'),\n"
        "          value: state.karaokeEnabled,\n"
        "          onChanged: (v) => state.update(() => state.karaokeEnabled = v),\n"
        "        ),\n",
        "home_screen.dart (karaoke toggle switch UI)", results,
    )

    # 1f. export_service.dart -- burned-in export must match the toggle too
    apply_literal(
        project_dir, EXPORT_SERVICE,
        "        final cue =\n"
        "            karaokeCueAt(chunkCache[seg] ??= buildKaraokeChunks(seg), videoT);\n"
        "        final chunk = cue.chunk;\n"
        "        text = chunk.text;\n"
        "        trans = chunk.translation;\n"
        "        words = chunk.words;\n"
        "        lit = cue.litWords;\n",

        "        final cue =\n"
        "            karaokeCueAt(chunkCache[seg] ??= buildKaraokeChunks(seg), videoT);\n"
        "        final chunk = cue.chunk;\n"
        "        text = chunk.text;\n"
        "        trans = chunk.translation;\n"
        "        // PATCH_S51_KARAOKE_TOGGLE: burn in plain static text instead of\n"
        "        // per-word lighting when the toggle is off -- renderTextOverlayPng\n"
        "        // already renders static text whenever karaokeWords is null/empty.\n"
        "        words = state.karaokeEnabled ? chunk.words : null;\n"
        "        lit = state.karaokeEnabled ? cue.litWords : 0;\n",
        "export_service.dart (karaoke export gate)", results,
    )

    # ================= 2. AI ART DELETE =================

    # 2a. ai_art_service.dart -- deleteCached()
    apply_literal(
        project_dir, AI_ART_SERVICE,
        "    try {\n"
        "      final res = await http.get(url).timeout(const Duration(seconds: 45));\n"
        "      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;\n"
        "      await cached.writeAsBytes(res.bodyBytes);\n"
        "      return cached.path;\n"
        "    } catch (_) {\n"
        "      return null;\n"
        "    }\n"
        "  }\n"
        "}\n",

        "    try {\n"
        "      final res = await http.get(url).timeout(const Duration(seconds: 45));\n"
        "      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;\n"
        "      await cached.writeAsBytes(res.bodyBytes);\n"
        "      return cached.path;\n"
        "    } catch (_) {\n"
        "      return null;\n"
        "    }\n"
        "  }\n"
        "\n"
        "  // PATCH_S51_AI_ART_DELETE: removes the base cached image AND every\n"
        "  // regenerate-bumped seed variant (_v1, _v2, ...) for this ayah, so\n"
        "  // \"delete\" actually clears the disk cache instead of only detaching\n"
        "  // the currently-displayed path. Silently ignores files already gone.\n"
        "  static Future<void> deleteCached(int surahNum, int ayahNum) async {\n"
        "    final dir = await _cacheDir();\n"
        "    if (!await dir.exists()) return;\n"
        "    final prefix = '${surahNum}_$ayahNum';\n"
        "    await for (final entry in dir.list()) {\n"
        "      if (entry is! File) continue;\n"
        "      final name = entry.uri.pathSegments.last;\n"
        "      if (name == '$prefix.png' || name.startsWith('${prefix}_v')) {\n"
        "        try {\n"
        "          await entry.delete();\n"
        "        } catch (_) {\n"
        "          // best-effort; a locked/already-deleted file shouldn't block the rest\n"
        "        }\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "}\n",
        "ai_art_service.dart (deleteCached)", results,
    )

    # 2b. studio_state.dart -- deleteAiArt()
    apply_literal(
        project_dir, STUDIO_STATE,
        "  // PATCH_S32_AI_ART_NANO_BANANA: manual regenerate -- bumps the seed instead of touching\n"
        "  // anything paid; no-ops quietly if there is no current ayah to redo.\n"
        "  Future<void> regenerateAiArt() async {\n"
        "    if (_aiArtSurah == null || _aiArtAyahNum == null || _aiArtAyahText == null) {\n"
        "      return;\n"
        "    }\n"
        "    _aiArtSeedOffset += 1;\n"
        "    await _generateAiArt(_aiArtSurah!, _aiArtAyahNum!, _aiArtAyahText!);\n"
        "  }\n",

        "  // PATCH_S32_AI_ART_NANO_BANANA: manual regenerate -- bumps the seed instead of touching\n"
        "  // anything paid; no-ops quietly if there is no current ayah to redo.\n"
        "  Future<void> regenerateAiArt() async {\n"
        "    if (_aiArtSurah == null || _aiArtAyahNum == null || _aiArtAyahText == null) {\n"
        "      return;\n"
        "    }\n"
        "    _aiArtSeedOffset += 1;\n"
        "    await _generateAiArt(_aiArtSurah!, _aiArtAyahNum!, _aiArtAyahText!);\n"
        "  }\n"
        "\n"
        "  // PATCH_S51_AI_ART_DELETE: wipes every cached file for this ayah from\n"
        "  // disk (so a later visit regenerates fresh instead of silently reusing\n"
        "  // the deleted one) and drops the current custom background back to the\n"
        "  // preset gradients. Leaves aiArtEnabled untouched -- this deletes what\n"
        "  // was made, it doesn't turn the feature off (use the switch for that).\n"
        "  Future<void> deleteAiArt() async {\n"
        "    if (_aiArtSurah == null || _aiArtAyahNum == null) return;\n"
        "    await AiArtService.deleteCached(_aiArtSurah!, _aiArtAyahNum!);\n"
        "    useCustomBg = false;\n"
        "    customBgPath = null;\n"
        "    _aiArtSeedOffset = 0;\n"
        "    notifyListeners();\n"
        "  }\n",
        "studio_state.dart (deleteAiArt)", results,
    )

    # 2c. home_screen.dart -- delete button next to regenerate
    apply_literal(
        project_dir, HOME_SCREEN,
        "          if (state.aiArtBusy)\n"
        "            const Padding(\n"
        "              padding: EdgeInsets.symmetric(vertical: 4),\n"
        "              child: Row(children: [\n"
        "                SizedBox(\n"
        "                    width: 16,\n"
        "                    height: 16,\n"
        "                    child: CircularProgressIndicator(strokeWidth: 2)),\n"
        "                SizedBox(width: 8),\n"
        "                Text('جارٍ توليد الفن...'),\n"
        "              ]),\n"
        "            )\n"
        "          else if (state.hasAiArt)\n"
        "            OutlinedButton.icon(\n"
        "              onPressed: () => state.regenerateAiArt(),\n"
        "              icon: const Icon(Icons.refresh, size: 18),\n"
        "              label: const Text('إعادة توليد فن هذه الآية'),\n"
        "            ),\n"
        "        ],\n",

        "          if (state.aiArtBusy)\n"
        "            const Padding(\n"
        "              padding: EdgeInsets.symmetric(vertical: 4),\n"
        "              child: Row(children: [\n"
        "                SizedBox(\n"
        "                    width: 16,\n"
        "                    height: 16,\n"
        "                    child: CircularProgressIndicator(strokeWidth: 2)),\n"
        "                SizedBox(width: 8),\n"
        "                Text('جارٍ توليد الفن...'),\n"
        "              ]),\n"
        "            )\n"
        "          else if (state.hasAiArt) ...[\n"
        "            OutlinedButton.icon(\n"
        "              onPressed: () => state.regenerateAiArt(),\n"
        "              icon: const Icon(Icons.refresh, size: 18),\n"
        "              label: const Text('إعادة توليد فن هذه الآية'),\n"
        "            ),\n"
        "            const SizedBox(height: 6),\n"
        "            // PATCH_S51_AI_ART_DELETE: distinct from regenerate -- wipes\n"
        "            // the cached image from disk and drops back to the preset\n"
        "            // background instead of making a new one.\n"
        "            OutlinedButton.icon(\n"
        "              onPressed: () => state.deleteAiArt(),\n"
        "              icon: const Icon(Icons.delete_outline, size: 18),\n"
        "              label: const Text('حذف الفن المولّد لهذه الآية'),\n"
        "            ),\n"
        "          ],\n"
        "        ],\n",
        "home_screen.dart (delete AI art button)", results,
    )

    # ================= 3. BACKGROUND CROSSFADE (live preview) =================

    apply_literal(
        project_dir, STAGE_PREVIEW,
        "          child: Container(\n"
        "            decoration: BoxDecoration(\n"
        "              gradient: state.useCustomBg && state.customBgPath != null\n"
        "                  ? null\n"
        "                  : kBackgrounds[state.bgIndex].gradient,\n"
        "              image: state.useCustomBg && state.customBgPath != null\n"
        "                  ? DecorationImage(\n"
        "                      image: FileImage(File(state.customBgPath!)),\n"
        "                      fit: BoxFit.cover)\n"
        "                  : null,\n"
        "              border: Border.all(color: AyatColors.hairline),\n"
        "              borderRadius: BorderRadius.circular(26),\n"
        "            ),\n"
        "            child: Stack(\n"
        "              fit: StackFit.expand,\n"
        "              children: [\n",

        "          child: Container(\n"
        "            decoration: BoxDecoration(\n"
        "              gradient: state.useCustomBg && state.customBgPath != null\n"
        "                  ? null\n"
        "                  : kBackgrounds[state.bgIndex].gradient,\n"
        "              border: Border.all(color: AyatColors.hairline),\n"
        "              borderRadius: BorderRadius.circular(26),\n"
        "            ),\n"
        "            child: Stack(\n"
        "              fit: StackFit.expand,\n"
        "              children: [\n"
        "                // PATCH_S51_BG_CROSSFADE: the AI-art/custom-photo background\n"
        "                // used to hard-cut via DecorationImage, so a new per-ayah AI\n"
        "                // art image popped in instantly between ayat. This crossfades\n"
        "                // using the same transition setting the export already\n"
        "                // respects (state.bgTransitionStyle / bgCrossfadeDuration),\n"
        "                // keyed on the file path so it only re-animates when the\n"
        "                // actual image changes.\n"
        "                if (state.useCustomBg && state.customBgPath != null)\n"
        "                  Positioned.fill(\n"
        "                    child: AnimatedSwitcher(\n"
        "                      duration: state.bgTransitionStyle ==\n"
        "                              BgTransitionStyle.crossfade\n"
        "                          ? Duration(\n"
        "                              milliseconds:\n"
        "                                  (state.bgCrossfadeDuration * 1000).round())\n"
        "                          : Duration.zero,\n"
        "                      switchInCurve: Curves.easeInOut,\n"
        "                      switchOutCurve: Curves.easeInOut,\n"
        "                      layoutBuilder: (current, previous) => Stack(\n"
        "                        fit: StackFit.expand,\n"
        "                        children: [\n"
        "                          ...previous,\n"
        "                          if (current != null) current,\n"
        "                        ],\n"
        "                      ),\n"
        "                      child: Image.file(\n"
        "                        File(state.customBgPath!),\n"
        "                        key: ValueKey(state.customBgPath),\n"
        "                        fit: BoxFit.cover,\n"
        "                      ),\n"
        "                    ),\n"
        "                  ),\n",
        "stage_preview.dart (AI art background crossfade)", results,
    )

    # ================= 4. NEW STAGE EFFECT: sparkle =================

    # 4a. enum + label + icon
    apply_literal(
        project_dir, STAGE_EFFECTS,
        "enum StageEffect { none, rain, snow, dust }\n"
        "\n"
        "extension StageEffectLabel on StageEffect {\n"
        "  String get label => switch (this) {\n"
        "        StageEffect.none => 'بدون تأثير',\n"
        "        StageEffect.rain => 'مطر',\n"
        "        StageEffect.snow => 'ثلج',\n"
        "        StageEffect.dust => 'غبار ضوئي',\n"
        "      };\n"
        "\n"
        "  IconData get icon => switch (this) {\n"
        "        StageEffect.none => Icons.block,\n"
        "        StageEffect.rain => Icons.water_drop_outlined,\n"
        "        StageEffect.snow => Icons.ac_unit,\n"
        "        StageEffect.dust => Icons.auto_awesome,\n"
        "      };\n"
        "}\n",

        "enum StageEffect { none, rain, snow, dust, sparkle }\n"
        "\n"
        "extension StageEffectLabel on StageEffect {\n"
        "  String get label => switch (this) {\n"
        "        StageEffect.none => 'بدون تأثير',\n"
        "        StageEffect.rain => 'مطر',\n"
        "        StageEffect.snow => 'ثلج',\n"
        "        StageEffect.dust => 'غبار ضوئي',\n"
        "        StageEffect.sparkle => 'بريق نجمي', // PATCH_S51_MORE_EFFECTS\n"
        "      };\n"
        "\n"
        "  IconData get icon => switch (this) {\n"
        "        StageEffect.none => Icons.block,\n"
        "        StageEffect.rain => Icons.water_drop_outlined,\n"
        "        StageEffect.snow => Icons.ac_unit,\n"
        "        StageEffect.dust => Icons.auto_awesome,\n"
        "        StageEffect.sparkle => Icons.star_outline, // PATCH_S51_MORE_EFFECTS\n"
        "      };\n"
        "}\n",
        "stage_effects.dart (sparkle enum/label/icon)", results,
    )

    # 4b. paint() switch
    apply_literal(
        project_dir, STAGE_EFFECTS,
        "  static void paint(Canvas canvas, Size size, StageEffect effect,\n"
        "      double timeSec, double intensity) {\n"
        "    switch (effect) {\n"
        "      case StageEffect.none:\n"
        "        return;\n"
        "      case StageEffect.rain:\n"
        "        _paintRain(canvas, size, timeSec, intensity);\n"
        "      case StageEffect.snow:\n"
        "        _paintSnow(canvas, size, timeSec, intensity);\n"
        "      case StageEffect.dust:\n"
        "        _paintDust(canvas, size, timeSec, intensity);\n"
        "    }\n"
        "  }\n",

        "  static void paint(Canvas canvas, Size size, StageEffect effect,\n"
        "      double timeSec, double intensity) {\n"
        "    switch (effect) {\n"
        "      case StageEffect.none:\n"
        "        return;\n"
        "      case StageEffect.rain:\n"
        "        _paintRain(canvas, size, timeSec, intensity);\n"
        "      case StageEffect.snow:\n"
        "        _paintSnow(canvas, size, timeSec, intensity);\n"
        "      case StageEffect.dust:\n"
        "        _paintDust(canvas, size, timeSec, intensity);\n"
        "      case StageEffect.sparkle: // PATCH_S51_MORE_EFFECTS\n"
        "        _paintSparkle(canvas, size, timeSec, intensity);\n"
        "    }\n"
        "  }\n",
        "stage_effects.dart (paint switch sparkle case)", results,
    )

    # 4c. _paintSparkle implementation, right after _paintDust
    apply_literal(
        project_dir, STAGE_EFFECTS,
        "  static void _paintDust(\n"
        "      Canvas canvas, Size size, double t, double intensity) {\n"
        "    final w = size.width, h = size.height;\n"
        "    final count = (70 * intensity).round();\n"
        "    final paint = Paint()\n"
        "      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 * w / 1080);\n"
        "    for (var i = 0; i < count; i++) {\n"
        "      final depth = _rand(i, 1);\n"
        "      final r = (1.0 + 2.4 * depth) * w / 1080;\n"
        "      // dust hovers in place: whole-cycle sways + twinkle, no net drift,\n"
        "      // so nothing needs to wrap at all\n"
        "      final phase = _rand(i, 4) * 2 * pi;\n"
        "      final swayCycles = 1 + (i % 2);\n"
        "      final x = _rand(i, 2) * w +\n"
        "          sin(2 * pi * swayCycles * t / loopSeconds + phase) * w * 0.015;\n"
        "      final y = _rand(i, 3) * h +\n"
        "          cos(2 * pi * swayCycles * t / loopSeconds + phase) * h * 0.008;\n"
        "      final twinkleCycles = 1 + (i % 3);\n"
        "      final twinkle =\n"
        "          0.5 + 0.5 * sin(2 * pi * twinkleCycles * t / loopSeconds + phase * 2);\n"
        "      paint.color = const Color(0xFFECC875)\n"
        "          .withValues(alpha: (0.10 + 0.55 * twinkle) * (0.4 + 0.6 * depth));\n"
        "      canvas.drawCircle(Offset(x, y), r, paint);\n"
        "    }\n"
        "  }\n"
        "\n"
        "  /// One transparent frame of the export loop as PNG bytes.\n",

        "  static void _paintDust(\n"
        "      Canvas canvas, Size size, double t, double intensity) {\n"
        "    final w = size.width, h = size.height;\n"
        "    final count = (70 * intensity).round();\n"
        "    final paint = Paint()\n"
        "      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 1.5 * w / 1080);\n"
        "    for (var i = 0; i < count; i++) {\n"
        "      final depth = _rand(i, 1);\n"
        "      final r = (1.0 + 2.4 * depth) * w / 1080;\n"
        "      // dust hovers in place: whole-cycle sways + twinkle, no net drift,\n"
        "      // so nothing needs to wrap at all\n"
        "      final phase = _rand(i, 4) * 2 * pi;\n"
        "      final swayCycles = 1 + (i % 2);\n"
        "      final x = _rand(i, 2) * w +\n"
        "          sin(2 * pi * swayCycles * t / loopSeconds + phase) * w * 0.015;\n"
        "      final y = _rand(i, 3) * h +\n"
        "          cos(2 * pi * swayCycles * t / loopSeconds + phase) * h * 0.008;\n"
        "      final twinkleCycles = 1 + (i % 3);\n"
        "      final twinkle =\n"
        "          0.5 + 0.5 * sin(2 * pi * twinkleCycles * t / loopSeconds + phase * 2);\n"
        "      paint.color = const Color(0xFFECC875)\n"
        "          .withValues(alpha: (0.10 + 0.55 * twinkle) * (0.4 + 0.6 * depth));\n"
        "      canvas.drawCircle(Offset(x, y), r, paint);\n"
        "    }\n"
        "  }\n"
        "\n"
        "  // PATCH_S51_MORE_EFFECTS: quick white twinkling glints -- fixed points\n"
        "  // that flash on and off fast, unlike the slow drifting golden dust.\n"
        "  // Whole twinkle cycles per loop keep the export tile seamless, same\n"
        "  // convention as the other effects.\n"
        "  static void _paintSparkle(\n"
        "      Canvas canvas, Size size, double t, double intensity) {\n"
        "    final w = size.width, h = size.height;\n"
        "    final count = (90 * intensity).round();\n"
        "    final paint = Paint();\n"
        "    for (var i = 0; i < count; i++) {\n"
        "      final x = _rand(i, 1) * w;\n"
        "      final y = _rand(i, 2) * h;\n"
        "      final twinkleCycles = 3 + (i % 4);\n"
        "      final phase = _rand(i, 3) * 2 * pi;\n"
        "      final twinkle =\n"
        "          0.5 + 0.5 * sin(2 * pi * twinkleCycles * t / loopSeconds + phase);\n"
        "      // most of the cycle stays dim/off; only a brief peak actually\n"
        "      // flashes, so sparkles read as scattered quick glints rather than\n"
        "      // a steady field\n"
        "      final flash = pow(twinkle, 6).toDouble();\n"
        "      if (flash < 0.02) continue;\n"
        "      final r = (0.8 + 1.6 * _rand(i, 4)) * w / 1080;\n"
        "      paint.color = Colors.white.withValues(alpha: flash * 0.9);\n"
        "      canvas.drawCircle(Offset(x, y), r, paint);\n"
        "      // a thin cross flare on the brightest sparkles sells the glint look\n"
        "      if (flash > 0.6) {\n"
        "        final flareLen = r * 5;\n"
        "        paint\n"
        "          ..color = Colors.white.withValues(alpha: (flash - 0.6) * 2 * 0.7)\n"
        "          ..strokeWidth = r * 0.5;\n"
        "        canvas.drawLine(\n"
        "            Offset(x - flareLen, y), Offset(x + flareLen, y), paint);\n"
        "        canvas.drawLine(\n"
        "            Offset(x, y - flareLen), Offset(x, y + flareLen), paint);\n"
        "      }\n"
        "    }\n"
        "  }\n"
        "\n"
        "  /// One transparent frame of the export loop as PNG bytes.\n",
        "stage_effects.dart (_paintSparkle)", results,
    )

    print("S51 patch results:")
    ok, missing, errors = 0, 0, 0
    for label, status in results.items():
        print(f"  - {label}: {status}")
        if status == "applied" or status == "already applied":
            ok += 1
        elif status.startswith("MISSING"):
            missing += 1
        else:
            errors += 1

    print(f"\nOK/already-applied: {ok}   Needs manual look: {missing}   Errors: {errors}")
    if missing or errors:
        print(
            "\nFor any 'MISSING' line above, paste back the actual current content "
            "around that spot and I'll write an exact-match patch for it."
        )
    else:
        print(
            "\nAll edits landed. Run `flutter analyze`, then rebuild and check:\n"
            "  - text formatting tab: new 'تظليل الكلمات مع التلاوة (كاريوكي)' switch\n"
            "  - AI art panel: new 'حذف الفن المولّد لهذه الآية' button next to regenerate\n"
            "  - stage effects row: new 'بريق نجمي' (sparkle) chip\n"
            "  - play an auto-synced video with AI art on: background should now\n"
            "    crossfade between ayat instead of popping in"
        )


if __name__ == "__main__":
    main()
