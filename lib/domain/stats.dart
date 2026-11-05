import '../data/db/app_database.dart';
import 'ledger.dart';
import 'period.dart';

/// Итоги за период в основной валюте. Переводы, корректировки и долги
/// не считаются ни доходом, ни расходом.
class PeriodTotals {
  const PeriodTotals({
    required this.income,
    required this.expense,
    required this.unconverted,
  });

  factory PeriodTotals.of(Iterable<OperationView> ops) {
    var income = 0, expense = 0;
    final unconverted = <OperationView>[];
    for (final v in ops) {
      if (!v.isIncome && !v.isExpense) continue;
      final amount = v.baseAmount;
      if (amount == null) {
        unconverted.add(v);
      } else if (v.isIncome) {
        income += amount;
      } else {
        expense += amount;
      }
    }
    return PeriodTotals(income: income, expense: expense, unconverted: unconverted);
  }

  final int income;
  final int expense;

  /// Операции в валютах без курса — не вошли в суммы.
  final List<OperationView> unconverted;

  /// Сколько осталось (доходы − расходы).
  int get net => income - expense;

  /// Доля отложенного от дохода (null — если доходов не было).
  double? get savingsRate => income > 0 ? net / income : null;
}

/// Прогноз суммы за месяц.
///
/// Если есть прошлые месяцы — к уже потраченному добавляется средний расход
/// прошлых месяцев за оставшиеся дни. Так крупный платёж в начале месяца
/// (аренда) не «умножается» на весь месяц. Если истории нет — простой темп
/// (потрачено / прошло дней × дней в месяце), но не раньше 7-го дня.
int? forecastMonth({
  required int spent,
  required int days,
  required int elapsed,
  List<int> previousMonths = const [],
}) {
  if (elapsed <= 0 || elapsed >= days) return null;
  if (previousMonths.isNotEmpty) {
    final avg = previousMonths.fold(0, (s, e) => s + e) / previousMonths.length;
    return spent + (avg * (days - elapsed) / days).round();
  }
  if (elapsed < 7) return null;
  return (spent * days / elapsed).round();
}

/// Суммы за [count] прошлых месяцев перед [month] — только с начала учёта
/// (с месяца первой операции).
List<int> previousMonthSums(
  Ledger ledger,
  Period month,
  int Function(Iterable<OperationView> ops) sum, {
  int count = 3,
}) {
  if (ledger.operations.isEmpty) return const [];
  final first = ledger.operations.map((v) => v.date).reduce((a, b) => a.isBefore(b) ? a : b);
  final firstMonth = DateTime(first.year, first.month);
  final result = <int>[];
  var p = month.previous;
  for (var i = 0; i < count && p != null && !p.start.isBefore(firstMonth); i++) {
    result.add(sum(ledger.inPeriod(p)));
    p = p.previous;
  }
  return result;
}

/// Период для сравнения: прошлый такой же период. Если текущий ещё идёт —
/// только столько же первых дней (5 дней ноября сравниваются с 1–5 октября,
/// а не со всем октябрём).
Period? comparisonPeriod(Period period, DateTime now) {
  final prev = period.previous;
  if (prev == null) return null;
  if (!period.contains(now)) return prev;
  final elapsed = period.daysElapsed(now);
  return Period.custom(
    prev.start,
    DateTime(prev.start.year, prev.start.month, prev.start.day + elapsed - 1),
  );
}

/// Доля категории в расходах (или доходах) за период.
class CategorySlice {
  const CategorySlice({
    required this.category,
    required this.amount,
    required this.share,
    required this.previousAmount,
    required this.count,
    required this.isParentItself,
  });

  /// null — операции без категории.
  final CategoryEntity? category;
  final int amount;

  /// Доля от итога, 0..1.
  final double share;

  /// Сумма за предыдущий такой же период (null — сравнивать не с чем).
  final int? previousAmount;

  /// Число операций.
  final int count;

  /// Для разбивки по подкатегориям: операции, записанные прямо
  /// в основную категорию, без подкатегории.
  final bool isParentItself;

  /// Изменение к прошлому периоду: 0.25 = +25%. null — не с чем сравнить.
  double? get change =>
      previousAmount == null || previousAmount == 0 ? null : amount / previousAmount! - 1;
}

/// Разбивка расходов или доходов по категориям.
///
/// Без [parentId] — по основным категориям (подкатегории входят в родителя).
/// С [parentId] — по подкатегориям этой категории.
List<CategorySlice> categoryBreakdown(
  Ledger ledger,
  Period period, {
  required CategoryType type,
  int? parentId,
  DateTime? now,
}) {
  final opType = type == CategoryType.expense ? OperationType.expense : OperationType.income;

  // Ключ группы: id категории; -1 — без категории.
  int? keyOf(OperationView v) {
    if (parentId == null) return v.topCategory?.id ?? -1;
    if (v.topCategory?.id != parentId) return null;
    return v.category?.id ?? -1;
  }

  Map<int, (int, int)> sum(Period p) {
    final result = <int, (int, int)>{};
    for (final v in ledger.inPeriod(p)) {
      if (v.type != opType || v.baseAmount == null) continue;
      final key = keyOf(v);
      if (key == null) continue;
      final (amount, count) = result[key] ?? (0, 0);
      result[key] = (amount + v.baseAmount!, count + 1);
    }
    return result;
  }

  final current = sum(period);
  final prevPeriod = comparisonPeriod(period, now ?? DateTime.now());
  final previous = prevPeriod == null ? null : sum(prevPeriod);
  final total = current.values.fold(0, (s, e) => s + e.$1);

  final slices = [
    for (final e in current.entries)
      CategorySlice(
        category: ledger.categories[e.key],
        amount: e.value.$1,
        share: total == 0 ? 0 : e.value.$1 / total,
        previousAmount: previous == null ? null : (previous[e.key]?.$1 ?? 0),
        count: e.value.$2,
        isParentItself: parentId != null && e.key == parentId,
      ),
  ]..sort((a, b) => b.amount.compareTo(a.amount));
  return slices;
}

/// Доходы и расходы за месяц.
class MonthPoint {
  const MonthPoint(this.month, this.income, this.expense);

  final DateTime month;
  final int income;
  final int expense;
}

/// Доходы и расходы по месяцам: [count] месяцев, последний — [lastMonth].
List<MonthPoint> monthlyTotals(Ledger ledger, DateTime lastMonth, int count) {
  return [
    for (var i = count - 1; i >= 0; i--)
      () {
        final p = Period.month(DateTime(lastMonth.year, lastMonth.month - i));
        final t = PeriodTotals.of(ledger.inPeriod(p));
        return MonthPoint(p.start, t.income, t.expense);
      }(),
  ];
}

/// Капитал на конец месяца.
class CapitalPoint {
  const CapitalPoint(this.month, this.amount, {this.complete = true});

  final DateTime month;
  final int amount;

  /// false — для части счетов не было курса, они не вошли в сумму.
  final bool complete;
}

/// Капитал (как в карточке «Общий капитал») на конец каждого месяца:
/// [count] месяцев, последний — [lastMonth]. Пересчёт — по курсу на конец месяца.
/// Счёт учитывается с даты начала учёта (создание счёта или первая операция).
List<CapitalPoint> capitalHistory(
  Ledger ledger,
  DateTime lastMonth,
  int count, {
  DateTime? now,
}) {
  final accounts =
      ledger.accounts.values.where((a) => a.includeInTotal && !a.isArchived).toList();
  if (accounts.isEmpty) return const [];
  final ids = {for (final a in accounts) a.id};

  // Когда начался учёт по каждому счёту.
  final start = {for (final a in accounts) a.id: a.createdAt};
  for (final v in ledger.operations) {
    for (final id in [v.op.accountId, v.op.toAccountId]) {
      if (id != null && ids.contains(id) && v.date.isBefore(start[id]!)) {
        start[id] = v.date;
      }
    }
  }

  final ops = [...ledger.operations]..sort((a, b) => a.date.compareTo(b.date));
  final delta = {for (final id in ids) id: 0};
  var next = 0;
  final today = now ?? DateTime.now();
  final result = <CapitalPoint>[];

  for (var i = count - 1; i >= 0; i--) {
    final month = DateTime(lastMonth.year, lastMonth.month - i);
    var end = DateTime(month.year, month.month + 1);
    if (month.isAfter(today)) break;
    // Для текущего месяца — на сегодня.
    final todayEnd = DateTime(today.year, today.month, today.day + 1);
    if (end.isAfter(todayEnd)) end = todayEnd;

    while (next < ops.length && ops[next].date.isBefore(end)) {
      final op = ops[next++].op;
      for (final id in [op.accountId, op.toAccountId]) {
        if (id != null && ids.contains(id)) {
          delta[id] = delta[id]! + accountDelta(op, id);
        }
      }
    }

    final rates = ledger.rates.at(DateTime(end.year, end.month, end.day - 1));
    var total = 0;
    var complete = true;
    for (final a in accounts) {
      if (!start[a.id]!.isBefore(end)) continue;
      final balance = a.initialBalance + delta[a.id]!;
      final converted = rates.convert(balance, ledger.currency(a.currencyCode), ledger.base);
      if (converted == null) {
        complete = false;
      } else {
        total += converted;
      }
    }
    result.add(CapitalPoint(month, total, complete: complete));
  }
  return result;
}

/// Крупнейшие расходы за период.
List<OperationView> topExpenses(Ledger ledger, Period period, {int limit = 5}) {
  final list = ledger
      .inPeriod(period)
      .where((v) => v.isExpense && v.baseAmount != null)
      .toList()
    ..sort((a, b) => b.baseAmount!.compareTo(a.baseAmount!));
  return list.take(limit).toList();
}
