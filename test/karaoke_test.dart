// PATCH_S33_KARAOKE_WORD_HIGHLIGHT: timing math for the word-lighting
// captions — chunk splitting, proportional windows and cue resolution.
import 'package:flutter_test/flutter_test.dart';

import 'package:ayat_studio_app/models/studio_state.dart';
import 'package:ayat_studio_app/services/ayah_matcher.dart';
import 'package:ayat_studio_app/services/karaoke.dart';

TimelineSegment seg(String ar, String en, double start, double end) =>
    TimelineSegment(
      start: start,
      end: end,
      confidence: 1,
      ayah: Ayah(surahNum: 15, surah: 'الحجر', num: 54, ar: ar, en: en),
    );

// PATCH_S42_KARAOKE_WEIGHTED: timing is letter-weighted now, so the helper
// pads the counter to keep every generated word the same length — with equal
// weights the original word-proportional expectations still hold exactly.
String words(int n, [String stem = 'كلمة']) =>
    List.generate(n, (i) => '$stem${(i + 1).toString().padLeft(2, '0')}')
        .join(' ');

void main() {
  test('short ayah stays as a single chunk covering the whole segment', () {
    final chunks = buildKaraokeChunks(seg(words(8), 'short line', 2.0, 6.0));
    expect(chunks.length, 1);
    expect(chunks.single.words.length, 8);
    expect(chunks.single.start, 2.0);
    expect(chunks.single.end, 6.0);
    expect(chunks.single.translation, 'short line');
  });

  test('long ayahs split into 2-3 parts above 12 words', () {
    expect(buildKaraokeChunks(seg(words(12), '', 0, 10)).length, 1);
    expect(buildKaraokeChunks(seg(words(13), '', 0, 10)).length, 2);
    expect(buildKaraokeChunks(seg(words(24), '', 0, 10)).length, 2);
    expect(buildKaraokeChunks(seg(words(30), '', 0, 10)).length, 3);
  });

  test('chunks tile the segment with word-proportional windows', () {
    final chunks = buildKaraokeChunks(seg(words(20), words(10, 'en'), 4.0, 14.0));
    expect(chunks.length, 2);
    expect(chunks[0].words.length + chunks[1].words.length, 20);
    expect(chunks[0].start, 4.0);
    expect(chunks[0].end, chunks[1].start);
    expect(chunks[1].end, 14.0);
    // 10+10 words -> equal halves of the 10s window
    expect(chunks[0].end, closeTo(9.0, 1e-9));
    // translation split follows the same part boundaries
    expect(chunks[0].translation, words(5, 'en'));
    expect(
        '${chunks[0].translation} ${chunks[1].translation}', words(10, 'en'));
  });

  test('cue lights words progressively and holds the full line at the end',
      () {
    final chunks = buildKaraokeChunks(seg(words(10), '', 0.0, 10.0));
    expect(karaokeCueAt(chunks, 0.0).litWords, 1); // first word lights at once
    final mid = karaokeCueAt(chunks, 4.5).litWords;
    expect(mid, greaterThan(1));
    expect(mid, lessThan(10));
    // lighting finishes within kKaraokeLightingSpan of the window
    expect(karaokeCueAt(chunks, 10.0 * kKaraokeLightingSpan).litWords, 10);
    expect(karaokeCueAt(chunks, 9.9).litWords, 10);
    // fp edge exactly at the segment end: keep the fully lit last chunk
    final atEnd = karaokeCueAt(chunks, 10.0);
    expect(atEnd.litWords, 10);
    expect(atEnd.chunk.index, chunks.last.index);
  });

  // PATCH_S42_KARAOKE_WEIGHTED
  test('longer words hold the highlight longer than short ones', () {
    // one very long word then many short ones: the long word must consume
    // clearly more than 1/n of the lighting window
    final chunks =
        buildKaraokeChunks(seg('طويييييييييييييلة ثم كلمات قصار هنا', '', 0.0, 10.0));
    final span = 10.0 * kKaraokeLightingSpan;
    // at 40% of the lighting window the first (heavy) word should still be
    // the only lit one — uniform timing would already be lighting word 2
    final cue = karaokeCueAt(chunks, span * 0.4);
    expect(cue.litWords, 1);
    // and everything is lit by the end of the lighting span
    expect(karaokeCueAt(chunks, span).litWords, 5);
  });

  // PATCH_S42_KARAOKE_WEIGHTED: chunk windows follow letter mass
  test('a heavier first half gets the longer time window', () {
    final light = words(7, 'قص'); // short words
    final heavy = words(7, 'طويييييييلة'); // long words
    final chunks = buildKaraokeChunks(seg('$heavy $light', '', 0.0, 10.0));
    expect(chunks.length, 2);
    final firstDur = chunks[0].end - chunks[0].start;
    final secondDur = chunks[1].end - chunks[1].start;
    expect(firstDur, greaterThan(secondDur));
    expect(chunks[0].end, chunks[1].start);
    expect(chunks[1].end, 10.0);
  });

  test('cue never crosses chunk boundaries', () {
    final chunks = buildKaraokeChunks(seg(words(24), '', 0.0, 12.0));
    final first = karaokeCueAt(chunks, 5.9);
    final second = karaokeCueAt(chunks, 6.1);
    expect(first.chunk.index, 0);
    expect(second.chunk.index, 1);
    expect(second.litWords, greaterThanOrEqualTo(1));
  });
}
