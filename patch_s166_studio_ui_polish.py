#!/usr/bin/env python3
"""
patch_s166_studio_ui_polish.py
==============================
Ayat Studio S166 - run from the repo root (after S165):

    python3 patch_s166_studio_ui_polish.py

Second pass on the studio screen: fewer buttons, more life.

  1. Sliding gold pill behind the 5 main tabs (one pill glides between tabs
     instead of each tab lighting up on its own)
  2. Frame picker: each aspect ratio is drawn as a real miniature frame
     (9:16 is tall, 16:9 is wide) instead of a text chip
  3. The wall of 7 full-width buttons becomes:
       - one big upload card (breathes softly until a file is loaded)
       - three action tiles: mic / detect from video / auto-sync (gold)
       - model picker (unchanged)
       - a collapsible "clip tools" drawer for merge + sequence
     Every handler and enabled-state is exactly the old one.
  4. Preview gets a slow breathing gold halo (own repaint layer, so the
     video never repaints for it)
  5. Ornament dividers (line - diamond - line) between sections of
     Shape and Media instead of plain rules
  6. A faint gold basmala above the studio while it is empty

Idempotent (marker PATCH_S166). Needs S165. Anchor-checked: if anything is
missing NOTHING is written.
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')

MARK = 'PATCH_S166'
HOME = os.path.join(ROOT, 'lib/screens/home_screen.dart')
if not os.path.exists(HOME):
    sys.exit('missing ' + HOME)
home = open(HOME, encoding='utf-8').read()
if MARK in home:
    print('  OK      already applied')
    sys.exit(0)
if 'PATCH_S165_UI_REFRESH' not in home:
    sys.exit('  STOP    S165 is not applied - run patch_s165_studio_ui_refresh.py first')

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


# ------------------------------------------------------------ 1. sliding tab pill
home = sub_once(
    home,
    """    return Row(
      children: [
        for (var i = 0; i < _tabs.length; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: i == 0 ? 0 : 4,
                right: i == _tabs.length - 1 ? 0 : 4,
              ),
              child: _tabButton(i),
            ),
          ),
      ],
    );
  }
""",
    """    // PATCH_S166_UI_POLISH: one gold pill glides behind the tabs. Directional
    // alignment, so it follows the tab order in both RTL and LTR.
    final n = _tabs.length;
    final sel = _safeSelectedTab;
    return Container(
      height: 62,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AyatColors.surface2,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AyatColors.hairline),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: AppMotion.d(AppMotion.medium),
            curve: Curves.easeOutBack,
            alignment: AlignmentDirectional(
                n <= 1 ? 0.0 : -1.0 + 2.0 * sel / (n - 1), 0),
            child: FractionallySizedBox(
              widthFactor: 1 / n,
              heightFactor: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AyatColors.goldBright, AyatColors.gold],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: AyatColors.gold.withValues(alpha: 0.4),
                      blurRadius: 14,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < n; i++)
                Expanded(child: _tabButton(i, slider: true)),
            ],
          ),
        ],
      ),
    );
  }
""",
    'tab row -> sliding pill')

NEW_TAB = """  Widget _tabButton(int i, {bool slider = false}) {
    // PATCH_S165_UI_REFRESH: animated pill. Selected = gold gradient + glow,
    // icon pops with a spring; everything is a no-op when animations are off.
    // PATCH_S166_UI_POLISH: slider = true means the shared sliding pill in
    // _tabChips paints the selected background, so this tab stays transparent.
    final selected = _safeSelectedTab == i;
    final dur = AppMotion.d(AppMotion.fast);
    return PressableScale(
      borderRadius: BorderRadius.circular(18),
      pressedScale: 0.94,
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedTab = i);
      },
      child: AnimatedContainer(
        duration: dur,
        curve: Curves.easeOutCubic,
        height: slider ? double.infinity : 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: (selected && !slider)
              ? const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AyatColors.goldBright, AyatColors.gold],
                )
              : null,
          color: (selected || slider) ? null : AyatColors.surface2,
          borderRadius: BorderRadius.circular(16),
          border: slider
              ? null
              : Border.all(
                  color:
                      selected ? AyatColors.goldBright : AyatColors.hairline,
                ),
          boxShadow: (selected && !slider)
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

# ------------------------------------------------------------ 2. frame picker
home = sub_once(
    home,
    """        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in kAspectRatios)
              ChoiceChip(
                label: Text(AppStrings(AppSettings.instance.lang).t('aspect.${entry.$1.name}')), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
                selected: state.aspectRatio == entry.$1,
                onSelected: (_) =>
                    state.update(() => state.aspectRatio = entry.$1),
              ),
          ],
        ),
""",
    """        // PATCH_S166_UI_POLISH: every shape drawn as a miniature of itself.
        Row(
          children: [
            for (var i = 0; i < kAspectRatios.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              Expanded(child: _ratioTile(kAspectRatios[i])),
            ],
          ],
        ),
""",
    'ratio chips')

# ------------------------------------------------------------ 3. media buttons
NEW_MEDIA = """  Widget _mediaButtons() {
    // PATCH_S166_UI_POLISH: one hero upload card, three action tiles, the
    // model picker, and the rarely-used clip tools tucked in a drawer.
    // Handlers and enabled-state are identical to the old button stack.
    final lang = AppStrings(AppSettings.instance.lang);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _uploadHero(),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _actionTile(
                icon: _listening ? Icons.stop_circle_outlined : Icons.mic,
                label: _listening ? 'إيقاف الاستماع' : 'تعرّف من الميكروفون',
                onTap: _busy ? null : _micDetect,
                active: _listening,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionTile(
                icon: Icons.manage_search,
                label: 'تعرّف من صوت الفيديو',
                onTap: _busy ? null : _detectFromVideo,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _actionTile(
                icon: Icons.auto_awesome,
                label: state.timelineActive
                    ? lang.t('autosync.btnRescan')
                    : lang.t('autosync.btn'),
                onTap: _busy ? null : _autoSync,
                primary: true,
              ),
            ),
          ],
        ),
        // PATCH_S101_AUTOSYNC_HINT_PARTIAL_AYAH: set expectations before they tap it --
        // it does the job well on roughly half the video; the rest may
        // need a manual touch-up from the review card above.
        const SizedBox(height: 8),
        Text(
          lang.t('autosync.hint'), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: AyatColors.goldDim, fontSize: 12),
        ),
        // PATCH_S75_COMPACT_PICKER_FALLBACK: model-size picker -- controls every detect/auto-sync
        // button above via WhisperService.setModelSize(). One compact row
        // that opens a bottom-sheet list on tap.
        _fieldLabel('دقة التعرّف على الكلام'),
        _modelSizeSelector(),
        const SizedBox(height: 8),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 4),
            childrenPadding: const EdgeInsets.only(bottom: 4),
            iconColor: AyatColors.goldBright,
            collapsedIconColor: AyatColors.parchmentDim,
            leading: const Icon(Icons.video_collection_outlined,
                size: 19, color: AyatColors.goldDim),
            title: const Text('أدوات المقاطع',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            children: [
              // PATCH_S79_CUSTOM_BG_NUMBER_AND_VIDEO_MERGE
              OutlinedButton.icon(
                onPressed:
                    (_busy || !state.hasVideo) ? null : _pickAndMergeVideo,
                icon: const Icon(Icons.video_collection_outlined, size: 18),
                label: const Text('دمج مع فيديو آخر'),
              ),
              const SizedBox(height: 8),
              // PATCH_S125_SEQUENCE: S79's merge is two clips, whole, butted
              // together. This is the general case -- any number of clips,
              // each trimmed, reordered, joined with a real transition.
              OutlinedButton.icon(
                onPressed: _busy ? null : _openSequence,
                icon: const Icon(Icons.playlist_add, size: 18),
                label: const Text('تركيب عدة مقاطع (قصّ وترتيب وانتقالات)'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // PATCH_S166_UI_POLISH: the primary entry point. While nothing is loaded
  // its halo breathes, drawing the eye to the one thing to do first.
  Widget _uploadHero() {
    final empty = !state.hasVideo;
    final disabled = _busy;
    final card = Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AyatColors.gold.withValues(alpha: empty ? 0.16 : 0.08),
            AyatColors.gold.withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AyatColors.gold.withValues(alpha: empty ? 0.55 : 0.28),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AyatColors.gold.withValues(alpha: 0.14),
              border:
                  Border.all(color: AyatColors.gold.withValues(alpha: 0.5)),
            ),
            child: const Icon(Icons.upload_file,
                size: 22, color: AyatColors.goldBright),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('رفع فيديو أو تلاوة صوتية',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AyatColors.parchment)),
                const SizedBox(height: 2),
                Text(
                  empty ? 'ابدأ من هنا' : 'استبدال الملف الحالي',
                  style: const TextStyle(
                      fontSize: 12, color: AyatColors.parchmentDim),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_left, color: AyatColors.goldDim),
        ],
      ),
    );
    return AnimatedOpacity(
      duration: AppMotion.d(AppMotion.fast),
      opacity: disabled ? 0.5 : 1,
      child: _Breathing(
        enabled: empty && !disabled,
        borderRadius: 22,
        child: PressableScale(
          borderRadius: BorderRadius.circular(22),
          onTap: disabled ? null : _pickVideo,
          child: card,
        ),
      ),
    );
  }

  // PATCH_S166_UI_POLISH: square-ish action tile. primary = gold (auto-sync).
  Widget _actionTile({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool primary = false,
    bool active = false,
  }) {
    final on = onTap != null;
    final fg = primary ? AyatColors.ink : AyatColors.parchment;
    return AnimatedOpacity(
      duration: AppMotion.d(AppMotion.fast),
      opacity: on ? 1 : 0.45,
      child: PressableScale(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 84),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
          decoration: BoxDecoration(
            gradient: primary
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AyatColors.goldBright, AyatColors.gold],
                  )
                : null,
            color: primary
                ? null
                : (active
                    ? AyatColors.gold.withValues(alpha: 0.18)
                    : AyatColors.surface2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: primary
                  ? AyatColors.goldBright
                  : (active ? AyatColors.gold : AyatColors.hairline),
            ),
            boxShadow: primary && on
                ? [
                    BoxShadow(
                      color: AyatColors.gold.withValues(alpha: 0.3),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : const [],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 24,
                  color: primary ? AyatColors.ink : AyatColors.goldBright),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // PATCH_S166_UI_POLISH: one aspect-ratio tile - a miniature frame drawn in
  // the real proportion of the shape it selects.
  Widget _ratioTile((AyatAspectRatio, String, int, int) entry) {
    final selected = state.aspectRatio == entry.$1;
    final isCustom = entry.$1 == AyatAspectRatio.custom;
    final ar = (entry.$4 > 0) ? entry.$3 / entry.$4 : 1.0;
    const box = 26.0;
    final gw = ar >= 1 ? box : box * ar;
    final gh = ar >= 1 ? box / ar : box;
    final dur = AppMotion.d(AppMotion.fast);
    final fg = selected ? AyatColors.ink : AyatColors.parchment;
    return PressableScale(
      borderRadius: BorderRadius.circular(16),
      pressedScale: 0.95,
      onTap: () {
        HapticFeedback.selectionClick();
        state.update(() => state.aspectRatio = entry.$1);
      },
      child: AnimatedContainer(
        duration: dur,
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
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
                    color: AyatColors.gold.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: box,
              height: box,
              child: Center(
                child: isCustom
                    ? Icon(Icons.tune, size: 20, color: fg)
                    : AnimatedContainer(
                        duration: dur,
                        width: gw,
                        height: gh,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: selected
                              ? AyatColors.ink.withValues(alpha: 0.12)
                              : Colors.transparent,
                          border: Border.all(
                            color: selected
                                ? AyatColors.ink
                                : AyatColors.parchmentDim,
                            width: 1.6,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                AppStrings(AppSettings.instance.lang)
                    .t('aspect.${entry.$1.name}'), // PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // PATCH_S166_UI_POLISH: line - diamond - line, replaces plain Divider
  // between panel sections.
  Widget _ornament() {
    const line = Expanded(
      child: SizedBox(
        height: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, AyatColors.hairline],
            ),
          ),
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          line,
          const SizedBox(width: 10),
          Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: AyatColors.gold,
                boxShadow: [
                  BoxShadow(
                    color: AyatColors.gold.withValues(alpha: 0.6),
                    blurRadius: 6,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Transform.flip(
              flipX: true,
              child: const SizedBox(
                height: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, AyatColors.hairline],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

"""
home = sub_re(
    home,
    r"  Widget _mediaButtons\(\) \{\n.*?\n  \}\n\n(?=  // PATCH_S134_AUTOSEG_WIZARD: guided multi-step entry point)",
    NEW_MEDIA,
    'media buttons')

# ------------------------------------------------------------ 5. ornament dividers
home = sub_once(
    home,
    "        _effectsPanel(),\n        const Divider(height: 28, color: AyatColors.hairline),\n        _templatesPanel(),\n",
    "        _effectsPanel(),\n        _ornament(), // PATCH_S166_UI_POLISH\n        _templatesPanel(),\n",
    'shape panel divider')
home = sub_once(
    home,
    "        _bgPanel(),\n        const Divider(height: 28, color: AyatColors.hairline),\n        _chromaPanel(),\n        const Divider(height: 28, color: AyatColors.hairline),\n        _recitersPanel(),\n",
    "        _bgPanel(),\n        _ornament(), // PATCH_S166_UI_POLISH\n        _chromaPanel(),\n        _ornament(),\n        _recitersPanel(),\n",
    'media panel dividers')

# ------------------------------------------------------------ 4. preview halo + 6. basmala
home = sub_once(
    home,
    """                StagePreview(
                  state: state,
                  videoController: _video,
                  liveOverride: _liveOverlay,
                ),
""",
    """                _Breathing(
                  enabled: true,
                  borderRadius: 18,
                  subtle: true,
                  child: StagePreview(
                    state: state,
                    videoController: _video,
                    liveOverride: _liveOverlay,
                  ),
                ), // PATCH_S166_UI_POLISH
""",
    'preview halo')

home = sub_once(
    home,
    "                FadeSlideIn(child: _statusCard()), // PATCH_S165_UI_REFRESH\n",
    """                // PATCH_S166_UI_POLISH: a faint gold basmala while empty.
                if (!state.hasVideo)
                  FadeSlideIn(
                    child: GoldShimmer(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          '\\uFDFD',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .displayLarge
                              ?.copyWith(
                                fontSize: 30,
                                height: 1.3,
                                color:
                                    AyatColors.gold.withValues(alpha: 0.75),
                              ),
                        ),
                      ),
                    ),
                  ),
                FadeSlideIn(child: _statusCard()), // PATCH_S165_UI_REFRESH
""",
    'basmala')

# ------------------------------------------------------------ _Breathing class
home = sub_once(
    home,
    "class _AmbientGlow extends StatelessWidget {\n",
    """// PATCH_S166_UI_POLISH: a slow breathing gold halo behind [child]. The halo
// lives in its own RepaintBoundary and the child is passed through untouched,
// so animating it never repaints the child (which may be a live video).
// Static when animations are off or [enabled] is false.
class _Breathing extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double borderRadius;
  final bool subtle;
  const _Breathing({
    required this.child,
    required this.enabled,
    this.borderRadius = 18,
    this.subtle = false,
  });

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3600));
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Breathing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (AppMotion.on && widget.enabled) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0.5;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.subtle ? 0.05 : 0.10;
    final swing = widget.subtle ? 0.10 : 0.22;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) {
                  final t = Curves.easeInOut.transform(_c.value);
                  return DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(widget.borderRadius),
                      boxShadow: [
                        BoxShadow(
                          color: AyatColors.gold
                              .withValues(alpha: base + swing * t),
                          blurRadius: 18 + 16 * t,
                          spreadRadius: 0.5 + 1.5 * t,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        widget.child,
      ],
    );
  }
}

class _AmbientGlow extends StatelessWidget {
""",
    'breathing class')

if problems:
    print('  SKIP    nothing written. Anchors that did not match:')
    for p in problems:
        print('          - ' + p)
    sys.exit(1)


def balanced(src):
    t = re.sub(r"//[^\n]*", '', src)
    t = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", t)
    t = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', t)
    return all(t.count(a) == t.count(b) for a, b in ('{}', '()', '[]'))


if not balanced(home):
    print('  STOP    result would be unbalanced - nothing written')
    sys.exit(1)

open(HOME, 'w', encoding='utf-8').write(home)
print('  PATCHED lib/screens/home_screen.dart')
print('  all balanced')
print('Next: flutter analyze && git add -A && git commit -m "S166: studio UI polish" && git push')
