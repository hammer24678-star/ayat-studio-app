#!/usr/bin/env python3
"""
PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE
=======================================================

Request: "استخدام جزء من الآية فقط" (pick a word range within one ayah)
and "نطاق آيات متعدد" (the manual multi-ayah timeline) were completely
disconnected -- picking a partial excerpt only ever set the single
static ayah on screen (state.setAyah), it never touched state.timeline,
so it could never show up in "مراجعة الآيات المرصودة" the way a
manually-added full ayah does. That's also why the timeline card seemed
to only ever appear after auto-sync ran on an uploaded video: the manual
path that doesn't need video (adding a segment by hand) was never wired
up for partial excerpts, only whole ayahs.

This adds a second action to the partial-ayah picker -- "إضافة هذا
الجزء إلى الخط الزمني" -- that adds the selected word range as a real
TimelineSegment (chained after the last one, defaulting to +4s, same
pattern already used by the full-ayah manual-add dialog), which:
  - makes state.timelineActive true, so "مراجعة الآيات المرصودة"
    appears immediately -- no video/audio needed, exactly like manually
    adding a full ayah already works.
  - lets the user fine-tune the exact start/end afterward from that
    same review card, instead of needing a separate time-entry UI here.

To make a timeline segment able to carry a *partial* excerpt at all,
TimelineSegment gets a new optional `textOverride` field (null for
ordinary whole-ayah segments); karaoke chunking and export both already
run per-segment, so pointing buildKaraokeChunks() at
`textOverride ?? ayah.ar` is the one place that needed to change for
the sliced text to actually flow through to export.

Also widens the partial-text preview box (more padding) per the "make
more space in the text ui" request.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s118_partial_ayah_timeline_merge.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE"


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


# --- 1. TimelineSegment: add textOverride field ---------------------------

_SEGMENT_OLD = """class TimelineSegment {
  double start;
  double end;
  final Ayah ayah;
  double confidence;
  // PATCH_S55_WORD_TIMESTAMPS: absolute onsets (seconds into the clip) of
  // the words Whisper heard inside this segment — the karaoke lighting
  // paces itself along these instead of assuming an even reciting speed.
  final List<double> wordStarts;
  // PATCH_S82_AUTOSYNC_MAX: true when this segment was never acoustically
  // matched — it was inserted because its neighbours are the same surah with
  // exactly this ayah missing between them and there was recitation time in
  // the gap. The UI flags these so the user knows to double-check them.
  final bool inferred;
  TimelineSegment({
    required this.start,
    required this.end,
    required this.ayah,
    required this.confidence,
    List<double>? wordStarts,
    this.inferred = false,
  }) : wordStarts = wordStarts ?? [];
}"""

_SEGMENT_NEW = """class TimelineSegment {
  double start;
  double end;
  final Ayah ayah;
  double confidence;
  // PATCH_S55_WORD_TIMESTAMPS: absolute onsets (seconds into the clip) of
  // the words Whisper heard inside this segment — the karaoke lighting
  // paces itself along these instead of assuming an even reciting speed.
  final List<double> wordStarts;
  // PATCH_S82_AUTOSYNC_MAX: true when this segment was never acoustically
  // matched — it was inserted because its neighbours are the same surah with
  // exactly this ayah missing between them and there was recitation time in
  // the gap. The UI flags these so the user knows to double-check them.
  final bool inferred;
  // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: when this segment is a sliced
  // word range from "استخدام جزء من الآية فقط" rather than the whole
  // ayah, the sliced text lives here -- null means "use ayah.ar as-is".
  final String? textOverride;
  TimelineSegment({
    required this.start,
    required this.end,
    required this.ayah,
    required this.confidence,
    List<double>? wordStarts,
    this.inferred = false,
    this.textOverride,
  }) : wordStarts = wordStarts ?? [];
}"""


# --- 2. addManualSegment: accept the optional override ---------------------

_ADDSEG_OLD = """  void addManualSegment(Ayah ayah, double start, double end) {
    final seg = TimelineSegment(
        start: start, end: end, ayah: ayah, confidence: 1.0);
    final idx = timeline.indexWhere((s) => s.start > start);
    if (idx == -1) {
      timeline.add(seg);
    } else {
      timeline.insert(idx, seg);
    }
    timelineActive = true;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
  }"""

_ADDSEG_NEW = """  void addManualSegment(Ayah ayah, double start, double end,
      {String? textOverride}) {
    final seg = TimelineSegment(
        start: start,
        end: end,
        ayah: ayah,
        confidence: 1.0,
        // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE
        textOverride: textOverride);
    final idx = timeline.indexWhere((s) => s.start > start);
    if (idx == -1) {
      timeline.add(seg);
    } else {
      timeline.insert(idx, seg);
    }
    timelineActive = true;
    trimFromIndex = -1;
    trimToIndex = -1;
    notifyListeners();
  }"""


# --- 3. buildKaraokeChunks: read the override when present ----------------

_CHUNKS_OLD = """List<KaraokeChunk> buildKaraokeChunks(TimelineSegment seg) {
  final words = seg.ayah.ar.trim().split(RegExp(r'\\s+'));"""

_CHUNKS_NEW = """List<KaraokeChunk> buildKaraokeChunks(TimelineSegment seg) {
  // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: a segment added from the
  // partial-ayah picker carries just the sliced words as textOverride --
  // karaoke chunking (and therefore export) reads that instead of the
  // full ayah when it's set.
  final words = (seg.textOverride ?? seg.ayah.ar).trim().split(RegExp(r'\\s+'));"""


# --- 4. _partialAyahSection: add the "add to timeline" action + more room -

_PANEL_OLD = """  Widget _partialAyahSection() {
    final a = _partialSourceAyah;
    if (a == null) return const SizedBox.shrink();
    final words = a.ar.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2) return const SizedBox.shrink();
    final from = _partialFromWord.clamp(0, words.length - 1);
    final to = _partialToWord.clamp(from, words.length - 1);
    final partialText = words.sublist(from, to + 1).join(' ');
    final isFull = from == 0 && to == words.length - 1;
    return Column(
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
          'فقط مثلاً بدل الآية كاملة.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'من كلمة'),
                value: from,
                items: [
                  for (var i = 0; i < words.length; i++)
                    DropdownMenuItem(
                      value: i,
                      // PATCH_S107_WORD_DROPDOWN_FONT: match the ayah font
                      // picked under 'خط الآية', same fix S105 already did
                      // for the preview box below.
                      child: Text('${i + 1}. ${words[i]}',
                          style: ayahTextStyle(state.fontKey, fontSize: 15)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _partialFromWord = v ?? 0;
                  if (_partialToWord < _partialFromWord) {
                    _partialToWord = _partialFromWord;
                  }
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'إلى كلمة'),
                value: to,
                items: [
                  for (var i = 0; i < words.length; i++)
                    DropdownMenuItem(
                      value: i,
                      // PATCH_S107_WORD_DROPDOWN_FONT: match the ayah font
                      // picked under 'خط الآية', same fix S105 already did
                      // for the preview box below.
                      child: Text('${i + 1}. ${words[i]}',
                          style: ayahTextStyle(state.fontKey, fontSize: 15)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _partialToWord = v ?? (words.length - 1);
                  if (_partialFromWord > _partialToWord) {
                    _partialFromWord = _partialToWord;
                  }
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: AyatColors.hairline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(partialText,
              textAlign: TextAlign.center,
              // PATCH_S105_DEFAULT_FONT_PREVIEW: use the ayah font the user
              // actually picked under 'خط الآية' (state.fontKey) instead of
              // the generic UI text style, so this preview matches what
              // will actually be exported.
              style: ayahTextStyle(state.fontKey,
                  fontSize: 20, color: AyatColors.parchment)),
        ),
        const SizedBox(height: 8),
        ElevatedButton(
          onPressed: isFull
              ? null
              : () {
                  _liveOverlay.value = null;
                  state.setAyah(
                    partialText,
                    a.en,
                    'جزء من: سورة ${a.surah} — آية ${a.num}',
                    surahNum: a.surahNum,
                    ayahNum: a.num,
                  );
                  _toast('تم استخدام جزء من الآية');
                },
          child: Text(isFull ? 'الآية كاملة محددة بالفعل' : 'استخدام هذا الجزء فقط'),
        ),
      ],
    );
  }"""

_PANEL_NEW = """  Widget _partialAyahSection() {
    final a = _partialSourceAyah;
    if (a == null) return const SizedBox.shrink();
    final words = a.ar.split(RegExp(r'\\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length < 2) return const SizedBox.shrink();
    final from = _partialFromWord.clamp(0, words.length - 1);
    final to = _partialToWord.clamp(from, words.length - 1);
    final partialText = words.sublist(from, to + 1).join(' ');
    final isFull = from == 0 && to == words.length - 1;
    return Column(
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
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'من كلمة'),
                value: from,
                items: [
                  for (var i = 0; i < words.length; i++)
                    DropdownMenuItem(
                      value: i,
                      // PATCH_S107_WORD_DROPDOWN_FONT: match the ayah font
                      // picked under 'خط الآية', same fix S105 already did
                      // for the preview box below.
                      child: Text('${i + 1}. ${words[i]}',
                          style: ayahTextStyle(state.fontKey, fontSize: 15)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _partialFromWord = v ?? 0;
                  if (_partialToWord < _partialFromWord) {
                    _partialToWord = _partialFromWord;
                  }
                }),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: DropdownButtonFormField<int>(
                decoration: const InputDecoration(labelText: 'إلى كلمة'),
                value: to,
                items: [
                  for (var i = 0; i < words.length; i++)
                    DropdownMenuItem(
                      value: i,
                      // PATCH_S107_WORD_DROPDOWN_FONT: match the ayah font
                      // picked under 'خط الآية', same fix S105 already did
                      // for the preview box below.
                      child: Text('${i + 1}. ${words[i]}',
                          style: ayahTextStyle(state.fontKey, fontSize: 15)),
                    ),
                ],
                onChanged: (v) => setState(() {
                  _partialToWord = v ?? (words.length - 1);
                  if (_partialFromWord > _partialToWord) {
                    _partialFromWord = _partialToWord;
                  }
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: more breathing room around
        // the preview text itself (was a tight EdgeInsets.all(10)).
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          decoration: BoxDecoration(
            border: Border.all(color: AyatColors.hairline),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(partialText,
              textAlign: TextAlign.center,
              // PATCH_S105_DEFAULT_FONT_PREVIEW: use the ayah font the user
              // actually picked under 'خط الآية' (state.fontKey) instead of
              // the generic UI text style, so this preview matches what
              // will actually be exported.
              style: ayahTextStyle(state.fontKey,
                  fontSize: 20, color: AyatColors.parchment)),
        ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: isFull
              ? null
              : () {
                  _liveOverlay.value = null;
                  state.setAyah(
                    partialText,
                    a.en,
                    'جزء من: سورة ${a.surah} — آية ${a.num}',
                    surahNum: a.surahNum,
                    ayahNum: a.num,
                  );
                  _toast('تم استخدام جزء من الآية');
                },
          child: Text(isFull ? 'الآية كاملة محددة بالفعل' : 'استخدام هذا الجزء فقط'),
        ),
        const SizedBox(height: 8),
        // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: the missing link between
        // this picker and "نطاق آيات متعدد" -- adds the sliced words as a
        // real timeline segment (chained after the last one, like the
        // full-ayah manual-add dialog), which makes timelineActive true
        // and brings up "مراجعة الآيات المرصودة" immediately. No video or
        // audio required, same as adding a full ayah manually.
        OutlinedButton.icon(
          onPressed: isFull
              ? null
              : () {
                  final start =
                      state.timeline.isNotEmpty ? state.timeline.last.end : 0.0;
                  final end = start + 4;
                  state.addManualSegment(a, start, end,
                      textOverride: partialText);
                  _toast(
                      'أُضيف هذا الجزء إلى الخط الزمني ✓ — عدّلي توقيته من '
                      '\\'مراجعة الآيات المرصودة\\' أعلى الشاشة');
                },
          icon: const Icon(Icons.playlist_add, size: 18),
          label: const Text('إضافة هذا الجزء إلى الخط الزمني'),
        ),
      ],
    );
  }"""


# --- 5. flag partial-excerpt segments in the timeline review list --------

_ROW_OLD = """                      Flexible(
                        child: Text(
                            'سورة ${seg.ayah.surah} — آية ${seg.ayah.num}',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge),
                      ),"""

_ROW_NEW = """                      Flexible(
                        child: Text(
                            // PATCH_S118_PARTIAL_AYAH_TIMELINE_MERGE: mark
                            // segments that only carry part of the ayah so
                            // they're not mistaken for the full ayah at a
                            // glance in the review list.
                            'سورة ${seg.ayah.surah} — آية ${seg.ayah.num}'
                            '${seg.textOverride != null ? ' (جزء)' : ''}',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyLarge),
                      ),"""


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(f"Usage: python3 {pathlib.Path(__file__).name} <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()

    state_file = None
    panel_file = None
    chunks_file = None
    for p in (root / "lib").rglob("*.dart"):
        content = p.read_text(encoding="utf-8")
        if "class TimelineSegment {" in content:
            state_file = p
        if "Widget _partialAyahSection()" in content:
            panel_file = p
        if "List<KaraokeChunk> buildKaraokeChunks(TimelineSegment seg) {" in content:
            chunks_file = p
    if state_file is None:
        raise SystemExit("ERROR: could not find 'class TimelineSegment {' under lib/.")
    if panel_file is None:
        raise SystemExit("ERROR: could not find 'Widget _partialAyahSection()' under lib/.")
    if chunks_file is None:
        raise SystemExit(
            "ERROR: could not find 'List<KaraokeChunk> buildKaraokeChunks(...)' under lib/."
        )

    print(f"Applying {MARKER}...")
    replace_once(state_file, _SEGMENT_OLD, _SEGMENT_NEW, "TimelineSegment.textOverride field")
    replace_once(state_file, _ADDSEG_OLD, _ADDSEG_NEW, "addManualSegment textOverride param")
    replace_once(chunks_file, _CHUNKS_OLD, _CHUNKS_NEW, "buildKaraokeChunks reads textOverride")
    replace_once(panel_file, _PANEL_OLD, _PANEL_NEW,
                 "partial-ayah section: add-to-timeline button + more padding")
    replace_once(panel_file, _ROW_OLD, _ROW_NEW, "flag partial segments in review list")
    print(f"Done. {MARKER} applied.")


if __name__ == "__main__":
    main()
