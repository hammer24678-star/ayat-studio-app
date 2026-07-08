// PATCH_S37_PERSISTENT_SETTINGS
// Remembers the user's style choices across app launches so the studio
// opens the way they left it: fonts, sizes, colors, text position, template,
// background, effect, intro/outro, ratio… Deliberately NOT persisted:
// anything tied to a session's files (video path, custom background/fonts,
// reciter audio, timeline) — those files may no longer exist next launch.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/studio_presets.dart';
import '../models/studio_state.dart';
import 'stage_effects.dart';

class SettingsService {
  static const _prefix = 'ayat_studio.';

  /// Applies previously saved settings onto [state] (single notify at the
  /// end). Missing/never-saved keys leave the defaults untouched.
  static Future<void> restore(StudioState state) async {
    final SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance();
    } catch (_) {
      return; // never block startup on a storage hiccup
    }
    T? read<T>(String key) {
      final v = p.get('$_prefix$key');
      return v is T ? v : null;
    }

    state.update(() {
      state.bgIndex =
          (read<int>('bgIndex') ?? state.bgIndex).clamp(0, kBackgrounds.length - 1);
      state.bgAnimated = read<bool>('bgAnimated') ?? state.bgAnimated;
      state.squareRatio = read<bool>('squareRatio') ?? state.squareRatio;
      state.templateIndex = (read<int>('templateIndex') ?? state.templateIndex)
          .clamp(0, kTemplates.length - 1);
      // PATCH_S39_PERSISTENT_FONTS: uploaded fonts are re-registered at
      // startup (FontService.loadSavedFonts, before restore() is called),
      // so any font the app currently knows — built-in or imported — is a
      // valid persisted choice.
      final fontKey = read<String>('fontKey');
      if (fontKey != null && state.allFonts.any((f) => f.key == fontKey)) {
        state.fontKey = fontKey;
      }
      state.ayahFontSize =
          (read<double>('ayahFontSize') ?? state.ayahFontSize).clamp(14.0, 30.0);
      state.transFontSize =
          (read<double>('transFontSize') ?? state.transFontSize).clamp(9.0, 18.0);
      final color = read<int>('textColor');
      if (color != null) state.textColor = Color(color);
      final pos = read<int>('textPosition');
      if (pos != null && pos >= 0 && pos < AyahTextPosition.values.length) {
        state.textPosition = AyahTextPosition.values[pos];
      }
      final extra = read<int>('frameExtra');
      if (extra != null && extra >= 0 && extra < FrameExtra.values.length) {
        state.extra = FrameExtra.values[extra];
      }
      state.showTranslation =
          read<bool>('showTranslation') ?? state.showTranslation;
      // PATCH_S46_DEFAULT_FONT_AND_GLOW
      state.glowEnabled = read<bool>('glowEnabled') ?? state.glowEnabled;
      state.glowIntensity =
          (read<double>('glowIntensity') ?? state.glowIntensity).clamp(0.0, 1.5);
      final effect = read<int>('effect');
      if (effect != null && effect >= 0 && effect < StageEffect.values.length) {
        state.effect = StageEffect.values[effect];
      }
      state.effectIntensity =
          (read<double>('effectIntensity') ?? state.effectIntensity)
              .clamp(0.2, 1.0);
      state.showIntro = read<bool>('showIntro') ?? state.showIntro;
      state.showOutro = read<bool>('showOutro') ?? state.showOutro;
      final outro = read<String>('outroText');
      if (outro != null && outro.trim().isNotEmpty) state.outroText = outro;
      state.staticDurationSec =
          (read<int>('staticDurationSec') ?? state.staticDurationSec)
              .clamp(2, 60);
      state.aiArtEnabled = read<bool>('aiArtEnabled') ?? state.aiArtEnabled;
      // PATCH_S43_MODEL_SIZE_PICKER
      final modelSize = read<int>('whisperModelSize');
      if (modelSize != null &&
          modelSize >= 0 &&
          modelSize < WhisperModelSize.values.length) {
        state.whisperModelSize = WhisperModelSize.values[modelSize];
      }
      // PATCH_S38_VIDEO_EFFECTS
      final grade = read<int>('colorGrade');
      if (grade != null && grade >= 0 && grade < ColorGrade.values.length) {
        state.colorGrade = ColorGrade.values[grade];
      }
      state.vignetteEnabled =
          read<bool>('vignetteEnabled') ?? state.vignetteEnabled;
      state.vignetteIntensity =
          (read<int>('vignetteIntensity') ?? state.vignetteIntensity)
              .clamp(0, 100);
      state.grainEnabled = read<bool>('grainEnabled') ?? state.grainEnabled;
      state.grainIntensity =
          (read<int>('grainIntensity') ?? state.grainIntensity).clamp(0, 100);
      state.kenBurnsEnabled =
          read<bool>('kenBurnsEnabled') ?? state.kenBurnsEnabled;
      state.softTransitions =
          read<bool>('softTransitions') ?? state.softTransitions;
      // PATCH_S40_MULTI_BG_CYCLE
      state.multiBgEnabled =
          read<bool>('multiBgEnabled') ?? state.multiBgEnabled;
      final multiBg = read<List<Object?>>('multiBgIndexes');
      if (multiBg != null) {
        state.multiBgIndexes = [
          for (final v in multiBg)
            if (v is String &&
                int.tryParse(v) != null &&
                int.parse(v) >= 0 &&
                int.parse(v) < kBackgrounds.length)
              int.parse(v),
        ];
      }
      final trigger = read<int>('bgSwitchTrigger');
      if (trigger != null &&
          trigger >= 0 &&
          trigger < BgSwitchTrigger.values.length) {
        state.bgSwitchTrigger = BgSwitchTrigger.values[trigger];
      }
      state.bgSwitchAyahs =
          (read<int>('bgSwitchAyahs') ?? state.bgSwitchAyahs).clamp(1, 10);
      state.bgSwitchSeconds =
          (read<int>('bgSwitchSeconds') ?? state.bgSwitchSeconds).clamp(3, 30);
      final transition = read<int>('bgTransitionStyle');
      if (transition != null &&
          transition >= 0 &&
          transition < BgTransitionStyle.values.length) {
        state.bgTransitionStyle = BgTransitionStyle.values[transition];
      }
      state.bgCrossfadeDuration =
          (read<double>('bgCrossfadeDuration') ?? state.bgCrossfadeDuration)
              .clamp(0.2, 3.0);
    });
  }

  /// Saves the persistable subset of [state]. Cheap enough to call debounced
  /// on every state change.
  static Future<void> persist(StudioState state) async {
    final SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    await Future.wait([
      p.setInt('${_prefix}bgIndex', state.bgIndex),
      p.setBool('${_prefix}bgAnimated', state.bgAnimated),
      p.setBool('${_prefix}squareRatio', state.squareRatio),
      p.setInt('${_prefix}templateIndex', state.templateIndex),
      p.setString('${_prefix}fontKey', state.fontKey),
      p.setDouble('${_prefix}ayahFontSize', state.ayahFontSize),
      p.setDouble('${_prefix}transFontSize', state.transFontSize),
      p.setInt('${_prefix}textColor', state.textColor.toARGB32()),
      p.setInt('${_prefix}textPosition', state.textPosition.index),
      p.setInt('${_prefix}frameExtra', state.extra.index),
      p.setBool('${_prefix}showTranslation', state.showTranslation),
      // PATCH_S46_DEFAULT_FONT_AND_GLOW
      p.setBool('${_prefix}glowEnabled', state.glowEnabled),
      p.setDouble('${_prefix}glowIntensity', state.glowIntensity),
      p.setInt('${_prefix}effect', state.effect.index),
      p.setDouble('${_prefix}effectIntensity', state.effectIntensity),
      p.setBool('${_prefix}showIntro', state.showIntro),
      p.setBool('${_prefix}showOutro', state.showOutro),
      p.setString('${_prefix}outroText', state.outroText),
      p.setInt('${_prefix}staticDurationSec', state.staticDurationSec),
      p.setBool('${_prefix}aiArtEnabled', state.aiArtEnabled),
      // PATCH_S43_MODEL_SIZE_PICKER
      p.setInt('${_prefix}whisperModelSize', state.whisperModelSize.index),
      // PATCH_S38_VIDEO_EFFECTS
      p.setInt('${_prefix}colorGrade', state.colorGrade.index),
      p.setBool('${_prefix}vignetteEnabled', state.vignetteEnabled),
      p.setInt('${_prefix}vignetteIntensity', state.vignetteIntensity),
      p.setBool('${_prefix}grainEnabled', state.grainEnabled),
      p.setInt('${_prefix}grainIntensity', state.grainIntensity),
      p.setBool('${_prefix}kenBurnsEnabled', state.kenBurnsEnabled),
      p.setBool('${_prefix}softTransitions', state.softTransitions),
      // PATCH_S40_MULTI_BG_CYCLE
      p.setBool('${_prefix}multiBgEnabled', state.multiBgEnabled),
      p.setStringList('${_prefix}multiBgIndexes',
          [for (final i in state.multiBgIndexes) '$i']),
      p.setInt('${_prefix}bgSwitchTrigger', state.bgSwitchTrigger.index),
      p.setInt('${_prefix}bgSwitchAyahs', state.bgSwitchAyahs),
      p.setInt('${_prefix}bgSwitchSeconds', state.bgSwitchSeconds),
      p.setInt('${_prefix}bgTransitionStyle', state.bgTransitionStyle.index),
      p.setDouble('${_prefix}bgCrossfadeDuration', state.bgCrossfadeDuration),
    ]);
  }
}
