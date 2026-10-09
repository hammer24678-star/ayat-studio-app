// PATCH_S195_AUDIO_TAB
// The sounds of the Audio tab, in the exported video.
//
// Every sound becomes: media input -> stereo 44.1k -> volume -> fade in / out
// -> delayed to its place on the timeline -> padded with silence to the end,
// then ALL of them are mixed over the audio the export already has (the
// recitation, the clip's own sound, the ambience bed). Same windows, volume
// and fades as AudioClip.gainAt, so export == preview.
import 'dart:math' as math;

import '../models/audio_clip.dart';
import '../models/studio_state.dart';

/// One sound as it is exported.
class AudioPlan {
  final AudioClip clip;

  /// Window on the OUTPUT clock (seconds from the start of the export,
  /// after any speed change).
  final double ws;
  final double we;

  /// Where in the media the window begins.
  final double ss;
  const AudioPlan(this.clip, this.ws, this.we, this.ss);
  double get len => we - ws;
}

class AudioClipsExport {
  /// The sounds that actually play in the export, in timeline order.
  /// [speed] is the export speed: a sound keeps its own tempo, but its place
  /// on the timeline moves with the picture.
  static List<AudioPlan> plan(StudioState st, double clipStart,
      double duration, double speed, Set<int>? usable) {
    final out = <AudioPlan>[];
    final sp = speed < 0.01 ? 1.0 : speed;
    for (final c in st.audioClips) {
      if (c.muted || c.volume <= 0.005) continue;
      if (usable != null && !usable.contains(c.id)) continue;
      final a = (c.start - clipStart).clamp(0.0, duration).toDouble();
      final b = (c.end - clipStart).clamp(a, duration).toDouble();
      if (b - a < 0.1) continue;
      final ws = a / sp;
      var we = b / sp;
      final ss = c.mediaTimeAt(math.max(c.start, clipStart));
      if (!c.loop && c.mediaDur > 0.05) {
        // a sound that is shorter than its window simply ends early
        we = math.min(we, ws + (c.mediaDur - ss));
      }
      if (we - ws < 0.1) continue;
      out.add(AudioPlan(c, ws, we, ss));
    }
    return out;
  }

  /// Adds the inputs and filters of every sound and mixes them over the
  /// current audio. The current audio is either the graph label [aLabel] or,
  /// when that is null, the raw input stream [aStream] with the pending
  /// filters [aChain]. Returns the new audio label and the next free input
  /// index, or null when there is nothing to add.
  static ({String label, int idx})? append({
    required StringBuffer inputs,
    required List<String> filters,
    required int idx,
    required StudioState st,
    required double clipStart,
    required double duration,
    required double outDuration,
    required double speed,
    required String? aLabel,
    required String? aStream,
    required List<String> aChain,
    Set<int>? usable,
  }) {
    final plans = plan(st, clipStart, duration, speed, usable);
    if (plans.isEmpty) return null;

    var next = idx;
    var mainLabel = aLabel ?? 'aclbase';
    if (aLabel == null) {
      // whatever the audio is so far has to be a graph label before it can
      // be an amix input
      final head = aChain.isEmpty ? 'anull' : aChain.join(',');
      filters.add('[${aStream ?? '0:a'}]$head,aresample=44100[aclbase]');
      mainLabel = 'aclbase';
    }

    final labels = StringBuffer();
    for (var n = 0; n < plans.length; n++) {
      final p = plans[n];
      final c = p.clip;
      final lenS = p.len.toStringAsFixed(3);
      final looped = c.loop &&
          c.mediaDur > 0.05 &&
          (c.mediaDur - p.ss) < p.len - 0.02;
      inputs.write('${looped ? '-stream_loop -1 ' : ''}'
          '-ss ${p.ss.toStringAsFixed(3)} -t $lenS -i "${c.path}" ');
      final inIdx = next++;

      final vol = c.volume.clamp(0.0, kAudioMaxVol).toStringAsFixed(3);
      final parts = <String>[
        'aresample=44100',
        'aformat=sample_fmts=fltp:channel_layouts=stereo',
        'volume=$vol',
      ];
      final fi = math.min(c.fadeIn, p.len / 2);
      final fo = math.min(c.fadeOut, p.len / 2);
      if (fi > 0.04) {
        parts.add('afade=t=in:st=0:d=${fi.toStringAsFixed(3)}');
      }
      if (fo > 0.04) {
        parts.add('afade=t=out:st=${(p.len - fo).toStringAsFixed(3)}'
            ':d=${fo.toStringAsFixed(3)}');
      }
      final ms = (p.ws * 1000).round();
      if (ms > 0) parts.add('adelay=$ms|$ms');
      // silence after the sound, so amix never sees an input end early and
      // re-balances the others
      parts.add('apad');
      filters.add('[$inIdx:a]${parts.join(',')}[acl$n]');
      labels.write('[acl$n]');
    }

    // amix AVERAGES its inputs, so volume=N puts every input back at the
    // level that was set - the same convention the reciter and bed mixes use.
    final nIn = plans.length + 1;
    filters.add('[$mainLabel]${labels.toString()}'
        'amix=inputs=$nIn:duration=first:dropout_transition=0,'
        'volume=$nIn[aclips]');
    return (label: 'aclips', idx: next);
  }
}
