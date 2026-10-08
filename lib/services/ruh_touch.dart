// PATCH_S181_CLIPTOUCH
// Touching the text on the stage lets its روح dress the stage by itself - the
// very same recipe the «روح الآية» card applies by hand (effect, text colour,
// grade, vignette). One undo step; the switch lives in the روح card.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../models/studio_state.dart';
import '../theme/ayat_theme.dart';
import 'ayah_mood.dart';

class RuhTouch {
  RuhTouch._();

  static void apply(BuildContext context, StudioState s, String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    final r = AyahMood.analyze(clean);
    // Already dressed in this روح: touching again must not nag.
    if (s.effect == r.effect && s.textColor == r.textColor) return;
    HapticFeedback.selectionClick();
    s.update(() {
      s.effect = r.effect;
      s.effectIntensity = r.intensity;
      s.textColor = r.textColor;
      s.colorGrade = r.grade;
      s.vignetteEnabled = r.vignette > 0;
      if (r.vignette > 0) s.vignetteIntensity = r.vignette;
    });
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('اكتست الآية روح «${r.labelAr}» ${r.emoji}',
            textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'تراجع',
          textColor: AyatColors.goldBright,
          onPressed: s.undoStep,
        ),
      ));
  }
}
