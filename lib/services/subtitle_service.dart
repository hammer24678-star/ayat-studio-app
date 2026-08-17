// PATCH_S125_SUBTITLES: captions were burn-in only. Once the ayah text is
// painted into the pixels it can't be turned off, translated, indexed by
// YouTube, or read by anyone using a screen reader — and a reciter who wants
// the same clip with and without on-screen text had to export twice.
//
// The auto-sync timeline already knows exactly which ayah was recited
// between which two seconds. That IS a subtitle track; it just had nowhere
// to go. This writes it out as SRT or WebVTT alongside the MP4.
import 'dart:math';

import '../models/studio_state.dart';

enum SubtitleFormat {
  /// The universal one — every player, every editor, YouTube, Instagram.
  srt,

  /// The web one — HTML5 <track>, and what most browsers prefer.
  vtt,
}

extension SubtitleFormatMeta on SubtitleFormat {
  String get extension => switch (this) {
        SubtitleFormat.srt => 'srt',
        SubtitleFormat.vtt => 'vtt',
      };

  String get labelAr => switch (this) {
        SubtitleFormat.srt => 'SRT (الأشهر)',
        SubtitleFormat.vtt => 'WebVTT (للويب)',
      };

  String get labelEn => switch (this) {
        SubtitleFormat.srt => 'SRT (most common)',
        SubtitleFormat.vtt => 'WebVTT (for the web)',
      };
}

/// What each cue should say.
enum SubtitleContent {
  /// Arabic ayah text only.
  arabic,

  /// English meaning only.
  translation,

  /// Arabic on the first line, the meaning underneath.
  both,
}

class SubtitleService {
  /// `HH:MM:SS,mmm` for SRT, `HH:MM:SS.mmm` for VTT. Both are always
  /// zero-padded to hours, which some players insist on.
  static String formatTimestamp(double seconds, SubtitleFormat format) {
    final clamped = max(0.0, seconds);
    final totalMs = (clamped * 1000).round();
    final ms = totalMs % 1000;
    final totalSec = totalMs ~/ 1000;
    final s = totalSec % 60;
    final m = (totalSec ~/ 60) % 60;
    final h = totalSec ~/ 3600;
    final sep = format == SubtitleFormat.srt ? ',' : '.';
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}$sep'
        '${ms.toString().padLeft(3, '0')}';
  }

  /// Builds the subtitle file body for [segments].
  ///
  /// [clipStart] is subtracted from every time, because the timeline is in
  /// SOURCE time while the exported file starts at zero — getting this wrong
  /// is the classic "subtitles drift by exactly the trim offset" bug.
  ///
  /// [leadInSec] shifts everything later, for when a bismillah card is
  /// prepended to the export and pushes the recitation down the timeline.
  ///
  /// Segments outside the exported range are dropped, not clamped to zero;
  /// a pile of cues stacked at 00:00 is worse than no cues.
  static String build(
    List<TimelineSegment> segments, {
    required SubtitleFormat format,
    SubtitleContent content = SubtitleContent.arabic,
    double clipStart = 0,
    double clipDuration = double.infinity,
    double leadInSec = 0,
    bool includeReference = false,
  }) {
    final buf = StringBuffer();
    if (format == SubtitleFormat.vtt) buf.writeln('WEBVTT\n');

    var index = 0;
    for (final seg in segments) {
      final start = seg.start - clipStart;
      final end = seg.end - clipStart;
      // Entirely before or after the exported window.
      if (end <= 0 || start >= clipDuration) continue;
      final from = max(0.0, start) + leadInSec;
      final to = min(clipDuration, end) + leadInSec;
      if (to - from < 0.05) continue; // too short to read, and to render

      final text = _cueText(seg, content, includeReference);
      if (text.trim().isEmpty) continue;

      index++;
      // VTT allows a cue identifier too, and players show it in some
      // editors, so both formats get the running number.
      buf.writeln('$index');
      buf.writeln('${formatTimestamp(from, format)} --> '
          '${formatTimestamp(to, format)}');
      buf.writeln(text);
      buf.writeln();
    }
    return buf.toString();
  }

  static String _cueText(
      TimelineSegment seg, SubtitleContent content, bool includeReference) {
    // A segment sliced to a word range carries its own text; the whole ayah
    // would be wrong for it.
    final arabic = (seg.textOverride ?? seg.ayah.ar).trim();
    final english = seg.ayah.en.trim();
    final reference = includeReference
        ? '[${seg.ayah.surah} ${seg.ayah.num}]'
        : '';

    final lines = <String>[];
    switch (content) {
      case SubtitleContent.arabic:
        if (arabic.isNotEmpty) lines.add(arabic);
      case SubtitleContent.translation:
        if (english.isNotEmpty) lines.add(english);
      case SubtitleContent.both:
        if (arabic.isNotEmpty) lines.add(arabic);
        if (english.isNotEmpty) lines.add(english);
    }
    if (reference.isNotEmpty && lines.isNotEmpty) lines.add(reference);
    // Subtitle files are line-based: a literal newline inside an ayah would
    // split one cue into two malformed ones.
    return lines.map((l) => l.replaceAll(RegExp(r'[\r\n]+'), ' ')).join('\n');
  }

  /// How many cues [build] would emit — for telling the user what they are
  /// about to get before they get it.
  static int cueCount(
    List<TimelineSegment> segments, {
    double clipStart = 0,
    double clipDuration = double.infinity,
  }) {
    var n = 0;
    for (final seg in segments) {
      final start = seg.start - clipStart;
      final end = seg.end - clipStart;
      if (end <= 0 || start >= clipDuration) continue;
      if (min(clipDuration, end) - max(0.0, start) < 0.05) continue;
      n++;
    }
    return n;
  }
}
