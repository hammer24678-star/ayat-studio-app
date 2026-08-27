// PATCH_S128_TEXT_EDITOR_PRO_SIMPLE_MODE_SELECTION_GUIDE_I18N
// AyahBlocksEditor: each ayah = one visible block. Dragging the handle
// BETWEEN two blocks moves end-of-first and start-of-second TOGETHER —
// no gap, no overlap, 1:1 with the finger. Auto-scrolls when the finger
// reaches either screen edge.
import 'package:flutter/material.dart';
import '../theme/ayat_theme.dart';

class SegVM { final String label; double start, end;
  SegVM(this.label, this.start, this.end); }

class AyahBlocksEditor extends StatefulWidget {
  final List<SegVM> segs; final double durationSec;
  final void Function() onChanged; // persist + rebuild after a drag
  const AyahBlocksEditor({super.key, required this.segs,
    required this.durationSec, required this.onChanged});
  @override
  State<AyahBlocksEditor> createState() => _AyahBlocksEditorState();
}

class _AyahBlocksEditorState extends State<AyahBlocksEditor> {
  final _ctl = ScrollController();
  static const _edge = 48.0; // px from viewport edge that triggers auto-scroll

  @override
  Widget build(BuildContext c) {
    final total = widget.durationSec <= 0 ? 1.0 : widget.durationSec;
    return LayoutBuilder(builder: (c, box) {
      final contentW = box.maxWidth * 2.5; // zoom: 2.5 screens of timeline
      final pps = contentW / total;        // pixels per second (1:1 drag)
      return SizedBox(height: 64, child: ListView(controller: _ctl,
        scrollDirection: Axis.horizontal, physics: const ClampingScrollPhysics(),
        children: [SizedBox(width: contentW, child: Stack(
          children: [for (var i = 0; i < widget.segs.length; i++) ...[
            Positioned(left: widget.segs[i].start * pps,
              width: (widget.segs[i].end - widget.segs[i].start) * pps - 3,
              top: 8, bottom: 8,
              child: Container(decoration: BoxDecoration(
                color: AyatColors.gold.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AyatColors.gold.withValues(alpha: .6))),
                alignment: Alignment.center,
                child: Text(widget.segs[i].label, maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: AyatColors.parchment)))),
            if (i < widget.segs.length - 1)
              Positioned(left: widget.segs[i].end * pps - 12, top: 0, bottom: 0,
                width: 24, child: GestureDetector(behavior: HitTestBehavior.opaque,
                  onHorizontalDragUpdate: (d) => _drag(i, d, pps),
                  child: Container(alignment: Alignment.center,
                    child: Container(width: 6, height: 40,
                      decoration: BoxDecoration(color: AyatColors.goldBright,
                        borderRadius: BorderRadius.circular(3))))),
          ])]))]);
    });
  }

  void _drag(int i, DragUpdateDetails d, double pps) {
    final dt = d.delta.dx / pps; // 1:1
    final a = widget.segs[i], b = widget.segs[i + 1];
    final t = (a.end + dt).clamp(a.start + 0.2, b.end - 0.2);
    a.end = t; b.start = t; // together: no gap, no overlap
    _autoScroll(d);
    setState(widget.onChanged);
  }

  void _autoScroll(DragUpdateDetails d) {
    if (!_ctl.hasClients) return;
    final vp = _ctl.position.viewportDimension;
    final px = d.localPosition.dx; // approx within viewport
    if (px > vp - _edge) _ctl.jumpTo((_ctl.offset + 8)
        .clamp(0, _ctl.position.maxScrollExtent));
    if (px < _edge) _ctl.jumpTo((_ctl.offset - 8).clamp(0, double.infinity));
  }
}
