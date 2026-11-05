import '../data/db/app_database.dart';
import 'ledger.dart';
import 'period.dart';
import 'schedule.dart';
import 'stats.dart';

/// Состояние бюджета (месячного лимита) за месяц.
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.category,
    required this.currency,
    required this.spent,
    required this.unconverted,
    required this.forecast,
    required this.daysLeft,
    this.expected = 0,
  });

  final Budget budget;
  final CategoryEntity? category;

  /// Валюта бюджета.
  final Currency currency;

  /// Потрачено за месяц в валюте бюджета (с подкатегориями).
  final int spent;

  /// Расходы в валютах без курса — не вошли в [spent].
  final List<OperationView> unconverted;

  /// Прогноз на конец месяца при текущем темпе (только для текущего месяца).
  final int? forecast;

  /// Сколько дней месяца осталось, включая сегодня (только для текущего месяца).
  final int? daysLeft;

  /// Ожидается ещё по плановым операциям в этом месяце (в валюте бюджета).
  final int expected;

  /// План дохода (а не лимит расхода).
  bool get isIncome => category?.type == CategoryType.income;

  int get limit => budget.monthlyLimit;
  int get remaining => limit - spent;
  double get ratio => limit == 0 ? 0 : spent / limit;
  bool get isOver => spent > limit;

  /// Можно тратить в день до конца месяца, чтобы уложиться.
  int? get dailyAllowance =>
      daysLeft == null || daysLeft! <= 0 || remaining <= 0 ? null : remaining ~/ daysLeft!;

  /// Прогноз превышает лимит.
  bool get forecastOver => forecast != null && forecast! > limit;
}

/// Подходит ли операция под бюджет категории [categoryId] (с подкатегориями).
bool budgetCovers(int categoryId, OperationView v) =>
    v.op.categoryId == categoryId || v.category?.parentId == categoryId;

/// Состояние бюджета за месяц [month].
///
/// [excludeOperationId] и [extraSpent] — чтобы заранее узнать, каким станет
/// бюджет после сохранения расхода (старая версия операции не считается,
/// новая сумма добавляется).
BudgetProgress budgetProgress(
  Ledger ledger,
  Budget budget,
  Period month, {
  DateTime? now,
  int? excludeOperationId,
  int extraSpent = 0,
  List<PlannedOperation> plans = const [],
}) {
  final currency = ledger.currency(budget.currencyCode);
  final isIncome = ledger.categories[budget.categoryId]?.type == CategoryType.income;
  bool matchesType(OperationView v) => isIncome ? v.isIncome : v.isExpense;
  final unconverted = <OperationView>[];
  int spentIn(Iterable<OperationView> ops, {bool collect = false}) {
    var spent = 0;
    for (final v in ops) {
      if (!matchesType(v) || !budgetCovers(budget.categoryId, v)) continue;
      if (v.op.id == excludeOperationId) continue;
      final amount = ledger.rates.at(v.date).convert(v.op.amount, v.currency, currency);
      if (amount == null) {
        if (collect) unconverted.add(v);
      } else {
        spent += amount;
      }
    }
    return spent;
  }

  final spent = extraSpent + spentIn(ledger.inPeriod(month), collect: true);
  final today = now ?? DateTime.now();

  // Ещё не проведённые плановые операции этого месяца по категории.
  var expected = 0;
  final planType = isIncome ? OperationType.income : OperationType.expense;
  for (final o in upcoming(plans, from: month.start, to: month.lastDay)) {
    final p = o.plan;
    if (p.type != planType || p.categoryId == null) continue;
    final cat = ledger.categories[p.categoryId];
    if (p.categoryId != budget.categoryId && cat?.parentId != budget.categoryId) continue;
    final from = ledger.currency(ledger.accounts[p.accountId]?.currencyCode ?? ledger.base.code);
    expected += ledger.rates.latest.convert(p.amount, from, currency) ?? 0;
  }

  final isCurrent = month.contains(today);
  final elapsed = month.daysElapsed(today);
  return BudgetProgress(
    budget: budget,
    category: ledger.categories[budget.categoryId],
    currency: currency,
    spent: spent,
    unconverted: unconverted,
    forecast: isCurrent
        ? forecastMonth(
            spent: spent,
            days: month.days,
            elapsed: elapsed,
            previousMonths: previousMonthSums(ledger, month, spentIn),
          )
        : null,
    daysLeft: isCurrent ? month.days - elapsed + 1 : null,
    expected: expected,
  );
}

List<BudgetProgress> allBudgetProgress(
  Ledger ledger,
  List<Budget> budgets,
  Period month, {
  DateTime? now,
  List<PlannedOperation> plans = const [],
}) =>
    [for (final b in budgets) budgetProgress(ledger, b, month, now: now, plans: plans)]
      ..sort((a, b) => b.ratio.compareTo(a.ratio));

/// Бюджет, который затронет расход, — каким он станет после сохранения.
/// null — бюджета нет или пересчитать сумму нельзя (нет курса).
/// Если бюджеты есть и у подкатегории, и у категории, берётся самый заполненный.
BudgetProgress? budgetAfterExpense(
  Ledger ledger,
  List<Budget> budgets, {
  required int categoryId,
  required DateTime date,
  required int amount,
  required Currency currency,
  int? replacingOperationId,
  DateTime? now,
}) {
  final category = ledger.categories[categoryId];
  BudgetProgress? worst;
  for (final b in budgets) {
    if (b.categoryId != categoryId && b.categoryId != category?.parentId) continue;
    if (ledger.categories[b.categoryId]?.type != CategoryType.expense) continue;
    final extra = ledger.rates.at(date).convert(amount, currency, ledger.currency(b.currencyCode));
    if (extra == null) continue;
    final p = budgetProgress(
      ledger, b, Period.month(date),
      now: now, excludeOperationId: replacingOperationId, extraSpent: extra,
    );
    if (worst == null || p.ratio > worst.ratio) worst = p;
  }
  return worst;
}
