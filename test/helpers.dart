import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/rates/rate_history.dart';
import 'package:personal_expense_accounting/data/repositories/operation_repository.dart';
import 'package:personal_expense_accounting/domain/ledger.dart';

/// Снимок данных базы, как его видит приложение.
Future<Ledger> ledgerOf(AppDatabase db, {String base = 'KGS'}) async => Ledger(
  operations: await OperationRepository(db).watchAll().first,
  accounts: await db.select(db.accounts).get(),
  currencies: await db.select(db.currencies).get(),
  categories: await db.select(db.categories).get(),
  debts: await db.select(db.debts).get(),
  baseCode: base,
  rates: RateHistory(await db.select(db.exchangeRates).get()),
);

Future<int> accountId(AppDatabase db, String name) async =>
    (await (db.select(db.accounts)..where((a) => a.name.equals(name))).getSingle()).id;

Future<CategoryEntity> category(AppDatabase db, String name, CategoryType type) =>
    (db.select(db.categories)
          ..where((c) => c.name.equals(name) & c.type.equalsValue(type)))
        .getSingle();

Future<int> addAccount(AppDatabase db, String name, String currency, {int initial = 0}) =>
    db.into(db.accounts).insert(AccountsCompanion.insert(
      name: name,
      type: AccountType.cash,
      currencyCode: currency,
      color: 0,
      initialBalance: Value(initial),
    ));

Future<void> addRate(AppDatabase db, String from, double rate, DateTime date,
        {String to = 'KGS', bool manual = false}) =>
    db.into(db.exchangeRates).insert(ExchangeRatesCompanion.insert(
      fromCode: from,
      toCode: to,
      rate: rate,
      date: date,
      isManual: Value(manual),
    ));

/// Быстро записать расход или доход.
Future<int> addOp(
  AppDatabase db,
  OperationType type,
  int account,
  int amount,
  DateTime date, {
  int? categoryId,
  int? toAccountId,
  int? toAmount,
  int? debtId,
  int? debtAmount,
  String note = '',
}) =>
    OperationRepository(db).save(OperationInput(
      type: type,
      date: date,
      accountId: account,
      amount: amount,
      categoryId: categoryId,
      toAccountId: toAccountId,
      toAmount: toAmount,
      debtId: debtId,
      debtAmount: debtAmount,
      note: note,
    ));
