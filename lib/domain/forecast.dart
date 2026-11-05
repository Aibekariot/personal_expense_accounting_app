import '../data/db/app_database.dart';
import 'ledger.dart';
import 'schedule.dart';

/// Капитал на день.
class ForecastPoint {
  const ForecastPoint(this.day, this.capital);

  final DateTime day;
  final int capital;
}

/// Прогноз капитала по плановым операциям.
class BalanceForecast {
  const BalanceForecast({
    required this.points,
    required this.occurrences,
    required this.incomplete,
  });

  /// По дню на точку: сегодня, завтра, …
  final List<ForecastPoint> points;

  /// Учтённые повторения планов (просроченные — тоже, они считаются сегодняшними).
  final List<Occurrence> occurrences;

  /// Часть планов не учтена: нет курса валюты.
  final bool incomplete;

  ForecastPoint get lowest => points.reduce((a, b) => b.capital < a.capital ? b : a);
  ForecastPoint get last => points.last;
}

/// Как повторение плана меняет общий капитал (в основной валюте, по текущему
/// курсу). Учитываются только активные счета «в капитале». null — нет курса.
int? capitalEffect(Ledger ledger, PlannedOperation p) {
  bool included(int? id) {
    final a = ledger.accounts[id];
    return a != null && a.includeInTotal && !a.isArchived;
  }

  int? toBase(int amount, int accountId) => ledger.rates.latest.convert(
        amount,
        ledger.currency(ledger.accounts[accountId]!.currencyCode),
        ledger.base,
      );

  var effect = 0;
  if (included(p.accountId)) {
    final v = toBase(p.amount, p.accountId);
    if (v == null) return null;
    effect += p.type == OperationType.income ? v : -v;
  }
  if (p.type == OperationType.transfer && included(p.toAccountId)) {
    final v = toBase(p.toAmount ?? 0, p.toAccountId!);
    if (v == null) return null;
    effect += v;
  }
  return effect;
}

/// Прогноз капитала на [days] дней вперёд от [today], начиная с [startCapital].
BalanceForecast balanceForecast({
  required Ledger ledger,
  required List<PlannedOperation> plans,
  required int startCapital,
  required DateTime today,
  int days = 30,
}) {
  final start = DateTime(today.year, today.month, today.day);
  final end = DateTime(start.year, start.month, start.day + days);
  final occurrences = upcoming(plans, to: end);

  final byDay = <int, int>{};
  var incomplete = false;
  for (final o in occurrences) {
    final effect = capitalEffect(ledger, o.plan);
    if (effect == null) {
      incomplete = true;
      continue;
    }
    final offset = o.date.isBefore(start)
        ? 0
        : DateTime.utc(o.date.year, o.date.month, o.date.day)
            .difference(DateTime.utc(start.year, start.month, start.day))
            .inDays;
    byDay[offset] = (byDay[offset] ?? 0) + effect;
  }

  var capital = startCapital;
  final points = <ForecastPoint>[];
  for (var i = 0; i <= days; i++) {
    capital += byDay[i] ?? 0;
    points.add(ForecastPoint(DateTime(start.year, start.month, start.day + i), capital));
  }
  return BalanceForecast(points: points, occurrences: occurrences, incomplete: incomplete);
}
