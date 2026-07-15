#!/usr/bin/env python3
"""
PATCH_S103_MORE_TEMPLATES
============================

Adds 12 more entries to kTemplates (lib/data/studio_presets.dart) --
the قوالب tab currently has 7. Each new one is a distinct pos/extra/
font/color combination (not just re-shuffling the same 7), built from
combinations the existing 7 don't already cover:

  - fonts: spreads across all 5 built-in fonts, including the two
    added in S100 (tharwatemara, digitalmadina) which had zero
    templates showcasing them until now.
  - positions: top / center / bottom, all represented.
  - frame styles: plain, boxed, framed, and the S38 glass look --
    every existing FrameExtra gets more than one template now.
  - colors: pulls from the existing kTextColors palette (teal,
    amber, sky blue, gold, cream, white) so nothing looks out of
    place next to the current 7.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s103_more_templates.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S103_MORE_TEMPLATES"


def replace_once(path: pathlib.Path, old: str, new: str, label: str) -> bool:
    text = path.read_text(encoding="utf-8")

    if new.strip() in text:
        print(f"  SKIP  ({label}): already applied")
        return False

    count = text.count(old)
    if count == 0:
        raise SystemExit(
            f"ERROR ({label}): expected old text not found in {path}. "
            f"File may have drifted since this patch was written -- "
            f"aborting instead of guessing."
        )
    if count > 1:
        raise SystemExit(
            f"ERROR ({label}): old text found {count} times in {path}, "
            f"expected exactly 1 -- refusing to guess which one."
        )

    path.write_text(text.replace(old, new, 1), encoding="utf-8")
    print(f"  OK    ({label}): patched")
    return True


_TEMPLATES_OLD = """  AyahTemplate(
      name: 'زجاج مصنفر أنيق',
      desc: 'لوحة شبه شفافة بلمسة زجاجية عصرية أسفل الشاشة',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.glass,
      fontKey: 'amiri',
      color: Color(0xFFFFFFFF)),
];"""

_TEMPLATES_NEW = """  AyahTemplate(
      name: 'زجاج مصنفر أنيق',
      desc: 'لوحة شبه شفافة بلمسة زجاجية عصرية أسفل الشاشة',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.glass,
      fontKey: 'amiri',
      color: Color(0xFFFFFFFF)),
  // PATCH_S103_MORE_TEMPLATES: 12 more -- spread across all 5 fonts (including
  // the S100 tharwatemara/digitalmadina, unused by any template until
  // now), all 3 positions, and every FrameExtra style.
  AyahTemplate(
      name: 'عنوان ثروت علوي',
      desc: 'خط ثروت عمارة أعلى الشاشة',
      pos: AyahTextPosition.top,
      extra: FrameExtra.none,
      fontKey: 'tharwatemara',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'توسّط المدينة الرقمية',
      desc: 'الآية بخط المدينة الرقمية في المنتصف',
      pos: AyahTextPosition.center,
      extra: FrameExtra.none,
      fontKey: 'digitalmadina',
      color: Color(0xFFFFFFFF)),
  AyahTemplate(
      name: 'لوحة زجاجية علوية',
      desc: 'نص داخل لوحة شبه شفافة أعلى الشاشة',
      pos: AyahTextPosition.top,
      extra: FrameExtra.glass,
      fontKey: 'amiri',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'إطار ذهبي سفلي',
      desc: 'نص داخل إطار مذهّب أسفل الشاشة',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.framed,
      fontKey: 'ruqaa',
      color: Color(0xFFECC875)),
  AyahTemplate(
      name: 'زجاج مصنفر علوي',
      desc: 'لوحة زجاجية عصرية أعلى الشاشة',
      pos: AyahTextPosition.top,
      extra: FrameExtra.glass,
      fontKey: 'tharwatemara',
      color: Color(0xFFFFFFFF)),
  AyahTemplate(
      name: 'توسّط زمردي هادئ',
      desc: 'الآية في المنتصف بلون أخضر زمردي هادئ',
      pos: AyahTextPosition.center,
      extra: FrameExtra.none,
      fontKey: 'amiri',
      color: Color(0xFF8FBBAF)),
  AyahTemplate(
      name: 'إطار المدينة المتوسط',
      desc: 'نص داخل إطار مذهّب بخط المدينة الرقمية في المنتصف',
      pos: AyahTextPosition.center,
      extra: FrameExtra.framed,
      fontKey: 'digitalmadina',
      color: Color(0xFFECC875)),
  AyahTemplate(
      name: 'لوحة زجاجية متوسطة',
      desc: 'نص داخل لوحة زجاجية شفافة في المنتصف',
      pos: AyahTextPosition.center,
      extra: FrameExtra.glass,
      fontKey: 'elgharib',
      color: Color(0xFFECE2CB)),
  AyahTemplate(
      name: 'عنوان الغريب سفلي',
      desc: 'خط الغريب نون حفص أسفل الشاشة بوضوح',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.none,
      fontKey: 'elgharib',
      color: Color(0xFFFFFFFF)),
  AyahTemplate(
      name: 'صندوق كهرماني علوي',
      desc: 'نص داخل صندوق كهرماني أعلى الشاشة',
      pos: AyahTextPosition.top,
      extra: FrameExtra.boxed,
      fontKey: 'ruqaa',
      color: Color(0xFFC9A24B)),
  AyahTemplate(
      name: 'توسّط سماوي',
      desc: 'الآية في المنتصف بلون أزرق سماوي هادئ',
      pos: AyahTextPosition.center,
      extra: FrameExtra.none,
      fontKey: 'tharwatemara',
      color: Color(0xFFA8C5D6)),
  AyahTemplate(
      name: 'لوحة زجاجية ذهبية سفلية',
      desc: 'لوحة زجاجية عصرية بلون ذهبي أسفل الشاشة',
      pos: AyahTextPosition.bottom,
      extra: FrameExtra.glass,
      fontKey: 'digitalmadina',
      color: Color(0xFFECC875)),
];"""


def patch_templates(root: pathlib.Path) -> bool:
    path = root / "lib" / "data" / "studio_presets.dart"
    return replace_once(path, _TEMPLATES_OLD, _TEMPLATES_NEW,
                         "studio_presets.dart: add 12 more kTemplates entries")


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 patch_s103_more_templates.py <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    if not root.exists():
        raise SystemExit(f"ERROR: project root not found: {root}")

    print(f"Patching under: {root}\n")

    print("-- templates --")
    patch_templates(root)

    print(f"\nDone. {MARKER} applied (or already present).")
    print("\nSanity-check next:")
    print("  1. dart analyze")
    print("  2. قوالب tab should show 19 templates now (7 existing + 12 new).")
    print("  3. Tap a few of the new ones -- تشغيل ثروت عمارة/المدينة الرقمية")
    print("     fonts should actually render (S100), and boxed/framed/glass")
    print("     frames should look distinct from each other in the preview.")


if __name__ == "__main__":
    main()
