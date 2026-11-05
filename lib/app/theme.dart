import 'package:flutter/material.dart';

const _seed = Color(0xFF00897B);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    extensions: [
      brightness == Brightness.light ? MoneyColors.light : MoneyColors.dark,
    ],
  );
}

/// Цвета для сумм: доходы зелёные, расходы красные.
class MoneyColors extends ThemeExtension<MoneyColors> {
  const MoneyColors({
    required this.income,
    required this.expense,
    required this.neutral,
  });

  final Color income;
  final Color expense;
  final Color neutral;

  static const light = MoneyColors(
    income: Color(0xFF2E7D32),
    expense: Color(0xFFC62828),
    neutral: Color(0xFF546E7A),
  );

  static const dark = MoneyColors(
    income: Color(0xFF81C784),
    expense: Color(0xFFEF9A9A),
    neutral: Color(0xFFB0BEC5),
  );

  static MoneyColors of(BuildContext context) =>
      Theme.of(context).extension<MoneyColors>()!;

  @override
  MoneyColors copyWith({Color? income, Color? expense, Color? neutral}) =>
      MoneyColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        neutral: neutral ?? this.neutral,
      );

  @override
  MoneyColors lerp(MoneyColors? other, double t) {
    if (other == null) return this;
    return MoneyColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
    );
  }
}
