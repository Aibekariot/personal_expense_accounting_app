import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Экранная клавиатура-калькулятор для ввода суммы.
///
/// Нижняя широкая кнопка — «=», если в выражении есть действие,
/// иначе — [actionLabel] (обычно «Сохранить»).
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({
    super.key,
    required this.onKey,
    required this.onAction,
    required this.onHide,
    required this.showEquals,
    this.actionLabel = 'Сохранить',
    this.allowComma = true,
    this.enabled = true,
  });

  /// Нажатие: цифра, `,`, `+ − × ÷`, `⌫`, `C`, `=`.
  final ValueChanged<String> onKey;
  final VoidCallback onAction;
  final VoidCallback onHide;
  final bool showEquals;
  final String actionLabel;
  final bool allowComma;
  final bool enabled;

  static const _rows = [
    ['7', '8', '9', '÷'],
    ['4', '5', '6', '×'],
    ['1', '2', '3', '−'],
    [',', '0', '⌫', '+'],
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final row in _rows)
                Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        child: _Key(
                          label: key,
                          isOperator: '÷×−+'.contains(key),
                          enabled: enabled && (key != ',' || allowComma),
                          onTap: () => _press(key),
                          onLongPress: key == '⌫' ? () => _press('C') : null,
                        ),
                      ),
                  ],
                ),
              Padding(
                padding: const EdgeInsets.all(3),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: 'Скрыть клавиатуру',
                      onPressed: onHide,
                      icon: const Icon(Icons.keyboard_hide_outlined),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: FilledButton(
                        onPressed: enabled ? (showEquals ? () => _press('=') : onAction) : null,
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: Text(
                          showEquals ? '=' : actionLabel,
                          style: TextStyle(fontSize: showEquals ? 24 : 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _press(String key) {
    HapticFeedback.selectionClick();
    onKey(key);
  }
}

class _Key extends StatelessWidget {
  const _Key({
    required this.label,
    required this.isOperator,
    required this.enabled,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final bool isOperator;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = isOperator ? scheme.primary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: isOperator ? scheme.primaryContainer.withValues(alpha: 0.5) : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          onLongPress: enabled ? onLongPress : null,
          child: SizedBox(
            height: 50,
            child: Center(
              child: label == '⌫'
                  ? Icon(Icons.backspace_outlined, color: color, size: 22)
                  : Text(
                      label,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: enabled ? color : color.withValues(alpha: 0.3),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
