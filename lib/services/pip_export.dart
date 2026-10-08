// PATCH_S188_PIP
// Picture-in-picture in the exported video.
//
// Every clip becomes: media input -> scale/crop to its box -> (rounded /
// circle mask) -> opacity -> soft ends -> rotation -> shifted to its place on
// the timeline -> overlaid on the video for exactly its window. Same geometry
// as PipLayer (the live preview), so export == preview.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/pip_clip.dart';
import '../models/studio_state.dart';

/// What the exporter prepared before building the command.
class PipExportPrep {
  /// clip id -> mask PNG (rounded / circle shapes only).
  final Map<int, String> masks;

  /// clip ids whose media file still exists; null = trust every clip.
  final Set<int>? usable;
  const PipExportPrep({this.masks = const {}, this.usable});
}

/// One clip as it is exported.
class PipPlan {
  final PipClip clip;

  /// Window on the OUTPUT clock (seconds from the start of the export).
  final double ws;
  final double we;

  /// Where in the media the window starts.
  final double ss;

  /// Box in output pixels (always even).
  final int pw;
  final int ph;
  const PipPlan(this.clip, this.ws, this.we, this.ss, this.pw, this.ph);
  double get len => we - ws;
}

class PipExport {
  static int _even(double v, int lo) {
    var n = v.round();
    if (n < lo) n = lo;
    if (n.isOdd) n += 1;
    return n;
  }

  /// The clips that actually show in the export, in layer order.
  static List<PipPlan> plan(StudioState st, int w, int h, double clipStart,
      double duration, Set<int>? usable) {
    final out = <PipPlan>[];
    for (final c in st.pipClips) {
      if (usable != null && !usable.contains(c.id)) continue;
      final ws = (c.start - clipStart).clamp(0.0, duration).toDouble();
      final we = (c.end - clipStart).clamp(ws, duration).toDouble();
      if (we - ws < 0.1) continue;
      final pw = _even(w * c.width.clamp(0.05, 1.6).toDouble(), 16);
      final ph = _even(pw / c.boxAspect, 16);
      out.add(PipPlan(c, ws, we, c.mediaTimeAt(math.max(c.start, clipStart)),
          pw, ph));
    }
    return out;
  }

  /// Checks the files and draws the shape masks. Call before building the
  /// ffmpeg command.
  static Future<PipExportPrep> prepare(StudioState st, String workDir, int w,
      int h, double clipStart, double duration) async {
    if (st.pipClips.isEmpty) return const PipExportPrep();
    final usable = <int>{
      for (final c in st.pipClips)
        if (File(c.path).existsSync()) c.id
    };
    final masks = <int, String>{};
    for (final p in plan(st, w, h, clipStart, duration, usable)) {
      if (p.clip.shape == PipShape.rect) continue;
      final rect = ui.Rect.fromLTWH(0, 0, p.pw.toDouble(), p.ph.toDouble());
      final rec = ui.PictureRecorder();
      final cv = ui.Canvas(rec);
      cv.drawRect(rect, ui.Paint()..color = const ui.Color(0xFF000000));
      final paint = ui.Paint()
        ..color = const ui.Color(0xFFFFFFFF)
        ..isAntiAlias = true;
      if (p.clip.shape == PipShape.circle) {
        cv.drawOval(rect, paint);
      } else {
        cv.drawRRect(
            ui.RRect.fromRectAndRadius(
                rect,
                ui.Radius.circular(
                    math.min(p.pw, p.ph).toDouble() * kPipRounded)),
            paint);
      }
      final img = await rec.endRecording().toImage(p.pw, p.ph);
      final bd = await img.toByteData(format: ui.ImageByteFormat.png);
      img.dispose();
      if (bd == null) continue;
      final f = File('$workDir/pipmask_${p.clip.id}.png');
      await f.writeAsBytes(bd.buffer.asUint8List());
      masks[p.clip.id] = f.path;
    }
    return PipExportPrep(masks: masks, usable: usable);
  }

  /// Adds the inputs and filters of every clip. Returns the new video label
  /// and the next free input index.
  static ({String base, int idx}) append({
    required StringBuffer inputs,
    required List<String> filters,
    required int idx,
    required String base,
    required StudioState st,
    required int w,
    required int h,
    required double clipStart,
    required double duration,
    required int fps,
    PipExportPrep? prep,
  }) {
    var n = 0;
    for (final p in plan(st, w, h, clipStart, duration, prep?.usable)) {
      final c = p.clip;
      final len = p.len;
      final lenS = len.toStringAsFixed(3);

      // ---- media input: pictures loop, short videos loop inside the window
      final inIdx = idx++;
      if (c.isImage) {
        inputs.write('-loop 1 -t $lenS -i "${c.path}" ');
      } else {
        final runsOut = c.mediaDur > 0.05 && (c.mediaDur - p.ss) < len - 0.02;
        inputs.write('${runsOut ? '-stream_loop -1 ' : ''}'
            '-ss ${p.ss.toStringAsFixed(3)} -t $lenS -i "${c.path}" ');
      }
      filters.add('[$inIdx:v]fps=$fps,'
          'scale=${p.pw}:${p.ph}:force_original_aspect_ratio=increase,'
          'crop=${p.pw}:${p.ph},format=rgba[pa$n]');
      var cur = 'pa$n';

      // ---- rounded / circle: a black-and-white mask becomes the alpha
      final maskPath = prep?.masks[c.id];
      if (c.shape != PipShape.rect && maskPath != null) {
        inputs.write('-loop 1 -t $lenS -i "$maskPath" ');
        final mIdx = idx++;
        filters.add('[$mIdx:v]format=gray[pm$n]');
        filters.add('[$cur][pm$n]alphamerge[pb$n]');
        cur = 'pb$n';
      }

      // ---- opacity, soft ends, rotation, then slide onto the timeline
      final tail = <String>[];
      if (c.opacity < 0.999) {
        tail.add(
            'colorchannelmixer=aa=${c.opacity.clamp(0.0, 1.0).toStringAsFixed(3)}');
      }
      if (c.fade) {
        final f = math.min(kPipFade, len / 2);
        if (f > 0.05) {
          tail.add('fade=t=in:st=0:d=${f.toStringAsFixed(3)}:alpha=1');
          tail.add(
              'fade=t=out:st=${(len - f).toStringAsFixed(3)}:d=${f.toStringAsFixed(3)}:alpha=1');
        }
      }
      if (c.rot.abs() > 0.05) {
        final a = (c.rot * math.pi / 180).toStringAsFixed(5);
        tail.add("rotate=a=$a:ow='rotw($a)':oh='roth($a)':c=none");
      }
      tail.add('setpts=PTS-STARTPTS+${p.ws.toStringAsFixed(3)}/TB');
      filters.add('[$cur]${tail.join(',')}[pip$n]');

      // ---- onto the picture, only inside its window
      final out = 'pipo$n';
      filters.add("[$base][pip$n]overlay="
          "x='${(c.cx * w).toStringAsFixed(2)}-w/2':"
          "y='${(c.cy * h).toStringAsFixed(2)}-h/2':"
          "eof_action=pass:"
          "enable='between(t,${p.ws.toStringAsFixed(3)},${p.we.toStringAsFixed(3)})'"
          "[$out]");
      base = out;
      n++;
    }
    return (base: base, idx: idx);
  }
}
