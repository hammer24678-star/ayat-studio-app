#!/usr/bin/env python3
"""
PATCH_S120_ADVANCED_OPTIONS_CLEANUP
=======================================================

Cleans up the "advanced options" stack under the ayah picker --
استخدام جزء من الآية فقط, تلوين كلمات بالأحمر, توقيت ظهور النص يدويًا,
نص إضافي, نطاق آيات متعدد, and بطاقات افتتاحية وختامية. On screen these
have been six sections just stacked one after another with nothing but
a SizedBox(height: 10) between most of them (a Divider only shows up
before two of the six) -- no card, no border, no consistent gap, so it
reads as one long undifferentiated wall of fields. Three concrete fixes:

1. GOLD BADGE CONSISTENCY -- `_partialAyahSection()`'s header badge was
   `ayahNumberBadge(a.num)`, which uses the *default* size/fontSize
   (26/11). Every other gold ayah badge in the app -- notably the
   السورة/الآية dropdown this section sits directly under -- explicitly
   passes `size: 22, fontSize: 10` (PATCH_S105). The mismatched larger
   badge, sitting right under the smaller ones with no card boundary
   around it, is what reads as visually "floating"/off against the
   dropdown and the hairline directly above it. Now explicitly matches.

2. SPACING -- every one of the six sections now renders inside a
   shared `_sectionCard()` (rounded surface2 container, hairline
   border, consistent top margin). This replaces the ad-hoc mix of
   bare SizedBox/Divider spacers that made the gaps inconsistent, and
   gives each section a visible boundary instead of bleeding into the
   next one.

3. INFO ON TAP -- every section header goes through a new
   `_sectionHeader(title, infoText, {badgeNum})` helper: a compact
   title row with an (i) icon button that opens a themed dialog with a
   fuller explanation (`_showSectionInfo`). The long explanatory
   sentences that used to sit permanently under each title (adding to
   the wall-of-text feel) moved into that popup, expanded with a bit
   more detail than before; each section keeps only its title inline.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s120_advanced_options_cleanup.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S120_ADVANCED_OPTIONS_CLEANUP"


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


# --- 1. shared helpers: _sectionHeader / _showSectionInfo / _sectionCard --

_HELPERS_ANCHOR_OLD = """  Widget _fieldLabel(String s) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(s,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AyatColors.goldDim)),
      );

  // ------------------------------------------------------------ tab: الآية"""

_HELPERS_ANCHOR_NEW = """  Widget _fieldLabel(String s) => Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 6),
        child: Text(s,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(color: AyatColors.goldDim)),
      );

  // PATCH_S120_ADVANCED_OPTIONS_CLEANUP: shared header for every optional
  // section below the ayah picker (partial-ayah, red words, manual
  // timing, caption, multi-ayah range, intro/outro cards). badgeNum
  // reuses the same gold ayahNumberBadge size/style as the السورة/الآية
  // dropdown above (size: 22, fontSize: 10) instead of each section
  // picking its own -- that mismatch was the "floating circle" mess.
  // The long explanation moves into a tap-to-open popup instead of
  // sitting permanently inline under the title.
  Widget _sectionHeader(String title, String infoText, {int? badgeNum}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (badgeNum != null) ...[
          ayahNumberBadge(badgeNum, size: 22, fontSize: 10),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        ),
        IconButton(
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.info_outline,
              size: 19, color: AyatColors.goldDim),
          tooltip: 'توضيح',
          onPressed: () => _showSectionInfo(title, infoText),
        ),
      ],
    );
  }

  Future<void> _showSectionInfo(String title, String text) {
    return showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AyatColors.surface2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: Theme.of(context).textTheme.headlineMedium),
        content: Text(text, style: Theme.of(context).textTheme.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسنًا'),
          ),
        ],
      ),
    );
  }

  // One consistent bordered surface for every optional section instead
  // of the previous mix of bare SizedBox/Divider spacers between them.
  Widget _sectionCard(Widget child) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AyatColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AyatColors.hairline),
      ),
      child: child,
    );
  }

  // ------------------------------------------------------------ tab: الآية"""


# --- 2. _partialAyahSection: matching badge + card + tap-for-info --------

_PARTIAL_HEAD_OLD = """    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        // PATCH_S105_GOLD_AYAH_BADGE: show which ayah this is, as the same
        // gold badge used elsewhere, next to the section title.
        Row(
          children: [
            ayahNumberBadge(a.num),
            const SizedBox(width: 8),
            Text('استخدام جزء من الآية فقط',
                style: Theme.of(context).textTheme.headlineMedium),
          ],
        ),
        Text(
          'اختاري من أي كلمة إلى أي كلمة من الآية المحددة أعلاه -- مفيد لعرض نصفها '
          'فقط مثلاً بدل الآية كاملة، أو لإضافتها كمقطع مستقل في الخط الزمني أدناه.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 10),"""

_PARTIAL_HEAD_NEW = """    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'استخدام جزء من الآية فقط',
          'اختاري من أي كلمة إلى أي كلمة من الآية المحددة أعلاه -- مفيد لعرض '
          'نصفها فقط مثلاً بدل الآية كاملة، أو لإضافتها كمقطع مستقل في الخط '
          'الزمني أدناه. مثال: لو اخترتِ من الكلمة الأولى إلى الثالثة فقط '
          'يظهر هذا الجزء بمفرده -- إمّا كنص الآية نفسه، أو كمقطع منفصل عبر '
          '"إضافة هذا الجزء إلى الخط الزمني" أسفل الصفحة.',
          badgeNum: a.num,
        ),
        const SizedBox(height: 10),"""


_PARTIAL_TAIL_OLD = """          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('إضافة هذا الجزء إلى الخط الزمني'),
        ),
      ],
    );
  }"""

_PARTIAL_TAIL_NEW = """          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('إضافة هذا الجزء إلى الخط الزمني'),
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }"""


# --- 3. _redWordsSection: card + tap-for-info -----------------------------

_REDWORDS_HEAD_OLD = """    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text('تلوين كلمات بالأحمر (اختياري)',
            style: Theme.of(context).textTheme.headlineMedium),
        Text(
          'اضغطي على أي كلمة لتلوينها بالأحمر في الفيديو المُصدَّر -- مفيدة '
          'لتمييز كلمة معينة من الآية.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Wrap("""

_REDWORDS_HEAD_NEW = """    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'تلوين كلمات بالأحمر (اختياري)',
          'اضغطي على أي كلمة لتلوينها بالأحمر في الفيديو المُصدَّر -- مفيدة '
          'لتمييز اسم الجلالة أو كلمة محورية من الآية. يمكنك تلوين أكثر '
          'من كلمة، واضغطي عليها مجددًا لإزالة اللون.',
        ),
        const SizedBox(height: 8),
        Wrap("""

_REDWORDS_TAIL_OLD = """                }),
              ),
          ],
        ),
      ],
    );
  }

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: optional manual override for"""

_REDWORDS_TAIL_NEW = """                }),
              ),
          ],
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: optional manual override for"""


# --- 4. _manualTimingSection: card + tap-for-info -------------------------

_TIMING_HEAD_OLD = """  Widget _manualTimingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text('توقيت ظهور النص يدويًا (اختياري)',
            style: Theme.of(context).textTheme.headlineMedium),
        Text(
          'حدّدي بالثواني متى يظهر نص الآية ومتى يختفي من الفيديو المُصدَّر -- '
          'اتركيهما فارغين ليظهر النص طوال المقطع كالمعتاد.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Row("""

_TIMING_HEAD_NEW = """  Widget _manualTimingSection() {
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'توقيت ظهور النص يدويًا (اختياري)',
          'حدّدي بالثواني متى يظهر نص الآية ومتى يختفي من الفيديو المُصدَّر -- '
          'مفيد لو أردتِ أن يظهر النص متأخرًا عن بداية المقطع أو يختفي قبل '
          'نهايته. اتركي الحقلين فارغين ليظهر النص طوال المقطع كالمعتاد.',
        ),
        const SizedBox(height: 8),
        Row("""

_TIMING_TAIL_OLD = """            ),
          ],
        ),
      ],
    );
  }

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: free-text caption (reciter"""

_TIMING_TAIL_NEW = """            ),
          ],
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }

  // PATCH_S109_TEXT_TIMING_RED_WORDS_CAPTION: free-text caption (reciter"""


# --- 5. _captionSection: card + tap-for-info ------------------------------

_CAPTION_HEAD_OLD = """  Widget _captionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        Text('نص إضافي (اسم الشيخ، نطاق الآيات...)',
            style: Theme.of(context).textTheme.headlineMedium),
        Text(
          'مثال: "من آية ١٦ إلى ١٨" أو اسم القارئ -- يظهر كسطر صغير أعلى أو '
          'أسفل الفيديو، بمعزل عن نص الآية نفسه.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _captionCtrl,"""

_CAPTION_HEAD_NEW = """  Widget _captionSection() {
    return _sectionCard(Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'نص إضافي (اسم الشيخ، نطاق الآيات...)',
          'مثال: "من آية ١٦ إلى ١٨" أو اسم القارئ -- يظهر كسطر صغير أعلى أو '
          'أسفل الفيديو، بمعزل تمامًا عن نص الآية نفسه، ويمكن اختيار مكانه '
          '(أعلى أو أسفل) من الخيارين تحت الحقل.',
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _captionCtrl,"""

_CAPTION_TAIL_OLD = """                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _ayahPanel() {"""

_CAPTION_TAIL_NEW = """                ),
              ),
          ],
        ),
      ],
    )); // PATCH_S120_ADVANCED_OPTIONS_CLEANUP
  }

  Widget _ayahPanel() {"""


# --- 6. multi-ayah range + intro/outro: card + tap-for-info, drop the ----
# --- two ad-hoc Dividers that used to separate them -----------------------

_TAIL_BLOCK_OLD = """        const Divider(height: 32, color: AyatColors.hairline),
        // PATCH_S57_MANUAL_MULTI_AYAH_ENTRY: the dropdown above sets ONE static ayah. For a
        // recitation that moves through several ayat, build a manual
        // timeline instead -- this opens the same add-a-segment dialog
        // used by the auto-sync review card, so the first ayah added
        // here becomes the start of a full multi-ayah timeline you can
        // keep extending from the card that appears above once it's
        // no longer empty.
        Text('نطاق آيات متعدد', style: Theme.of(context).textTheme.headlineMedium),
        Text(
          'لتلاوة تمر بعدة آيات، أضيفي كل آية بتوقيتها الخاص -- ستظهر بطاقة \\'مراجعة الآيات المرصودة\\' أعلى الشاشة بعد أول آية لإكمال الباقي أو تعديل التوقيت.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _addManualSegmentDialog,
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('إضافة آية إلى خط زمني متعدد'),
        ),
        const Divider(height: 32, color: AyatColors.hairline),
        Text('بطاقات افتتاحية وختامية',
            style: Theme.of(context).textTheme.headlineMedium),
        ToggleRow(
          label: 'بسملة في مقدمة المقطع',
          value: state.showIntro,
          onChanged: (v) => state.update(() => state.showIntro = v),
        ),
        ToggleRow(
          label: 'خاتمة بعد التلاوة',
          value: state.showOutro,
          onChanged: (v) => state.update(() => state.showOutro = v),
        ),
        if (state.showOutro)
          TextField(
            controller: _outroCtrl,
            decoration: const InputDecoration(hintText: 'نص الخاتمة'),
            onChanged: (v) =>
                state.outroText = v.trim().isEmpty ? kDefaultOutro : v.trim(),
          ),
        const SizedBox(height: 6),
        Text(
          'تظهر البسملة والخاتمة كشاشتين مستقلتين قبل/بعد المقطع فقط — لا تُدمجان أبدًا فوق الفيديو أو أي موسيقى.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }"""

_TAIL_BLOCK_NEW = """        // PATCH_S57_MANUAL_MULTI_AYAH_ENTRY: the dropdown above sets ONE static ayah. For a
        // recitation that moves through several ayat, build a manual
        // timeline instead -- this opens the same add-a-segment dialog
        // used by the auto-sync review card, so the first ayah added
        // here becomes the start of a full multi-ayah timeline you can
        // keep extending from the card that appears above once it's
        // no longer empty.
        // PATCH_S120_ADVANCED_OPTIONS_CLEANUP: card replaces the old bare
        // Divider(height: 32) that used to separate this from the field
        // above -- the card's own border/margin does that job now.
        _sectionCard(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(
              'نطاق آيات متعدد',
              'لتلاوة تمر بعدة آيات، أضيفي كل آية بتوقيتها الخاص. ستظهر '
              'بطاقة \\'مراجعة الآيات المرصودة\\' أعلى الشاشة بعد أول آية '
              'لإكمال الباقي أو تعديل التوقيت -- يمكنك إضافة آية كاملة من '
              'هنا، أو جزء من آية فقط عبر قسم "استخدام جزء من الآية فقط" '
              'أعلاه.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addManualSegmentDialog,
              icon: const Icon(Icons.playlist_add, size: 18),
              label: const Text('إضافة آية إلى خط زمني متعدد'),
            ),
          ],
        )),
        _sectionCard(Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(
              'بطاقات افتتاحية وختامية',
              'تظهر البسملة والخاتمة كشاشتين مستقلتين قبل/بعد المقطع فقط — '
              'لا تُدمجان أبدًا فوق الفيديو أو أي موسيقى. عطّلي أيًا منهما '
              'إن لم ترغبي بها، ويمكنك تخصيص نص الخاتمة بعد تفعيلها.',
            ),
            ToggleRow(
              label: 'بسملة في مقدمة المقطع',
              value: state.showIntro,
              onChanged: (v) => state.update(() => state.showIntro = v),
            ),
            ToggleRow(
              label: 'خاتمة بعد التلاوة',
              value: state.showOutro,
              onChanged: (v) => state.update(() => state.showOutro = v),
            ),
            if (state.showOutro)
              TextField(
                controller: _outroCtrl,
                decoration: const InputDecoration(hintText: 'نص الخاتمة'),
                onChanged: (v) => state.outroText =
                    v.trim().isEmpty ? kDefaultOutro : v.trim(),
              ),
          ],
        )),
      ],
    );
  }"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()

    home_file = None
    for p in (root / "lib").rglob("*.dart"):
        content = p.read_text(encoding="utf-8")
        if "Widget _partialAyahSection()" in content and "Future<void> _addManualSegmentDialog()" in content:
            home_file = p
            break
    if home_file is None:
        raise SystemExit(
            "ERROR: could not find the screen containing both "
            "_partialAyahSection() and _addManualSegmentDialog() under lib/."
        )

    print(f"Applying {MARKER} to {home_file}...")
    replace_once(home_file, _HELPERS_ANCHOR_OLD, _HELPERS_ANCHOR_NEW,
                 "add _sectionHeader/_showSectionInfo/_sectionCard helpers")
    replace_once(home_file, _PARTIAL_HEAD_OLD, _PARTIAL_HEAD_NEW,
                 "_partialAyahSection: matching badge + card + info popup")
    replace_once(home_file, _PARTIAL_TAIL_OLD, _PARTIAL_TAIL_NEW,
                 "_partialAyahSection: close card wrapper")
    replace_once(home_file, _REDWORDS_HEAD_OLD, _REDWORDS_HEAD_NEW,
                 "_redWordsSection: card + info popup")
    replace_once(home_file, _REDWORDS_TAIL_OLD, _REDWORDS_TAIL_NEW,
                 "_redWordsSection: close card wrapper")
    replace_once(home_file, _TIMING_HEAD_OLD, _TIMING_HEAD_NEW,
                 "_manualTimingSection: card + info popup")
    replace_once(home_file, _TIMING_TAIL_OLD, _TIMING_TAIL_NEW,
                 "_manualTimingSection: close card wrapper")
    replace_once(home_file, _CAPTION_HEAD_OLD, _CAPTION_HEAD_NEW,
                 "_captionSection: card + info popup")
    replace_once(home_file, _CAPTION_TAIL_OLD, _CAPTION_TAIL_NEW,
                 "_captionSection: close card wrapper")
    replace_once(home_file, _TAIL_BLOCK_OLD, _TAIL_BLOCK_NEW,
                 "multi-ayah range + intro/outro: cards + info popups")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
