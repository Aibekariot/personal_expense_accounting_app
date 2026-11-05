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
///
/// Для графиков — отдельная пара синий/оранжевый: красный с зелёным
/// плохо различают люди с дальтонизмом (пара проверена валидатором палитр).
class MoneyColors extends ThemeExtension<MoneyColors> {
  const MoneyColors({
    required this.income,
    required this.expense,
    required this.neutral,
    required this.chartIncome,
    required this.chartExpense,
  });

  final Color income;
  final Color expense;
  final Color neutral;
  final Color chartIncome;
  final Color chartExpense;

  static const light = MoneyColors(
    income: Color(0xFF2E7D32),
    expense: Color(0xFFC62828),
    neutral: Color(0xFF546E7A),
    chartIncome: Color(0xFF2A78D6),
    chartExpense: Color(0xFFEB6834),
  );

  static const dark = MoneyColors(
    income: Color(0xFF81C784),
    expense: Color(0xFFEF9A9A),
    neutral: Color(0xFFB0BEC5),
    chartIncome: Color(0xFF3987E5),
    chartExpense: Color(0xFFD95926),
  );

  static MoneyColors of(BuildContext context) =>
      Theme.of(context).extension<MoneyColors>()!;

  @override
  MoneyColors copyWith({
    Color? income,
    Color? expense,
    Color? neutral,
    Color? chartIncome,
    Color? chartExpense,
  }) =>
      MoneyColors(
        income: income ?? this.income,
        expense: expense ?? this.expense,
        neutral: neutral ?? this.neutral,
        chartIncome: chartIncome ?? this.chartIncome,
        chartExpense: chartExpense ?? this.chartExpense,
      );

  @override
  MoneyColors lerp(MoneyColors? other, double t) {
    if (other == null) return this;
    return MoneyColors(
      income: Color.lerp(income, other.income, t)!,
      expense: Color.lerp(expense, other.expense, t)!,
      neutral: Color.lerp(neutral, other.neutral, t)!,
      chartIncome: Color.lerp(chartIncome, other.chartIncome, t)!,
      chartExpense: Color.lerp(chartExpense, other.chartExpense, t)!,
    );
  }
}
