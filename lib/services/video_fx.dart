// PATCH_S194_CUT_FX
// The everyday video-editor looks (black & white, negative, cinematic bars,
// fade from / to black, flash, shake, pulse ...). Pure Dart: the preview
// (VideoFxLayer) and the exporter (VideoFxFilters) read the same table.
enum VideoFx {
  none,
  bw,
  negative,
  dramatic,
  warm,
  cool,
  bars,
  fadeIn,
  fadeOut,
  fadeBoth,
  flash,
  shake,
  pulse,
}

extension VideoFxInfo on VideoFx {
  String get label => switch (this) {
        VideoFx.none => 'بدون',
        VideoFx.bw => 'أبيض وأسود',
        VideoFx.negative => 'نيجاتيف',
        VideoFx.dramatic => 'درامي',
        VideoFx.warm => 'دافئ',
        VideoFx.cool => 'بارد',
        VideoFx.bars => 'شريط سينمائي',
        VideoFx.fadeIn => 'ظهور من الأسود',
        VideoFx.fadeOut => 'اختفاء للأسود',
        VideoFx.fadeBoth => 'ظهور واختفاء',
        VideoFx.flash => 'وميض',
        VideoFx.shake => 'اهتزاز',
        VideoFx.pulse => 'نبض',
      };

  /// Colour looks (same on every frame) vs. time-based ones.
  bool get isColor =>
      this == VideoFx.bw ||
      this == VideoFx.negative ||
      this == VideoFx.dramatic ||
      this == VideoFx.warm ||
      this == VideoFx.cool;
}

/// Length of the fades / flash (seconds).
const double kVideoFxFade = 0.8;
const double kVideoFxFlash = 0.35;

/// Bar height as a fraction of the frame height (each bar).
const double kVideoFxBar = 0.12;

/// 4x5 colour matrix of the colour looks, for the live preview.
List<double>? videoFxMatrix(VideoFx f) => switch (f) {
      VideoFx.bw => const <double>[
          0.299, 0.587, 0.114, 0, 0, //
          0.299, 0.587, 0.114, 0, 0,
          0.299, 0.587, 0.114, 0, 0,
          0, 0, 0, 1, 0,
        ],
      VideoFx.negative => const <double>[
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255,
          0, 0, -1, 0, 255,
          0, 0, 0, 1, 0,
        ],
      // contrast 1.35 around mid-grey, saturation ~0.6
      VideoFx.dramatic => const <double>[
          1.13, 0.30, 0.06, 0, -45, //
          0.12, 1.31, 0.06, 0, -45,
          0.12, 0.30, 1.07, 0, -45,
          0, 0, 0, 1, 0,
        ],
      VideoFx.warm => const <double>[
          1.08, 0, 0, 0, 8, //
          0, 1.0, 0, 0, 0,
          0, 0, 0.9, 0, -8,
          0, 0, 0, 1, 0,
        ],
      VideoFx.cool => const <double>[
          0.9, 0, 0, 0, -8, //
          0, 1.0, 0, 0, 0,
          0, 0, 1.1, 0, 8,
          0, 0, 0, 1, 0,
        ],
      _ => null,
    };

class VideoFxFilters {
  /// The colour looks, as an ffmpeg filter ('' for the others).
  static String color(VideoFx f) => switch (f) {
        VideoFx.bw => 'hue=s=0',
        VideoFx.negative => 'negate',
        VideoFx.dramatic => 'eq=contrast=1.35:saturation=0.6:brightness=-0.04',
        VideoFx.warm => 'colorbalance=rs=0.10:gs=0.02:bs=-0.10',
        VideoFx.cool => 'colorbalance=rs=-0.10:gs=0.0:bs=0.12',
        _ => '',
      };

  /// The time-based looks for a clip of [w]x[h] and [duration] seconds
  /// ('' for the others). Goes after the colour chain, on the main clip only.
  static String timed(VideoFx f, int w, int h, double duration) {
    String d(double v) => v.toStringAsFixed(3);
    final fadeLen = (duration / 3).clamp(0.1, kVideoFxFade).toDouble();
    final outAt = (duration - fadeLen).clamp(0.0, double.infinity).toDouble();
    switch (f) {
      case VideoFx.bars:
        return 'drawbox=x=0:y=0:w=iw:h=ih*$kVideoFxBar:color=black:t=fill,'
            'drawbox=x=0:y=ih-ih*$kVideoFxBar:w=iw:h=ih*$kVideoFxBar:color=black:t=fill';
      case VideoFx.fadeIn:
        return 'fade=t=in:st=0:d=${d(fadeLen)}';
      case VideoFx.fadeOut:
        return 'fade=t=out:st=${d(outAt)}:d=${d(fadeLen)}';
      case VideoFx.fadeBoth:
        return 'fade=t=in:st=0:d=${d(fadeLen)},'
            'fade=t=out:st=${d(outAt)}:d=${d(fadeLen)}';
      case VideoFx.flash:
        return 'fade=t=in:st=0:d=${d(kVideoFxFlash)}:color=white';
      case VideoFx.shake:
        return 'scale=$w*1.06:$h*1.06,'
            "crop=$w:$h:x='(iw-ow)/2+sin(t*40)*(iw-ow)/2':"
            "y='(ih-oh)/2+cos(t*33)*(ih-oh)/2'";
      case VideoFx.pulse:
        return "scale=w='$w*(1+0.05*abs(sin(t*3)))':"
            "h='$h*(1+0.05*abs(sin(t*3)))':eval=frame:flags=bilinear,"
            'crop=$w:$h';
      default:
        return '';
    }
  }
}
