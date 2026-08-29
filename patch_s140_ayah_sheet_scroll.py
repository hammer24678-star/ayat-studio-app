# patch_s140_ayah_sheet_scroll.py
#
# lib/screens/mushaf_screen.dart -- _openAyahActions() (the sheet that opens
# when you tap an ayah: تفسير / استماع / مشاركة / نسخ / استخدام في الاستوديو)
# never passed `isScrollControlled: true` to showModalBottomSheet, and its
# content was a plain Column with no scroll view around it. Without
# isScrollControlled, a bottom sheet is capped at roughly half the screen's
# height -- and on a phone that's not tall enough for the ayah text plus all
# five actions, the Column just clips at that cap. There was nothing to
# scroll: the whole sheet was a fixed-size Column, so the actions below the
# cut-off line (Copy, Use in Studio) were simply unreachable.
#
# Fix: add isScrollControlled: true (so the sheet can grow up to a real
# limit instead of a fixed half-screen box), cap that limit at 85% of the
# screen height with a ConstrainedBox (so it never claims the whole screen
# on a tall list), and wrap the Column in a SingleChildScrollView so
# anything past that cap scrolls instead of clipping.
#
# The reciter-listen sheet (_openReciterSheet, PATCH_S138) already passes
# isScrollControlled: true and its reciter list is its own independently
# scrolling ListView inside a fixed-height SizedBox, so it isn't touched
# here -- this patch is only the ayah-actions sheet.
#
# Run from the project root.

from pathlib import Path

ROOT = Path(__file__).resolve().parent
LEDGER = []
MARKER = 'PATCH_S140_AYAH_SHEET_SCROLL'
MARKER_HEADER = 'PATCH_S140_HEADER'
MARKER_BODY = 'PATCH_S140_BODY'


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


def main():
    apply_literal(
        MUSHAF,
        "    showModalBottomSheet<void>(\n"
        "      context: context,\n"
        "      backgroundColor: _p.surface,\n"
        "      showDragHandle: true,\n"
        "      shape: const RoundedRectangleBorder(\n"
        "        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),\n"
        "      ),\n"
        "      builder: (sheetCtx) => Directionality(\n"
        "        textDirection: TextDirection.rtl,\n"
        "        child: SafeArea(\n"
        "          child: Padding(\n"
        "            padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),\n"
        "            child: Column(\n"
        "              mainAxisSize: MainAxisSize.min,\n"
        "              crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "              children: [\n"
        "                Row(\n"
        "                  children: [\n"
        "                    ayahRosetteOrnament(ayah.num, _p, size: 30),\n",
        f"    // {MARKER_HEADER}: isScrollControlled + the ConstrainedBox/\n"
        "    // SingleChildScrollView below replace a plain half-screen-capped,\n"
        "    // non-scrolling Column -- on a short screen the ayah text plus all\n"
        "    // five actions used to just clip at that cap with nothing to scroll,\n"
        "    // leaving Copy and Use in Studio unreachable.\n"
        "    showModalBottomSheet<void>(\n"
        "      context: context,\n"
        "      backgroundColor: _p.surface,\n"
        "      showDragHandle: true,\n"
        "      isScrollControlled: true,\n"
        "      shape: const RoundedRectangleBorder(\n"
        "        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),\n"
        "      ),\n"
        "      builder: (sheetCtx) => Directionality(\n"
        "        textDirection: TextDirection.rtl,\n"
        "        child: SafeArea(\n"
        "          child: ConstrainedBox(\n"
        "            constraints: BoxConstraints(\n"
        "                maxHeight: MediaQuery.of(sheetCtx).size.height * 0.85),\n"
        "            child: SingleChildScrollView(\n"
        "              padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),\n"
        "              child: Column(\n"
        "                mainAxisSize: MainAxisSize.min,\n"
        "                crossAxisAlignment: CrossAxisAlignment.stretch,\n"
        "                children: [\n"
        "                  Row(\n"
        "                    children: [\n"
        "                      ayahRosetteOrnament(ayah.num, _p, size: 30),\n",
        "mushaf_screen.dart: ayah-actions sheet header + scroll wrapper",
        skip_if=MARKER_HEADER,
    )

    # The rest of the sheet's body keeps its old indentation (2 spaces
    # shallower than where it now sits, since it moved one level deeper
    # into SingleChildScrollView/Column) -- Dart doesn't care, but this
    # keeps the diff honest by re-indenting the body to match, in one
    # literal block covering the whole rest of the method.
    apply_literal(
        MUSHAF,
        "                    const SizedBox(width: 10),\n"
        "                    Expanded(\n"
        "                      child: Text(\n"
        "                        'سورة ${ayah.surah} — ${_s.t('mushaf.page')} ${pageOfAyahId(id)}'\n"
        "                        ' · ${_s.t('mushaf.juz')} ${juzOfAyahId(id)}',\n"
        "                        style: GoogleFonts.tajawal(\n"
        "                            color: _p.textDim, fontSize: 12.5),\n"
        "                      ),\n"
        "                    ),\n"
        "                  ],\n"
        "                ),\n"
        "                const SizedBox(height: 12),\n"
        "                Text(\n"
        "                  ayah.ar,\n"
        "                  textAlign: TextAlign.center,\n"
        "                  style: ayahTextStyle(widget.fontKey,\n"
        "                      fontSize: 20, height: 1.9, color: _p.text),\n"
        "                ),\n"
        "                if (ayah.en.isNotEmpty) ...[\n"
        "                  const SizedBox(height: 10),\n"
        "                  Text(\n"
        "                    ayah.en,\n"
        "                    textAlign: TextAlign.center,\n"
        "                    textDirection: TextDirection.ltr,\n"
        "                    style: GoogleFonts.tajawal(\n"
        "                        color: _p.textDim, fontSize: 12.5, height: 1.6),\n"
        "                  ),\n"
        "                ],\n"
        "                const SizedBox(height: 16),\n"
        "                _SheetAction(\n"
        "                  palette: _p,\n"
        "                  icon: Icons.menu_book_outlined,\n"
        "                  label: _s.t('mushaf.tafsir'),\n"
        "                  onTap: () {\n"
        "                    Navigator.pop(sheetCtx);\n"
        "                    _tabs.animateTo(2);\n"
        "                  },\n"
        "                ),\n"
        "                // PATCH_S138_LISTEN_ACTION: hear a reciter or cache one for\n"
        "                // offline reading, without leaving المصحف.\n"
        "                _SheetAction(\n"
        "                  palette: _p,\n"
        "                  icon: Icons.graphic_eq,\n"
        "                  label: 'استماع',\n"
        "                  onTap: () {\n"
        "                    Navigator.pop(sheetCtx);\n"
        "                    _openReciterSheet(ayah);\n"
        "                  },\n"
        "                ),\n"
        "                _SheetAction(\n"
        "                  palette: _p,\n"
        "                  icon: Icons.ios_share_outlined,\n"
        "                  label: _s.t('common.share'),\n"
        "                  onTap: () {\n"
        "                    Navigator.pop(sheetCtx);\n"
        "                    // The reference travels with the text -- an ayah pasted\n"
        "                    // into a chat without one is a quote nobody can check.\n"
        "                    SharePlus.instance.share(ShareParams(\n"
        "                      text: '${ayah.ar}\\n\\n[سورة ${ayah.surah}: ${ayah.num}]',\n"
        "                    ));\n"
        "                  },\n"
        "                ),\n"
        "                _SheetAction(\n"
        "                  palette: _p,\n"
        "                  icon: Icons.copy_all_outlined,\n"
        "                  label: _s.t('common.copy'),\n"
        "                  onTap: () async {\n"
        "                    await Clipboard.setData(ClipboardData(\n"
        "                        text: '${ayah.ar}\\n[${ayah.surah}: ${ayah.num}]'));\n"
        "                    if (!sheetCtx.mounted || !mounted) return;\n"
        "                    Navigator.pop(sheetCtx);\n"
        "                    ScaffoldMessenger.of(context).showSnackBar(\n"
        "                      SnackBar(content: Text(_s.t('common.copied'))),\n"
        "                    );\n"
        "                  },\n"
        "                ),\n"
        "                if (widget.onUseAyah != null)\n"
        "                  _SheetAction(\n"
        "                    palette: _p,\n"
        "                    icon: Icons.movie_creation_outlined,\n"
        "                    label: _s.t('mushaf.useInStudio'),\n"
        "                    highlighted: true,\n"
        "                    onTap: () {\n"
        "                      Navigator.pop(sheetCtx);\n"
        "                      widget.onUseAyah!(ayah);\n"
        "                      Navigator.of(context).maybePop();\n"
        "                    },\n"
        "                  ),\n"
        "              ],\n"
        "            ),\n"
        "          ),\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n",
        "                      const SizedBox(width: 10), // PATCH_S140_BODY\n"
        "                      Expanded(\n"
        "                        child: Text(\n"
        "                          'سورة ${ayah.surah} — ${_s.t('mushaf.page')} ${pageOfAyahId(id)}'\n"
        "                          ' · ${_s.t('mushaf.juz')} ${juzOfAyahId(id)}',\n"
        "                          style: GoogleFonts.tajawal(\n"
        "                              color: _p.textDim, fontSize: 12.5),\n"
        "                        ),\n"
        "                      ),\n"
        "                    ],\n"
        "                  ),\n"
        "                  const SizedBox(height: 12),\n"
        "                  Text(\n"
        "                    ayah.ar,\n"
        "                    textAlign: TextAlign.center,\n"
        "                    style: ayahTextStyle(widget.fontKey,\n"
        "                        fontSize: 20, height: 1.9, color: _p.text),\n"
        "                  ),\n"
        "                  if (ayah.en.isNotEmpty) ...[\n"
        "                    const SizedBox(height: 10),\n"
        "                    Text(\n"
        "                      ayah.en,\n"
        "                      textAlign: TextAlign.center,\n"
        "                      textDirection: TextDirection.ltr,\n"
        "                      style: GoogleFonts.tajawal(\n"
        "                          color: _p.textDim, fontSize: 12.5, height: 1.6),\n"
        "                    ),\n"
        "                  ],\n"
        "                  const SizedBox(height: 16),\n"
        "                  _SheetAction(\n"
        "                    palette: _p,\n"
        "                    icon: Icons.menu_book_outlined,\n"
        "                    label: _s.t('mushaf.tafsir'),\n"
        "                    onTap: () {\n"
        "                      Navigator.pop(sheetCtx);\n"
        "                      _tabs.animateTo(2);\n"
        "                    },\n"
        "                  ),\n"
        "                  // PATCH_S138_LISTEN_ACTION: hear a reciter or cache one for\n"
        "                  // offline reading, without leaving المصحف.\n"
        "                  _SheetAction(\n"
        "                    palette: _p,\n"
        "                    icon: Icons.graphic_eq,\n"
        "                    label: 'استماع',\n"
        "                    onTap: () {\n"
        "                      Navigator.pop(sheetCtx);\n"
        "                      _openReciterSheet(ayah);\n"
        "                    },\n"
        "                  ),\n"
        "                  _SheetAction(\n"
        "                    palette: _p,\n"
        "                    icon: Icons.ios_share_outlined,\n"
        "                    label: _s.t('common.share'),\n"
        "                    onTap: () {\n"
        "                      Navigator.pop(sheetCtx);\n"
        "                      // The reference travels with the text -- an ayah pasted\n"
        "                      // into a chat without one is a quote nobody can check.\n"
        "                      SharePlus.instance.share(ShareParams(\n"
        "                        text: '${ayah.ar}\\n\\n[سورة ${ayah.surah}: ${ayah.num}]',\n"
        "                      ));\n"
        "                    },\n"
        "                  ),\n"
        "                  _SheetAction(\n"
        "                    palette: _p,\n"
        "                    icon: Icons.copy_all_outlined,\n"
        "                    label: _s.t('common.copy'),\n"
        "                    onTap: () async {\n"
        "                      await Clipboard.setData(ClipboardData(\n"
        "                          text: '${ayah.ar}\\n[${ayah.surah}: ${ayah.num}]'));\n"
        "                      if (!sheetCtx.mounted || !mounted) return;\n"
        "                      Navigator.pop(sheetCtx);\n"
        "                      ScaffoldMessenger.of(context).showSnackBar(\n"
        "                        SnackBar(content: Text(_s.t('common.copied'))),\n"
        "                      );\n"
        "                    },\n"
        "                  ),\n"
        "                  if (widget.onUseAyah != null)\n"
        "                    _SheetAction(\n"
        "                      palette: _p,\n"
        "                      icon: Icons.movie_creation_outlined,\n"
        "                      label: _s.t('mushaf.useInStudio'),\n"
        "                      highlighted: true,\n"
        "                      onTap: () {\n"
        "                        Navigator.pop(sheetCtx);\n"
        "                        widget.onUseAyah!(ayah);\n"
        "                        Navigator.of(context).maybePop();\n"
        "                      },\n"
        "                    ),\n"
        "                ],\n"
        "              ),\n"
        "            ),\n"
        "          ),\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n",
        "mushaf_screen.dart: re-indent ayah-actions sheet body + close scroll wrapper",
        skip_if=MARKER_BODY,
    )

    print("\n=== S140 gauntlet loop ledger ===")
    for label, status in LEDGER:
        print(f"[{status}] {label}")
    print("==================================\n")


if __name__ == "__main__":
    main()
