#!/usr/bin/env python3
"""
patch_s168_export_button_fix.py
===============================
Ayat Studio S168 - run from the repo root (after S167):

    python3 patch_s168_export_button_fix.py

SYMPTOM (screenshot): the gold "تصدير المقطع" button is drawn at the top of the
screen, wider than the cards (touching the left edge), on top of the panel text.
Its real place is the LAST item of the scroll column, so it is a paint glitch,
not a layout bug.

CAUSE (most likely): S165 wrapped the button - gradient, 20px blurred glow
shadow, press-scale - in GoldShimmer, which is a ShaderMask(srcATop). A
ShaderMask forces an offscreen layer sized to its child; with a blurred shadow
inside it and the child scrolled off-screen, Flutter's renderer can draw that
layer at the wrong place (it is a known class of ShaderMask-in-a-scrollable
bugs). I could not run the app here, so this is the cause the code points to,
not one I reproduced.

FIX: a new GoldSheen widget draws the same moving highlight with a plain
CustomPainter on top of the child (no ShaderMask, no offscreen layer), clipped
to the rounded shape. Used on every box-shaped shimmer: export button, Quran
entry card, progress bar. Text shimmers (title, basmala, splash) keep
GoldShimmer. The export button is also wrapped in a RepaintBoundary.

Idempotent (marker PATCH_S168). Anchor-checked: if anything is missing NOTHING
is written.
"""
import os, re, sys

ROOT = os.getcwd()
if not os.path.exists(os.path.join(ROOT, 'pubspec.yaml')):
    sys.exit('Run this from the repo root (pubspec.yaml not found).')
MARK = 'PATCH_S168'


def rd(p):
    with open(os.path.join(ROOT, p), encoding='utf-8') as f:
        return f.read()


files = {p: rd(p) for p in ('lib/widgets/motion.dart', 'lib/screens/home_screen.dart',
                            'lib/widgets/quran_entry_button.dart')}
if all(MARK in t for t in files.values()):
    print('  OK      already applied'); sys.exit(0)

new = dict(files)
problems = []


def need(cond, msg):
    if not cond:
        problems.append(msg)


# ---------------- motion.dart: GoldSheen ----------------
SHEEN = r"""

// PATCH_S168_EXPORT_BUTTON_FIX
// The same moving gold highlight as GoldShimmer, drawn as a plain overlay
// (CustomPainter) instead of a ShaderMask. No offscreen layer, so it cannot be
// painted at the wrong place when it scrolls. Use for box-shaped children;
// GoldShimmer stays for text.
class GoldSheen extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Duration period;
  const GoldSheen({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.period = const Duration(milliseconds: 3200),
  });

  @override
  State<GoldSheen> createState() => _GoldSheenState();
}

class _GoldSheenState extends State<GoldSheen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.period);
    if (AppMotion.on) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AppMotion.on) return widget.child;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: CustomPaint(painter: _SheenPainter(_c)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SheenPainter extends CustomPainter {
  final Animation<double> t;
  _SheenPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final p = -0.4 + t.value * 1.8; // same sweep + rest beat as GoldShimmer
    final rect = Offset.zero & size;
    final shader = LinearGradient(
      begin: Alignment.centerRight,
      end: Alignment.centerLeft,
      stops: [
        (p - 0.18).clamp(0.0, 1.0),
        p.clamp(0.0, 1.0),
        (p + 0.18).clamp(0.0, 1.0),
      ],
      colors: [
        Colors.transparent,
        AyatColors.goldBright.withValues(alpha: 0.30),
        Colors.transparent,
      ],
    ).createShader(rect);
    canvas.drawRect(rect, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.t != t;
}
"""
m = files['lib/widgets/motion.dart']
if MARK not in m:
    need('class GoldShimmer extends StatefulWidget' in m, 'motion.dart: GoldShimmer not found')
    new['lib/widgets/motion.dart'] = m.rstrip('\n') + '\n' + SHEEN

# ---------------- home_screen.dart: export button + progress bar ----------------
EXPORT = r"""  // PATCH_S165_UI_REFRESH: the export call-to-action. Gold gradient, glow,
  // press-in scale and a slow sheen; dims while a job is running.
  // PATCH_S168_EXPORT_BUTTON_FIX: sheen is a plain overlay (GoldSheen), not a
  // ShaderMask, and the whole button paints in its own RepaintBoundary.
  Widget _exportButton() {
    final disabled = _busy;
    return RepaintBoundary(
      child: AnimatedOpacity(
        duration: AppMotion.d(AppMotion.fast),
        opacity: disabled ? 0.5 : 1,
        child: PressableScale(
          borderRadius: BorderRadius.circular(20),
          pressedScale: 0.97,
          onTap: disabled
              ? null
              : () {
                  HapticFeedback.mediumImpact(); // PATCH_S167_APP_POLISH
                  _export();
                },
          child: Container(
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
            child: GoldSheen(
              borderRadius: BorderRadius.circular(20),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
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
        ),
      ),
    );
  }

"""
h = files['lib/screens/home_screen.dart']
if MARK not in h:
    pat = re.compile(r"  // PATCH_S165_UI_REFRESH: the export call-to-action\..*?(?=  Widget _statusBusyCard\(\))", re.S)
    mm = pat.search(h)
    need(mm is not None, 'home_screen.dart: _exportButton block not found')
    old_bar = ("                  child: GoldShimmer(\n"
               "                    child: ClipRRect(\n"
               "                      borderRadius: BorderRadius.circular(999),\n"
               "                      child: LinearProgressIndicator(")
    need(old_bar in h, 'home_screen.dart: progress-bar shimmer not found')
    if mm is not None and old_bar in h:
        hh = h[:mm.start()] + EXPORT + h[mm.end():]
        hh = hh.replace(old_bar,
                        "                  child: GoldSheen(\n"
                        "                    borderRadius: BorderRadius.circular(999), // PATCH_S168\n"
                        "                    child: ClipRRect(\n"
                        "                      borderRadius: BorderRadius.circular(999),\n"
                        "                      child: LinearProgressIndicator(")
        new['lib/screens/home_screen.dart'] = hh

# ---------------- quran_entry_button.dart ----------------
q = files['lib/widgets/quran_entry_button.dart']
if MARK not in q:
    old = "      child: GoldShimmer(period: const Duration(milliseconds: 4200), child: card),"
    need(old in q, 'quran_entry_button.dart: GoldShimmer line not found')
    if old in q:
        new['lib/widgets/quran_entry_button.dart'] = q.replace(
            old,
            "      // PATCH_S168_EXPORT_BUTTON_FIX: overlay sheen, not a ShaderMask\n"
            "      child: GoldSheen(\n"
            "        period: const Duration(milliseconds: 4200),\n"
            "        borderRadius: BorderRadius.circular(18),\n"
            "        child: card,\n"
            "      ),")

if problems:
    print('  NOTHING WRITTEN. Missing anchors:')
    for p in problems:
        print('   -', p)
    sys.exit(1)

bad = 0
for p, t in new.items():
    s = re.sub(r"//[^\n]*", '', t)
    s = re.sub(r"'(?:\\.|[^'\\\n])*'", "''", s)
    s = re.sub(r'"(?:\\.|[^"\\\n])*"', '""', s)
    for a, b in ('{}', '()', '[]'):
        if s.count(a) != s.count(b):
            bad += 1
            print('  UNBALANCED', p, a, s.count(a), b, s.count(b))
if bad:
    sys.exit('  NOTHING WRITTEN (brackets unbalanced).')

for p, t in new.items():
    if t != files[p]:
        with open(os.path.join(ROOT, p), 'w', encoding='utf-8') as f:
            f.write(t)
        print('  PATCHED', p)
print('Done. Next: git add -A && git commit -m "S168: export button paint fix (GoldSheen)" && git push')
