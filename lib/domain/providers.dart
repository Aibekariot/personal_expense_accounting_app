import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/async_utils.dart';
import '../data/providers.dart';
import 'debts.dart';
import 'ledger.dart';
import 'operation_filter.dart';
import 'period.dart';

/// Все данные для истории, статистики, бюджетов и долгов.
/// Пересчитывается сам при любом изменении в базе.
final ledgerProvider = Provider<AsyncValue<Ledger>>((ref) {
  final operations = ref.watch(operationsProvider);
  final accounts = ref.watch(accountsProvider);
  final currencies = ref.watch(currenciesProvider);
  final categories = ref.watch(categoriesProvider);
  final debts = ref.watch(debtsProvider);
  final base = ref.watch(baseCurrencyCodeProvider);
  final rates = ref.watch(rateHistoryProvider);
  return combineAsync(
    [operations, accounts, currencies, categories, debts, base, rates],
    () => Ledger(
      operations: operations.requireValue,
      accounts: accounts.requireValue,
      currencies: currencies.requireValue,
      categories: categories.requireValue,
      debts: debts.requireValue,
      baseCode: base.requireValue,
      rates: rates.requireValue,
    ),
  );
});

/// Выбранный период (отдельно для истории, статистики и бюджетов).
class PeriodNotifier extends Notifier<Period> {
  @override
  Period build() => Period.month(DateTime.now());

  void select(Period p) => state = p;

  void previous() => state = state.previous ?? state;

  void next() => state = state.next ?? state;
}

final operationsPeriodProvider =
    NotifierProvider<PeriodNotifier, Period>(PeriodNotifier.new);

final statsPeriodProvider =
    NotifierProvider<PeriodNotifier, Period>(PeriodNotifier.new);

final budgetsMonthProvider =
    NotifierProvider<PeriodNotifier, Period>(PeriodNotifier.new);

class OperationFilterNotifier extends Notifier<OperationFilter> {
  @override
  OperationFilter build() => const OperationFilter();

  void set(OperationFilter f) => state = f;

  void setQuery(String q) => state = state.copyWith(query: q);

  void reset() => state = OperationFilter(query: state.query);
}

final operationFilterProvider =
    NotifierProvider<OperationFilterNotifier, OperationFilter>(
  OperationFilterNotifier.new,
);

/// Все долги с остатками.
final debtViewsProvider = Provider<AsyncValue<List<DebtView>>>((ref) {
  final ledger = ref.watch(ledgerProvider);
  return ledger.whenData(
    (l) => [for (final d in l.debts.values) debtView(l, d)],
  );
});
