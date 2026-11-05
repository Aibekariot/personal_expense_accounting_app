import 'package:flutter/material.dart';

/// Цвета для счетов и категорий.
const pickerColors = [
  0xFF43A047, 0xFF1E88E5, 0xFFFB8C00, 0xFF8E24AA,
  0xFFE53935, 0xFF00897B, 0xFF546E7A, 0xFFD81B60,
  0xFF3949AB, 0xFF6D4C41, 0xFFFDD835, 0xFF00ACC1,
];

class ColorPicker extends StatelessWidget {
  const ColorPicker({super.key, required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final c in pickerColors)
          InkWell(
            onTap: () => onChanged(c),
            customBorder: const CircleBorder(),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Color(c),
              child: c == selected
                  ? const Icon(Icons.check, color: Colors.white)
                  : null,
            ),
          ),
      ],
    );
  }
}
