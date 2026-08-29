# patch_s136_surah_tap_and_wizard_width.py
#
# Two independent fixes:
#
# 1) lib/screens/mushaf_screen.dart -- tapping a surah in the "السور" tab
#    (or any _goToAyah() caller) could leave the on-screen surah header
#    showing an earlier surah while the footer already said the target
#    page/surah. Normal swiping never showed this -- only programmatic
#    jumps did.
#
#    Root cause: the header is built per-page straight from the PageView's
#    own index (itemBuilder: (context, i) => _MushafPageBody(page: i + 1,
#    ...)) -- it reflects whatever page is ACTUALLY painted, nothing else.
#    The footer, by contrast, is built from the `_page` state field.
#    Everywhere else in this file (`_stepPage`), `_page`/`_surah` are left
#    alone and only ever updated from PageView's own `onPageChanged` once
#    the view has genuinely moved -- that's why paging works. `_goToAyah`
#    was the one place that broke this pattern: it set `_page`/`_surah`
#    eagerly, before the PageView had actually moved there, so the footer
#    raced ahead of what was on screen. On top of that, S132 added a
#    persistent `_pageCtrl` listener (`_syncPageFromController`) that
#    fired on every in-flight frame of the animated jump and kept
#    overwriting `_page`/`_surah` with the controller's transient,
#    not-yet-settled position -- fighting the very animation `_goToAyah`
#    had just started.
#
#    Fix: bring `_goToAyah` in line with `_stepPage`'s already-working
#    pattern -- let `onPageChanged` be the single source of truth for
#    `_page`/`_surah` in paged mode (whole-surah scroll mode has no
#    PageView, so it still sets them directly, same as before). Demote
#    `_syncPageFromController` back to the one-shot first-frame
#    correction it was originally meant to be, instead of an ongoing
#    listener.
#
# 2) lib/widgets/autoseg_wizard.dart -- the wizard dialog's step body used
#    a hardcoded `SizedBox(width: 220)` for the left-hand step rail,
#    sized for its `ConstrainedBox(maxWidth: 860)` desktop-ish frame. On
#    an actual phone the dialog is nowhere near 860 wide, so that fixed
#    220 ate nearly the whole available width and squeezed the step body
#    -- title/description text, including English strings like "Legacy
#    V1" -- into a sliver so narrow it wrapped one glyph per line.
#
#    Fix: wrap the step area in a LayoutBuilder. Below 560 logical px,
#    stack instead of splitting side by side -- audio status card, a
#    horizontally scrollable strip of step chips, then the step body at
#    full width. Above that width, keep the original side-by-side layout
#    unchanged.
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
    if skip_if and skip_if in text:
        _log(label, "SKIPPED-ALREADY")
        return
    n = text.count(old)
    if n != 1:
        raise SystemExit(f"ERROR ({label}): expected 1 match, found {n} in {rel_path} "
                          f"-- refusing to guess, no changes made.")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")
    _log(label, "APPLIED")


MUSHAF = "lib/screens/mushaf_screen.dart"
WIZARD = "lib/widgets/autoseg_wizard.dart"


def main():
    # -----------------------------------------------------------------
    # 1a) initState: stop listening to _pageCtrl forever -- keep only
    #     the original one-shot first-frame correction.
    # -----------------------------------------------------------------
    apply_literal(
        MUSHAF,
        "    // PATCH_S132_GAUNTLET_LOOP: PageController.initialPage can settle a\n"
        "    // frame later than _page once the PageView's real viewport size is\n"
        "    // known (this sits 3 layouts deep inside a TabBarView) -- the footer\n"
        "    // is built straight from _page with no layout dependency, so it can\n"
        "    // briefly disagree with what's actually painted. Re-assert once real\n"
        "    // layout lands, and keep _page authoritative on the controller after.\n"
        "    _pageCtrl.addListener(_syncPageFromController);\n"
        "    WidgetsBinding.instance\n"
        "        .addPostFrameCallback((_) => _syncPageFromController());\n"
        "  }\n",
        "    // PATCH_S132_GAUNTLET_LOOP: PageController.initialPage can settle a\n"
        "    // frame later than _page once the PageView's real viewport size is\n"
        "    // known (this sits 3 layouts deep inside a TabBarView) -- the footer\n"
        "    // is built straight from _page with no layout dependency, so it can\n"
        "    // briefly disagree with what's actually painted. Re-assert once real\n"
        "    // layout lands.\n"
        "    // PATCH_S136_SURAH_TAP_HEADER_FOOTER_DESYNC: one-shot only -- do NOT\n"
        "    // keep listening. An ongoing listener here fought _goToAyah's\n"
        "    // animated jump, repeatedly overwriting _page/_surah mid-flight with\n"
        "    // the controller's transient, not-yet-settled position. That's how\n"
        "    // tapping a surah could leave the header on the previous surah while\n"
        "    // the footer already showed the target page.\n"
        "    WidgetsBinding.instance\n"
        "        .addPostFrameCallback((_) => _syncPageFromController());\n"
        "  }\n",
        "mushaf_screen.dart: initState -- make the controller sync one-shot, not persistent",
        skip_if="PATCH_S136_SURAH_TAP_HEADER_FOOTER_DESYNC",
    )

    # -----------------------------------------------------------------
    # 1b) dispose(): drop the now-nonexistent listener removal.
    # -----------------------------------------------------------------
    apply_literal(
        MUSHAF,
        "    _settings.removeListener(_onSettings);\n"
        "    _pageCtrl.removeListener(_syncPageFromController);\n"
        "    _tabs.dispose();\n",
        "    _settings.removeListener(_onSettings);\n"
        "    _tabs.dispose();\n",
        "mushaf_screen.dart: dispose -- drop removeListener for the retired persistent listener",
        skip_if="_settings.removeListener(_onSettings);\n    _tabs.dispose();",
    )

    # -----------------------------------------------------------------
    # 1c) _goToAyah: let onPageChanged own _page/_surah in paged mode,
    #     same pattern _stepPage already uses successfully. Whole-surah
    #     mode has no PageView/onPageChanged, so it still sets them
    #     directly.
    # -----------------------------------------------------------------
    apply_literal(
        MUSHAF,
        "  void _goToAyah(int globalId, {bool select = true}) {\n"
        "    if (globalId < 1 || globalId > kTotalAyat) return;\n"
        "    setState(() {\n"
        "      if (select) _selectedAyahId = globalId;\n"
        "      _page = pageOfAyahId(globalId);\n"
        "      _surah = _surahOfId(globalId);\n"
        "    });\n"
        "    _settings.setLastReadAyahId(globalId);\n"
        "    _tabs.animateTo(1);\n"
        "    // The PageView may not be attached yet on the very first frame after a\n"
        "    // tab switch — jump once it is.\n"
        "    WidgetsBinding.instance.addPostFrameCallback((_) {\n"
        "      if (!mounted || !_pageCtrl.hasClients) return;\n"
        "      if (AppMotion.on) {\n"
        "        _pageCtrl.animateToPage(_page - 1,\n"
        "            duration: AppMotion.medium, curve: Curves.easeOutCubic);\n"
        "      } else {\n"
        "        _pageCtrl.jumpToPage(_page - 1);\n"
        "      }\n"
        "    });\n"
        "  }\n",
        "  void _goToAyah(int globalId, {bool select = true}) {\n"
        "    if (globalId < 1 || globalId > kTotalAyat) return;\n"
        "    final targetPage = pageOfAyahId(globalId);\n"
        "    // PATCH_S136_SURAH_TAP_HEADER_FOOTER_DESYNC: in paged mode, don't set\n"
        "    // _page/_surah here -- the header is painted straight from the\n"
        "    // PageView's own index, so setting them ahead of the actual jump is\n"
        "    // what let the footer race ahead of what was on screen. Let\n"
        "    // onPageChanged own both once the view genuinely gets there, exactly\n"
        "    // like _stepPage already does (that path never showed this bug).\n"
        "    // Whole-surah mode has no PageView to fire onPageChanged, so it still\n"
        "    // needs to be set directly.\n"
        "    if (_settings.mushafView == MushafViewMode.surah) {\n"
        "      setState(() {\n"
        "        if (select) _selectedAyahId = globalId;\n"
        "        _page = targetPage;\n"
        "        _surah = _surahOfId(globalId);\n"
        "      });\n"
        "    } else if (select) {\n"
        "      setState(() => _selectedAyahId = globalId);\n"
        "    }\n"
        "    _settings.setLastReadAyahId(globalId);\n"
        "    _tabs.animateTo(1);\n"
        "    if (_settings.mushafView == MushafViewMode.surah) return;\n"
        "    void jump() {\n"
        "      if (!mounted || !_pageCtrl.hasClients) return;\n"
        "      if (AppMotion.on) {\n"
        "        _pageCtrl.animateToPage(targetPage - 1,\n"
        "            duration: AppMotion.medium, curve: Curves.easeOutCubic);\n"
        "      } else {\n"
        "        _pageCtrl.jumpToPage(targetPage - 1);\n"
        "      }\n"
        "    }\n"
        "    // The PageView may not be attached yet on the very first frame after a\n"
        "    // tab switch -- retry once more on the following frame if so.\n"
        "    WidgetsBinding.instance.addPostFrameCallback((_) {\n"
        "      if (!mounted) return;\n"
        "      if (_pageCtrl.hasClients) {\n"
        "        jump();\n"
        "      } else {\n"
        "        WidgetsBinding.instance.addPostFrameCallback((_) => jump());\n"
        "      }\n"
        "    });\n"
        "  }\n",
        "mushaf_screen.dart: _goToAyah -- stop racing the footer ahead of the real page",
        skip_if="PATCH_S136_SURAH_TAP_HEADER_FOOTER_DESYNC: in paged mode",
    )

    # -----------------------------------------------------------------
    # 2) autoseg_wizard.dart: responsive step layout so English/Arabic
    #    text never gets squeezed into a one-glyph-per-line sliver.
    # -----------------------------------------------------------------
    apply_literal(
        WIZARD,
        "          Expanded(\n"
        "            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [\n"
        "              SizedBox(\n"
        "                width: 220,\n"
        "                child: ListView(\n"
        "                  padding: const EdgeInsets.all(12),\n"
        "                  children: [\n"
        "                    Container(\n"
        "                      padding: const EdgeInsets.all(10),\n"
        "                      decoration: BoxDecoration(\n"
        "                          border: Border.all(color: AyatColors.hairline),\n"
        "                          borderRadius: BorderRadius.circular(10)),\n"
        "                      child: Column(\n"
        "                          crossAxisAlignment: CrossAxisAlignment.start,\n"
        "                          children: [\n"
        "                            Icon(\n"
        "                                widget.audioPath != null\n"
        "                                    ? Icons.check_circle\n"
        "                                    : Icons.warning_amber_rounded,\n"
        "                                color: widget.audioPath != null\n"
        "                                    ? const Color(0xFF43A047)\n"
        "                                    : AyatColors.goldDim,\n"
        "                                size: 18),\n"
        "                            const SizedBox(height: 6),\n"
        "                            Text(\n"
        "                                widget.audioPath != null\n"
        "                                    ? '${_s.t('wizard.audio')}: $_audioName'\n"
        "                                    : _s.t('wizard.noAudio'),\n"
        "                                style: const TextStyle(fontSize: 11)),\n"
        "                          ]),\n"
        "                    ),\n"
        "                    const SizedBox(height: 10),\n"
        "                    for (final st in steps)\n"
        "                      Padding(\n"
        "                        padding: const EdgeInsets.only(bottom: 8),\n"
        "                        child: _card(\n"
        "                            selected: _step == st,\n"
        "                            onTap: () => setState(() => _step = st),\n"
        "                            child: Text(\n"
        "                                {\n"
        "                                  _Step.version: _s.t('wizard.version'),\n"
        "                                  _Step.runtime: _s.t('wizard.runtime'),\n"
        "                                  _Step.models: _s.t('wizard.models'),\n"
        "                                  _Step.segmentation: _s.t('wizard.segmentation'),\n"
        "                                  _Step.run: _s.t('wizard.run'),\n"
        "                                }[st]!,\n"
        "                                style: const TextStyle(fontSize: 13))),\n"
        "                      ),\n"
        "                  ],\n"
        "                ),\n"
        "              ),\n"
        "              const VerticalDivider(width: 1, color: AyatColors.hairline),\n"
        "              Expanded(\n"
        "                  child: ListView(\n"
        "                      padding: const EdgeInsets.all(16),\n"
        "                      children: [_stepBody()])),\n"
        "            ]),\n"
        "          ),\n",
        "          Expanded(\n"
        "            // PATCH_S136_WIZARD_NARROW_WIDTH: the fixed width: 220 rail\n"
        "            // below was sized for this dialog's ConstrainedBox(maxWidth:\n"
        "            // 860) desktop-ish frame. On an actual phone the dialog is\n"
        "            // nowhere near that wide, so 220 ate almost the whole width\n"
        "            // and squeezed the step body into a sliver so narrow that\n"
        "            // English words like \"Legacy V1\" wrapped one glyph per line.\n"
        "            // Below 560 logical px, stack instead of splitting side by\n"
        "            // side; above it, keep the original layout unchanged.\n"
        "            child: LayoutBuilder(builder: (context, constraints) {\n"
        "              final stepLabels = <_Step, String>{\n"
        "                _Step.version: _s.t('wizard.version'),\n"
        "                _Step.runtime: _s.t('wizard.runtime'),\n"
        "                _Step.models: _s.t('wizard.models'),\n"
        "                _Step.segmentation: _s.t('wizard.segmentation'),\n"
        "                _Step.run: _s.t('wizard.run'),\n"
        "              };\n"
        "              final audioStatus = Container(\n"
        "                padding: const EdgeInsets.all(10),\n"
        "                decoration: BoxDecoration(\n"
        "                    border: Border.all(color: AyatColors.hairline),\n"
        "                    borderRadius: BorderRadius.circular(10)),\n"
        "                child: Row(children: [\n"
        "                  Icon(\n"
        "                      widget.audioPath != null\n"
        "                          ? Icons.check_circle\n"
        "                          : Icons.warning_amber_rounded,\n"
        "                      color: widget.audioPath != null\n"
        "                          ? const Color(0xFF43A047)\n"
        "                          : AyatColors.goldDim,\n"
        "                      size: 18),\n"
        "                  const SizedBox(width: 8),\n"
        "                  Expanded(\n"
        "                      child: Text(\n"
        "                          widget.audioPath != null\n"
        "                              ? '${_s.t('wizard.audio')}: $_audioName'\n"
        "                              : _s.t('wizard.noAudio'),\n"
        "                          style: const TextStyle(fontSize: 11))),\n"
        "                ]),\n"
        "              );\n"
        "              final stepChips = <Widget>[\n"
        "                for (final st in steps)\n"
        "                  _card(\n"
        "                      selected: _step == st,\n"
        "                      onTap: () => setState(() => _step = st),\n"
        "                      child: Text(stepLabels[st]!,\n"
        "                          style: const TextStyle(fontSize: 13))),\n"
        "              ];\n"
        "              if (constraints.maxWidth < 560) {\n"
        "                return Column(children: [\n"
        "                  Padding(\n"
        "                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),\n"
        "                      child: audioStatus),\n"
        "                  SizedBox(\n"
        "                    height: 52,\n"
        "                    child: ListView(\n"
        "                      scrollDirection: Axis.horizontal,\n"
        "                      padding: const EdgeInsets.all(12),\n"
        "                      children: [\n"
        "                        for (final chip in stepChips)\n"
        "                          Padding(\n"
        "                              padding:\n"
        "                                  const EdgeInsetsDirectional.only(end: 8),\n"
        "                              child: chip),\n"
        "                      ],\n"
        "                    ),\n"
        "                  ),\n"
        "                  const Divider(height: 1, color: AyatColors.hairline),\n"
        "                  Expanded(\n"
        "                      child: ListView(\n"
        "                          padding: const EdgeInsets.all(16),\n"
        "                          children: [_stepBody()])),\n"
        "                ]);\n"
        "              }\n"
        "              return Row(\n"
        "                  crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "                  children: [\n"
        "                    SizedBox(\n"
        "                      width: 220,\n"
        "                      child: ListView(\n"
        "                        padding: const EdgeInsets.all(12),\n"
        "                        children: [\n"
        "                          audioStatus,\n"
        "                          const SizedBox(height: 10),\n"
        "                          for (final chip in stepChips)\n"
        "                            Padding(\n"
        "                                padding:\n"
        "                                    const EdgeInsets.only(bottom: 8),\n"
        "                                child: chip),\n"
        "                        ],\n"
        "                      ),\n"
        "                    ),\n"
        "                    const VerticalDivider(\n"
        "                        width: 1, color: AyatColors.hairline),\n"
        "                    Expanded(\n"
        "                        child: ListView(\n"
        "                            padding: const EdgeInsets.all(16),\n"
        "                            children: [_stepBody()])),\n"
        "                  ]);\n"
        "            }),\n"
        "          ),\n",
        "autoseg_wizard.dart: responsive step layout instead of a fixed-220 rail",
        skip_if="PATCH_S136_WIZARD_NARROW_WIDTH",
    )

    print("\n=== S136 gauntlet loop ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================\n")


if __name__ == "__main__":
    main()
