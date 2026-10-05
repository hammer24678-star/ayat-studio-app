#!/usr/bin/env python3
"""
patch_s165_studio_ui_refresh.py
===============================
Ayat Studio S165 - run from the repo root (after S164):

    python3 patch_s165_studio_ui_refresh.py

Simpler, calmer, more alive main studio screen. Brings the Flutter app closer
to docs/ayat_studio225.html (ambient emerald/burgundy glow, hairline header,
glowing gold active tab, springy press feedback) using only widgets the app
already has (AppMotion, FadeSlideIn, PressableScale, GoldShimmer). Every
animation collapses to a static frame when Settings > animations is off.

  home_screen.dart
    1. app bar: transparent, shimmering title, gold hairline underneath;
       settings + info folded into one overflow menu (undo/redo stay)
    2. body: faint ambient glow behind everything (_AmbientGlow)
    3. status: a slim pill when idle, the full progress card only while busy
    4. cards: soft depth (gradient + shadow), rounder corners
    5. tabs: animated pill - gold gradient + glow when selected, icon pop
    6. panels: cross-fade + slide when switching tabs
    7. export: one gold gradient hero button with a subtitle and shimmer
    8. panel titles: small gold accent bar
    9. first open: top-level blocks stagger in
  ayat_theme.dart
   10. chips, sliders, dialogs, bottom sheets, snack bars share the same look

Idempotent (marker PATCH_S165). Every edit is anchor-checked first; if any
anchor is missing NOTHING is written.
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S165'
HOME = os.path.join(ROOT, 'lib/screens/home_screen.dart')
THEME = os.path.join(ROOT, 'lib/theme/ayat_theme.dart')
for p in (HOME, THEME):
    if not os.path.exists(p):
        sys.exit('missing ' + p)

home = open(HOME, encoding='utf-8').read()
theme = open(THEME, encoding='utf-8').read()
if MARK in home and MARK in theme:
    print('  OK      already applied')
    sys.exit(0)
if (MARK in home) != (MARK in theme):
    sys.exit('  STOP    half-applied state (one file has PATCH_S165) - restore with git and rerun')

problems = []


def sub_once(text, old, new, label):
    n = text.count(old)
    if n != 1:
        problems.append('%s (found %d, need 1)' % (label, n))
        return text
    return text.replace(old, new)


def sub_re(text, pattern, new, label):
    m = list(re.finditer(pattern, text, flags=re.S))
    if len(m) != 1:
        problems.append('%s (regex found %d, need 1)' % (label, len(m)))
        return text
    return text[:m[0].start()] + new + text[m[0].end():]


# ------------------------------------------------------------ 1. app bar
home = sub_once(
    home,
    "      appBar: AppBar(\n        title: Text(_t('app.name')),\n        actions: [\n",
    """      // PATCH_S165_UI_REFRESH: transparent bar, shimmering wordmark, gold
      // hairline - the prototype's header.
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        title: GoldShimmer(child: Text(_t('app.name'))),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  AyatColors.hairline,
                  AyatColors.hairline,
                  Colors.transparent,
                ],
                stops: [0, 0.2, 0.8, 1],
              ),
            ),
          ),
        ),
        actions: [
""",
    'appbar head')

OLD_ACTIONS = """          // PATCH_S123_SETTINGS_SCREEN: language, animations and the reader's
          // light mode live one tap from anywhere in the studio.
          IconButton(
            onPressed: () => Navigator.of(context)
                .push(AppMotion.route(const SettingsScreen())),
            icon: const Icon(Icons.settings_outlined),
            tooltip: _t('settings.title'),
          ),
          IconButton(
            onPressed: _showInfo,
            icon: const Icon(Icons.info_outline),
            tooltip: _t('studio.info'),
          ),
"""
NEW_ACTIONS = """          // PATCH_S123_SETTINGS_SCREEN: language, animations and the reader's
          // light mode live one tap from anywhere in the studio.
          // PATCH_S165_UI_REFRESH: settings + info share one overflow menu so
          // the bar only carries the two actions used while editing.
          PopupMenuButton<int>(
            icon: const Icon(Icons.more_vert),
            color: AyatColors.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: const BorderSide(color: AyatColors.hairline),
            ),
            onSelected: (v) {
              if (v == 0) {
                Navigator.of(context)
                    .push(AppMotion.route(const SettingsScreen()));
              } else {
                _showInfo();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<int>(
                value: 0,
                child: Row(
                  children: [
                    const Icon(Icons.settings_outlined,
                        size: 18, color: AyatColors.goldBright),
                    const SizedBox(width: 10),
                    Text(_t('settings.title')),
                  ],
                ),
              ),
              PopupMenuItem<int>(
                value: 1,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline,
                        size: 18, color: AyatColors.goldBright),
                    const SizedBox(width: 10),
                    Text(_t('studio.info')),
                  ],
                ),
              ),
            ],
          ),
"""
home = sub_once(home, OLD_ACTIONS, NEW_ACTIONS, 'appbar actions')

# ------------------------------------------------------------ 2. ambient glow
home = sub_once(
    home,
    "      body: SafeArea(\n        child: ListenableBuilder(\n          listenable: state,\n",
    "      body: Stack(\n        children: [\n          const Positioned.fill(child: _AmbientGlow()), // PATCH_S165_UI_REFRESH\n          SafeArea(\n        child: ListenableBuilder(\n          listenable: state,\n",
    'body head')

home = sub_once(
    home,
    "                const SizedBox(height: 24),\n              ],\n            ),\n          ),\n        ),\n      ),\n    );\n  }\n\n  Widget _card(",
    "                const SizedBox(height: 24),\n              ],\n            ),\n          ),\n        ),\n      ),\n        ],\n      ),\n    );\n  }\n\n  Widget _card(",
    'body tail')

# ------------------------------------------------------------ 9. stagger-in
home = sub_once(
    home,
    "                _statusCard(),\n                const SizedBox(height: 14),\n                _ratioToggle(),\n",
    "                FadeSlideIn(child: _statusCard()), // PATCH_S165_UI_REFRESH\n                const SizedBox(height: 14),\n                FadeSlideIn(\n                    delay: const Duration(milliseconds: 60),\n                    child: _ratioToggle()),\n",
    'stagger status/ratio')
home = sub_once(
    home,
    "                _simpleTopTabs(), // PATCH_S128: 5 grouped tabs (آيات/نص/شكل/وسائط/مزيد)\n                const SizedBox(height: 12),\n                _panelCard(),\n",
    "                FadeSlideIn(\n                    delay: const Duration(milliseconds: 140),\n                    child: _simpleTopTabs()), // PATCH_S128 + PATCH_S165\n                const SizedBox(height: 12),\n                FadeSlideIn(\n                    delay: const Duration(milliseconds: 220),\n                    child: _panelCard()),\n",
    'stagger tabs/panel')

# ------------------------------------------------------------ 7. export button
home = sub_re(
    home,
    r"                ElevatedButton\.icon\(\n                  onPressed: _busy \? null : _export,.*?label: const Text\('تصدير المقطع \(MP4 — بدون حد للمدة أو الدقة\)'\),\n                \),\n",
    "                FadeSlideIn(\n                    delay: const Duration(milliseconds: 300),\n                    child: _exportButton()), // PATCH_S165_UI_REFRESH\n",
    'export button')

# ------------------------------------------------------------ 4. card + status + new widgets
OLD_CARD = """  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AyatColors.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AyatColors.hairline),
        ),
        child: child,
      );

  Widget _statusCard() {
    return _card("""

NEW_CARD = """  // PATCH_S165_UI_REFRESH: a touch of depth - top-lit gradient + soft shadow.
  Widget _card({required Widget child, EdgeInsets? padding}) => Container(
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0F201B), AyatColors.surface],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AyatColors.hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      );

  // PATCH_S165_UI_REFRESH: idle = one quiet line, busy = the full progress
  // card. AnimatedSize makes the swap glide instead of jump.
  Widget _statusCard() {
    return AnimatedSize(
      duration: AppMotion.d(AppMotion.medium),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: _busy ? _statusBusyCard() : _statusPill(),
    );
  }

  Widget _statusPill() {
    final text = state.corpusStatus;
    if (text.isEmpty) return const SizedBox(width: double.infinity);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: AyatColors.gold.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AyatColors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AyatColors.goldBright,
                boxShadow: [
                  BoxShadow(
                    color: AyatColors.gold.withValues(alpha: 0.7),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12, color: AyatColors.parchmentDim),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PATCH_S165_UI_REFRESH: the export call-to-action. Gold gradient, glow,
  // press-in scale and a slow shimmer; dims while a job is running.
  Widget _exportButton() {
    final disabled = _busy;
    return AnimatedOpacity(
      duration: AppMotion.d(AppMotion.fast),
      opacity: disabled ? 0.5 : 1,
      child: PressableScale(
        borderRadius: BorderRadius.circular(20),
        pressedScale: 0.97,
        onTap: disabled ? null : _export,
        child: GoldShimmer(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AyatColors.goldBright, AyatColors.gold],
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AyatColors.gold.withValues(alpha: 0.35),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.movie_creation_outlined,
                    size: 22, color: AyatColors.ink),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text('تصدير المقطع',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AyatColors.ink)),
                      Text('MP4 — بدون حد للمدة أو الدقة',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xCC050F0D))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusBusyCard() {
    return _card("""
home = sub_once(home, OLD_CARD, NEW_CARD, 'card/status')

# ------------------------------------------------------------ 5. tab button
NEW_TAB = """  Widget _tabButton(int i) {
    // PATCH_S165_UI_REFRESH: animated pill. Selected = gold gradient + glow,
    // icon pops with a spring; everything is a no-op when animations are off.
    final selected = _selectedTab == i;
    final dur = AppMotion.d(AppMotion.fast);
    return PressableScale(
      borderRadius: BorderRadius.circular(16),
      pressedScale: 0.94,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedTab = i);
      },
      child: AnimatedContainer(
        duration: dur,
        curve: Curves.easeOutCubic,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AyatColors.goldBright, AyatColors.gold],
                )
              : null,
          color: selected ? null : AyatColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? AyatColors.goldBright : AyatColors.hairline,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AyatColors.gold.withValues(alpha: 0.38),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedScale(
              scale: selected ? 1.14 : 1.0,
              duration: dur,
              curve: AppMotion.spring,
              child: Icon(_tabs[i].$1,
                  size: 19,
                  color: selected ? AyatColors.ink : AyatColors.parchmentDim),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: dur,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: selected ? AyatColors.ink : AyatColors.parchment,
              ),
              child: Text(_tabs[i].$2),
            ),
          ],
        ),
      ),
    );
  }

"""
home = sub_re(
    home,
    r"  Widget _tabButton\(int i\) \{\n.*?\n  \}\n\n(?=  // PATCH_S129_WIRE_AND_SIMPLIFY_UI: case map matches the 5-group bar\.)",
    NEW_TAB,
    'tab button')

# ------------------------------------------------------------ 6. panel switcher
NEW_PANEL = """  Widget _panelCard() {
    // PATCH_S165_UI_REFRESH: cross-fade + a small upward slide between tabs.
    // Keyed on tab + mode so switching classic/grouped also animates.
    return _card(
      child: AnimatedSwitcher(
        duration: AppMotion.d(AppMotion.medium),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeIn,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        ),
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.topCenter,
          fit: StackFit.passthrough,
          children: [...previous, if (current != null) current],
        ),
        child: KeyedSubtree(
          key: ValueKey('${AppSettings.instance.classicTabs}-$_selectedTab'),
          child: _panelBody(),
        ),
      ),
    );
  }

  Widget _panelBody() {
    return AppSettings.instance.classicTabs
        ? switch (_selectedTab) {
            0 => _ayahPanel(),
            1 => _bgPanel(),
            2 => _effectsPanel(),
            3 => _chromaPanel(),
            4 => _recitersPanel(),
            5 => _templatesPanel(),
            6 => _textEditorProPanel(),
            _ => _exportPanel(),
          }
        : switch (_selectedTab) {
            0 => _ayahPanel(),
            1 => _textEditorProPanel(),
            2 => _shapePanel(), // effects + templates
            3 => _mediaPanel(), // backgrounds + chroma + reciters
            _ => _exportPanel(),
          };
  }

"""
home = sub_re(
    home,
    r"  Widget _panelCard\(\) \{\n    return _card\(\n      child: AppSettings\.instance\.classicTabs\n.*?\n  \}\n\n(?=  // PATCH_S129_WIRE_AND_SIMPLIFY_UI: \"الشكل\")",
    NEW_PANEL,
    'panel card')

# ------------------------------------------------------------ 8. panel title + section card
home = sub_once(
    home,
    """  Widget _panelTitle(String title, [String? hint]) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Text(hint, style: Theme.of(context).textTheme.bodyMedium),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
""",
    """  Widget _panelTitle(String title, [String? hint]) {
    // PATCH_S165_UI_REFRESH: small gold accent bar before the title.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(3),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AyatColors.goldBright, AyatColors.goldDim],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: Theme.of(context).textTheme.headlineMedium),
            ),
          ],
        ),
        if (hint != null) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 13),
            child: Text(hint, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }
""",
    'panel title')

home = sub_once(
    home,
    "      margin: const EdgeInsets.only(top: 14),\n      padding: const EdgeInsets.all(14),\n      decoration: BoxDecoration(\n        color: AyatColors.surface2,\n        borderRadius: BorderRadius.circular(12),\n",
    "      margin: const EdgeInsets.only(top: 14),\n      padding: const EdgeInsets.all(14),\n      decoration: BoxDecoration(\n        color: AyatColors.surface2,\n        borderRadius: BorderRadius.circular(16), // PATCH_S165_UI_REFRESH\n",
    'section card')

# ------------------------------------------------------------ 2b. _AmbientGlow class
home = sub_once(
    home,
    "class _EffectPicker extends StatefulWidget {\n",
    """// PATCH_S165_UI_REFRESH: the prototype's ambient background - emerald light
// from the top corner, a whisper of burgundy from the bottom. Static, so it
// sits in its own repaint layer and never costs a frame while scrolling.
class _AmbientGlow extends StatelessWidget {
  const _AmbientGlow();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.9, -0.85),
                  radius: 1.15,
                  colors: [
                    AyatColors.emerald.withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.9, 1.0),
                  radius: 1.0,
                  colors: [
                    const Color(0xFF5C2430).withValues(alpha: 0.22),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EffectPicker extends StatefulWidget {
""",
    'ambient glow class')

# ------------------------------------------------------------ 10. theme
theme = sub_once(
    theme,
    "        progressIndicatorTheme: const ProgressIndicatorThemeData(\n",
    """        // PATCH_S165_UI_REFRESH: one look for chips, sliders, dialogs, sheets
        // and snack bars - gold on deep green, pill shaped, hairline edged.
        chipTheme: ChipThemeData(
          backgroundColor: AyatColors.surface2,
          selectedColor: AyatColors.gold,
          side: const BorderSide(color: AyatColors.hairline),
          shape: const StadiumBorder(),
          showCheckmark: false,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          labelStyle: GoogleFonts.tajawal(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: AyatColors.parchment),
          secondaryLabelStyle: GoogleFonts.tajawal(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AyatColors.ink),
        ),
        sliderTheme: SliderThemeData(
          trackHeight: 4,
          activeTrackColor: AyatColors.gold,
          inactiveTrackColor: AyatColors.surface3,
          thumbColor: AyatColors.goldBright,
          overlayColor: AyatColors.gold.withValues(alpha: 0.16),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AyatColors.surface2,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
            side: const BorderSide(color: AyatColors.hairline),
          ),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: AyatColors.surface,
          surfaceTintColor: Colors.transparent,
          showDragHandle: true,
          dragHandleColor: AyatColors.goldDim,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: AyatColors.surface3,
          behavior: SnackBarBehavior.floating,
          contentTextStyle: GoogleFonts.tajawal(
              fontSize: 13, color: AyatColors.parchment),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: AyatColors.hairline),
          ),
        ),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
""",
    'theme block')

if problems:
    print('  SKIP    nothing written. Anchors that did not match:')
    for p in problems:
        print('          - ' + p)
    sys.exit(1)

# ------------------------------------------------------------ write + sanity
def balanced(src):
    t = re.sub(r"//[^\n]*", '', src)
    t = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", t)
    t = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', t)
    return all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))


if not (balanced(home) and balanced(theme)):
    print('  STOP    result would be unbalanced - nothing written')
    sys.exit(1)

# marker lives in both files so the idempotency check above is exact
if MARK not in home:
    home = home.replace('// PATCH_S165_UI_REFRESH: transparent bar',
                        '// PATCH_S165_UI_REFRESH: transparent bar', 1)
open(HOME, 'w', encoding='utf-8').write(home)
open(THEME, 'w', encoding='utf-8').write(theme)
print('  PATCHED lib/screens/home_screen.dart')
print('  PATCHED lib/theme/ayat_theme.dart')
print('  all balanced')
print('Next: flutter analyze && git add -A && git commit -m "S165: studio UI refresh" && git push')
