#!/usr/bin/env python3
"""
patch_s167_app_polish.py
========================
Ayat Studio S167 - run from the repo root (after S166):

    python3 patch_s167_app_polish.py

App-wide polish: the small things that make an app feel finished.

  main.dart
    1. Bouncy iOS-style scrolling everywhere, no Android glow
    2. Text scale clamped to 0.9x-1.2x so a huge system font can't break
       layouts (still honours the user's setting inside that range)
  ayat_theme.dart
    3. Gold cursor / selection handles on every text field
    4. Outlined + text buttons match the elevated ones (rounder, same type)
    5. Gold switches, checkboxes, scrollbars; styled tooltips, popup menus,
       expansion tiles, list tiles, dividers
    6. Elevated buttons: corner radius 9 -> 14 to match the new tiles
  home_screen.dart
    7. Transport: round gold play/pause button with an animated icon swap
    8. Progress bar: thicker, with the gold shimmer sweeping across it
    9. Toasts: gold spark + left-aligned text, floating with margins
   10. Haptics: soft tick on tiles and upload, firm tap on export

Idempotent (marker PATCH_S167). Anchor-checked: if anything is missing
NOTHING is written.
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S167'
HOME = os.path.join(ROOT, 'lib/screens/home_screen.dart')
THEME = os.path.join(ROOT, 'lib/theme/ayat_theme.dart')
MAIN = os.path.join(ROOT, 'lib/main.dart')
for p in (HOME, THEME, MAIN):
    if not os.path.exists(p):
        sys.exit('missing ' + p)

src = {p: open(p, encoding='utf-8').read() for p in (HOME, THEME, MAIN)}
has = [MARK in src[p] for p in src]
if all(has):
    print('  OK      already applied')
    sys.exit(0)
if any(has):
    sys.exit('  STOP    half-applied state - restore with git and rerun')
if 'PATCH_S166_UI_POLISH' not in src[HOME]:
    sys.exit('  STOP    S166 is not applied - run patch_s166_studio_ui_polish.py first')

problems = []


def sub_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        problems.append('%s (found %d, need 1)' % (label, n))
        return text
    return text.replace(old, new)


home, theme, main = src[HOME], src[THEME], src[MAIN]

# ------------------------------------------------------------ main.dart
main = sub_once(
    main,
    "          theme: AyatTheme.dark,\n",
    "          theme: AyatTheme.dark,\n          scrollBehavior: const _AyatScrollBehavior(), // PATCH_S167_APP_POLISH\n",
    'main scrollBehavior')
main = sub_once(
    main,
    """          builder: (context, child) => Directionality(
            textDirection: settings.textDirection,
            child: child ?? const SizedBox.shrink(),
          ),
""",
    """          // PATCH_S167_APP_POLISH: honour the system font size, but inside a
          // range the layouts were actually designed for.
          builder: (context, child) => MediaQuery.withClampedTextScaling(
            minScaleFactor: 0.9,
            maxScaleFactor: 1.2,
            child: Directionality(
              textDirection: settings.textDirection,
              child: child ?? const SizedBox.shrink(),
            ),
          ),
""",
    'main builder')
main = main.rstrip('\n') + """

// PATCH_S167_APP_POLISH: bouncy overscroll on every platform and no Android
// glow, so every list and sheet feels like the same physical material.
class _AyatScrollBehavior extends MaterialScrollBehavior {
  const _AyatScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
          BuildContext context, Widget child, ScrollableDetails details) =>
      child;
}
"""

# ------------------------------------------------------------ theme
theme = sub_once(
    theme,
    "            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),\n",
    "            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), // PATCH_S167_APP_POLISH\n",
    'elevated radius')
theme = sub_once(
    theme,
    "        progressIndicatorTheme: const ProgressIndicatorThemeData(\n",
    """        // PATCH_S167_APP_POLISH: the finishing layer - every remaining stock
        // control picks up the gold/emerald language.
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: AyatColors.goldBright,
          selectionColor: AyatColors.gold.withValues(alpha: 0.30),
          selectionHandleColor: AyatColors.goldBright,
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AyatColors.parchment,
            side: BorderSide(color: AyatColors.goldDim.withValues(alpha: 0.7)),
            textStyle:
                GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12.5),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AyatColors.goldBright,
            textStyle:
                GoogleFonts.tajawal(fontWeight: FontWeight.w700, fontSize: 12.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AyatColors.ink
                  : AyatColors.parchmentDim),
          trackColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AyatColors.gold
                  : AyatColors.surface3),
          trackOutlineColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? Colors.transparent
                  : AyatColors.hairline),
        ),
        checkboxTheme: CheckboxThemeData(
          fillColor: WidgetStateProperty.resolveWith((s) =>
              s.contains(WidgetState.selected)
                  ? AyatColors.gold
                  : Colors.transparent),
          checkColor: const WidgetStatePropertyAll(AyatColors.ink),
          side: const BorderSide(color: AyatColors.goldDim, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStatePropertyAll(
              AyatColors.gold.withValues(alpha: 0.35)),
          radius: const Radius.circular(8),
          thickness: const WidgetStatePropertyAll(3),
        ),
        tooltipTheme: TooltipThemeData(
          waitDuration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            color: AyatColors.surface3,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AyatColors.hairline),
          ),
          textStyle:
              GoogleFonts.tajawal(fontSize: 12, color: AyatColors.parchment),
        ),
        popupMenuTheme: PopupMenuThemeData(
          color: AyatColors.surface2,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AyatColors.hairline),
          ),
          textStyle:
              GoogleFonts.tajawal(fontSize: 13, color: AyatColors.parchment),
        ),
        expansionTileTheme: const ExpansionTileThemeData(
          iconColor: AyatColors.goldBright,
          collapsedIconColor: AyatColors.parchmentDim,
          textColor: AyatColors.parchment,
          collapsedTextColor: AyatColors.parchment,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: AyatColors.goldBright,
          textColor: AyatColors.parchment,
        ),
        dividerTheme: const DividerThemeData(
          color: AyatColors.hairline,
          thickness: 1,
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
""",
    'theme block')

# ------------------------------------------------------------ home: play button
home = sub_once(
    home,
    """                  IconButton(
                    onPressed: () => v.isPlaying ? c.pause() : c.play(),
                    icon: Icon(
                      v.isPlaying
                          ? Icons.pause_circle_outline
                          : Icons.play_circle_outline,
                      color: AyatColors.goldBright,
                    ),
                    tooltip: 'تشغيل/إيقاف',
                  ),
""",
    """                  // PATCH_S167_APP_POLISH: round gold play/pause with an animated
                  // icon swap and a soft glow.
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Tooltip(
                      message: 'تشغيل/إيقاف',
                      child: PressableScale(
                        borderRadius: BorderRadius.circular(22),
                        pressedScale: 0.9,
                        onTap: () => v.isPlaying ? c.pause() : c.play(),
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [AyatColors.goldBright, AyatColors.gold],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AyatColors.gold.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: AnimatedSwitcher(
                            duration: AppMotion.d(AppMotion.fast),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: FadeTransition(opacity: anim, child: child),
                            ),
                            child: Icon(
                              v.isPlaying
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              key: ValueKey(v.isPlaying),
                              size: 26,
                              color: AyatColors.ink,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
""",
    'transport play button')

# ------------------------------------------------------------ home: progress shimmer
home = sub_once(
    home,
    """                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: _busyProgress,
                      minHeight: 6,
                      backgroundColor: AyatColors.surface3,
                      valueColor: const AlwaysStoppedAnimation(AyatColors.gold),
                    ),
                  ),
                ),
""",
    """                Expanded(
                  // PATCH_S167_APP_POLISH: thicker bar with the gold sweep.
                  child: GoldShimmer(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: _busyProgress,
                        minHeight: 9,
                        backgroundColor: AyatColors.surface3,
                        valueColor:
                            const AlwaysStoppedAnimation(AyatColors.gold),
                      ),
                    ),
                  ),
                ),
""",
    'progress bar')

# ------------------------------------------------------------ home: toast
home = sub_once(
    home,
    """      ..showSnackBar(SnackBar(
        content: Text(msg, textAlign: TextAlign.center),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 2200),
      ));
""",
    """      ..showSnackBar(SnackBar(
        // PATCH_S167_APP_POLISH: gold spark + text; shape/colour from the theme.
        content: Row(
          children: [
            const Icon(Icons.auto_awesome,
                size: 16, color: AyatColors.goldBright),
            const SizedBox(width: 10),
            Expanded(child: Text(msg)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(milliseconds: 2200),
      ));
""",
    'toast')

# ------------------------------------------------------------ home: haptics
home = sub_once(
    home,
    "        onTap: disabled ? null : _export,\n",
    "        onTap: disabled\n            ? null\n            : () {\n                HapticFeedback.mediumImpact(); // PATCH_S167_APP_POLISH\n                _export();\n              },\n",
    'export haptic')
home = sub_once(
    home,
    "          onTap: disabled ? null : _pickVideo,\n",
    "          onTap: disabled\n              ? null\n              : () {\n                  HapticFeedback.selectionClick(); // PATCH_S167_APP_POLISH\n                  _pickVideo();\n                },\n",
    'upload haptic')
home = sub_once(
    home,
    "        borderRadius: BorderRadius.circular(18),\n        onTap: onTap,\n        child: Container(\n          constraints: const BoxConstraints(minHeight: 84),\n",
    "        borderRadius: BorderRadius.circular(18),\n        onTap: onTap == null\n            ? null\n            : () {\n                HapticFeedback.selectionClick(); // PATCH_S167_APP_POLISH\n                onTap();\n              },\n        child: Container(\n          constraints: const BoxConstraints(minHeight: 84),\n",
    'tile haptic')

if problems:
    print('  SKIP    nothing written. Anchors that did not match:')
    for p in problems:
        print('          - ' + p)
    sys.exit(1)


def balanced(s):
    t = re.sub(r"//[^\n]*", '', s)
    t = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", t)
    t = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', t)
    return all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))


out = {HOME: home, THEME: theme, MAIN: main}
for p, s in out.items():
    if not balanced(s):
        print('  STOP    %s would be unbalanced - nothing written' % p)
        sys.exit(1)
for p, s in out.items():
    open(p, 'w', encoding='utf-8').write(s)
    print('  PATCHED ' + os.path.relpath(p, ROOT))
print('  all balanced')
print('Next: flutter analyze && git add -A && git commit -m "S167: app-wide polish" && git push')
