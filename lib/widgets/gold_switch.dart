import 'package:flutter/material.dart';
import '../theme/ayat_theme.dart';

/// The gold pill toggle from the HTML prototype's .switch element.
class GoldSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  const GoldSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      button: true,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 42,
          height: 24,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: value ? AyatColors.gold.withValues(alpha: 0.55) : AyatColors.surface3,
            border: Border.all(
                color: value ? AyatColors.goldBright : AyatColors.goldDim),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 180),
            // In an RTL app "start" is the right edge — off sits at start.
            alignment:
                value ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
            child: Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? AyatColors.goldBright : AyatColors.parchmentDim,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Labeled row with a trailing GoldSwitch — the .toggle-row pattern.
class ToggleRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const ToggleRow(
      {super.key, required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodyLarge)),
          GoldSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
