import 'package:flutter/material.dart';

/// Фирменный акцент приложения — фиолетовый.
const _seed = Color(0xFF6E5BFF);

/// Тёмная тема: почти чёрный фон и слегка приподнятые карточки.
ColorScheme _darkScheme() => ColorScheme.fromSeed(
  seedColor: _seed,
  brightness: Brightness.dark,
).copyWith(
  primary: const Color(0xFFA699FF),
  onPrimary: const Color(0xFF1B1060),
  primaryContainer: const Color(0xFF3A2FA0),
  onPrimaryContainer: const Color(0xFFE6E1FF),
  tertiary: const Color(0xFF5FE0B0),
  surface: const Color(0xFF0F1014),
  surfaceContainerLowest: const Color(0xFF0A0B0E),
  surfaceContainerLow: const Color(0xFF15161B),
  surfaceContainer: const Color(0xFF1A1B21),
  surfaceContainerHigh: const Color(0xFF212229),
  surfaceContainerHighest: const Color(0xFF292A32),
  outlineVariant: const Color(0xFF2C2D36),
);

ColorScheme _lightScheme() => ColorScheme.fromSeed(
  seedColor: _seed,
  brightness: Brightness.light,
).copyWith(
  primary: const Color(0xFF5643E0),
  tertiary: const Color(0xFF00916A),
  surface: const Color(0xFFF7F7FB),
);

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme() : _lightScheme();
  final radius = BorderRadius.circular(16);

  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    extensions: [dark ? MoneyColors.dark : MoneyColors.light],
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: scheme.onSurface,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primary.withValues(alpha: 0.18),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(64, 48),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(shape: const StadiumBorder(), minimumSize: const Size(64, 44)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.error),
      ),
    ),
    chipTheme: ChipThemeData(shape: const StadiumBorder(), side: BorderSide(color: scheme.outlineVariant)),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.primary.withValues(alpha: 0.2),
        selectedForegroundColor: scheme.primary,
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? scheme.onPrimary : null,
      ),
    ),
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
    income: Color(0xFF1E8E4E),
    expense: Color(0xFFD03B3B),
    neutral: Color(0xFF5C6370),
    chartIncome: Color(0xFF2A78D6),
    chartExpense: Color(0xFFEB6834),
  );

  static const dark = MoneyColors(
    income: Color(0xFF5FD68E),
    expense: Color(0xFFFF7A7A),
    neutral: Color(0xFFA8AEBA),
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
