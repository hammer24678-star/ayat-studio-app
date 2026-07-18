#!/usr/bin/env python3
"""
patch_s59_tab_grid.py

The complaint: the 8 section tabs (الآية / خلفيات / تأثيرات / كروم / قرّاء /
قوالب / النص / تصدير) sit in a Wrap(), which lets each chip claim only the
width its own label needs. At the current font/padding that produces an
awkward organic wrap -- 3 chips on row 1, 4 on row 2, 1 orphaned alone on
row 3 -- instead of a tidy grid.

Fix: replace the Wrap of ChoiceChips with a fixed 4-column GridView, so all
8 tabs lay out as a clean 4+4 grid every time regardless of label width.
Each cell is a custom bordered button (Material + InkWell) matching the
existing gold-fill-when-selected / hairline-border-otherwise look, sized
uniformly rather than to its own content.

  lib/screens/home_screen.dart
    - _tabChips() now returns a non-scrolling GridView.count(crossAxisCount: 4)
      instead of a Wrap.
    - new _tabButton(i) helper draws each cell.

Usage:
  python3 patch_s59_tab_grid.py /path/to/ayat_studio_app
  (defaults to . if no path given)
"""

import sys
import pathlib

MARKER = "PATCH_S59_TAB_GRID"


def die(msg):
    print(f"ERROR: {msg}")
    sys.exit(1)


def replace_once(text, old, new, label):
    count = text.count(old)
    if count == 0:
        die(f"could not find anchor for [{label}] -- file may have changed since S59 was written.")
    if count > 1:
        die(f"anchor for [{label}] is not unique ({count} matches) -- refusing to guess, no changes made.")
    return text.replace(old, new, 1)


def patch_home_screen(project_dir):
    target = project_dir / "lib" / "screens" / "home_screen.dart"
    if not target.exists():
        die(f"{target} not found.")
    text = target.read_text()
    if MARKER in text:
        return False

    old = (
        "  Widget _tabChips() {\n"
        "    return Wrap(\n"
        "      spacing: 6,\n"
        "      runSpacing: 6,\n"
        "      alignment: WrapAlignment.center,\n"
        "      children: [\n"
        "        for (var i = 0; i < _tabs.length; i++)\n"
        "          ChoiceChip(\n"
        "            avatar: Icon(_tabs[i].$1,\n"
        "                size: 15,\n"
        "                color: _selectedTab == i\n"
        "                    ? AyatColors.goldBright\n"
        "                    : AyatColors.parchmentDim),\n"
        "            label: Text(_tabs[i].$2),\n"
        "            selected: _selectedTab == i,\n"
        "            onSelected: (_) => setState(() => _selectedTab = i),\n"
        "          ),\n"
        "      ],\n"
        "    );\n"
        "  }\n"
    )

    new = (
        f"  // {MARKER}: fixed 4-column grid so 8 tabs always lay out as a\n"
        "  // clean 4+4, instead of Wrap's width-driven 3/4/1 orphan row.\n"
        "  Widget _tabChips() {\n"
        "    return GridView.count(\n"
        "      crossAxisCount: 4,\n"
        "      shrinkWrap: true,\n"
        "      physics: const NeverScrollableScrollPhysics(),\n"
        "      mainAxisSpacing: 8,\n"
        "      crossAxisSpacing: 8,\n"
        "      childAspectRatio: 1.55,\n"
        "      children: [\n"
        "        for (var i = 0; i < _tabs.length; i++) _tabButton(i),\n"
        "      ],\n"
        "    );\n"
        "  }\n"
        "\n"
        f"  Widget _tabButton(int i) {{\n"
        "    final selected = _selectedTab == i;\n"
        "    return Material(\n"
        "      color: selected ? AyatColors.goldBright : AyatColors.surface2,\n"
        "      borderRadius: BorderRadius.circular(14),\n"
        "      child: InkWell(\n"
        "        borderRadius: BorderRadius.circular(14),\n"
        "        onTap: () => setState(() => _selectedTab = i),\n"
        "        child: Container(\n"
        "          decoration: BoxDecoration(\n"
        "            borderRadius: BorderRadius.circular(14),\n"
        "            border: Border.all(\n"
        "              color: selected ? AyatColors.goldBright : AyatColors.hairline,\n"
        "            ),\n"
        "          ),\n"
        "          alignment: Alignment.center,\n"
        "          child: Column(\n"
        "            mainAxisAlignment: MainAxisAlignment.center,\n"
        "            mainAxisSize: MainAxisSize.min,\n"
        "            children: [\n"
        "              Icon(_tabs[i].$1,\n"
        "                  size: 18,\n"
        "                  color: selected ? AyatColors.ink : AyatColors.parchmentDim),\n"
        "              const SizedBox(height: 4),\n"
        "              Text(_tabs[i].$2,\n"
        "                  textAlign: TextAlign.center,\n"
        "                  style: TextStyle(\n"
        "                    fontSize: 12.5,\n"
        "                    fontWeight: FontWeight.w700,\n"
        "                    color: selected ? AyatColors.ink : AyatColors.parchment,\n"
        "                  )),\n"
        "            ],\n"
        "          ),\n"
        "        ),\n"
        "      ),\n"
        "    );\n"
        "  }\n"
    )

    text = replace_once(text, old, new, "_tabChips Wrap -> GridView")
    target.write_text(text)
    return True


def main():
    project_dir = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    changed = patch_home_screen(project_dir)
    if changed:
        print(f"OK: patched {project_dir / 'lib' / 'screens' / 'home_screen.dart'}")
    else:
        print("SKIP: S59 marker already present, no changes made.")


if __name__ == "__main__":
    main()
