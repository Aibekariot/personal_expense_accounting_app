import 'package:flutter/material.dart';

/// Получатель с подсказками из истории (частые — первыми).
class PayeeField extends StatelessWidget {
  const PayeeField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.suggestions,
    required this.onChanged,
    required this.onSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            counterText: '',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.storefront_outlined),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
          onChanged: onChanged,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 6,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    label: Text(s),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onSelected(s),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
