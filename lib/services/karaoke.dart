// PATCH_S33_KARAOKE_WORD_HIGHLIGHT
// Karaoke-style timing for the auto-sync timeline: instead of revealing an
// ayah character-by-character, the whole line is shown dimmed and each word
// lights up as the reciter reaches it. Long ayahs (more than
// [kKaraokeMaxWordsPerChunk] words) are split into 2-3+ sequential parts so
// the text stays large and readable, like classic Quran-video captions.
// Used identically by the live preview (home_screen._tickAutoSync) and the
// exporter (export_service._renderKaraokeSequence) so what you see during
// playback is exactly what gets burned into the MP4.
import 'dart:math';

import '../models/studio_state.dart';

/// An ayah with more words than this gets split into multiple parts.
const int kKaraokeMaxWordsPerChunk = 12;

/// Words finish lighting up within this fraction of the chunk's window; the
/// remaining tail holds the fully lit line before the next part fades in.
const double kKaraokeLightingSpan = 0.9;

// PATCH_S42_KARAOKE_WEIGHTED: reciters dwell longer on longer words (more
// letters, more madd) — so time is carved per word as its letter count plus
// a constant per-word beat, instead of assuming equal time for every word.
// The constant keeps very short words (لا، من، بل) from flashing by.
double _wordWeight(String word) => word.length + 2.0;

double _weightOf(Iterable<String> words) =>
    words.fold(0.0, (sum, w) => sum + _wordWeight(w));

/// One sequential part of an ayah on the karaoke timeline. [start]/[end] are
/// absolute seconds into the source clip, carved out of the parent
/// [TimelineSegment] proportionally to each part's word count (the reciter
/// spends roughly equal time per word).
class KaraokeChunk {
  final List<String> words;
  final String translation;
  final double start;
  final double end;
  final int index;
  final int totalChunks;
  KaraokeChunk({
    required this.words,
    required this.translation,
    required this.start,
    required this.end,
    required this.index,
    required this.totalChunks,
  });

  String get text => words.join(' ');
}

/// What should be on screen at one instant: a chunk and how many of its
/// words have already been recited (and should therefore be lit).
class KaraokeCue {
  final KaraokeChunk chunk;
  final int litWords;
  const KaraokeCue(this.chunk, this.litWords);
}

List<KaraokeChunk> buildKaraokeChunks(TimelineSegment seg) {
  final words = seg.ayah.ar.trim().split(RegExp(r'\s+'));
  final total = words.length;
  final parts = max(1, (total / kKaraokeMaxWordsPerChunk).ceil());
  final enWords = seg.ayah.en.trim().isEmpty
      ? const <String>[]
      : seg.ayah.en.trim().split(RegExp(r'\s+'));
  final segDur = max(0.001, seg.end - seg.start);
  // PATCH_S42_KARAOKE_WEIGHTED: each part's share of the recitation window
  // follows its letter mass, not just its word count.
  final totalWeight = max(0.001, _weightOf(words));
  final chunks = <KaraokeChunk>[];
  var wordFrom = 0;
  var enFrom = 0;
  var tFrom = seg.start;
  for (var p = 0; p < parts; p++) {
    final wordTo = ((p + 1) * total / parts).round();
    final enTo = ((p + 1) * enWords.length / parts).round();
    final isLast = p == parts - 1;
    final tTo = isLast
        ? seg.end
        : tFrom +
            segDur * _weightOf(words.sublist(wordFrom, wordTo)) / totalWeight;
    chunks.add(KaraokeChunk(
      words: words.sublist(wordFrom, wordTo),
      translation: enWords.sublist(enFrom, enTo).join(' '),
      start: tFrom,
      end: tTo,
      index: p,
      totalChunks: parts,
    ));
    wordFrom = wordTo;
    enFrom = enTo;
    tFrom = tTo;
  }
  return chunks;
}

/// Resolves which chunk is on screen at clip-time [t] and how many of its
/// words are lit. Falls back to the fully lit last chunk for the fp-edge
/// right at the segment's end, so the line never flickers off early.
KaraokeCue karaokeCueAt(List<KaraokeChunk> chunks, double t) {
  for (final c in chunks) {
    if (t >= c.start && t < c.end) {
      final dur = max(0.001, c.end - c.start);
      final frac = ((t - c.start) / (dur * kKaraokeLightingSpan)).clamp(0.0, 1.0);
      // PATCH_S42_KARAOKE_WEIGHTED: a word lights once the reciter's
      // letter-mass progress reaches its start — long words hold the
      // highlight longer, short particles pass quickly.
      final target = frac * _weightOf(c.words);
      var lit = 0;
      var cum = 0.0;
      for (final w in c.words) {
        if (cum >= target) break;
        lit++;
        cum += _wordWeight(w);
      }
      return KaraokeCue(c, max(1, lit));
    }
  }
  final last = chunks.last;
  return KaraokeCue(last, last.words.length);
}
