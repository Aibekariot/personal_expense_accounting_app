import 'package:intl/intl.dart';

import '../data/db/app_database.dart';
import 'money.dart';

extension CurrencyFormat on Currency {
  /// `150050` → `1 500,50 сом` (с учётом знаков после запятой этой валюты).
  String format(int minor, {bool signed = false}) =>
      Money.format(minor, decimals: decimals, symbol: symbol, signed: signed);

  /// Примерная сумма без копеек — для прогнозов и средних: `≈ 1 234 сом`.
  String formatRounded(int minor) {
    final f = Money.factor(decimals);
    return format((minor / f).round() * f);
  }

  /// Подпись для списков: `USD — Доллар США`.
  String get label => '$code — $name';
}

/// Курс для отображения: `87,4566`, `0,011435`.
String formatRate(double rate) {
  final digits = rate >= 0.01 ? 4 : 8;
  return NumberFormat('#,##0.${'#' * digits}', 'ru').format(rate);
}

/// Разбирает введённый курс: `"87,45"` → `87.45`. null — если ввод некорректен.
double? parseRate(String input) {
  final s = input.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
  final v = double.tryParse(s);
  if (v == null || !v.isFinite || v <= 0) return null;
  return v;
}

String formatDate(DateTime d) => DateFormat('dd.MM.yyyy', 'ru').format(d);

String formatDateTime(DateTime d) =>
    DateFormat('dd.MM.yyyy, HH:mm', 'ru').format(d);

String capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

DateTime dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

/// Заголовок дня в истории: «Сегодня», «Вчера», «3 ноября, вторник».
String formatDayHeader(DateTime day, {DateTime? today}) {
  final t = dayOf(today ?? DateTime.now());
  final d = dayOf(day);
  if (d == t) return 'Сегодня';
  if (d == DateTime(t.year, t.month, t.day - 1)) return 'Вчера';
  final pattern = d.year == t.year ? 'd MMMM, EEEE' : 'd MMMM yyyy, EEEE';
  return DateFormat(pattern, 'ru').format(d);
}

/// Короткая дата: «3 ноя» (или «3 ноя 2025», если год не текущий).
String formatShortDate(DateTime d, {DateTime? today}) {
  final t = today ?? DateTime.now();
  return DateFormat(d.year == t.year ? 'd MMM' : 'd MMM yyyy', 'ru')
      .format(d)
      .replaceAll('.', '');
}

/// Месяц для подписей графиков: «ноя», «янв 26».
String formatMonthAxis(DateTime d, {bool withYear = false}) {
  final m = DateFormat('LLL', 'ru').format(d).replaceAll('.', '');
  return withYear ? '$m ${d.year % 100}' : m;
}

/// Процент: 0.1234 → «12%», 0.004 → «0,4%».
String formatPercent(double ratio) {
  final p = ratio * 100;
  if (p.abs() < 1 && p != 0) return '${NumberFormat('0.#', 'ru').format(p)}%';
  return '${p.round()}%';
}

/// Короткая сумма для осей графиков: «125 тыс», «1,2 млн».
String formatCompact(double value) {
  final abs = value.abs();
  final sign = value < 0 ? '−' : '';
  final f = NumberFormat('#,##0.#', 'ru');
  if (abs >= 1e6) return '$sign${f.format(abs / 1e6)} млн';
  if (abs >= 1e3) return '$sign${f.format(abs / 1e3)} тыс';
  return '$sign${f.format(abs)}';
}

/// «Октябрь 2026».
String formatMonthFull(DateTime d) => capitalize(DateFormat('LLLL yyyy', 'ru').format(d));
