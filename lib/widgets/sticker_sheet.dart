// PATCH_S206_STICKERS
// The sticker picker: built-in library + the user's own stickers, with a
// "new sticker from a picture" door into the editor.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/sticker_service.dart';
import '../theme/ayat_theme.dart';
import 'sticker_editor.dart';

Future<void> showStickerSheet(
  BuildContext context, {
  required void Function(String path) onPick,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AyatColors.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    builder: (_) => _StickerSheet(onPick: onPick),
  );
}

class _StickerSheet extends StatefulWidget {
  final void Function(String path) onPick;
  const _StickerSheet({required this.onPick});

  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  int _tab = 0; // 0 library, 1 mine
  List<String> _mine = const [];
  bool _loadedMine = false;

  @override
  void initState() {
    super.initState();
    _refreshMine();
  }

  Future<void> _refreshMine() async {
    final l = await StickerService.customPaths();
    if (!mounted) return;
    setState(() {
      _mine = l;
      _loadedMine = true;
    });
  }

  void _choose(String path) {
    HapticFeedback.selectionClick();
    Navigator.of(context).pop();
    widget.onPick(path);
  }

  Future<void> _create() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = res?.files.single.path;
    if (path == null || !mounted) return;
    final saved = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => StickerEditorPage(sourcePath: path)),
    );
    if (!mounted) return;
    await _refreshMine();
    if (saved != null && mounted) _choose(saved);
  }

  Future<void> _confirmDelete(String path) async {
    HapticFeedback.mediumImpact();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('حذف الملصق؟'),
        content: const Text('سيُحذف من «ملصقاتي». ما أُضيف منه إلى مقاطعك يبقى كما هو.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف')),
        ],
      ),
    );
    if (ok != true) return;
    await StickerService.deleteCustom(path);
    _refreshMine();
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;
    return SafeArea(
      child: SizedBox(
        height: h * 0.72,
        child: Column(children: [
          const SizedBox(height: 10),
          Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                  color: AyatColors.hairline,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            ChoiceChip(
              label: const Text('المكتبة'),
              selected: _tab == 0,
              onSelected: (_) => setState(() => _tab = 0),
            ),
            const SizedBox(width: 10),
            ChoiceChip(
              label: Text(_mine.isEmpty ? 'ملصقاتي' : 'ملصقاتي (${_mine.length})'),
              selected: _tab == 1,
              onSelected: (_) => setState(() => _tab = 1),
            ),
          ]),
          const SizedBox(height: 8),
          Expanded(child: _tab == 0 ? _library() : _mineGrid()),
        ]),
      ),
    );
  }

  Widget _cell({required Widget child, VoidCallback? onTap, VoidCallback? onLong}) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onLong,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AyatColors.surface2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AyatColors.hairline),
        ),
        child: Center(child: child),
      ),
    );
  }

  static const _grid = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 4,
    mainAxisSpacing: 10,
    crossAxisSpacing: 10,
  );

  Widget _library() {
    final items = StickerService.builtins;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      gridDelegate: _grid,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final it = items[i];
        return FutureBuilder<String?>(
          future: StickerService.builtinPath(it.key),
          builder: (context, snap) {
            final p = snap.data;
            return _cell(
              onTap: p == null ? null : () => _choose(p),
              child: p == null
                  ? (snap.connectionState == ConnectionState.done
                      ? const Icon(Icons.broken_image_outlined, size: 20)
                      : const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2)))
                  : Tooltip(
                      message: it.label,
                      child: Image.file(File(p),
                          fit: BoxFit.contain, gaplessPlayback: true),
                    ),
            );
          },
        );
      },
    );
  }

  Widget _mineGrid() {
    if (!_loadedMine) {
      return const Center(child: CircularProgressIndicator());
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 18),
      gridDelegate: _grid,
      itemCount: _mine.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) {
          return _cell(
            onTap: _create,
            child: Column(mainAxisSize: MainAxisSize.min, children: const [
              Icon(Icons.add_photo_alternate_outlined,
                  color: AyatColors.goldBright, size: 26),
              SizedBox(height: 4),
              Text('ملصق جديد',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10.5, color: AyatColors.goldBright)),
            ]),
          );
        }
        final p = _mine[i - 1];
        return _cell(
          onTap: () => _choose(p),
          onLong: () => _confirmDelete(p),
          child: Image.file(File(p), fit: BoxFit.contain, gaplessPlayback: true),
        );
      },
    );
  }
}
