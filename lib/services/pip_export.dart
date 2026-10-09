// PATCH_S188_PIP
// PATCH_S193_PIP_POWER
// Picture-in-picture in the exported video.
//
// Every clip becomes: media input -> scale/crop to its box -> mirror ->
// picture adjust -> (transparent background) -> (rounded / circle mask) ->
// (frame) -> (shadow) -> opacity -> entrance / exit -> rotation -> shifted to
// its place on the timeline -> overlaid on the video for exactly its window.
// Same geometry as PipLayer (the live preview), so export == preview.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../models/pip_clip.dart';
import '../models/studio_state.dart';

/// What the exporter prepared before building the command.
class PipExportPrep {
  /// clip id -> mask PNG (rounded / circle shapes only).
  final Map<int, String> masks;

  /// clip id -> frame PNG (clips with a border).
  final Map<int, String> rings;

  /// clip id -> soft shadow PNG (clips with a shadow).
  final Map<int, String> shadows;

  /// clip ids whose media file still exists; null = trust every clip.
  final Set<int>? usable;
  const PipExportPrep({
    this.masks = const {},
    this.rings = const {},
    this.shadows = const {},
    this.usable,
  });
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

  /// Blur radius of the soft shadow, in output pixels.
  static double _shadowBlur(PipPlan p) => math.min(p.pw, p.ph) * 0.14;

  /// Empty margin the shadow picture adds around the box on every side.
  static int _shadowMargin(PipPlan p) => _even(_shadowBlur(p) * 1.6 + 4, 8);

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

  static Future<void> _writePng(ui.PictureRecorder rec, int w, int h,
      String path) async {
    final img = await rec.endRecording().toImage(w, h);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    if (bd == null) return;
    await File(path).writeAsBytes(bd.buffer.asUint8List());
  }

  static void _drawShape(
      ui.Canvas cv, PipPlan p, ui.Rect rect, ui.Paint paint) {
    switch (p.clip.shape) {
      case PipShape.rect:
        cv.drawRect(rect, paint);
      case PipShape.circle:
        cv.drawOval(rect, paint);
      case PipShape.rounded:
        cv.drawRRect(
            ui.RRect.fromRectAndRadius(
                rect,
                ui.Radius.circular(
                    math.min(p.pw, p.ph).toDouble() * p.clip.radiusFrac)),
            paint);
    }
  }

  /// Checks the files and draws the shape masks, frames and shadows. Call
  /// before building the ffmpeg command.
  static Future<PipExportPrep> prepare(StudioState st, String workDir, int w,
      int h, double clipStart, double duration) async {
    if (st.pipClips.isEmpty) return const PipExportPrep();
    final usable = <int>{
      for (final c in st.pipClips)
        if (File(c.path).existsSync()) c.id
    };
    final masks = <int, String>{};
    final rings = <int, String>{};
    final shadows = <int, String>{};
    for (final p in plan(st, w, h, clipStart, duration, usable)) {
      final c = p.clip;
      final rect = ui.Rect.fromLTWH(0, 0, p.pw.toDouble(), p.ph.toDouble());

      // ---- shape mask: white where the picture shows
      if (c.shape != PipShape.rect) {
        final rec = ui.PictureRecorder();
        final cv = ui.Canvas(rec);
        cv.drawRect(rect, ui.Paint()..color = const ui.Color(0xFF000000));
        _drawShape(
            cv,
            p,
            rect,
            ui.Paint()
              ..color = const ui.Color(0xFFFFFFFF)
              ..isAntiAlias = true);
        final f = '$workDir/pipmask_${c.id}.png';
        await _writePng(rec, p.pw, p.ph, f);
        if (File(f).existsSync()) masks[c.id] = f;
      }

      // ---- frame: a ring that follows the shape, drawn inside the box
      if (c.hasBorder) {
        final rec = ui.PictureRecorder();
        final cv = ui.Canvas(rec);
        final bwid = math.max(1.0, c.borderW * math.min(p.pw, p.ph));
        final stroke = ui.Paint()
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = bwid * 2
          ..isAntiAlias = true
          ..color = ui.Color(c.borderColor);
        switch (c.shape) {
          case PipShape.rect:
            cv.clipRect(rect);
          case PipShape.circle:
            cv.clipPath(ui.Path()..addOval(rect));
          case PipShape.rounded:
            cv.clipRRect(
                ui.RRect.fromRectAndRadius(
                    rect,
                    ui.Radius.circular(
                        math.min(p.pw, p.ph).toDouble() * c.radiusFrac)),
                doAntiAlias: true);
        }
        _drawShape(cv, p, rect, stroke);
        final f = '$workDir/pipring_${c.id}.png';
        await _writePng(rec, p.pw, p.ph, f);
        if (File(f).existsSync()) rings[c.id] = f;
      }

      // ---- shadow: a blurred copy of the shape, a little lower, in a
      // picture bigger than the box by a margin on every side
      if (c.shadow) {
        final m = _shadowMargin(p);
        final sw = p.pw + 2 * m;
        final sh = p.ph + 2 * m;
        final rec = ui.PictureRecorder();
        final cv = ui.Canvas(rec);
        final minSide = math.min(p.pw, p.ph).toDouble();
        final r2 = ui.Rect.fromLTWH(
            m.toDouble(), m + minSide * 0.04, p.pw.toDouble(), p.ph.toDouble());
        _drawShape(
            cv,
            p,
            r2,
            ui.Paint()
              ..color = const ui.Color(0x99000000)
              ..maskFilter =
                  ui.MaskFilter.blur(ui.BlurStyle.normal, _shadowBlur(p) / 2));
        final f = '$workDir/pipshadow_${c.id}.png';
        await _writePng(rec, sw, sh, f);
        if (File(f).existsSync()) shadows[c.id] = f;
      }
    }
    return PipExportPrep(
        masks: masks, rings: rings, shadows: shadows, usable: usable);
  }

  // ---- ffmpeg expression pieces (all times in seconds) ---------------------

  static String _n(double v) => v.toStringAsFixed(3);

  /// Smooth 0..1 ramp of the progress expression [p].
  static String _ease(String p) => '($p*$p*(3-2*$p))';

  /// Progress of the entrance / exit as an expression of the frame time `t`.
  /// [origin] is where the clip's own clock starts: 0 inside the clip's
  /// filters (their `t` starts at zero), the window start on the overlay (its
  /// `t` is the export clock).
  static String _pIn(double d, double origin) =>
      'clip((t-${_n(origin)})/${_n(d)},0,1)';
  static String _pOut(double d, double endAt) =>
      'clip((${_n(endAt)}-t)/${_n(d)},0,1)';

  static String? _scaleTerm(PipAnim a, String p) {
    switch (a) {
      case PipAnim.zoom:
        return '(0.5+0.5*${_ease(p)})';
      case PipAnim.pop:
        return 'max(0.02,(1+2.70158*pow($p-1,3)+1.70158*pow($p-1,2)))';
      case PipAnim.spin:
        return '(0.3+0.7*${_ease(p)})';
      default:
        return null;
    }
  }

  /// Extra turn in radians while arriving / leaving.
  static String? _rotTerm(PipAnim a, String p) {
    if (a != PipAnim.spin) return null;
    final rad = (kPipSpinDeg * math.pi / 180).toStringAsFixed(5);
    return '(-$rad*(1-${_ease(p)}))';
  }

  static String? _dxTerm(PipAnim a, String p, int w) {
    switch (a) {
      case PipAnim.slideLeft:
        return '(-(1-${_ease(p)})*$kPipSlideX*$w)';
      case PipAnim.slideRight:
        return '((1-${_ease(p)})*$kPipSlideX*$w)';
      default:
        return null;
    }
  }

  static String? _dyTerm(PipAnim a, String p, int h) {
    switch (a) {
      case PipAnim.slideUp:
        return '((1-${_ease(p)})*$kPipSlideY*$h)';
      case PipAnim.slideDown:
        return '(-(1-${_ease(p)})*$kPipSlideY*$h)';
      default:
        return null;
    }
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
      final head = StringBuffer('[$inIdx:v]fps=$fps,'
          'scale=${p.pw}:${p.ph}:force_original_aspect_ratio=increase,'
          'crop=${p.pw}:${p.ph}');
      if (c.flipH) head.write(',hflip');
      if (c.flipV) head.write(',vflip');
      if (c.hasAdjust) {
        head.write(',eq=brightness=${c.brightness.toStringAsFixed(3)}'
            ':contrast=${c.contrast.toStringAsFixed(3)}'
            ':saturation=${c.saturation.toStringAsFixed(3)}');
      }
      head.write(',format=rgba[pa$n]');
      filters.add(head.toString());
      var cur = 'pa$n';

      // ---- transparent background
      if (c.keyOn) {
        final hex = (c.keyColor & 0xFFFFFF)
            .toRadixString(16)
            .padLeft(6, '0')
            .toUpperCase();
        filters.add('[$cur]colorkey=0x$hex:'
            '${c.keySim.clamp(0.01, 1.0).toStringAsFixed(3)}:'
            '${c.keyBlend.clamp(0.0, 1.0).toStringAsFixed(3)}[pk$n]');
        cur = 'pk$n';
      }

      // ---- rounded / circle: a black-and-white mask becomes the alpha
      // (multiplied with the alpha the key left, so both hold)
      final maskPath = prep?.masks[c.id];
      if (c.shape != PipShape.rect && maskPath != null) {
        inputs.write('-loop 1 -t $lenS -i "$maskPath" ');
        final mIdx = idx++;
        filters.add('[$mIdx:v]format=gray[pm$n]');
        if (c.keyOn) {
          filters.add('[$cur]split=2[pkx$n][pky$n]');
          filters.add('[pky$n]alphaextract[pke$n]');
          filters.add('[pke$n][pm$n]blend=all_mode=multiply[pam$n]');
          filters.add('[pkx$n][pam$n]alphamerge[pb$n]');
        } else {
          filters.add('[$cur][pm$n]alphamerge[pb$n]');
        }
        cur = 'pb$n';
      }

      // ---- frame (inside the box)
      final ringPath = prep?.rings[c.id];
      if (c.hasBorder && ringPath != null) {
        inputs.write('-loop 1 -t $lenS -i "$ringPath" ');
        final rIdx = idx++;
        filters.add('[$rIdx:v]format=rgba[prr$n]');
        filters.add(
            '[$cur][prr$n]overlay=0:0:format=auto:shortest=1,format=rgba[pr$n]');
        cur = 'pr$n';
      }

      // ---- shadow (a bigger picture: the box sits in the middle of it)
      final shadowPath = prep?.shadows[c.id];
      if (c.shadow && shadowPath != null) {
        inputs.write('-loop 1 -t $lenS -i "$shadowPath" ');
        final sIdx = idx++;
        final m = _shadowMargin(p);
        filters.add('[$sIdx:v]format=rgba[psh$n]');
        filters.add('[psh$n][$cur]overlay=$m:$m:format=auto:shortest=1,'
            'format=rgba[ps$n]');
        cur = 'ps$n';
      }

      // ---- opacity, entrance / exit, rotation, then slide onto the timeline
      final tail = <String>[];
      if (c.opacity < 0.999) {
        tail.add(
            'colorchannelmixer=aa=${c.opacity.clamp(0.0, 1.0).toStringAsFixed(3)}');
      }
      final di = c.inLen;
      final dOut = c.outLen;
      final fadeIn = di * pipAnimAlphaFrac(c.inAnim);
      if (fadeIn > 0.04) {
        tail.add('fade=t=in:st=0:d=${_n(fadeIn)}:alpha=1');
      }
      final fadeOut = dOut * pipAnimAlphaFrac(c.outAnim);
      if (fadeOut > 0.04) {
        tail.add('fade=t=out:st=${_n(len - fadeOut)}:d=${_n(fadeOut)}:alpha=1');
      }

      // rotation: the clip's own angle plus the spin of an entrance / exit
      final pInRel = di > 0.001 ? _pIn(di, 0) : '1';
      final pOutRel = dOut > 0.001 ? _pOut(dOut, len) : '1';
      final spinIn = _rotTerm(c.inAnim, pInRel);
      final spinOut = _rotTerm(c.outAnim, pOutRel);
      if (spinIn != null || spinOut != null) {
        final parts = <String>[
          if (c.rot.abs() > 0.05) (c.rot * math.pi / 180).toStringAsFixed(5),
          if (spinIn != null) spinIn,
          if (spinOut != null) spinOut,
        ];
        tail.add("rotate=a='${parts.join('+')}':"
            "ow='hypot(iw,ih)':oh='hypot(iw,ih)':c=none");
      } else if (c.rot.abs() > 0.05) {
        final a = (c.rot * math.pi / 180).toStringAsFixed(5);
        tail.add("rotate=a=$a:ow='rotw($a)':oh='roth($a)':c=none");
      }

      // size change of an entrance / exit (zoom, pop, spin)
      final sIn = _scaleTerm(c.inAnim, pInRel);
      final sOut = _scaleTerm(c.outAnim, pOutRel);
      if (sIn != null || sOut != null) {
        final s = <String>[
          if (sIn != null) sIn,
          if (sOut != null) sOut,
        ].join('*');
        tail.add("scale=w='max(2,iw*$s)':h='max(2,ih*$s)':eval=frame");
      }
      tail.add('setpts=PTS-STARTPTS+${p.ws.toStringAsFixed(3)}/TB');
      filters.add('[$cur]${tail.join(',')}[pip$n]');

      // ---- onto the picture, only inside its window (slides move it here)
      final pInAbs = di > 0.001 ? _pIn(di, p.ws) : '1';
      final pOutAbs = dOut > 0.001 ? _pOut(dOut, p.we) : '1';
      final dxIn = _dxTerm(c.inAnim, pInAbs, w);
      final dxOut = _dxTerm(c.outAnim, pOutAbs, w);
      final dyIn = _dyTerm(c.inAnim, pInAbs, h);
      final dyOut = _dyTerm(c.outAnim, pOutAbs, h);
      final dxs = <String>[
        if (dxIn != null) dxIn,
        if (dxOut != null) dxOut,
      ];
      final dys = <String>[
        if (dyIn != null) dyIn,
        if (dyOut != null) dyOut,
      ];
      final xe =
          '${(c.cx * w).toStringAsFixed(2)}-w/2${dxs.map((e) => '+$e').join()}';
      final ye =
          '${(c.cy * h).toStringAsFixed(2)}-h/2${dys.map((e) => '+$e').join()}';
      final out = 'pipo$n';
      filters.add("[$base][pip$n]overlay="
          "x='$xe':"
          "y='$ye':"
          "eof_action=pass:"
          "enable='between(t,${p.ws.toStringAsFixed(3)},${p.we.toStringAsFixed(3)})'"
          "[$out]");
      base = out;
      n++;
    }
    return (base: base, idx: idx);
  }
}
