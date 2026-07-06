// Small self-contained precise color picker (RGB sliders + live swatch +
// hex readout) — the native stand-in for the HTML's hidden <input
// type="color"> behind the swatch trigger.
import 'package:flutter/material.dart';
import '../theme/ayat_theme.dart';

Future<Color?> showAyatColorPicker(BuildContext context, Color initial) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _ColorPickerDialog(initial: initial),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  final Color initial;
  const _ColorPickerDialog({required this.initial});
  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late int r, g, b;

  @override
  void initState() {
    super.initState();
    r = (widget.initial.r * 255).round();
    g = (widget.initial.g * 255).round();
    b = (widget.initial.b * 255).round();
  }

  Color get color => Color.fromARGB(255, r, g, b);

  Widget _slider(String label, int value, ValueChanged<int> onChanged) {
    return Row(
      children: [
        SizedBox(width: 20, child: Text(label)),
        Expanded(
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 255,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        SizedBox(width: 34, child: Text('$value', textAlign: TextAlign.end)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hex = '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
    return AlertDialog(
      backgroundColor: AyatColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AyatColors.hairline),
      ),
      title: const Text('اختر اللون بدقة'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 46,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AyatColors.hairline),
            ),
            alignment: Alignment.center,
            child: Text(hex,
                style: TextStyle(
                    color: color.computeLuminance() > 0.5
                        ? Colors.black
                        : Colors.white)),
          ),
          const SizedBox(height: 10),
          _slider('R', r, (v) => setState(() => r = v)),
          _slider('G', g, (v) => setState(() => g = v)),
          _slider('B', b, (v) => setState(() => b = v)),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
            onPressed: () => Navigator.pop(context, color),
            child: const Text('اعتماد اللون')),
      ],
    );
  }
}
