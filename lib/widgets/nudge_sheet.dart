// PATCH_S190_COMFORT: precise placement of the selected block.
//
// A short sheet that leaves the preview visible. Pick what to move (start,
// end, or the whole block) and tap - or hold - the step buttons:
// 1 frame, 0.1 s, 1 s, both directions. Holding repeats, and every step shows
// the result at once because the caller moves the playhead to the edge.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ayat_theme.dart';

Future<void> showNudgeSheet(
  BuildContext context, {
  required String title,
  required bool canMove,
  required double frame,
  required (double, double) Function() range,
  required void Function(int mode, double delta) onNudge,
}) {
  return showModalBottomSheet<void>(
    context: context,
    barrierColor: Colors.transparent,
    backgroundColor: AyatColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (ctx) => _NudgeSheet(
      title: title,
      canMove: canMove,
      frame: frame,
      range: range,
      onNudge: onNudge,
    ),
  );
}

class _NudgeSheet extends StatefulWidget {
  final String title;
  final bool canMove;
  final double frame;
  final (double, double) Function() range;
  final void Function(int mode, double delta) onNudge;
  const _NudgeSheet({
    required this.title,
    required this.canMove,
    required this.frame,
    required this.range,
    required this.onNudge,
  });

  @override
  State<_NudgeSheet> createState() => _NudgeSheetState();
}

class _NudgeSheetState extends State<_NudgeSheet> {
  late int _mode = widget.canMove ? 2 : 0; // 0 start, 1 end, 2 whole block

  static String _fmt(double s) {
    final m = s ~/ 60;
    final sec = s - m * 60;
    return '$m:${sec.toStringAsFixed(2).padLeft(5, '0')}';
  }

  void _step(double d) {
    widget.onNudge(_mode, d);
    if (mounted) setState(() {});
  }

  Widget _btn(String label, double d) => Expanded(
        child: _Hold(
          onStep: () => _step(d),
          child: Container(
            height: 46,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AyatColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AyatColors.hairline),
            ),
            child: Text(label,
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AyatColors.parchment)),
          ),
        ),
      );

  Widget _modeChip(int m, String label) {
    final on = _mode == m;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _mode = m);
        },
        child: Container(
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AyatColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: on ? AyatColors.gold : AyatColors.hairline),
          ),
          child: Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: on ? AyatColors.ink : AyatColors.parchmentDim)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (a, b) = widget.range();
    final f = widget.frame;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                Expanded(
                  child: Text(widget.title,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AyatColors.parchment)),
                ),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text('${_fmt(a)}  →  ${_fmt(b)}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AyatColors.goldBright,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                _modeChip(0, 'البداية'),
                _modeChip(1, 'النهاية'),
                if (widget.canMove) _modeChip(2, 'الكل'),
              ]),
              const SizedBox(height: 10),
              Directionality(
                textDirection: TextDirection.ltr,
                child: Row(children: [
                  _btn('−1ث', -1.0),
                  _btn('−0.1', -0.1),
                  _btn('−إطار', -f),
                  _btn('+إطار', f),
                  _btn('+0.1', 0.1),
                  _btn('+1ث', 1.0),
                ]),
              ),
              const SizedBox(height: 6),
              const Text('اضغط مطولًا للتكرار',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AyatColors.parchmentDim)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap = one step; hold = steps repeat, getting out of the way of the finger.
class _Hold extends StatefulWidget {
  final Widget child;
  final VoidCallback onStep;
  const _Hold({required this.child, required this.onStep});

  @override
  State<_Hold> createState() => _HoldState();
}

class _HoldState extends State<_Hold> {
  Timer? _t;

  void _start() {
    HapticFeedback.selectionClick();
    widget.onStep();
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 380), () {
      _t = Timer.periodic(
          const Duration(milliseconds: 70), (_) => widget.onStep());
    });
  }

  void _stop() {
    _t?.cancel();
    _t = null;
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _stop(),
        onPointerCancel: (_) => _stop(),
        child: widget.child,
      );
}
