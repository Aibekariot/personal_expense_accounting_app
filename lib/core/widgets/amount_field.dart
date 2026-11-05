import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../money.dart';

/// Поле ввода суммы. Принимает запятую и точку, проверяет число знаков
/// после запятой для валюты. Значение читается через [AmountField.valueOf].
class AmountField extends StatelessWidget {
  const AmountField({
    super.key,
    required this.controller,
    required this.decimals,
    this.symbol,
    this.label = 'Сумма',
    this.helperText,
    this.allowNegative = false,
    this.emptyIsZero = false,
    this.autofocus = false,
    this.enabled = true,
    this.onChanged,
    this.textStyle,
  });

  final TextEditingController controller;
  final int decimals;
  final String? symbol;
  final String label;
  final String? helperText;

  /// Разрешить минус (показывается кнопка ±).
  final bool allowNegative;

  /// Пустое поле = 0 (иначе пустое поле — ошибка).
  final bool emptyIsZero;
  final bool autofocus;
  final bool enabled;

  /// Вызывается только при вводе пользователем (не при смене текста из кода).
  final ValueChanged<String>? onChanged;
  final TextStyle? textStyle;

  /// Сумма из текста поля в минимальных единицах или null, если ввод неверен.
  static int? valueOf(
    TextEditingController controller, {
    required int decimals,
    bool emptyIsZero = false,
  }) {
    if (controller.text.trim().isEmpty) return emptyIsZero ? 0 : null;
    return Money.parse(controller.text, decimals: decimals);
  }

  void _toggleSign() {
    final text = controller.text.trimLeft();
    final next = text.startsWith('-') || text.startsWith('−')
        ? text.substring(1)
        : '-$text';
    controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    onChanged?.call(next);
  }

  String? _validate(String? text) {
    final t = text ?? '';
    if (t.trim().isEmpty) return emptyIsZero ? null : 'Введите сумму';
    final v = Money.parse(t, decimals: decimals);
    if (v == null) {
      return decimals == 0
          ? 'Введите целое число, например 1500'
          : 'Неверная сумма (не больше $decimals знаков после запятой)';
    }
    if (!allowNegative && v < 0) return 'Сумма не может быть отрицательной';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      onChanged: onChanged,
      style: textStyle,
      keyboardType: TextInputType.numberWithOptions(
        decimal: decimals > 0,
        signed: allowNegative,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          RegExp(allowNegative ? r'[0-9.,\s\-−]' : r'[0-9.,\s]'),
        ),
      ],
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        helperMaxLines: 3,
        suffixText: symbol,
        prefixIcon: allowNegative
            ? IconButton(
                icon: const Icon(Icons.exposure),
                tooltip: 'Плюс / минус',
                onPressed: enabled ? _toggleSign : null,
              )
            : null,
      ),
      validator: _validate,
    );
  }
}
