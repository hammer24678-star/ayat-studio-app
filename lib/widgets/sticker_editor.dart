// PATCH_S206_STICKERS
// Make or fix a sticker from any picture: crop it, take the background out,
// flip / turn it, then save it to "ملصقاتي". Pops with the saved PNG's path.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sticker_ops.dart';
import '../services/sticker_service.dart';
import '../theme/ayat_theme.dart';

Uint8List _bgJob(List<Object?> a) {
  final src = RgbaImage(a[1] as int, a[2] as int, a[0] as Uint8List);
  return removeBackground(src,
      keyRgb: a[3] as int?, tolerance: a[4] as int, feather: a[5] as int).px;
}

enum _Tool { crop, bg, flip }

enum _Grab { none, move, tl, tr, bl, br, l, r, t, b }

class StickerEditorPage extends StatefulWidget {
  final String sourcePath;
  final String title;
  const StickerEditorPage(
      {super.key, required this.sourcePath, this.title = 'ملصق جديد'});

  @override
  State<StickerEditorPage> createState() => _StickerEditorPageState();
}

class _StickerEditorPageState extends State<StickerEditorPage> {
  RgbaImage? _base;
  RgbaImage? _preview; // background-removal preview, not committed yet
  ui.Image? _shown;
  final List<RgbaImage> _undo = [];
  _Tool _tool = _Tool.crop;
  bool _loading = true;
  bool _busy = false;
  bool _failed = false;
  int _job = 0;

  // crop (fractions of the picture)
  Rect _crop = const Rect.fromLTWH(0, 0, 1, 1);
  double? _ratio; // w / h, null = free
  _Grab _grab = _Grab.none;

  // background removal
  int? _key; // 0xRRGGBB, null = the corner colour
  double _tol = 28;
  double _feather = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _shown?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final im = await StickerService.decodeFile(widget.sourcePath);
    if (!mounted) return;
    if (im == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    _base = im;
    await _show(im);
    if (!mounted) return;
    setState(() => _loading = false);
  }

  Future<void> _show(RgbaImage im) async {
    final ui1 = await StickerService.toUiImage(im);
    if (!mounted) {
      ui1.dispose();
      return;
    }
    final old = _shown;
    setState(() => _shown = ui1);
    old?.dispose();
  }

  RgbaImage get _current => _preview ?? _base!;

  void _commit(RgbaImage next) {
    final cur = _base;
    if (cur != null) {
      _undo.add(cur);
      if (_undo.length > 8) _undo.removeAt(0);
    }
    _base = next;
    _preview = null;
    _crop = const Rect.fromLTWH(0, 0, 1, 1);
    _ratio = null;
    _show(next);
  }

  Future<void> _undoStep() async {
    if (_undo.isEmpty) return;
    HapticFeedback.selectionClick();
    _base = _undo.removeLast();
    _preview = null;
    _crop = const Rect.fromLTWH(0, 0, 1, 1);
    await _show(_base!);
    if (_tool == _Tool.bg) _runBg();
  }

  // ------------------------------------------------------------------ crop

  void _applyCrop() {
    final b = _base;
    if (b == null) return;
    final x = (_crop.left * b.w).round();
    final y = (_crop.top * b.h).round();
    final w = (_crop.width * b.w).round();
    final h = (_crop.height * b.h).round();
    if (w < 8 || h < 8) return;
    HapticFeedback.mediumImpact();
    setState(() => _commit(cropRgba(b, x, y, w, h)));
  }

  void _setRatio(double? r) {
    final b = _base;
    if (b == null) return;
    setState(() {
      _ratio = r;
      if (r == null) return;
      final imgR = b.w / b.h;
      // largest centred rectangle of ratio r inside the picture
      double fw, fh;
      if (r >= imgR) {
        fw = 1.0;
        fh = imgR / r;
      } else {
        fh = 1.0;
        fw = r / imgR;
      }
      _crop = Rect.fromLTWH((1 - fw) / 2, (1 - fh) / 2, fw, fh);
    });
  }

  _Grab _pick(Offset p, Rect r) {
    const corner = 34.0;
    const edge = 22.0;
    bool near(Offset a) => (a - p).distance < corner;
    if (_ratio == null) {
      if (near(r.topLeft)) return _Grab.tl;
      if (near(r.topRight)) return _Grab.tr;
      if (near(r.bottomLeft)) return _Grab.bl;
      if (near(r.bottomRight)) return _Grab.br;
      final inX = p.dx > r.left && p.dx < r.right;
      final inY = p.dy > r.top && p.dy < r.bottom;
      if (inX && (p.dy - r.top).abs() < edge) return _Grab.t;
      if (inX && (p.dy - r.bottom).abs() < edge) return _Grab.b;
      if (inY && (p.dx - r.left).abs() < edge) return _Grab.l;
      if (inY && (p.dx - r.right).abs() < edge) return _Grab.r;
    }
    return r.inflate(8).contains(p) ? _Grab.move : _Grab.none;
  }

  void _dragCrop(Offset d, Rect fit) {
    if (_grab == _Grab.none) return;
    final dx = d.dx / fit.width;
    final dy = d.dy / fit.height;
    const minS = 0.04;
    var l = _crop.left, t = _crop.top, r = _crop.right, b = _crop.bottom;
    switch (_grab) {
      case _Grab.move:
        final w = r - l, h = b - t;
        l = (l + dx).clamp(0.0, 1.0 - w).toDouble();
        t = (t + dy).clamp(0.0, 1.0 - h).toDouble();
        r = l + w;
        b = t + h;
      case _Grab.tl:
        l = (l + dx).clamp(0.0, r - minS).toDouble();
        t = (t + dy).clamp(0.0, b - minS).toDouble();
      case _Grab.tr:
        r = (r + dx).clamp(l + minS, 1.0).toDouble();
        t = (t + dy).clamp(0.0, b - minS).toDouble();
      case _Grab.bl:
        l = (l + dx).clamp(0.0, r - minS).toDouble();
        b = (b + dy).clamp(t + minS, 1.0).toDouble();
      case _Grab.br:
        r = (r + dx).clamp(l + minS, 1.0).toDouble();
        b = (b + dy).clamp(t + minS, 1.0).toDouble();
      case _Grab.l:
        l = (l + dx).clamp(0.0, r - minS).toDouble();
      case _Grab.r:
        r = (r + dx).clamp(l + minS, 1.0).toDouble();
      case _Grab.t:
        t = (t + dy).clamp(0.0, b - minS).toDouble();
      case _Grab.b:
        b = (b + dy).clamp(t + minS, 1.0).toDouble();
      case _Grab.none:
        break;
    }
    setState(() => _crop = Rect.fromLTRB(l, t, r, b));
  }

  // ------------------------------------------------------------- background

  Future<void> _runBg() async {
    final b = _base;
    if (b == null) return;
    final my = ++_job;
    setState(() => _busy = true);
    try {
      final px = await compute(_bgJob, <Object?>[
        b.px,
        b.w,
        b.h,
        _key,
        _tol.round(),
        _feather.round(),
      ]);
      if (!mounted || my != _job) return;
      final res = RgbaImage(b.w, b.h, px);
      _preview = res;
      await _show(res);
    } catch (_) {
      if (mounted) _toast('تعذّرت إزالة الخلفية');
    } finally {
      if (mounted && my == _job) setState(() => _busy = false);
    }
  }

  void _pickColor(Offset local, Rect fit) {
    final b = _base;
    if (b == null || !fit.contains(local)) return;
    final x = ((local.dx - fit.left) / fit.width * b.w).floor().clamp(0, b.w - 1).toInt();
    final y = ((local.dy - fit.top) / fit.height * b.h).floor().clamp(0, b.h - 1).toInt();
    final i = (y * b.w + x) * 4;
    HapticFeedback.selectionClick();
    _key = (b.px[i] << 16) | (b.px[i + 1] << 8) | b.px[i + 2];
    _runBg();
  }

  void _commitBg() {
    final p = _preview;
    if (p == null) return;
    HapticFeedback.mediumImpact();
    setState(() => _commit(p));
  }

  void _selectTool(_Tool t) {
    if (t == _tool) return;
    HapticFeedback.selectionClick();
    setState(() {
      _tool = t;
      if (t != _Tool.bg && _preview != null) {
        _job++; // drop any running preview
        _preview = null;
        _show(_base!);
      }
    });
    if (t == _Tool.bg) _runBg();
  }

  // ------------------------------------------------------------------ misc

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
          content: Text(m), behavior: SnackBarBehavior.floating));
  }

  Future<void> _save() async {
    if (_base == null || _busy) return;
    setState(() => _busy = true);
    try {
      final done = trimTransparent(_current);
      final png = await StickerService.encodePng(done);
      final path = await StickerService.saveCustom(png);
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.of(context).pop(path);
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _toast('تعذّر حفظ الملصق');
      }
    }
  }

  Rect _fitRect(Size area) {
    final b = _base!;
    const pad = 14.0;
    final aw = area.width - pad * 2;
    final ah = area.height - pad * 2;
    final k = math.min(aw / b.w, ah / b.h);
    final w = b.w * k;
    final h = b.h * k;
    return Rect.fromLTWH((area.width - w) / 2, (area.height - h) / 2, w, h);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AyatColors.ink,
      appBar: AppBar(
        backgroundColor: AyatColors.surface,
        title: Text(widget.title, style: const TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'تراجع',
            onPressed: _undo.isEmpty ? null : _undoStep,
            icon: const Icon(Icons.undo),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton.icon(
              onPressed: (_base == null || _busy) ? null : _save,
              icon: const Icon(Icons.check, size: 18),
              label: const Text('حفظ'),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed
              ? const Center(child: Text('تعذّر فتح الصورة'))
              : Column(children: [
                  Expanded(child: _stage()),
                  _panel(),
                  _toolRow(),
                ]),
    );
  }

  Widget _stage() {
    return LayoutBuilder(builder: (context, c) {
      final area = Size(c.maxWidth, c.maxHeight);
      final fit = _fitRect(area);
      final shown = _shown;
      final screenCrop = Rect.fromLTRB(
        fit.left + _crop.left * fit.width,
        fit.top + _crop.top * fit.height,
        fit.left + _crop.right * fit.width,
        fit.top + _crop.bottom * fit.height,
      );
      final cropping = _tool == _Tool.crop;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          if (_tool == _Tool.bg) _pickColor(d.localPosition, fit);
        },
        onPanStart: cropping
            ? (d) => _grab = _pick(d.localPosition, screenCrop)
            : null,
        onPanUpdate: cropping ? (d) => _dragCrop(d.delta, fit) : null,
        onPanEnd: cropping ? (_) => _grab = _Grab.none : null,
        child: Stack(children: [
          Positioned.fromRect(
            rect: fit,
            child: CustomPaint(
              painter: const _CheckerPainter(),
              child: shown == null
                  ? const SizedBox.expand()
                  : RawImage(image: shown, fit: BoxFit.fill),
            ),
          ),
          if (cropping)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                    painter: _CropPainter(screenCrop, fit)),
              ),
            ),
          if (_busy)
            const Positioned(
              top: 12,
              right: 12,
              child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5)),
            ),
        ]),
      );
    });
  }

  Widget _panel() {
    Widget body;
    switch (_tool) {
      case _Tool.crop:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 8, children: [
            for (final (label, r) in <(String, double?)>[
              ('حر', null),
              ('1:1', 1.0),
              ('4:3', 4 / 3),
              ('3:4', 3 / 4),
              ('16:9', 16 / 9),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _ratio == r,
                onSelected: (_) => _setRatio(r),
              ),
          ]),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _applyCrop,
            icon: const Icon(Icons.crop, size: 18),
            label: const Text('تطبيق القص'),
          ),
        ]);
      case _Tool.bg:
        body = Column(mainAxisSize: MainAxisSize.min, children: [
          Text(
            _key == null
                ? 'اضغط على لون الخلفية في الصورة لتحديده — أو اتركه تلقائيًا'
                : 'اللون محدد — اضغط على مكان آخر لتغييره',
            style: const TextStyle(fontSize: 12, color: AyatColors.parchmentDim),
          ),
          Row(children: [
            const SizedBox(width: 64, child: Text('الحساسية', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                value: _tol,
                min: 2,
                max: 80,
                onChanged: (v) => setState(() => _tol = v),
                onChangeEnd: (_) => _runBg(),
              ),
            ),
          ]),
          Row(children: [
            const SizedBox(width: 64, child: Text('نعومة الحافة', style: TextStyle(fontSize: 12))),
            Expanded(
              child: Slider(
                value: _feather,
                min: 0,
                max: 6,
                divisions: 6,
                onChanged: (v) => setState(() => _feather = v),
                onChangeEnd: (_) => _runBg(),
              ),
            ),
          ]),
          FilledButton.icon(
            onPressed: _preview == null || _busy ? null : _commitBg,
            icon: const Icon(Icons.auto_fix_high, size: 18),
            label: const Text('تثبيت إزالة الخلفية'),
          ),
        ]);
      case _Tool.flip:
        body = Wrap(spacing: 10, runSpacing: 6, children: [
          OutlinedButton.icon(
            onPressed: () => setState(
                () => _commit(flipRgba(_base!, horizontal: true))),
            icon: const Icon(Icons.flip, size: 18),
            label: const Text('قلب أفقي'),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(
                () => _commit(flipRgba(_base!, vertical: true))),
            icon: const Icon(Icons.swap_vert, size: 18),
            label: const Text('قلب رأسي'),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() => _commit(rotate90(_base!))),
            icon: const Icon(Icons.rotate_90_degrees_cw, size: 18),
            label: const Text('تدوير'),
          ),
        ]);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      color: AyatColors.surface,
      child: body,
    );
  }

  Widget _toolRow() {
    Widget item(_Tool t, IconData icon, String label) {
      final on = _tool == t;
      final col = on ? AyatColors.goldBright : AyatColors.parchmentDim;
      return Expanded(
        child: InkWell(
          onTap: () => _selectTool(t),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, color: col, size: 22),
              const SizedBox(height: 3),
              Text(label,
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: col)),
            ]),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        color: AyatColors.ink,
        child: Row(children: [
          item(_Tool.crop, Icons.crop, 'قص'),
          item(_Tool.bg, Icons.blur_on, 'إزالة الخلفية'),
          item(_Tool.flip, Icons.flip, 'قلب وتدوير'),
        ]),
      ),
    );
  }
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final a = Paint()..color = const Color(0xFF2A2F2D);
    final b = Paint()..color = const Color(0xFF1C201F);
    const s = 12.0;
    for (var y = 0; y * s < size.height; y++) {
      for (var x = 0; x * s < size.width; x++) {
        canvas.drawRect(Rect.fromLTWH(x * s, y * s, s, s), (x + y).isEven ? a : b);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _CropPainter extends CustomPainter {
  final Rect crop;
  final Rect fit;
  _CropPainter(this.crop, this.fit);

  @override
  void paint(Canvas canvas, Size size) {
    // darken everything outside the crop
    final dim = Paint()..color = const Color(0x99000000);
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(fit)
        ..addRect(crop),
      dim,
    );
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = AyatColors.goldBright;
    canvas.drawRect(crop, line);
    final grid = Paint()
      ..strokeWidth = 1
      ..color = const Color(0x55FFFFFF);
    for (var k = 1; k < 3; k++) {
      final x = crop.left + crop.width * k / 3;
      final y = crop.top + crop.height * k / 3;
      canvas.drawLine(Offset(x, crop.top), Offset(x, crop.bottom), grid);
      canvas.drawLine(Offset(crop.left, y), Offset(crop.right, y), grid);
    }
    final dot = Paint()..color = AyatColors.goldBright;
    for (final p in [crop.topLeft, crop.topRight, crop.bottomLeft, crop.bottomRight]) {
      canvas.drawCircle(p, 7, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _CropPainter old) =>
      old.crop != crop || old.fit != fit;
}
