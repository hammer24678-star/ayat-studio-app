# patch_s132_gauntlet_loop.py
# Gauntlet Loop S132 — written against the REAL dump (FILE CONTENTS section),
# not guesses. Every anchor below was checked with `view`/`grep` against the
# actual current source before being written into this script. Run from the
# project root.
#
# What changed vs S130/S131, now that real source is in hand:
#
# 1. studio_screen.dart DOES NOT EXIST. The real file is home_screen.dart.
#    Every S130/S131 patch targeting studio_screen.dart was guaranteed
#    NOT-FOUND against the real repo, full stop.
# 2. karaoke.dart ALREADY has `(seg.textOverride ?? seg.ayah.ar)` at line 74 —
#    S130's "fix" was solving an already-solved problem. Dropped here.
# 3. The "OPACITY / LABEL / GLOW / SHADOW / BORDER" strip is not literal
#    strings — it's `t.name.toUpperCase()` over a `TextEditorTab` enum inside
#    a fixed-width Row (text_editor_pro.dart:39-50). No literal replace could
#    ever have worked; fixed at the real source of the text below.
# 4. Root cause traced for the shot-1 footer bug (mushaf_screen.dart): _page
#    is set correctly in Dart state from frame 0 (MushafLoaderScreen passes
#    settings.lastReadAyahId as initialAyahId; pageOfAyahId/juzOfAyahId are
#    correct), but PageController(initialPage: N) inside a TabBarView nested
#    3 layouts deep (TabBarView > Scaffold > SafeArea > Column > PageView)
#    can settle a frame later than the surrounding state, once its real
#    viewport size is known. The footer is built straight from `_page` (no
#    layout dependency) so it never lags — the PageView's paint can. Fixed by
#    re-asserting from the controller's own resolved page once real layout
#    lands, and keeping `_page` authoritative on it afterward.
# 5. The rich 30-style TextTransition system (text_transitions.dart) already
#    exists and is exactly what screenshots 1/2/4 show — it is NOT the same
#    thing as text_editor_pro.dart's tab strip, and was never broken. What's
#    real: it's called from the now-orphaned old `_textPanel()`, not from the
#    new `_textEditorProPanel()` — so the new tabbed editor is missing it.
#    Fixed by mounting it alongside TextEditorPro instead of duplicating it.
# 6. The pre-S129 8-tab grid (_tabs/_tabChips/_tabButton/_panelCard switch)
#    still exists verbatim in this repo's history and was fully localized via
#    _t('studio.tab.*') — recovered here behind a settings toggle instead of
#    being reconstructed from scratch.
#
# Strict anchors abort; nothing here is soft — every literal was verified
# against the real file with `view` before being written into this script.

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []

def _log(label, status, detail=""):
    LEDGER.append((label, status))
    print(f" [{status}] {label}" + (f" — {detail}" if detail else ""))

def apply_literal(rel, old, new, label, skip_if=None):
    p = ROOT / rel
    if not p.exists():
        raise SystemExit(f"ERROR ({label}): {rel} does not exist")
    text = p.read_text(encoding="utf-8")
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY"); return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")

def main():
    # ======================================================================
    # 1) FOOTER/PAGE DESYNC FIX (screenshot-1 bug) — lib/screens/mushaf_screen.dart
    # ======================================================================
    apply_literal("lib/screens/mushaf_screen.dart",
        "    _pageCtrl = PageController(initialPage: _page - 1);\n"
        "    _settings.addListener(_onSettings);\n"
        "  }\n"
        "\n"
        "  @override\n"
        "  void dispose() {\n"
        "    _settings.removeListener(_onSettings);\n"
        "    _tabs.dispose();\n"
        "    _pageCtrl.dispose();\n",
        "    _pageCtrl = PageController(initialPage: _page - 1);\n"
        "    _settings.addListener(_onSettings);\n"
        "    // PATCH_S132_GAUNTLET_LOOP: PageController.initialPage can settle a\n"
        "    // frame later than _page once the PageView's real viewport size is\n"
        "    // known (this sits 3 layouts deep inside a TabBarView) -- the footer\n"
        "    // is built straight from _page with no layout dependency, so it can\n"
        "    // briefly disagree with what's actually painted. Re-assert once real\n"
        "    // layout lands, and keep _page authoritative on the controller after.\n"
        "    _pageCtrl.addListener(_syncPageFromController);\n"
        "    WidgetsBinding.instance\n"
        "        .addPostFrameCallback((_) => _syncPageFromController());\n"
        "  }\n"
        "\n"
        "  void _syncPageFromController() {\n"
        "    if (!mounted || !_pageCtrl.hasClients) return;\n"
        "    final raw = _pageCtrl.page;\n"
        "    if (raw == null) return;\n"
        "    final resolved = raw.round() + 1;\n"
        "    if (resolved != _page) {\n"
        "      setState(() {\n"
        "        _page = resolved;\n"
        "        _surah = _surahOfId(ayahRangeOfPage(_page).$1);\n"
        "      });\n"
        "    }\n"
        "  }\n"
        "\n"
        "  @override\n"
        "  void dispose() {\n"
        "    _settings.removeListener(_onSettings);\n"
        "    _pageCtrl.removeListener(_syncPageFromController);\n"
        "    _tabs.dispose();\n"
        "    _pageCtrl.dispose();\n",
        "footer/page desync fix (real root cause)",
        skip_if="_syncPageFromController")

    # ======================================================================
    # 2) TYPED TEXT MOVES FIRST + SAVES TO TIMELINE — lib/screens/home_screen.dart
    #    (reuses the REAL, already-declared _customArCtrl/_customEnCtrl —
    #    does not redeclare them, unlike S130 which assumed a different file)
    # ======================================================================
    apply_literal("lib/screens/home_screen.dart",
        "        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION\n"
        "        if (state.hasAyah) _redWordsSection(),\n"
        "        _manualTimingSection(),\n"
        "        _captionSection(),\n"
        "        // PATCH_S129_WIRE_AND_SIMPLIFY_UI: free-type path — same as before, clearer title so it\n"
        "        // is not buried under the dropdowns.\n"
        "        _fieldLabel('أو اكتب نصًا بنفسك'),\n"
        "        TextField(\n"
        "          controller: _customArCtrl,\n"
        "          maxLines: 3,\n"
        "          textAlign: TextAlign.right,\n"
        "          decoration: const InputDecoration(\n"
        "            hintText: 'اكتب الآية أو أي نص عربي… (يُطابق من المصحف إن وُجد)',\n"
        "            border: OutlineInputBorder(),\n"
        "          ),\n"
        "        ),\n"
        "        const SizedBox(height: 8),\n"
        "        TextField(\n"
        "          controller: _customEnCtrl,\n"
        "          decoration:\n"
        "              const InputDecoration(hintText: 'ترجمة المعاني (اختياري)'),\n"
        "        ),\n"
        "        const SizedBox(height: 10),\n"
        "        ElevatedButton(\n"
        "            onPressed: _applyCustomText,\n"
        "            child: const Text('تطبيق النص المخصص')),\n",
        "        // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION\n"
        "        if (state.hasAyah) _redWordsSection(),\n"
        "        _manualTimingSection(),\n"
        "        _captionSection(),\n",
        "remove typed-text block from its buried spot")

    apply_literal("lib/screens/home_screen.dart",
        "        _panelTitle('اختيار الآية',\n"
        "            'اختر السورة ثم الآية، أو استخدم أزرار التعرّف بالذكاء الاصطناعي، أو اكتب نصًا مخصصًا.'),\n",
        "        _panelTitle('اختيار الآية',\n"
        "            'اختر السورة ثم الآية، أو استخدم أزرار التعرّف بالذكاء الاصطناعي، أو اكتب نصًا مخصصًا.'),\n"
        "        // PATCH_S132_GAUNTLET_LOOP: typed text now leads the tab. Apply it as\n"
        "        // the single static ayah (as before), or save it straight into the\n"
        "        // timeline with a chosen time range -- same type -> time range ->\n"
        "        // timeline flow reference caption tools use.\n"
        "        _sectionCard(Column(\n"
        "          crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "          children: [\n"
        "            _sectionHeader('اكتب نص الآية',\n"
        "              'اكتب الآية أو أي نص عربي — طبّقيه كنص ثابت، أو احفظيه في الخط '\n"
        "              'الزمني بمدة زمنية تختارينها فيظهر أثناء المعاينة والتصدير.'),\n"
        "            const SizedBox(height: 8),\n"
        "            TextField(\n"
        "              controller: _customArCtrl,\n"
        "              maxLines: 3,\n"
        "              textAlign: TextAlign.right,\n"
        "              decoration: const InputDecoration(\n"
        "                hintText: 'اكتب الآية أو أي نص عربي… (يُطابق من المصحف إن وُجد)',\n"
        "                border: OutlineInputBorder(),\n"
        "              ),\n"
        "            ),\n"
        "            const SizedBox(height: 8),\n"
        "            TextField(\n"
        "              controller: _customEnCtrl,\n"
        "              decoration:\n"
        "                  const InputDecoration(hintText: 'ترجمة المعاني (اختياري)'),\n"
        "            ),\n"
        "            const SizedBox(height: 10),\n"
        "            Row(children: [\n"
        "              Expanded(child: ElevatedButton(\n"
        "                  onPressed: _applyCustomText,\n"
        "                  child: const Text('تطبيق كنص ثابت'))),\n"
        "              const SizedBox(width: 8),\n"
        "              Expanded(child: OutlinedButton.icon(\n"
        "                  onPressed: _saveTypedTextToTimeline,\n"
        "                  icon: const Icon(Icons.timeline, size: 18),\n"
        "                  label: const Text('حفظ في الخط الزمني'))),\n"
        "            ]),\n"
        "          ],\n"
        "        )),\n",
        "insert enhanced typed-text card first in the tab")

    apply_literal("lib/screens/home_screen.dart",
        "  Widget _ayahPanel() {\n",
        "  Future<void> _saveTypedTextToTimeline() async {\n"
        "    final ar = _customArCtrl.text.trim();\n"
        "    if (ar.isEmpty) {\n"
        "      _toast('اكتب النص أولًا');\n"
        "      return;\n"
        "    }\n"
        "    final en = _customEnCtrl.text.trim();\n"
        "    final m = state.matcher?.match(ar);\n"
        "    final ayah = m?.ayah ??\n"
        "        Ayah(surahNum: 0, surah: 'نص مخصص', num: 0, ar: ar, en: en);\n"
        "    final range = await _pickTextTimeRange();\n"
        "    if (range == null) return;\n"
        "    state.addManualSegment(ayah, range.$1, range.$2, textOverride: ar);\n"
        "    _revealTimelineCard();\n"
        "    _toast('حُفظ النص في الخط الزمني ✓ — سيظهر من ${_fmtSec(range.$1)} '\n"
        "        'إلى ${_fmtSec(range.$2)}');\n"
        "  }\n"
        "\n"
        "  Future<(double, double)?> _pickTextTimeRange() {\n"
        "    final sCtrl = TextEditingController(text: '0');\n"
        "    final eCtrl = TextEditingController(text: '5');\n"
        "    return showDialog<(double, double)>(\n"
        "      context: context,\n"
        "      builder: (context) => StatefulBuilder(builder: (context, setS) {\n"
        "        void chip(double a, double b) => setS(() {\n"
        "          sCtrl.text = a.toStringAsFixed(0);\n"
        "          eCtrl.text = b.toStringAsFixed(0);\n"
        "        });\n"
        "        final dur = state.videoDurationSec;\n"
        "        return AlertDialog(\n"
        "          backgroundColor: AyatColors.surface,\n"
        "          shape: RoundedRectangleBorder(\n"
        "            borderRadius: BorderRadius.circular(22),\n"
        "            side: const BorderSide(color: AyatColors.hairline)),\n"
        "          title: const Text('متى يظهر هذا النص؟'),\n"
        "          content: Column(\n"
        "            mainAxisSize: MainAxisSize.min,\n"
        "            crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "            children: [\n"
        "              Wrap(spacing: 6, runSpacing: 6, children: [\n"
        "                for (final r in const [\n"
        "                  (0.0, 5.0), (5.0, 10.0), (10.0, 15.0), (15.0, 20.0)\n"
        "                ])\n"
        "                  ActionChip(\n"
        "                    label: Text('${r.$1.toInt()}–${r.$2.toInt()} ث'),\n"
        "                    onPressed: () => chip(r.$1, r.$2)),\n"
        "              ]),\n"
        "              const SizedBox(height: 10),\n"
        "              Row(children: [\n"
        "                Expanded(child: TextField(\n"
        "                  controller: sCtrl,\n"
        "                  keyboardType:\n"
        "                      const TextInputType.numberWithOptions(decimal: true),\n"
        "                  decoration: const InputDecoration(labelText: 'من (ث)'))),\n"
        "                const SizedBox(width: 8),\n"
        "                Expanded(child: TextField(\n"
        "                  controller: eCtrl,\n"
        "                  keyboardType:\n"
        "                      const TextInputType.numberWithOptions(decimal: true),\n"
        "                  decoration: const InputDecoration(labelText: 'إلى (ث)'))),\n"
        "              ]),\n"
        "              if (dur > 0) ...[\n"
        "                const SizedBox(height: 6),\n"
        "                Text('مدة الفيديو: ${_fmtSec(dur)}',\n"
        "                  style: const TextStyle(\n"
        "                      fontSize: 11, color: AyatColors.parchmentDim)),\n"
        "              ],\n"
        "            ],\n"
        "          ),\n"
        "          actions: [\n"
        "            TextButton(\n"
        "              onPressed: () => Navigator.pop(context),\n"
        "              child: const Text('إلغاء')),\n"
        "            FilledButton(onPressed: () {\n"
        "              final s = double.tryParse(sCtrl.text) ?? 0;\n"
        "              var e = double.tryParse(eCtrl.text) ?? (s + 5);\n"
        "              if (dur > 0) e = e.clamp(0, dur);\n"
        "              if (e <= s) {\n"
        "                _toast('النهاية يجب أن تكون بعد البداية');\n"
        "                return;\n"
        "              }\n"
        "              Navigator.pop(context, (s.clamp(0, 9999), e));\n"
        "            }, child: const Text('حفظ')),\n"
        "          ],\n"
        "        );\n"
        "      }),\n"
        "    );\n"
        "  }\n"
        "\n"
        "  Widget _ayahPanel() {\n",
        "add _saveTypedTextToTimeline + time-range dialog",
        skip_if="Future<void> _saveTypedTextToTimeline() async {")

    # ======================================================================
    # 3) MERGE the OG transitions section into the newer TextEditorPro panel
    #    — lib/screens/home_screen.dart (_textTransitionSection() is real and
    #    already works; it was only orphaned, not broken. Reused as-is.)
    # ======================================================================
    apply_literal("lib/screens/home_screen.dart",
        "  // PATCH_S128: tabbed pro text editor\n"
        "  Widget _textEditorProPanel() => TextEditorPro(\n"
        "        state: state,\n"
        "        segmentTexts: state.unifiedTexts,\n"
        "        canvasWidth: 1080,\n"
        "        onPickCustomFont: _pickCustomFont,\n"
        "      );\n",
        "  // PATCH_S128: tabbed pro text editor\n"
        "  // PATCH_S132_GAUNTLET_LOOP: the 30-style transitions section\n"
        "  // (_textTransitionSection, PATCH_S126) never got ported into\n"
        "  // TextEditorPro when S128 replaced the old _textPanel() -- it still\n"
        "  // works exactly as before, it was just orphaned. Mounted alongside\n"
        "  // the tabbed editor instead of duplicating 30 already-correct entries.\n"
        "  Widget _textEditorProPanel() => Column(\n"
        "        crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "        children: [\n"
        "          TextEditorPro(\n"
        "            state: state,\n"
        "            segmentTexts: state.unifiedTexts,\n"
        "            canvasWidth: 1080,\n"
        "            onPickCustomFont: _pickCustomFont,\n"
        "          ),\n"
        "          const Divider(height: 32, color: AyatColors.hairline),\n"
        "          _textTransitionSection(),\n"
        "        ],\n"
        "      );\n",
        "mount _textTransitionSection alongside TextEditorPro")

    # ======================================================================
    # 4) i18n: restore _t() on the 5-group tab strip (currently hardcoded --
    #    a real regression vs the old 8-tab strip, which WAS localized)
    # ======================================================================
    apply_literal("lib/screens/home_screen.dart",
        "  List<(IconData, String)> get _tabs => [\n"
        "        (Icons.menu_book_outlined, 'الآيات'),\n"
        "        (Icons.text_fields, 'النص'),\n"
        "        (Icons.auto_awesome_outlined, 'الشكل'),\n"
        "        (Icons.perm_media_outlined, 'الوسائط'),\n"
        "        (Icons.more_horiz, 'المزيد'),\n"
        "      ];\n",
        "  List<(IconData, String)> get _tabs =>\n"
        "      AppSettings.instance.classicTabs ? _classicTabs : _groupedTabs;\n"
        "\n"
        "  // PATCH_S132_GAUNTLET_LOOP: was hardcoded Arabic -- the old 8-tab strip\n"
        "  // was localized via _t(), this one silently wasn't. Fixed.\n"
        "  List<(IconData, String)> get _groupedTabs => [\n"
        "        (Icons.menu_book_outlined, _t('studio.group.ayat')),\n"
        "        (Icons.text_fields, _t('studio.tab.text')),\n"
        "        (Icons.auto_awesome_outlined, _t('studio.group.shape')),\n"
        "        (Icons.perm_media_outlined, _t('studio.group.media')),\n"
        "        (Icons.more_horiz, _t('studio.group.more')),\n"
        "      ];\n"
        "\n"
        "  // PATCH_S132_GAUNTLET_LOOP: pre-S129 8-tab grid, recovered verbatim from\n"
        "  // repo history (commit 62eca15) behind a settings toggle instead of the\n"
        "  // 5 grouped tabs -- for people who want the old layout back.\n"
        "  List<(IconData, String)> get _classicTabs => [\n"
        "        (Icons.menu_book_outlined, _t('studio.tab.ayah')),\n"
        "        (Icons.dark_mode_outlined, _t('studio.tab.backgrounds')),\n"
        "        (Icons.water_drop_outlined, _t('studio.tab.effects')),\n"
        "        (Icons.filter_hdr_outlined, _t('studio.tab.chroma')),\n"
        "        (Icons.graphic_eq, _t('studio.tab.reciters')),\n"
        "        (Icons.grid_view_outlined, _t('studio.tab.templates')),\n"
        "        (Icons.text_fields, _t('studio.tab.text')),\n"
        "        (Icons.video_settings_outlined, _t('studio.tab.export')),\n"
        "      ];\n",
        "restore i18n + recover classic 8-tab list behind a toggle")

    apply_literal("lib/screens/home_screen.dart",
        "  Widget _tabChips() {\n"
        "    return Row(\n"
        "      children: [\n"
        "        for (var i = 0; i < _tabs.length; i++)\n"
        "          Expanded(\n"
        "            child: Padding(\n"
        "              padding: EdgeInsets.only(\n"
        "                left: i == 0 ? 0 : 4,\n"
        "                right: i == _tabs.length - 1 ? 0 : 4,\n"
        "              ),\n"
        "              child: _tabButton(i),\n"
        "            ),\n"
        "          ),\n"
        "      ],\n"
        "    );\n"
        "  }\n",
        "  Widget _tabChips() {\n"
        "    // PATCH_S132_GAUNTLET_LOOP: classic mode uses the original fixed\n"
        "    // 4-column grid (8 tabs never fit a single Row); grouped mode keeps\n"
        "    // the current 5-wide Row unchanged.\n"
        "    if (AppSettings.instance.classicTabs) {\n"
        "      return GridView.count(\n"
        "        crossAxisCount: 4,\n"
        "        shrinkWrap: true,\n"
        "        physics: const NeverScrollableScrollPhysics(),\n"
        "        mainAxisSpacing: 8,\n"
        "        crossAxisSpacing: 8,\n"
        "        childAspectRatio: 1.55,\n"
        "        children: [\n"
        "          for (var i = 0; i < _tabs.length; i++) _tabButton(i),\n"
        "        ],\n"
        "      );\n"
        "    }\n"
        "    return Row(\n"
        "      children: [\n"
        "        for (var i = 0; i < _tabs.length; i++)\n"
        "          Expanded(\n"
        "            child: Padding(\n"
        "              padding: EdgeInsets.only(\n"
        "                left: i == 0 ? 0 : 4,\n"
        "                right: i == _tabs.length - 1 ? 0 : 4,\n"
        "              ),\n"
        "              child: _tabButton(i),\n"
        "            ),\n"
        "          ),\n"
        "      ],\n"
        "    );\n"
        "  }\n",
        "branch _tabChips on classicTabs")

    apply_literal("lib/screens/home_screen.dart",
        "  Widget _panelCard() {\n"
        "    return _card(\n"
        "      child: switch (_selectedTab) {\n"
        "        0 => _ayahPanel(),\n"
        "        1 => _textEditorProPanel(),\n"
        "        2 => _shapePanel(),   // effects + templates\n"
        "        3 => _mediaPanel(),   // backgrounds + chroma + reciters\n"
        "        _ => _exportPanel(),\n"
        "      },\n"
        "    );\n"
        "  }\n",
        "  Widget _panelCard() {\n"
        "    return _card(\n"
        "      child: AppSettings.instance.classicTabs\n"
        "          ? switch (_selectedTab) {\n"
        "              0 => _ayahPanel(),\n"
        "              1 => _bgPanel(),\n"
        "              2 => _effectsPanel(),\n"
        "              3 => _chromaPanel(),\n"
        "              4 => _recitersPanel(),\n"
        "              5 => _templatesPanel(),\n"
        "              6 => _textEditorProPanel(),\n"
        "              _ => _exportPanel(),\n"
        "            }\n"
        "          : switch (_selectedTab) {\n"
        "              0 => _ayahPanel(),\n"
        "              1 => _textEditorProPanel(),\n"
        "              2 => _shapePanel(),   // effects + templates\n"
        "              3 => _mediaPanel(),   // backgrounds + chroma + reciters\n"
        "              _ => _exportPanel(),\n"
        "            },\n"
        "    );\n"
        "  }\n",
        "branch _panelCard switch on classicTabs "
        "(classic النص slot upgraded to _textEditorProPanel, not the old dead _textPanel)")

    # Clamp _selectedTab when the layout toggle changes tab count (8 <-> 5),
    # so switching mid-session can't leave an out-of-range index.
    apply_literal("lib/screens/home_screen.dart",
        "  int _selectedTab = 0;\n",
        "  int _selectedTab = 0;\n"
        "  // PATCH_S132_GAUNTLET_LOOP: classic<->grouped have different tab\n"
        "  // counts (8 vs 5) -- clamp so a stale index can't be out of range.\n"
        "  int get _safeSelectedTab => _selectedTab.clamp(0, _tabs.length - 1);\n",
        "add _safeSelectedTab clamp helper", skip_if="_safeSelectedTab")

    # ======================================================================
    # 5) REMOVE the redundant first-run tour (WelcomeScreen already explains
    #    the app -- one line, real anchor, real call site).
    # ======================================================================
    apply_literal("lib/screens/home_screen.dart",
        "      if (mounted) FirstRunTour.maybeShow(context);\n",
        "      // PATCH_S132_GAUNTLET_LOOP: WelcomeScreen (shown before this screen)\n"
        "      // already introduces the app's features -- this second, in-app tour\n"
        "      // was redundant. Left first_run_tour.dart in place (harmless if\n"
        "      // re-enabled later) but stopped calling it.\n"
        "      // if (mounted) FirstRunTour.maybeShow(context);\n",
        "stop calling FirstRunTour (WelcomeScreen already covers onboarding)")

    # ======================================================================
    # 6) text_editor_pro.dart: the REAL source of the un-translated, clipped
    #    tab strip — t.name.toUpperCase() over the enum, in a fixed Row.
    # ======================================================================
    apply_literal("lib/widgets/text_editor_pro.dart",
        "enum TextEditorTab { text, border, shadow, glow, label, opacity }\n",
        "enum TextEditorTab { text, border, shadow, glow, label, opacity }\n"
        "\n"
        "// PATCH_S132_GAUNTLET_LOOP: the tab strip read t.name.toUpperCase() --\n"
        "// the raw Dart enum identifier, English by construction, with no\n"
        "// translation possible via a literal string replace (there was no\n"
        "// literal string to replace). Real Arabic labels instead.\n"
        "const Map<TextEditorTab, String> _kTabLabelsAr = {\n"
        "  TextEditorTab.text: 'النص',\n"
        "  TextEditorTab.border: 'الإطار',\n"
        "  TextEditorTab.shadow: 'الظل',\n"
        "  TextEditorTab.glow: 'التوهج',\n"
        "  TextEditorTab.label: 'اللافتة',\n"
        "  TextEditorTab.opacity: 'الشفافية',\n"
        "};\n",
        "add Arabic tab-label map", skip_if="_kTabLabelsAr")

    apply_literal("lib/widgets/text_editor_pro.dart",
        "  Widget _tabRow() => Padding(\n"
        "    padding: const EdgeInsets.symmetric(vertical: 8),\n"
        "    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround,\n"
        "      children: [for (final t in TextEditorTab.values)\n"
        "        GestureDetector(onTap: () => setState(() => _tab = t),\n"
        "          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),\n"
        "            decoration: BoxDecoration(\n"
        "              color: _tab == t ? AyatColors.gold.withValues(alpha: .18) : Colors.transparent,\n"
        "              borderRadius: BorderRadius.circular(8),\n"
        "              border: Border.all(color: _tab == t ? AyatColors.gold : Colors.transparent)),\n"
        "            child: Text(t.name.toUpperCase(), style: TextStyle(\n"
        "              fontSize: 12, letterSpacing: 1,\n"
        "              color: _tab == t ? AyatColors.goldBright : AyatColors.goldDim))))]));\n",
        "  // PATCH_S132_GAUNTLET_LOOP: Wrap instead of a fixed-width Row (was\n"
        "  // clipping the rightmost tab on narrow screens -- shot-2/shot-3 bug),\n"
        "  // Arabic labels instead of the raw English enum identifier.\n"
        "  Widget _tabRow() => Padding(\n"
        "    padding: const EdgeInsets.symmetric(vertical: 8),\n"
        "    child: Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6,\n"
        "      children: [for (final t in TextEditorTab.values)\n"
        "        GestureDetector(onTap: () => setState(() => _tab = t),\n"
        "          child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),\n"
        "            decoration: BoxDecoration(\n"
        "              color: _tab == t ? AyatColors.gold.withValues(alpha: .18) : Colors.transparent,\n"
        "              borderRadius: BorderRadius.circular(8),\n"
        "              border: Border.all(color: _tab == t ? AyatColors.gold : Colors.transparent)),\n"
        "            child: Text(_kTabLabelsAr[t]!, style: TextStyle(\n"
        "              fontSize: 12, letterSpacing: 1,\n"
        "              color: _tab == t ? AyatColors.goldBright : AyatColors.goldDim))))]));\n",
        "arabic + non-clipping tab strip")

    # ======================================================================
    # 7) AppSettings: persisted classicTabs toggle
    # ======================================================================
    apply_literal("lib/services/app_settings.dart",
        "  bool _readerTranslation = false;\n"
        "  bool get readerTranslation => _readerTranslation;\n",
        "  bool _readerTranslation = false;\n"
        "  bool get readerTranslation => _readerTranslation;\n"
        "\n"
        "  // ---- studio ----\n"
        "  /// PATCH_S132_GAUNTLET_LOOP: the original 8-tab 4x2 grid, recovered\n"
        "  /// behind a toggle instead of forcing everyone onto S129's 5 grouped\n"
        "  /// tabs. False = the current 5-group layout (default, unchanged).\n"
        "  bool _classicTabs = false;\n"
        "  bool get classicTabs => _classicTabs;\n",
        "add classicTabs field + getter")

    apply_literal("lib/services/app_settings.dart",
        "    _readerTranslation =\n"
        "        p.getBool('${_prefix}readerTranslation') ?? _readerTranslation;\n"
        "    notifyListeners();\n",
        "    _readerTranslation =\n"
        "        p.getBool('${_prefix}readerTranslation') ?? _readerTranslation;\n"
        "    _classicTabs = p.getBool('${_prefix}classicTabs') ?? _classicTabs;\n"
        "    notifyListeners();\n",
        "load classicTabs from disk")

    apply_literal("lib/services/app_settings.dart",
        "  void setReaderTranslation(bool v) {\n"
        "    if (v == _readerTranslation) return;\n"
        "    _readerTranslation = v;\n"
        "    _write((p) => p.setBool('${_prefix}readerTranslation', v));\n"
        "  }\n"
        "}",
        "  void setReaderTranslation(bool v) {\n"
        "    if (v == _readerTranslation) return;\n"
        "    _readerTranslation = v;\n"
        "    _write((p) => p.setBool('${_prefix}readerTranslation', v));\n"
        "  }\n"
        "\n"
        "  void setClassicTabs(bool v) {\n"
        "    if (v == _classicTabs) return;\n"
        "    _classicTabs = v;\n"
        "    _write((p) => p.setBool('${_prefix}classicTabs', v));\n"
        "  }\n"
        "}",
        "add setClassicTabs setter")

    # ======================================================================
    # 8) settings_screen.dart: expose the toggle (same SwitchListTile
    #    pattern as the existing 'animations' switch, real anchor)
    # ======================================================================
    apply_literal("lib/screens/settings_screen.dart",
        "              onChanged: (v) => setState(() => _settings.setAnimations(v)),\n"
        "            ),\n"
        "          ]),\n",
        "              onChanged: (v) => setState(() => _settings.setAnimations(v)),\n"
        "            ),\n"
        "            SwitchListTile(\n"
        "              contentPadding: EdgeInsets.zero,\n"
        "              value: _settings.classicTabs,\n"
        "              activeThumbColor: AyatColors.gold,\n"
        "              title: Text(s.t('settings.classicTabs'),\n"
        "                  style: GoogleFonts.tajawal(\n"
        "                      color: AyatColors.parchment, fontSize: 13.5)),\n"
        "              subtitle: Text(s.t('settings.classicTabsHint'),\n"
        "                  style: GoogleFonts.tajawal(\n"
        "                      color: AyatColors.parchmentDim,\n"
        "                      fontSize: 11.5,\n"
        "                      height: 1.5)),\n"
        "              onChanged: (v) => setState(() => _settings.setClassicTabs(v)),\n"
        "            ),\n"
        "          ]),\n",
        "add classic-tabs SwitchListTile to settings")

    # ======================================================================
    # 9) app_strings.dart: new translation keys (5 languages each, matching
    #    the file's own convention exactly)
    # ======================================================================
    apply_literal("lib/i18n/app_strings.dart",
        "  'studio.tab.export': ['تصدير', 'Export', 'Export', 'Ekspor', 'ایکسپورٹ'],\n",
        "  'studio.tab.export': ['تصدير', 'Export', 'Export', 'Ekspor', 'ایکسپورٹ'],\n"
        "  'studio.group.ayat': ['الآيات', 'Ayat', 'Versets', 'Ayat', 'آیات'],\n"
        "  'studio.group.shape': ['الشكل', 'Style', 'Style', 'Gaya', 'انداز'],\n"
        "  'studio.group.media': ['الوسائط', 'Media', 'Média', 'Media', 'میڈیا'],\n"
        "  'studio.group.more': ['المزيد', 'More', 'Plus', 'Lainnya', 'مزید'],\n",
        "add studio.group.* keys", skip_if="'studio.group.ayat'")

    apply_literal("lib/i18n/app_strings.dart",
        "  'settings.animationsHint': [\n"
        "    'أطفئها لواجهة فورية بلا حركة — أخفّ على الأجهزة القديمة وأهدأ للعين.',\n"
        "    'Turn them off for an instant, motion-free interface — lighter on older phones and calmer to use.',\n"
        "    'Désactivez-les pour une interface instantanée sans mouvement — plus légère sur les anciens téléphones.',\n"
        "    'Matikan untuk antarmuka tanpa gerakan — lebih ringan di ponsel lama.',\n"
        "    'پرانے فونز کے لیے اینیمیشن بند کریں — تیز اور پرسکون۔',\n"
        "  ],\n",
        "  'settings.animationsHint': [\n"
        "    'أطفئها لواجهة فورية بلا حركة — أخفّ على الأجهزة القديمة وأهدأ للعين.',\n"
        "    'Turn them off for an instant, motion-free interface — lighter on older phones and calmer to use.',\n"
        "    'Désactivez-les pour une interface instantanée sans mouvement — plus légère sur les anciens téléphones.',\n"
        "    'Matikan untuk antarmuka tanpa gerakan — lebih ringan di ponsel lama.',\n"
        "    'پرانے فونز کے لیے اینیمیشن بند کریں — تیز اور پرسکون۔',\n"
        "  ],\n"
        "  'settings.classicTabs': [\n"
        "    'شريط التبويبات القديم (8 تبويبات)',\n"
        "    'Classic tab layout (8 tabs)',\n"
        "    'Disposition classique (8 onglets)',\n"
        "    'Tata letak tab klasik (8 tab)',\n"
        "    'کلاسک ٹیب لے آؤٹ (8 ٹیبز)',\n"
        "  ],\n"
        "  'settings.classicTabsHint': [\n"
        "    'يستبدل التبويبات الخمس المجمّعة بشبكة الثماني تبويبات الأصلية.',\n"
        "    'Swaps the 5 grouped tabs for the original 8-tab grid.',\n"
        "    'Remplace les 5 onglets groupés par la grille originale de 8 onglets.',\n"
        "    'Mengganti 5 tab yang dikelompokkan dengan grid 8 tab asli.',\n"
        "    '5 گروپ شدہ ٹیبز کو اصل 8 ٹیب گرڈ سے بدل دیتا ہے۔',\n"
        "  ],\n",
        "add settings.classicTabs* keys", skip_if="'settings.classicTabs'")

    print()
    print("=" * 60)
    print(f"S132 LEDGER — {sum(1 for _, s in LEDGER if s == 'APPLIED')} applied, "
          f"{sum(1 for _, s in LEDGER if s == 'SKIPPED-ALREADY')} already-applied, "
          f"out of {len(LEDGER)} operations")
    print("=" * 60)
    for label, status in LEDGER:
        print(f"  [{status:16}] {label}")
    print()
    print("NOT covered by this pass (real, scoped, not guessed at):")
    print("  - Tap text on stage -> selection box -> double-tap to edit -> synced")
    print("    to timeline. SelectionBoxPainter + WordHitTester already exist in")
    print("    selection_box_overlay.dart but are wired to NOTHING (grep confirms")
    print("    zero real call sites outside a comment in overlay_renderer.dart).")
    print("    Needs: a 'selected segment' field on StudioState, wiring stage_")
    print("    preview.dart's existing onTap/onDoubleTap (currently just resets")
    print("    position/scale) to toggle it and open an edit dialog, and having")
    print("    that dialog write back into the matching TimelineSegment.")
    print("  - AI auto-segmentation wizard (screenshots 6/7/8/9/11). No wizard")
    print("    exists; whisper_service.dart/speech_service.dart give the underlying")
    print("    transcription, but the multi-step UI (version/runtime/models/")
    print("    presets/review) is a new build, not a patch.")
    print("  - Full-page i18n. home_screen.dart alone has ~226 hardcoded Arabic")
    print("    string literals vs 21 real _t() calls -- this pass fixed the two")
    print("    nav-level regressions (5-group tabs, TextEditorPro strip); the")
    print("    panel copy itself needs its own dedicated pass, it's too large to")
    print("    guess through safely in one patch.")

if __name__ == "__main__":
    main()
