#!/usr/bin/env python3
"""
PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS
============================================

Two additions:

1. 12 MORE BACKGROUNDS -- sky/clouds, forest/trees, and space/planets
   themed gradients added to kBackgrounds (lib/data/studio_presets.dart).
   Same BgDef gradient system as every existing background (this app has
   no raster/photo backgrounds, only gradients + the CustomPaint stage
   effects on top) -- kept dark/jewel-toned like the rest so gold/white
   ayah text stays readable, and they automatically get the existing
   animated-sheen toggle since that applies to any kBackgrounds entry.

2. TWO NEW BURST EFFECTS -- 'starBurst' (small gold 8-point stars
   sparking outward from a few anchor points, like distant fireworks)
   and 'flowerBurst' (six-petal blossoms blooming outward and fading).
   Added as ordinary StageEffect entries (so they're pickable anywhere
   effects already are), PLUS the chosen effect now also renders over
   the intro/outro بسملة/خاتمة cards -- previously effects only ever
   showed on the main clip. This reuses the exact same rendered fx PNG
   sequence, so no extra frames are generated for the intro/outro pass.

Idempotent: safe to run multiple times.

Usage:
    python3 patch_s102_backgrounds_burst_effects.py <project_root>
"""
import sys
import pathlib

MARKER = "PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS"


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


# ---------------------------------------------------------------------
# 1. lib/data/studio_presets.dart -- 12 more backgrounds
# ---------------------------------------------------------------------

_BG_OLD = """  BgDef(stops: [Color(0xFF33260A), Color(0xFF6B4E14), Color(0xFF40300C)]), // wheat field gold
  BgDef(radial: true, stops: [Color(0xFF2A2438), Color(0xFF120F1C)]), // mountain dusk
];"""

_BG_NEW = """  BgDef(stops: [Color(0xFF33260A), Color(0xFF6B4E14), Color(0xFF40300C)]), // wheat field gold
  BgDef(radial: true, stops: [Color(0xFF2A2438), Color(0xFF120F1C)]), // mountain dusk
  // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS: sky/clouds, forest/trees, and space/planets
  // themed additions -- same gradient-only system as every background
  // above, kept dark/jewel-toned so gold/white ayah text stays readable.
  BgDef(radial: true, stops: [Color(0xFF274461), Color(0xFF0C1B2E)]), // dawn clouds
  BgDef(stops: [Color(0xFF1A3350), Color(0xFF3E6488), Color(0xFF23415F)]), // pale blue sky
  BgDef(radial: true, stops: [Color(0xFF0E2B3D), Color(0xFF040E16)]), // overcast sky & mist
  BgDef(stops: [Color(0xFF0B2A1C), Color(0xFF184A2E), Color(0xFF0E3320)]), // pine forest
  BgDef(radial: true, stops: [Color(0xFF15311F), Color(0xFF081A10)]), // misty woodland
  BgDef(stops: [Color(0xFF203218), Color(0xFF4A6B2C), Color(0xFF2B4519)]), // sunlit tree canopy
  BgDef(radial: true, stops: [Color(0xFF060A1E), Color(0xFF01020A)]), // deep space starfield
  BgDef(stops: [Color(0xFF1B0F3A), Color(0xFF4A1E63), Color(0xFF250F42)]), // cosmic nebula
  BgDef(radial: true, stops: [Color(0xFF2E1A4D), Color(0xFF0A0616)]), // violet galaxy
  BgDef(stops: [Color(0xFF3A2410), Color(0xFF8A5A22), Color(0xFF4E3212)]), // ringed planet gold
  BgDef(radial: true, stops: [Color(0xFF102A3E), Color(0xFF041019)]), // blue planet horizon
  BgDef(stops: [Color(0xFF14202E), Color(0xFF33507A), Color(0xFF1D2E46)]), // aurora night sky
];"""


def patch_backgrounds(root: pathlib.Path) -> bool:
    path = root / "lib" / "data" / "studio_presets.dart"
    return replace_once(path, _BG_OLD, _BG_NEW,
                         "studio_presets.dart: add 12 sky/forest/space backgrounds")


# ---------------------------------------------------------------------
# 2. lib/services/stage_effects.dart -- starBurst + flowerBurst
# ---------------------------------------------------------------------

_ENUM_OLD = "enum StageEffect { none, rain, snow, dust, sparkle, geometricShimmer, confetti, glitch, fireflies, fog, rays, spinningStar } // PATCH_S100_FONTS_SPINSTAR_TINT"
_ENUM_NEW = "enum StageEffect { none, rain, snow, dust, sparkle, geometricShimmer, confetti, glitch, fireflies, fog, rays, spinningStar, starBurst, flowerBurst } // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS"

_LABEL_OLD = "        StageEffect.spinningStar => 'نجمة إسلامية دوّارة', // PATCH_S100_FONTS_SPINSTAR_TINT\n      };"
_LABEL_NEW = ("        StageEffect.spinningStar => 'نجمة إسلامية دوّارة', // PATCH_S100_FONTS_SPINSTAR_TINT\n"
              "        StageEffect.starBurst => 'انفجار نجمي', // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS\n"
              "        StageEffect.flowerBurst => 'تفتّح الزهور', // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS\n"
              "      };")

_ICON_OLD = "        StageEffect.spinningStar => Icons.star_rate_rounded, // PATCH_S100_FONTS_SPINSTAR_TINT\n      };"
_ICON_NEW = ("        StageEffect.spinningStar => Icons.star_rate_rounded, // PATCH_S100_FONTS_SPINSTAR_TINT\n"
             "        StageEffect.starBurst => Icons.auto_awesome_outlined, // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS\n"
             "        StageEffect.flowerBurst => Icons.local_florist_outlined, // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS\n"
             "      };")

_DISPATCH_OLD = """      case StageEffect.spinningStar: // PATCH_S100_FONTS_SPINSTAR_TINT
        _paintSpinningStar(canvas, size, timeSec, intensity);
    }
  }"""
_DISPATCH_NEW = """      case StageEffect.spinningStar: // PATCH_S100_FONTS_SPINSTAR_TINT
        _paintSpinningStar(canvas, size, timeSec, intensity);
      case StageEffect.starBurst: // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS
        _paintStarBurst(canvas, size, timeSec, intensity);
      case StageEffect.flowerBurst: // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS
        _paintFlowerBurst(canvas, size, timeSec, intensity);
    }
  }"""

# Inserted right after the existing _paintConfetti method (before the blank
# lines / glitch-effect comment block that follows it).
_PAINTER_ANCHOR_OLD = """      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: pw, height: ph), paint);
      canvas.restore();
    }
  }


  // PATCH_S73_SIMPLE_GLITCH_RAIN:"""

_PAINTER_ANCHOR_NEW = """      canvas.drawRect(
          Rect.fromCenter(center: Offset.zero, width: pw, height: ph), paint);
      canvas.restore();
    }
  }

  // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS: small gold 8-point stars sparking
  // outward from a few anchor points and fading, like distant fireworks --
  // distinct from spinningStar (rotates in place) and confetti (falls).
  // Reuses _drawEightPointStar so the sparks read as tiny stars rather than
  // generic dots. Each particle's own cycle offset (mod 1.0 of loopSeconds)
  // keeps the export tile seamless, same convention as every effect here.
  static void _paintStarBurst(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final anchors = [
      Offset(w * 0.22, h * 0.28),
      Offset(w * 0.78, h * 0.34),
      Offset(w * 0.50, h * 0.70),
    ];
    final perAnchor = (7 * intensity).round().clamp(2, 12);
    final paint = Paint()..style = PaintingStyle.fill;
    for (var a = 0; a < anchors.length; a++) {
      for (var i = 0; i < perAnchor; i++) {
        final idx = a * 100 + i;
        final angle = _rand(idx, 1) * 2 * pi;
        final cycleOffset = _rand(idx, 2); // stagger each particle's burst
        final cyclePos = ((t / loopSeconds) + cycleOffset) % 1.0;
        final travel = _easeInOutSine(cyclePos);
        final maxR = (0.10 + 0.05 * _rand(idx, 3)) * w;
        final r = travel * maxR;
        // fast fade-in, slower fade-out -- reads as a spark, not a pulse
        final fade = cyclePos < 0.15
            ? cyclePos / 0.15
            : (1 - (cyclePos - 0.15) / 0.85).clamp(0.0, 1.0);
        final alpha = fade * intensity * 0.9;
        if (alpha <= 0.02) continue;
        final starR =
            (2.2 + 2.0 * _rand(idx, 4)) * w / 1080 * (0.5 + 0.5 * fade);
        paint.color = const Color(0xFFFFF3D6).withValues(alpha: alpha);
        canvas.save();
        canvas.translate(
            anchors[a].dx + cos(angle) * r, anchors[a].dy + sin(angle) * r);
        canvas.rotate(angle);
        _drawEightPointStar(canvas, paint, starR);
        canvas.restore();
      }
    }
  }

  // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS: a handful of six-petal blossoms
  // that bloom outward from a few anchor points, hold, then fade and bloom
  // again -- a softer "flower" reading than starBurst's sharp sparks, built
  // from rotated ellipses instead of a new asset. Same seamless-loop
  // convention (whole cycles via t/loopSeconds mod 1.0) as every effect here.
  static void _paintFlowerBurst(
      Canvas canvas, Size size, double t, double intensity) {
    final w = size.width, h = size.height;
    final anchors = [
      Offset(w * 0.20, h * 0.24),
      Offset(w * 0.80, h * 0.30),
      Offset(w * 0.50, h * 0.74),
      Offset(w * 0.30, h * 0.60),
    ];
    const petals = 6;
    final paint = Paint()..style = PaintingStyle.fill;
    for (var a = 0; a < anchors.length; a++) {
      final cycleOffset = _rand(a, 11);
      final cyclePos = ((t / loopSeconds) + cycleOffset) % 1.0;
      // bloom (0..0.35), hold (0.35..0.55), fade (0.55..1)
      double bloom;
      double fade;
      if (cyclePos < 0.35) {
        bloom = _easeInOutSine(cyclePos / 0.35);
        fade = bloom;
      } else if (cyclePos < 0.55) {
        bloom = 1.0;
        fade = 1.0;
      } else {
        bloom = 1.0;
        fade = (1 - (cyclePos - 0.55) / 0.45).clamp(0.0, 1.0);
      }
      if (fade <= 0.02) continue;
      final maxR = (0.07 + 0.02 * _rand(a, 12)) * w;
      final petalLen = maxR * bloom;
      final petalW = petalLen * 0.42;
      final baseAngle = _rand(a, 13) * 2 * pi;
      final alpha = fade * intensity * 0.75;
      final petalColor = Color.lerp(const Color(0xFFECC875),
          const Color(0xFFFFF3D6), _rand(a, 14))!
          .withValues(alpha: alpha);
      paint.color = petalColor;
      canvas.save();
      canvas.translate(anchors[a].dx, anchors[a].dy);
      for (var p = 0; p < petals; p++) {
        final ang = baseAngle + p * 2 * pi / petals;
        canvas.save();
        canvas.rotate(ang);
        canvas.translate(petalLen * 0.5, 0);
        canvas.drawOval(
            Rect.fromCenter(center: Offset.zero, width: petalLen, height: petalW),
            paint);
        canvas.restore();
      }
      // small bright core so it reads as a blossom, not a pinwheel
      paint.color = const Color(0xFFFFF3D6).withValues(alpha: alpha);
      canvas.drawCircle(Offset.zero, petalW * 0.35, paint);
      canvas.restore();
    }
  }


  // PATCH_S73_SIMPLE_GLITCH_RAIN:"""


def patch_stage_effects(root: pathlib.Path) -> bool:
    path = root / "lib" / "services" / "stage_effects.dart"
    a = replace_once(path, _ENUM_OLD, _ENUM_NEW,
                      "stage_effects.dart: add starBurst + flowerBurst to StageEffect enum")
    b = replace_once(path, _LABEL_OLD, _LABEL_NEW,
                      "stage_effects.dart: starBurst/flowerBurst labels")
    c = replace_once(path, _ICON_OLD, _ICON_NEW,
                      "stage_effects.dart: starBurst/flowerBurst icons")
    d = replace_once(path, _DISPATCH_OLD, _DISPATCH_NEW,
                      "stage_effects.dart: dispatch starBurst + flowerBurst")
    e = replace_once(path, _PAINTER_ANCHOR_OLD, _PAINTER_ANCHOR_NEW,
                      "stage_effects.dart: insert _paintStarBurst + _paintFlowerBurst")
    return a or b or c or d or e


# ---------------------------------------------------------------------
# 3. lib/services/export_service.dart -- play the chosen effect over
#    intro/outro cards too (previously main-clip only)
# ---------------------------------------------------------------------

_INTRO_CALL_OLD = """      if (state.showIntro) {
        onStatus?.call('جارٍ إنشاء بطاقة البسملة…');
        parts.add(await _renderTitleSegment(
            work, 'intro', kBasmala, state, w, h));
      }
      parts.add(mainMp4);
      if (state.showOutro) {
        onStatus?.call('جارٍ إنشاء بطاقة الخاتمة…');
        parts.add(await _renderTitleSegment(
            work, 'outro',
            state.outroText.trim().isEmpty ? kDefaultOutro : state.outroText,
            state, w, h));
      }"""

_INTRO_CALL_NEW = """      if (state.showIntro) {
        onStatus?.call('جارٍ إنشاء بطاقة البسملة…');
        parts.add(await _renderTitleSegment(
            work, 'intro', kBasmala, state, w, h,
            // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS: the chosen stage effect now
            // plays over the intro card too, not just the main clip.
            effectSeqPattern: effectSeqPattern));
      }
      parts.add(mainMp4);
      if (state.showOutro) {
        onStatus?.call('جارٍ إنشاء بطاقة الخاتمة…');
        parts.add(await _renderTitleSegment(
            work, 'outro',
            state.outroText.trim().isEmpty ? kDefaultOutro : state.outroText,
            state, w, h,
            effectSeqPattern: effectSeqPattern)); // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS
      }"""

_RENDER_TITLE_OLD = """  static Future<String> _renderTitleSegment(Directory work, String name,
      String text, StudioState state, int w, int h) async {
    final png = '${work.path}/$name.png';
    await File(png).writeAsBytes(await OverlayRenderer.renderTitleCardPng(
      w: w,
      h: h,
      text: text,
      bgIndex: state.bgIndex,
      customBgPath: state.useCustomBg ? state.customBgPath : null,
    ));
    final mp4 = '${work.path}/$name.mp4';
    // PATCH_S38_VIDEO_EFFECTS: same Ken Burns + color grade/vignette/grain
    // as the main clip, plus a gentle fade in/out of its own when soft
    // transitions are on — keeps the bismillah/outro consistent with the
    // chosen look and less abrupt.
    final vf = <String>[_staticImageFilterChain(w, h, state.kenBurnsEnabled)];
    final post = _postFilterChain(state);
    if (post.isNotEmpty) vf.add(post);
    if (state.softTransitions) {
      final fadeOutStart = (titleCardSec - 0.35).clamp(0.0, double.infinity);
      vf.add('fade=t=in:st=0:d=0.35');
      vf.add('fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=0.35');
    }
    final cmd = '-y -loop 1 -t $titleCardSec -i "$png" '
        '-f lavfi -t $titleCardSec -i anullsrc=channel_layout=stereo:sample_rate=44100 '
        '-vf "${vf.join(',')}" -map 0:v -map 1:a ${_encodeParams(state.exportQuality)} "$mp4"';
    await _run(cmd, titleCardSec, null);
    return mp4;
  }"""

_RENDER_TITLE_NEW = """  static Future<String> _renderTitleSegment(Directory work, String name,
      String text, StudioState state, int w, int h,
      {String? effectSeqPattern}) async { // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS
    final png = '${work.path}/$name.png';
    await File(png).writeAsBytes(await OverlayRenderer.renderTitleCardPng(
      w: w,
      h: h,
      text: text,
      bgIndex: state.bgIndex,
      customBgPath: state.useCustomBg ? state.customBgPath : null,
    ));
    final mp4 = '${work.path}/$name.mp4';
    // PATCH_S38_VIDEO_EFFECTS: same Ken Burns + color grade/vignette/grain
    // as the main clip, plus a gentle fade in/out of its own when soft
    // transitions are on — keeps the bismillah/outro consistent with the
    // chosen look and less abrupt.
    final vf = <String>[_staticImageFilterChain(w, h, state.kenBurnsEnabled)];
    final post = _postFilterChain(state);
    if (post.isNotEmpty) vf.add(post);
    if (state.softTransitions) {
      final fadeOutStart = (titleCardSec - 0.35).clamp(0.0, double.infinity);
      vf.add('fade=t=in:st=0:d=0.35');
      vf.add('fade=t=out:st=${fadeOutStart.toStringAsFixed(3)}:d=0.35');
    }
    // PATCH_S102_MORE_BACKGROUNDS_BURST_EFFECTS: reuses the exact same rendered fx PNG
    // sequence the main clip uses -- no extra frames generated here, just
    // one more overlay pass via filter_complex instead of the plain -vf
    // path below. Only kicks in when an effect is actually active.
    if (effectSeqPattern != null) {
      final cmd = '-y -loop 1 -t $titleCardSec -i "$png" '
          '-framerate ${StageEffects.exportFps} -stream_loop -1 -start_number 0 -i "$effectSeqPattern" '
          '-f lavfi -t $titleCardSec -i anullsrc=channel_layout=stereo:sample_rate=44100 '
          '-filter_complex "[0:v]${vf.join(',')}[base];[1:v]format=rgba,scale=$w:$h[fx];[base][fx]overlay=0:0[outv]" '
          '-map "[outv]" -map 2:a -t $titleCardSec ${_encodeParams(state.exportQuality)} "$mp4"';
      await _run(cmd, titleCardSec, null);
      return mp4;
    }
    final cmd = '-y -loop 1 -t $titleCardSec -i "$png" '
        '-f lavfi -t $titleCardSec -i anullsrc=channel_layout=stereo:sample_rate=44100 '
        '-vf "${vf.join(',')}" -map 0:v -map 1:a ${_encodeParams(state.exportQuality)} "$mp4"';
    await _run(cmd, titleCardSec, null);
    return mp4;
  }"""


def patch_export_service(root: pathlib.Path) -> bool:
    path = root / "lib" / "services" / "export_service.dart"
    a = replace_once(path, _INTRO_CALL_OLD, _INTRO_CALL_NEW,
                      "export_service.dart: pass effectSeqPattern to intro/outro segments")
    b = replace_once(path, _RENDER_TITLE_OLD, _RENDER_TITLE_NEW,
                      "export_service.dart: _renderTitleSegment composites effect overlay")
    return a or b


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: python3 patch_s102_backgrounds_burst_effects.py <project_root>")

    root = pathlib.Path(sys.argv[1]).resolve()
    if not root.exists():
        raise SystemExit(f"ERROR: project root not found: {root}")

    print(f"Patching under: {root}\n")

    print("-- backgrounds --")
    patch_backgrounds(root)

    print("\n-- starBurst + flowerBurst effects --")
    patch_stage_effects(root)

    print("\n-- intro/outro now play the chosen effect too --")
    patch_export_service(root)

    print(f"\nDone. {MARKER} applied (or already present).")
    print("\nSanity-check next:")
    print("  1. dart analyze")
    print("  2. خلفيات tab should now show 26 background tiles total")
    print("     (14 existing + these 12 new sky/forest/space ones).")
    print("  3. تأثيرات tab should list two new options: 'انفجار نجمي' (star")
    print("     sparks radiating from 3 points) and 'تفتّح الزهور' (blossoms")
    print("     blooming from 4 points) -- preview both in the live stage.")
    print("  4. Pick starBurst or flowerBurst, turn on بسملة في مقدمة المقطع,")
    print("     and export a short clip -- the burst should now also be")
    print("     visible over the بسملة card itself, not just the main video.")
    print("  5. Export with effect = 'بدون تأثير' (none) once too, to confirm")
    print("     the untouched plain -vf intro/outro path still works exactly")
    print("     as before.")


if __name__ == "__main__":
    main()
