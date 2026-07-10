#!/usr/bin/env python3
"""
patch_s69_ai_art_fix.py

FIXES: "AI art doesn't do shit when I click it."

TWO separate bugs found, not one:

1. UI/state bug (what the original plan assumed): regenerateAiArt() only
   ever shows up once art already exists for the current ayah
   (hasAiArt == true). If you enable "aiArtEnabled" AFTER an ayah was
   already matched -- or the match came from a source that doesn't carry
   surah/ayah numbers into aiArtEnabled's auto-trigger -- there is no
   button at all. Nothing renders, nothing happens when you tap around.
   Fixed by tracking the last-matched surah/ayah/text unconditionally
   (not just when aiArtEnabled was already on) and adding a real
   standalone "generate now" entry point + visible error text instead of
   a silent no-op.

2. MUCH BIGGER bug (not visible until you actually check Pollinations'
   current docs, which the original S32/S69 write-ups never did):
   Pollinations retired free/keyless image generation. As of their
   current API (gen.pollinations.ai), GET /image/{prompt} is NOT in
   their "relaxed auth" list anymore -- it requires a Bearer key or
   ?key= param (pk_... publishable keys are fine client-side, per their
   own docs). Anonymous unauthenticated calls now get 401. This is
   almost certainly the real reason art "does nothing": every request
   has been silently failing at the network layer with no error shown
   (artFor() swallowed the exception and returned null).

   THIS MEANS: to keep this feature working at all, you need a free
   Pollinations API key. Sign up at https://enter.pollinations.ai,
   create a "publishable" (pk_...) key -- these are explicitly designed
   to be safe to ship inside a mobile app, unlike secret sk_ keys.
   Free/anonymous-tier accounts still get pollen credits on a refill
   cycle per their docs; you don't need to pay anything to get this
   working again, just to have an account + key.

   This patch adds a Settings field to paste that key in (stored via
   SharedPreferences, same pattern as every other persisted setting) --
   there's no way for a patch script to obtain a key on your behalf,
   you'll need to grab one yourself, once.

WHAT THIS PATCH DOES:
  1. lib/services/ai_art_service.dart
     - adds a settable `apiKey` (populated from Settings at startup)
       appended as `&key=...` on every request when non-empty
     - removes the swallow-everything try/catch -- artFor() now throws
       AiArtException with a real, specific reason (auth missing/
       invalid, budget exhausted, network failure, timeout, bad
       response) instead of returning null on every failure
       indiscriminately
     - drops the no-longer-documented `nologo` param (Pollinations'
       current API doesn't list it; harmless either way, just cleanup)
  2. lib/models/studio_state.dart
     - tracks the last matched surah/ayah/text UNCONDITIONALLY in
       setAyah() (previously only captured when aiArtEnabled was
       already on at match time)
     - adds `aiArtError` (String?) surfaced to the UI
     - adds `generateAiArtNow()`: a real standalone entry point that
       works from whatever ayah was last matched, with a clear error
       message if there's no ayah context yet instead of a silent no-op
     - adds `pollinationsApiKey` (persisted setting)
  3. lib/services/settings_service.dart
     - persists/restores pollinationsApiKey, wires it into
       AiArtService.apiKey on restore
  4. lib/screens/home_screen.dart
     - shows a real "generate now" button when AI art is enabled but
       nothing has been generated yet (previously: nothing rendered)
     - shows state.aiArtError as visible text instead of hiding failures
     - adds the API key input field with an explanatory note + link

Usage:
  python3 patch_s69_ai_art_fix.py /path/to/ayat_studio_app
  (defaults to . if no path given)

HOW TO VERIFY:
  1. Get a free pk_ key from https://enter.pollinations.ai, paste it into
     the new field under فن الذكاء الاصطناعي in Settings.
  2. Match/select any ayah, enable AI art, tap "توليد الآن" if no art
     shows automatically.
  3. If it still fails, the error text now tells you WHY (bad key,
     budget exhausted, network, etc.) instead of silence.
"""

import sys
import pathlib

MARKER = "PATCH_S69_AI_ART_FIX"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S69 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


# ---------------------------------------------------------------------------
# 1. lib/services/ai_art_service.dart
# ---------------------------------------------------------------------------

def patch_ai_art_service(project_dir):
    target = project_dir / "lib" / "services" / "ai_art_service.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    # 1a. class header: add settable apiKey + exception type
    text = replace_once(
        text,
        "class AiArtService {\n"
        "  static const String _base = 'https://gen.pollinations.ai/image/';\n"
        "\n"
        "  static Future<Directory> _cacheDir() async {\n",
        f"// {MARKER}: Pollinations retired free/keyless image generation --\n"
        "// GET /image/{prompt} now requires a Bearer key or ?key= param (401\n"
        "// otherwise). Get a free publishable (pk_...) key at\n"
        "// https://enter.pollinations.ai -- pk_ keys are explicitly documented\n"
        "// as safe to ship inside a mobile app, unlike secret sk_ keys. Set via\n"
        "// Settings; wired in from studio_state.pollinationsApiKey.\n"
        "class AiArtException implements Exception {\n"
        "  final String message;\n"
        "  AiArtException(this.message);\n"
        "  @override\n"
        "  String toString() => message;\n"
        "}\n"
        "\n"
        "class AiArtService {\n"
        "  static const String _base = 'https://gen.pollinations.ai/image/';\n"
        "  static String apiKey = '';\n"
        "\n"
        "  static Future<Directory> _cacheDir() async {\n",
        "ai_art_service class header",
    )

    # 1b. artFor(): stop swallowing errors, append key, drop dead nologo param
    text = replace_once(
        text,
        "    final prompt = _buildPrompt(ayahArabic);\n"
        "    // Deterministic seed from surah:ayah (+ offset) -- same ayah always\n"
        "    // reproduces the same art; a regenerate tap bumps the offset for a\n"
        "    // genuinely different result.\n"
        "    final seed = (surahNum * 1000 + ayahNum) * 97 + seedOffset;\n"
        "    final url = Uri.parse('$_base${Uri.encodeComponent(prompt)}'\n"
        "        '?width=1080&height=1920&seed=$seed&nologo=true&model=flux');\n"
        "\n"
        "    try {\n"
        "      final res = await http.get(url).timeout(const Duration(seconds: 45));\n"
        "      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;\n"
        "      await cached.writeAsBytes(res.bodyBytes);\n"
        "      return cached.path;\n"
        "    } catch (_) {\n"
        "      return null;\n"
        "    }\n"
        "  }\n",
        f"    final prompt = _buildPrompt(ayahArabic);\n"
        "    // Deterministic seed from surah:ayah (+ offset) -- same ayah always\n"
        "    // reproduces the same art; a regenerate tap bumps the offset for a\n"
        "    // genuinely different result.\n"
        "    final seed = (surahNum * 1000 + ayahNum) * 97 + seedOffset;\n"
        "    // PATCH_S69_AI_ART_FIX: current Pollinations API requires ?key=\n"
        "    // (pk_/sk_) for this endpoint; empty apiKey will 401 with a clear\n"
        "    // error below instead of silently failing like before.\n"
        "    final keyParam = apiKey.trim().isEmpty ? '' : '&key=${Uri.encodeComponent(apiKey.trim())}';\n"
        "    final url = Uri.parse('$_base${Uri.encodeComponent(prompt)}'\n"
        "        '?width=1080&height=1920&seed=$seed&model=flux$keyParam');\n"
        "\n"
        "    http.Response res;\n"
        "    try {\n"
        "      res = await http.get(url).timeout(const Duration(seconds: 45));\n"
        "    } on Exception catch (e) {\n"
        "      throw AiArtException('تعذر الاتصال بخدمة توليد الفن: $e');\n"
        "    }\n"
        "    if (res.statusCode == 401) {\n"
        "      throw AiArtException(\n"
        "          'مفتاح Pollinations مفقود أو غير صالح -- أضف مفتاحًا مجانيًا من enter.pollinations.ai في الإعدادات');\n"
        "    }\n"
        "    if (res.statusCode == 402) {\n"
        "      throw AiArtException('تم استهلاك رصيد Pollinations المجاني لهذه الفترة -- حاول لاحقًا');\n"
        "    }\n"
        "    if (res.statusCode == 429) {\n"
        "      throw AiArtException('طلبات كثيرة جدًا خلال فترة قصيرة -- انتظر قليلًا ثم أعد المحاولة');\n"
        "    }\n"
        "    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {\n"
        "      throw AiArtException('فشل توليد الفن (رمز الحالة: ${res.statusCode})');\n"
        "    }\n"
        "    await cached.writeAsBytes(res.bodyBytes);\n"
        "    return cached.path;\n"
        "  }\n",
        "ai_art_service artFor() body",
    )

    target.write_text(text)
    return True


# ---------------------------------------------------------------------------
# 2. lib/models/studio_state.dart
# ---------------------------------------------------------------------------

def patch_studio_state(project_dir):
    target = project_dir / "lib" / "models" / "studio_state.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    # 2a. new fields
    text = replace_once(
        text,
        "  bool aiArtEnabled = false;\n"
        "  bool aiArtBusy = false;\n"
        "  int? _aiArtSurah;\n"
        "  int? _aiArtAyahNum;\n"
        "  String? _aiArtAyahText;\n"
        "  int _aiArtSeedOffset = 0;\n"
        "  bool get hasAiArt => useCustomBg && aiArtEnabled && _aiArtSurah != null;\n",
        "  bool aiArtEnabled = false;\n"
        "  bool aiArtBusy = false;\n"
        "  int? _aiArtSurah;\n"
        "  int? _aiArtAyahNum;\n"
        "  String? _aiArtAyahText;\n"
        "  int _aiArtSeedOffset = 0;\n"
        "  bool get hasAiArt => useCustomBg && aiArtEnabled && _aiArtSurah != null;\n"
        f"  // {MARKER}: surfaced to the UI instead of failing silently.\n"
        "  String? aiArtError;\n"
        "  // Tracked on EVERY match regardless of aiArtEnabled, so a manual\n"
        "  // generate works even if the toggle was flipped on after the match\n"
        "  // already happened (previously: no context, silent no-op).\n"
        "  int? _lastMatchedSurah;\n"
        "  int? _lastMatchedAyahNum;\n"
        "  String? _lastMatchedAyahText;\n"
        "  // Free pk_ key from https://enter.pollinations.ai -- current\n"
        "  // Pollinations API requires this even for free-tier image gen.\n"
        "  String pollinationsApiKey = '';\n",
        "studio_state AI art fields",
    )

    # 2b. setAyah(): always track last-matched, keep auto-trigger gated
    text = replace_once(
        text,
        "    // PATCH_S32_AI_ART_NANO_BANANA: only ayat resolved against the real corpus carry a\n"
        "    // surah/ayah number -- free-typed unmatched text is skipped since\n"
        "    // there is nothing reliable to cache the art against.\n"
        "    if (aiArtEnabled && surahNum != null && ayahNum != null) {\n"
        "      _aiArtSeedOffset = 0;\n"
        "      _generateAiArt(surahNum, ayahNum, ar);\n"
        "    }\n"
        "  }\n",
        "    // PATCH_S32_AI_ART_NANO_BANANA: only ayat resolved against the real corpus carry a\n"
        "    // surah/ayah number -- free-typed unmatched text is skipped since\n"
        "    // there is nothing reliable to cache the art against.\n"
        f"    // {MARKER}: track the match UNCONDITIONALLY (not just when\n"
        "    // aiArtEnabled happened to already be on) so a later manual\n"
        "    // generateAiArtNow() always has something to work from.\n"
        "    if (surahNum != null && ayahNum != null) {\n"
        "      _lastMatchedSurah = surahNum;\n"
        "      _lastMatchedAyahNum = ayahNum;\n"
        "      _lastMatchedAyahText = ar;\n"
        "    }\n"
        "    if (aiArtEnabled && surahNum != null && ayahNum != null) {\n"
        "      _aiArtSeedOffset = 0;\n"
        "      _generateAiArt(surahNum, ayahNum, ar);\n"
        "    }\n"
        "  }\n",
        "studio_state setAyah()",
    )

    # 2c. _generateAiArt(): capture real errors instead of swallowing
    text = replace_once(
        text,
        "  // PATCH_S32_AI_ART_NANO_BANANA\n"
        "  Future<void> _generateAiArt(int surahNum, int ayahNum, String arText) async {\n"
        "    _aiArtSurah = surahNum;\n"
        "    _aiArtAyahNum = ayahNum;\n"
        "    _aiArtAyahText = arText;\n"
        "    aiArtBusy = true;\n"
        "    notifyListeners();\n"
        "    try {\n"
        "      final path = await AiArtService.artFor(\n"
        "        surahNum: surahNum,\n"
        "        ayahNum: ayahNum,\n"
        "        ayahArabic: arText,\n"
        "        seedOffset: _aiArtSeedOffset,\n"
        "      );\n"
        "      if (path != null) {\n"
        "        useCustomBg = true;\n"
        "        customBgPath = path;\n"
        "      }\n"
        "    } finally {\n"
        "      aiArtBusy = false;\n"
        "      notifyListeners();\n"
        "    }\n"
        "  }\n",
        "  // PATCH_S32_AI_ART_NANO_BANANA\n"
        "  Future<void> _generateAiArt(int surahNum, int ayahNum, String arText) async {\n"
        "    _aiArtSurah = surahNum;\n"
        "    _aiArtAyahNum = ayahNum;\n"
        "    _aiArtAyahText = arText;\n"
        "    aiArtBusy = true;\n"
        f"    aiArtError = null; // {MARKER}\n"
        "    notifyListeners();\n"
        "    try {\n"
        "      final path = await AiArtService.artFor(\n"
        "        surahNum: surahNum,\n"
        "        ayahNum: ayahNum,\n"
        "        ayahArabic: arText,\n"
        "        seedOffset: _aiArtSeedOffset,\n"
        "      );\n"
        "      if (path != null) {\n"
        "        useCustomBg = true;\n"
        "        customBgPath = path;\n"
        "      }\n"
        "    } on AiArtException catch (e) {\n"
        "      aiArtError = e.message;\n"
        "    } catch (e) {\n"
        "      aiArtError = 'تعذر توليد الفن: $e';\n"
        "    } finally {\n"
        "      aiArtBusy = false;\n"
        "      notifyListeners();\n"
        "    }\n"
        "  }\n",
        "studio_state _generateAiArt()",
    )

    # 2d. add generateAiArtNow() right after regenerateAiArt()
    text = replace_once(
        text,
        "  Future<void> regenerateAiArt() async {\n"
        "    if (_aiArtSurah == null || _aiArtAyahNum == null || _aiArtAyahText == null) {\n"
        "      return;\n"
        "    }\n"
        "    _aiArtSeedOffset += 1;\n"
        "    await _generateAiArt(_aiArtSurah!, _aiArtAyahNum!, _aiArtAyahText!);\n"
        "  }\n",
        "  Future<void> regenerateAiArt() async {\n"
        "    if (_aiArtSurah == null || _aiArtAyahNum == null || _aiArtAyahText == null) {\n"
        "      return;\n"
        "    }\n"
        "    _aiArtSeedOffset += 1;\n"
        "    await _generateAiArt(_aiArtSurah!, _aiArtAyahNum!, _aiArtAyahText!);\n"
        "  }\n"
        "\n"
        f"  // {MARKER}: standalone manual entry point -- works from whatever ayah\n"
        "  // was last matched, with a real, visible error instead of the old\n"
        "  // silent no-op when there's no context yet.\n"
        "  Future<void> generateAiArtNow() async {\n"
        "    if (_lastMatchedSurah == null ||\n"
        "        _lastMatchedAyahNum == null ||\n"
        "        _lastMatchedAyahText == null) {\n"
        "      aiArtError = 'اختر آية أولًا (بالتعرف التلقائي أو من المصحف) قبل توليد الفن';\n"
        "      notifyListeners();\n"
        "      return;\n"
        "    }\n"
        "    _aiArtSeedOffset = 0;\n"
        "    await _generateAiArt(\n"
        "        _lastMatchedSurah!, _lastMatchedAyahNum!, _lastMatchedAyahText!);\n"
        "  }\n",
        "studio_state generateAiArtNow()",
    )

    target.write_text(text)
    return True


# ---------------------------------------------------------------------------
# 3. lib/services/settings_service.dart
# ---------------------------------------------------------------------------

def patch_settings_service(project_dir):
    target = project_dir / "lib" / "services" / "settings_service.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    # 3a. restore()
    text = replace_once(
        text,
        "      state.aiArtEnabled = read<bool>('aiArtEnabled') ?? state.aiArtEnabled;\n"
        "      // PATCH_S51_KARAOKE_TOGGLE\n",
        f"      state.aiArtEnabled = read<bool>('aiArtEnabled') ?? state.aiArtEnabled;\n"
        f"      // {MARKER}\n"
        "      state.pollinationsApiKey =\n"
        "          read<String>('pollinationsApiKey') ?? state.pollinationsApiKey;\n"
        "      AiArtService.apiKey = state.pollinationsApiKey;\n"
        "      // PATCH_S51_KARAOKE_TOGGLE\n",
        "settings_service restore() aiArtEnabled",
    )

    # 3b. persist()
    text = replace_once(
        text,
        "      p.setBool('${_prefix}aiArtEnabled', state.aiArtEnabled),\n"
        "      // PATCH_S51_KARAOKE_TOGGLE\n",
        f"      p.setBool('${{_prefix}}aiArtEnabled', state.aiArtEnabled),\n"
        f"      // {MARKER}\n"
        "      p.setString('${_prefix}pollinationsApiKey', state.pollinationsApiKey),\n"
        "      // PATCH_S51_KARAOKE_TOGGLE\n",
        "settings_service persist() aiArtEnabled",
    )

    # 3c. import AiArtService if not already imported
    if "ai_art_service.dart" not in text:
        text = replace_once(
            text,
            "import 'whisper_service.dart'; // PATCH_S47_SETTINGS_WHISPER_IMPORT_FIX: WhisperModelSize lives here\n",
            "import 'whisper_service.dart'; // PATCH_S47_SETTINGS_WHISPER_IMPORT_FIX: WhisperModelSize lives here\n"
            f"import 'ai_art_service.dart'; // {MARKER}: AiArtService.apiKey\n",
            "settings_service AiArtService import",
        )

    target.write_text(text)
    return True


# ---------------------------------------------------------------------------
# 4. lib/screens/home_screen.dart
# ---------------------------------------------------------------------------

def patch_home_screen(project_dir):
    target = project_dir / "lib" / "screens" / "home_screen.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    old = (
        "        // PATCH_S32_AI_ART_NANO_BANANA\n"
        "        const Divider(height: 32, color: AyatColors.hairline),\n"
        "        ToggleRow(\n"
        "          label: 'فن الذكاء الاصطناعي لكل آية',\n"
        "          value: state.aiArtEnabled,\n"
        "          onChanged: (v) => state.update(() => state.aiArtEnabled = v),\n"
        "        ),\n"
        "        if (state.aiArtEnabled) ...[\n"
        "          const SizedBox(height: 6),\n"
        "          Text(\n"
        "            'تُنشأ خلفية بأسلوب خطوط متوهجة أحادية اللون لكل آية تُكتشف تلقائيًا، بلا وجوه بشرية أبدًا؛ إن ذُكر نبي في الآية يظهر عمود نور واسمه بخط عربي بدل أي شخصية.',\n"
        "            style: Theme.of(context)\n"
        "                .textTheme\n"
        "                .bodyMedium\n"
        "                ?.copyWith(color: AyatColors.goldBright),\n"
        "          ),\n"
        "          const SizedBox(height: 8),\n"
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
        "        ],\n"
        "        const SizedBox(height: 10),\n"
    )
    new = (
        "        // PATCH_S32_AI_ART_NANO_BANANA\n"
        "        const Divider(height: 32, color: AyatColors.hairline),\n"
        "        ToggleRow(\n"
        "          label: 'فن الذكاء الاصطناعي لكل آية',\n"
        "          value: state.aiArtEnabled,\n"
        "          onChanged: (v) => state.update(() => state.aiArtEnabled = v),\n"
        "        ),\n"
        "        if (state.aiArtEnabled) ...[\n"
        "          const SizedBox(height: 6),\n"
        "          Text(\n"
        "            'تُنشأ خلفية بأسلوب خطوط متوهجة أحادية اللون لكل آية تُكتشف تلقائيًا، بلا وجوه بشرية أبدًا؛ إن ذُكر نبي في الآية يظهر عمود نور واسمه بخط عربي بدل أي شخصية.',\n"
        "            style: Theme.of(context)\n"
        "                .textTheme\n"
        "                .bodyMedium\n"
        "                ?.copyWith(color: AyatColors.goldBright),\n"
        "          ),\n"
        f"          // {MARKER}: Pollinations now requires a free API key for image\n"
        "          // generation -- get one at enter.pollinations.ai (publishable/pk_).\n"
        "          const SizedBox(height: 8),\n"
        "          TextField(\n"
        "            controller: TextEditingController(text: state.pollinationsApiKey)\n"
        "              ..selection = TextSelection.collapsed(\n"
        "                  offset: state.pollinationsApiKey.length),\n"
        "            style: const TextStyle(fontSize: 13),\n"
        "            decoration: const InputDecoration(\n"
        "              labelText: 'مفتاح Pollinations (pk_...)',\n"
        "              helperText: 'مجاني من enter.pollinations.ai -- مطلوب الآن لتوليد الفن',\n"
        "              helperMaxLines: 2,\n"
        "              isDense: true,\n"
        "            ),\n"
        "            onChanged: (v) => state.update(() {\n"
        "              state.pollinationsApiKey = v.trim();\n"
        "              AiArtService.apiKey = state.pollinationsApiKey;\n"
        "            }),\n"
        "          ),\n"
        "          const SizedBox(height: 8),\n"
        "          if (state.aiArtError != null)\n"
        "            Padding(\n"
        "              padding: const EdgeInsets.symmetric(vertical: 4),\n"
        "              child: Text(\n"
        "                state.aiArtError!,\n"
        "                style: Theme.of(context)\n"
        "                    .textTheme\n"
        "                    .bodySmall\n"
        "                    ?.copyWith(color: Colors.redAccent),\n"
        "              ),\n"
        "            ),\n"
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
        "          ] else\n"
        f"            // {MARKER}: previously nothing rendered here at all when no\n"
        "            // art existed yet -- this was the actual \"does nothing\" bug.\n"
        "            ElevatedButton.icon(\n"
        "              onPressed: () => state.generateAiArtNow(),\n"
        "              icon: const Icon(Icons.auto_awesome, size: 18),\n"
        "              label: const Text('توليد الآن'),\n"
        "            ),\n"
        "        ],\n"
        "        const SizedBox(height: 10),\n"
    )
    text = replace_once(text, old, new, "home_screen AI art section")

    if "ai_art_service.dart" not in text:
        text = replace_once(
            text,
            "import 'whisper_service.dart'; // PATCH_S47_SETTINGS_WHISPER_IMPORT_FIX: WhisperModelSize lives here\n",
            "import 'whisper_service.dart'; // PATCH_S47_SETTINGS_WHISPER_IMPORT_FIX: WhisperModelSize lives here\n"
            f"import '../services/ai_art_service.dart'; // {MARKER}: AiArtService.apiKey\n",
            "home_screen AiArtService import",
        )

    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    results = {
        "lib/services/ai_art_service.dart": patch_ai_art_service(project_dir),
        "lib/models/studio_state.dart": patch_studio_state(project_dir),
        "lib/services/settings_service.dart": patch_settings_service(project_dir),
        "lib/screens/home_screen.dart": patch_home_screen(project_dir),
    }
    for path, changed in results.items():
        print(f"{'OK: patched' if changed else 'SKIP: already applied'} {path}")

    print()
    print("IMPORTANT -- this alone will NOT make AI art work. Pollinations retired")
    print("free/keyless image generation; you need a free key:")
    print("  1. Sign up at https://enter.pollinations.ai")
    print("  2. Create a PUBLISHABLE key (pk_...) -- these are safe to embed in an app")
    print("  3. Open the app -> خلفيات tab -> enable AI art -> paste the pk_ key")
    print("     into the new 'مفتاح Pollinations' field")
    print()
    print("Next steps:")
    print("  git add lib/services/ai_art_service.dart lib/models/studio_state.dart \\")
    print("      lib/services/settings_service.dart lib/screens/home_screen.dart")
    print("  git commit -m 'S69: fix AI art -- manual generate button, real errors, Pollinations API key support'")
    print("  git push")
    print()
    print("HOW TO VERIFY: after adding your pk_ key, match/select any ayah, enable AI")
    print("art. If it doesn't auto-generate, tap 'توليد الآن' -- you should see either")
    print("real art or a clear red error message (never silence) within ~45s.")


if __name__ == "__main__":
    main()
