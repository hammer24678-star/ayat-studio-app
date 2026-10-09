// PATCH_S195_AUDIO_TAB
// Sounds laid on the timeline: music, effects, a voice-over, or the sound of
// another video. Pure Dart. The live player (AudioLayer), the timeline lane
// and the exporter all read THIS geometry, so what you hear while editing is
// what gets mixed into the exported file.
//
// Times are seconds on the main clip's own clock - the same clock the text
// blocks, the ayah blocks and the PIP clips use.
import 'dart:math' as math;

enum AudioKind { music, effect, voice, extracted }

String audioKindLabel(AudioKind k) => switch (k) {
      AudioKind.music => 'موسيقى',
      AudioKind.effect => 'مؤثر',
      AudioKind.voice => 'تعليق',
      AudioKind.extracted => 'من فيديو',
    };

/// Shortest a sound may be (seconds).
const double kAudioMinLen = 0.3;

/// Loudest a sound may be set (1.0 = as recorded). Above 1.0 only the
/// exported file gets the boost; the live preview player tops out at 1.0.
const double kAudioMaxVol = 2.0;

class AudioClip {
  static int _seq = 1;

  /// Stable identity (survives undo / redo copies).
  final int id;
  String path;
  String name;
  AudioKind kind;

  /// Length of the media in seconds (0 when unknown).
  double mediaDur;

  /// Window on the main clip's clock.
  double start;
  double end;

  /// Where inside the media the window begins (seconds).
  double srcIn;

  /// 0..kAudioMaxVol, 1.0 = as recorded.
  double volume;

  /// Soft start / end (seconds).
  double fadeIn;
  double fadeOut;

  /// Repeat the media when the window is longer than it.
  bool loop;

  /// Silent, but kept on the timeline.
  bool muted;

  AudioClip({
    int? id,
    required this.path,
    required this.name,
    this.kind = AudioKind.music,
    this.mediaDur = 0,
    required this.start,
    required this.end,
    this.srcIn = 0,
    this.volume = 1.0,
    this.fadeIn = 0.0,
    this.fadeOut = 0.0,
    this.loop = false,
    this.muted = false,
  }) : id = id ?? _seq++;

  AudioClip _clone(int? newId) => AudioClip(
        id: newId,
        path: path,
        name: name,
        kind: kind,
        mediaDur: mediaDur,
        start: start,
        end: end,
        srcIn: srcIn,
        volume: volume,
        fadeIn: fadeIn,
        fadeOut: fadeOut,
        loop: loop,
        muted: muted,
      );

  AudioClip copy() => _clone(id);

  /// A fresh sound (new identity) with the same look and timing.
  AudioClip duplicate() => _clone(null);

  /// The second half of a cut: it carries on exactly where the first half
  /// stops, without a fresh fade-in.
  AudioClip splitTail(double t) {
    final c = _clone(null);
    c.start = t;
    c.end = end;
    c.srcIn = srcIn + (t - start);
    c.fadeIn = 0.0;
    return c;
  }

  double get length => end - start;

  bool activeAt(double t) => t >= start && t < end;

  /// Effective fade lengths: never more than half the sound.
  double get fadeInLen => math.min(fadeIn, length / 2);
  double get fadeOutLen => math.min(fadeOut, length / 2);

  /// Where in the media the sound should be at main-clock time [t]
  /// (wraps when [loop] is on).
  double mediaTimeAt(double t) {
    final raw = srcIn + (t - start);
    if (mediaDur < 0.05) return raw < 0 ? 0.0 : raw;
    if (loop) {
      final m = raw % mediaDur;
      return m < 0 ? m + mediaDur : m;
    }
    return raw < 0 ? 0.0 : (raw > mediaDur ? mediaDur : raw);
  }

  /// True while there is still media left to play at [t].
  bool playsAt(double t) {
    if (!activeAt(t)) return false;
    if (loop || mediaDur < 0.05) return true;
    return srcIn + (t - start) < mediaDur - 0.02;
  }

  /// 0..kAudioMaxVol loudness at [t]: the volume times the fades. The
  /// exporter writes the same ramps with ffmpeg's afade.
  double gainAt(double t) {
    if (muted || !activeAt(t)) return 0.0;
    var g = volume;
    final fi = fadeInLen;
    final fo = fadeOutLen;
    if (fi > 0.001) g *= ((t - start) / fi).clamp(0.0, 1.0).toDouble();
    if (fo > 0.001) g *= ((end - t) / fo).clamp(0.0, 1.0).toDouble();
    return g;
  }
}

/// Puts sounds that overlap in time on different rows of the timeline lane
/// (at most [maxRows]; past that they share the row that frees up first).
/// Returns one row number per clip, in the clips' own order.
List<int> assignAudioRows(List<AudioClip> clips, {int maxRows = 3}) {
  final order = List<int>.generate(clips.length, (i) => i)
    ..sort((a, b) => clips[a].start.compareTo(clips[b].start));
  final rows = List<int>.filled(clips.length, 0);
  final ends = <double>[];
  for (final i in order) {
    final c = clips[i];
    var r = ends.indexWhere((e) => e <= c.start + 1e-6);
    if (r < 0) {
      if (ends.length < maxRows) {
        ends.add(c.end);
        r = ends.length - 1;
      } else {
        var best = 0;
        for (var k = 1; k < ends.length; k++) {
          if (ends[k] < ends[best]) best = k;
        }
        r = best;
        ends[r] = math.max(ends[r], c.end);
      }
    } else {
      ends[r] = c.end;
    }
    rows[i] = r;
  }
  return rows;
}
