import '../data/db/app_database.dart';
import 'ledger.dart';

/// Долг с вычисленным остатком.
class DebtView {
  const DebtView({
    required this.debt,
    required this.currency,
    required this.total,
    required this.repaid,
    required this.operations,
  });

  final Debt debt;
  final Currency currency;

  /// Всего было в долг: начальная сумма + все «дал/взял в долг».
  final int total;

  /// Сколько уже вернули.
  final int repaid;

  /// Операции по долгу, новые сверху.
  final List<OperationView> operations;

  /// Сколько ещё должны (или должен я).
  int get remaining => total - repaid;

  bool get theyOwe => debt.direction == DebtDirection.theyOwe;

  bool isOverdue(DateTime today) =>
      !debt.isClosed &&
      remaining > 0 &&
      debt.dueDate != null &&
      debt.dueDate!.isBefore(DateTime(today.year, today.month, today.day));
}

/// Сумма операции в валюте долга.
int debtAmountOf(Operation op) => op.debtAmount ?? op.amount;

DebtView debtView(Ledger ledger, Debt debt) {
  var total = debt.initialAmount;
  var repaid = 0;
  final ops = <OperationView>[];
  for (final v in ledger.operations) {
    if (v.op.debtId != debt.id) continue;
    ops.add(v);
    if (debtOperationIncreases(debt.direction, v.type)) {
      total += debtAmountOf(v.op);
    } else {
      repaid += debtAmountOf(v.op);
    }
  }
  return DebtView(
    debt: debt,
    currency: ledger.currency(debt.currencyCode),
    total: total,
    repaid: repaid,
    operations: ops,
  );
}

/// Итоги по долгам: по валютам, отдельно «мне должны» и «я должен».
class DebtTotals {
  const DebtTotals({required this.theyOwe, required this.iOwe});

  /// Код валюты → сумма открытых долгов.
  final Map<String, int> theyOwe;
  final Map<String, int> iOwe;

  factory DebtTotals.of(Iterable<DebtView> debts) {
    final theyOwe = <String, int>{};
    final iOwe = <String, int>{};
    for (final d in debts) {
      if (d.debt.isClosed || d.remaining <= 0) continue;
      final map = d.theyOwe ? theyOwe : iOwe;
      map[d.currency.code] = (map[d.currency.code] ?? 0) + d.remaining;
    }
    return DebtTotals(theyOwe: theyOwe, iOwe: iOwe);
  }
}

/// Изменение остатка долга от операции (+ — долг вырос, − — уменьшился).
int debtEffect(DebtDirection direction, OperationType type, int debtAmount) =>
    debtOperationIncreases(direction, type) ? debtAmount : -debtAmount;

/// Остаток долга после сохранения операции: старая версия операции
/// ([replacing]) убирается, новая ([type], [debtAmount]) добавляется.
/// Для удаления операции передайте [debtAmount] = 0.
int debtRemainingAfter(
  DebtView view, {
  Operation? replacing,
  required OperationType type,
  required int debtAmount,
}) {
  var remaining = view.remaining;
  if (replacing != null && replacing.debtId == view.debt.id) {
    remaining -= debtEffect(view.debt.direction, replacing.type, debtAmountOf(replacing));
  }
  return remaining + debtEffect(view.debt.direction, type, debtAmount);
}
