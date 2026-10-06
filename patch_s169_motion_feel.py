#!/usr/bin/env python3
"""
patch_s169_motion_feel.py
=========================
Ayat Studio S169 - run from the repo root (after S168):

    python3 patch_s169_motion_feel.py

A motion-and-feel pass. Everything honours Settings > animations (off = static).
No ShaderMask anywhere (see S168).

  motion.dart
    1. Page transitions: incoming page fades + scales up + lifts; the page
       underneath recedes (scale + dim) instead of sitting still
    2. PulseGlow      - slow gold glow that breathes while a job is running
    3. SmoothProgressBar - the progress bar glides to each new value
    4. showGoldBurst  - ring + gold sparks when an export finishes
  home_screen.dart
    5. progress card pulses while busy; bar glides instead of jumping
    6. status line cross-fades when its text changes
    7. panel card animates its HEIGHT between tabs (no more snap)
    8. play button glow swells while the video plays
    9. gold burst + success haptic when the export is ready
  ayat_theme.dart
   10. sparkle ink splash on every tap

Idempotent (marker PATCH_S169). Anchor-checked: if anything is missing NOTHING
is written.
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
MARK = 'PATCH_S169'


def rd(p):
    with open(os.path.join(ROOT, p), encoding='utf-8') as f:
        return f.read()


PATHS = ('lib/widgets/motion.dart', 'lib/screens/home_screen.dart', 'lib/theme/ayat_theme.dart')
files = {p: rd(p) for p in PATHS}
if all(MARK in t for t in files.values()):
    print('  OK      already applied'); sys.exit(0)
new = dict(files)
problems = []


def need(c, m):
    if not c:
        problems.append(m)


# ===================================================================== motion.dart
m = files['lib/widgets/motion.dart']
if MARK not in m:
    ROUTE = r"""  /// A page route: the new page fades, scales up and lifts into place while
  /// the page underneath recedes (smaller + dimmer). Honours the motion switch.
  /// PATCH_S169_MOTION_FEEL
  static Route<T> route<T>(Widget page) {
    if (!on) {
      return PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => page,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      );
    }
    return PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, secondary, child) {
        final inC = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutQuart,
            reverseCurve: Curves.easeInCubic);
        final outC = CurvedAnimation(
            parent: secondary,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: Tween<double>(begin: 1.0, end: 0.7).animate(outC),
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 0.95).animate(outC),
            child: FadeTransition(
              opacity: inC,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.95, end: 1.0).animate(inC),
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.04),
                    end: Offset.zero,
                  ).animate(inC),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
"""
    pat = re.compile(r"  /// A page route that cross-fades and lifts.*?\n}\n(?=\n/// Fades \+ lifts)", re.S)
    mm = pat.search(m)
    need(mm is not None, 'motion.dart: AppMotion.route block not found')

    EXTRA = r"""

// PATCH_S169_MOTION_FEEL ---------------------------------------------------

/// A slow gold glow that breathes while [active]. The wrapper is always in the
/// tree (only the shadow changes) so the child never loses its state.
class PulseGlow extends StatefulWidget {
  final Widget child;
  final bool active;
  final BorderRadius borderRadius;
  const PulseGlow({
    super.key,
    required this.child,
    required this.active,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
  });

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1500));
    _sync();
  }

  @override
  void didUpdateWidget(PulseGlow old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    if (widget.active && AppMotion.on) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final live = widget.active && AppMotion.on;
        final v = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            boxShadow: live
                ? [
                    BoxShadow(
                      color: AyatColors.gold.withValues(alpha: 0.10 + 0.22 * v),
                      blurRadius: 14 + 14 * v,
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
    );
  }
}

/// LinearProgressIndicator that glides to each new value.
class SmoothProgressBar extends StatelessWidget {
  final double? value;
  final double minHeight;
  final Color backgroundColor;
  final Color color;
  const SmoothProgressBar({
    super.key,
    required this.value,
    this.minHeight = 9,
    required this.backgroundColor,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    Widget bar(double? v) => LinearProgressIndicator(
          value: v,
          minHeight: minHeight,
          backgroundColor: backgroundColor,
          valueColor: AlwaysStoppedAnimation(color),
        );
    final v = value;
    if (v == null || !AppMotion.on) return bar(v);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: v),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (_, val, __) => bar(val),
    );
  }
}

/// Ring + gold sparks, played once over the whole screen (e.g. export done).
void showGoldBurst(BuildContext context) {
  if (!AppMotion.on) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _GoldBurst(onDone: () {
      if (entry.mounted) entry.remove();
    }),
  );
  overlay.insert(entry);
}

class _GoldBurst extends StatefulWidget {
  final VoidCallback onDone;
  const _GoldBurst({required this.onDone});

  @override
  State<_GoldBurst> createState() => _GoldBurstState();
}

class _GoldBurstState extends State<_GoldBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1300))
      ..forward().whenComplete(() {
        if (mounted) widget.onDone();
      });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox.expand(
        child: RepaintBoundary(
          child: CustomPaint(painter: _BurstPainter(_c)),
        ),
      ),
    );
  }
}

class _BurstPainter extends CustomPainter {
  final Animation<double> t;
  _BurstPainter(this.t) : super(repaint: t);

  static const int _n = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final p = t.value;
    if (p <= 0 || p >= 1) return;
    final e = Curves.easeOutCubic.transform(p);
    final fade = (1 - p).clamp(0.0, 1.0);
    final c = Offset(size.width / 2, size.height * 0.42);

    // soft glow
    canvas.drawCircle(
      c,
      40 + 150 * e,
      Paint()
        ..shader = RadialGradient(colors: [
          AyatColors.goldBright.withValues(alpha: 0.28 * fade),
          Colors.transparent,
        ]).createShader(Rect.fromCircle(center: c, radius: 40 + 150 * e)),
    );
    // expanding ring
    canvas.drawCircle(
      c,
      20 + 140 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1 + 4 * fade
        ..color = AyatColors.goldBright.withValues(alpha: 0.9 * fade),
    );
    // sparks
    for (var i = 0; i < _n; i++) {
      final jitter = math.sin(i * 12.9898) * 0.5 + 0.5; // stable 0..1
      final ang = i * 2 * math.pi / _n + jitter * 0.4;
      final dist = (70 + 130 * jitter) * e;
      final pos = c +
          Offset(math.cos(ang) * dist, math.sin(ang) * dist + 46 * p * p);
      canvas.drawCircle(
        pos,
        0.8 + (1 + 2.6 * jitter) * fade,
        Paint()
          ..color = (i.isEven ? AyatColors.goldBright : AyatColors.gold)
              .withValues(alpha: fade),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t;
}
"""
    if mm is not None:
        mnew = m[:mm.start()] + ROUTE + m[mm.end():]
        mnew = mnew.rstrip('\n') + '\n' + EXTRA
        new['lib/widgets/motion.dart'] = mnew

# ===================================================================== home_screen.dart
h = files['lib/screens/home_screen.dart']
if MARK not in h:
    hh = h

    def sub(old, newtxt, label, count=1):
        global hh
        n = hh.count(old)
        need(n >= 1, 'home_screen.dart: ' + label + ' not found')
        if n >= 1:
            hh = hh.replace(old, newtxt, count)

    # 5. busy card pulse + smooth bar
    sub("  Widget _statusBusyCard() {\n    return _card(",
        "  // PATCH_S169_MOTION_FEEL: the busy card breathes a gold glow.\n"
        "  Widget _statusBusyCard() => PulseGlow(\n"
        "      active: _busy,\n"
        "      borderRadius: BorderRadius.circular(24),\n"
        "      child: _statusBusyCardBody());\n\n"
        "  Widget _statusBusyCardBody() {\n    return _card(",
        '_statusBusyCard')
    sub("                      child: LinearProgressIndicator(\n"
        "                        value: _busyProgress,\n"
        "                        minHeight: 9,\n"
        "                        backgroundColor: AyatColors.surface3,\n"
        "                        valueColor:\n"
        "                            const AlwaysStoppedAnimation(AyatColors.gold),\n"
        "                      ),",
        "                      child: SmoothProgressBar( // PATCH_S169_MOTION_FEEL\n"
        "                        value: _busyProgress,\n"
        "                        minHeight: 9,\n"
        "                        backgroundColor: AyatColors.surface3,\n"
        "                        color: AyatColors.gold,\n"
        "                      ),",
        'progress bar')

    # 6. status text cross-fade
    sub("            Flexible(\n"
        "              child: Text(\n"
        "                text,\n"
        "                maxLines: 1,\n"
        "                overflow: TextOverflow.ellipsis,\n"
        "                style: const TextStyle(\n"
        "                    fontSize: 12, color: AyatColors.parchmentDim),\n"
        "              ),\n"
        "            ),",
        "            Flexible(\n"
        "              child: AnimatedSwitcher( // PATCH_S169_MOTION_FEEL\n"
        "                duration: AppMotion.d(AppMotion.medium),\n"
        "                child: Text(\n"
        "                  text,\n"
        "                  key: ValueKey(text),\n"
        "                  maxLines: 1,\n"
        "                  overflow: TextOverflow.ellipsis,\n"
        "                  style: const TextStyle(\n"
        "                      fontSize: 12, color: AyatColors.parchmentDim),\n"
        "                ),\n"
        "              ),\n"
        "            ),",
        'status pill text')

    # 7. panel height animation
    sub("    return _card(\n      child: AnimatedSwitcher(\n"
        "        duration: AppMotion.d(AppMotion.medium),\n"
        "        switchInCurve: Curves.easeOutCubic,",
        "    return _card(\n      child: AnimatedSize( // PATCH_S169_MOTION_FEEL: glide the height\n"
        "        duration: AppMotion.d(AppMotion.medium),\n"
        "        curve: Curves.easeOutCubic,\n"
        "        alignment: Alignment.topCenter,\n"
        "        child: AnimatedSwitcher(\n"
        "        duration: AppMotion.d(AppMotion.medium),\n"
        "        switchInCurve: Curves.easeOutCubic,",
        'panel switcher open')
    sub("          child: _panelBody(),\n        ),\n      ),\n    );",
        "          child: _panelBody(),\n        ),\n      ),\n      ),\n    );",
        'panel switcher close')

    # 8. play button glow
    sub("                        child: Container(\n"
        "                          width: 44,\n"
        "                          height: 44,\n"
        "                          decoration: BoxDecoration(\n"
        "                            shape: BoxShape.circle,",
        "                        child: AnimatedContainer( // PATCH_S169_MOTION_FEEL\n"
        "                          duration: AppMotion.d(AppMotion.medium),\n"
        "                          width: 44,\n"
        "                          height: 44,\n"
        "                          decoration: BoxDecoration(\n"
        "                            shape: BoxShape.circle,",
        'play button container')
    sub("                                color: AyatColors.gold.withValues(alpha: 0.35),\n"
        "                                blurRadius: 12,\n"
        "                                offset: const Offset(0, 3),",
        "                                color: AyatColors.gold.withValues(\n"
        "                                    alpha: v.isPlaying ? 0.6 : 0.35),\n"
        "                                blurRadius: v.isPlaying ? 22 : 12,\n"
        "                                offset: const Offset(0, 3),",
        'play button shadow')

    # 9. burst on export ready
    sub("    HapticFeedback.mediumImpact(); // PATCH_S83_SYNC_QOL\n"
        "    // PATCH_S83_SYNC_QOL: the file size answers",
        "    HapticFeedback.mediumImpact(); // PATCH_S83_SYNC_QOL\n"
        "    showGoldBurst(context); // PATCH_S169_MOTION_FEEL\n"
        "    // PATCH_S83_SYNC_QOL: the file size answers",
        'export done haptic')
    new['lib/screens/home_screen.dart'] = hh

# ===================================================================== theme
t = files['lib/theme/ayat_theme.dart']
if MARK not in t:
    old = "        useMaterial3: true,\n        brightness: Brightness.dark,"
    need(old in t, 'ayat_theme.dart: dark ThemeData header not found')
    if old in t:
        new['lib/theme/ayat_theme.dart'] = t.replace(
            old,
            "        useMaterial3: true,\n"
            "        splashFactory: InkSparkle.splashFactory, // PATCH_S169_MOTION_FEEL\n"
            "        brightness: Brightness.dark,", 1)

if problems:
    print('  NOTHING WRITTEN. Missing anchors:')
    for p in problems:
        print('   -', p)
    sys.exit(1)

bad = 0
for p, txt in new.items():
    s = re.sub(r"//[^\n]*", '', txt)
    s = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", s)
    s = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', s)
    for a, b in ('{}', '()', '[]'):
        if s.count(a) != s.count(b):
            bad += 1
            print('  UNBALANCED', p, a, s.count(a), b, s.count(b))
if bad:
    sys.exit('  NOTHING WRITTEN (brackets unbalanced).')

for p, txt in new.items():
    if txt != files[p]:
        with open(os.path.join(ROOT, p), 'w', encoding='utf-8') as f:
            f.write(txt)
        print('  PATCHED', p)
print('Done. Next: git add -A && git commit -m "S169: motion + feel pass" && git push')
