import '../core/money.dart';
import '../data/db/app_database.dart';
import '../data/rates/rate_history.dart';
import 'period.dart';

/// Подпись операции по долгу с точки зрения пользователя.
String debtOperationLabel(DebtDirection direction, OperationType type) =>
    switch ((direction, type)) {
      (DebtDirection.theyOwe, OperationType.debtOut) => 'Дал в долг',
      (DebtDirection.theyOwe, _) => 'Мне вернули долг',
      (DebtDirection.iOwe, OperationType.debtIn) => 'Взял в долг',
      (DebtDirection.iOwe, _) => 'Вернул долг',
    };

/// Увеличивает ли операция долг (а не гасит его).
bool debtOperationIncreases(DebtDirection direction, OperationType type) =>
    (direction == DebtDirection.theyOwe && type == OperationType.debtOut) ||
    (direction == DebtDirection.iOwe && type == OperationType.debtIn);

/// На сколько операция меняет баланс счёта [accountId] (в его валюте).
/// Те же правила, что в SQL-запросе балансов в AccountRepository.
int accountDelta(Operation op, int accountId) {
  var delta = 0;
  if (op.accountId == accountId) {
    delta += switch (op.type) {
      OperationType.income || OperationType.adjustment || OperationType.debtIn => op.amount,
      OperationType.expense || OperationType.transfer || OperationType.debtOut => -op.amount,
    };
  }
  if (op.type == OperationType.transfer && op.toAccountId == accountId) {
    delta += op.toAmount ?? 0;
  }
  return delta;
}

/// Операция вместе со всем, что нужно для показа: счёт, валюта, категория.
class OperationView {
  OperationView._({
    required this.op,
    required this.account,
    required this.currency,
    required this.toAccount,
    required this.toCurrency,
    required this.category,
    required this.topCategory,
    required this.debt,
    required this.baseAmount,
  });

  final Operation op;
  final Account? account;
  final Currency currency;
  final Account? toAccount;
  final Currency? toCurrency;

  /// Категория операции (может быть подкатегорией).
  final CategoryEntity? category;

  /// Основная категория (для подкатегории — её родитель).
  final CategoryEntity? topCategory;
  final Debt? debt;

  /// Для расходов и доходов — сумма в основной валюте по курсу на дату
  /// операции. null — для остальных типов или если курса нет.
  final int? baseAmount;

  OperationType get type => op.type;
  DateTime get date => op.date;
  bool get isExpense => op.type == OperationType.expense;
  bool get isIncome => op.type == OperationType.income;
  bool get isDebt => op.type == OperationType.debtIn || op.type == OperationType.debtOut;

  /// Главная подпись: категория, «Перевод», «Дал в долг» и т.п.
  String get title => switch (op.type) {
    OperationType.expense || OperationType.income => category?.name ?? 'Без категории',
    OperationType.transfer =>
      currency.code == toCurrency?.code ? 'Перевод' : 'Обмен валюты',
    OperationType.adjustment => 'Корректировка баланса',
    OperationType.debtOut || OperationType.debtIn => debt == null
        ? 'Долг'
        : '${debtOperationLabel(debt!.direction, op.type)}: ${debt!.personName}',
  };

  /// Вторая строка: родительская категория, счёт(а).
  String get details {
    final accountName = account?.name ?? 'Удалённый счёт';
    return switch (op.type) {
      OperationType.transfer => '$accountName → ${toAccount?.name ?? 'Удалённый счёт'}',
      OperationType.expense || OperationType.income =>
        category?.parentId != null && topCategory != null
            ? '${topCategory!.name} · $accountName'
            : accountName,
      _ => accountName,
    };
  }

  /// Строка для поиска: всё, что пользователь может вспомнить об операции.
  late final String searchText = [
    title,
    details,
    op.note,
    debt?.personName ?? '',
    Money.toEditable(op.amount.abs(), decimals: currency.decimals),
    if (op.toAmount != null)
      Money.toEditable(op.toAmount!, decimals: toCurrency?.decimals ?? 2),
  ].join(' ').toLowerCase();
}

/// Снимок всех данных для истории, статистики, бюджетов и долгов.
class Ledger {
  Ledger({
    required List<Operation> operations,
    required List<Account> accounts,
    required List<Currency> currencies,
    required List<CategoryEntity> categories,
    required List<Debt> debts,
    required String baseCode,
    required this.rates,
  })  : accounts = {for (final a in accounts) a.id: a},
        currencies = {for (final c in currencies) c.code: c},
        categories = {for (final c in categories) c.id: c},
        debts = {for (final d in debts) d.id: d} {
    base = currency(baseCode);
    this.operations = [for (final o in operations) _view(o)];
  }

  final RateHistory rates;
  final Map<int, Account> accounts;
  final Map<String, Currency> currencies;
  final Map<int, CategoryEntity> categories;
  final Map<int, Debt> debts;
  late final Currency base;

  /// Все операции в порядке, в котором их дал источник (обычно — новые сверху).
  late final List<OperationView> operations;

  Currency currency(String code) =>
      currencies[code] ??
      Currency(code: code, name: code, symbol: code, decimals: 2, sortOrder: 0);

  /// Основная категория для [id] (для подкатегории — её родитель).
  CategoryEntity? topCategory(int? id) {
    final c = categories[id];
    if (c == null || c.parentId == null) return c;
    return categories[c.parentId] ?? c;
  }

  /// Пересчёт в основную валюту по курсу на дату [date].
  int? toBase(int amount, String code, DateTime date) =>
      rates.at(date).convert(amount, currency(code), base);

  Iterable<OperationView> inPeriod(Period p) =>
      operations.where((v) => p.contains(v.date));

  OperationView _view(Operation o) {
    final account = accounts[o.accountId];
    final currency = this.currency(account?.currencyCode ?? base.code);
    final toAccount = o.toAccountId == null ? null : accounts[o.toAccountId];
    final isCategorized =
        o.type == OperationType.expense || o.type == OperationType.income;
    return OperationView._(
      op: o,
      account: account,
      currency: currency,
      toAccount: toAccount,
      toCurrency: toAccount == null ? null : this.currency(toAccount.currencyCode),
      category: categories[o.categoryId],
      topCategory: topCategory(o.categoryId),
      debt: debts[o.debtId],
      baseAmount: isCategorized
          ? rates.at(o.date).convert(o.amount, currency, base)
          : null,
    );
  }
}
