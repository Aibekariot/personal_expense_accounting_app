import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/rates/rate_book.dart';
import 'package:personal_expense_accounting/data/rates/rates_api.dart';
import 'package:personal_expense_accounting/data/repositories/account_repository.dart';
import 'package:personal_expense_accounting/data/repositories/currency_repository.dart';
import 'package:personal_expense_accounting/data/repositories/rates_repository.dart';
import 'package:personal_expense_accounting/data/repositories/settings_repository.dart';
import 'package:personal_expense_accounting/features/accounts/accounts_overview.dart';

/// Источник курсов без интернета.
class FakeRatesApi extends RatesApi {
  FakeRatesApi(this.result);
  final UsdRates result;

  @override
  Future<UsdRates> fetchUsdRates() async => result;
}

void main() {
  late AppDatabase db;
  late AccountRepository accounts;
  late CurrencyRepository currencies;
  late SettingsRepository settings;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    accounts = AccountRepository(db);
    currencies = CurrencyRepository(db);
    settings = SettingsRepository(db);
  });

  tearDown(() => db.close());

  Future<int> op(
    OperationType type,
    int accountId,
    int amount, {
    int? toAccountId,
    int? toAmount,
  }) =>
      db.into(db.operations).insert(OperationsCompanion.insert(
            type: type,
            date: DateTime(2026, 11, 5),
            accountId: accountId,
            amount: amount,
            toAccountId: Value(toAccountId),
            toAmount: Value(toAmount),
          ));

  Future<({int cash, int card, int usd})> setUpAccounts() async {
    final all = await db.select(db.accounts).get();
    final cash = all.firstWhere((a) => a.name == 'Наличные').id;
    final card = all.firstWhere((a) => a.name == 'Карта').id;
    final usd = await accounts.create(
      name: 'Наличные \$',
      type: AccountType.cash,
      currencyCode: 'USD',
      initialBalance: 0,
      color: 0,
      includeInTotal: true,
    );
    // Начальный остаток наличных: 5 000 сом.
    await accounts.update((await accounts.getById(cash))!.copyWith(initialBalance: 500000));
    return (cash: cash, card: card, usd: usd);
  }

  test('баланс учитывает все типы операций', () async {
    final a = await setUpAccounts();

    await op(OperationType.expense, a.cash, 150000); //      −1 500 сом
    await op(OperationType.income, a.cash, 1000000); //     +10 000 сом
    await op(OperationType.adjustment, a.cash, -5000); //       −50 сом
    await op(OperationType.debtOut, a.cash, 100000); //      −1 000 сом (дал в долг)
    await op(OperationType.income, a.usd, 20000); //           +200 $
    // Обмен: 100 $ → 8 745 сом на карту.
    await op(OperationType.transfer, a.usd, 10000, toAccountId: a.card, toAmount: 874500);
    await op(OperationType.debtIn, a.card, 50000); //          +500 сом (вернули долг)

    final balances = await accounts.watchBalances().first;
    expect(balances[a.cash], 500000 - 150000 + 1000000 - 5000 - 100000);
    expect(balances[a.card], 874500 + 50000);
    expect(balances[a.usd], 20000 - 10000);
  });

  test('баланс пересчитывается после удаления операции', () async {
    final a = await setUpAccounts();
    final id = await op(OperationType.expense, a.cash, 150000);
    expect((await accounts.watchBalances().first)[a.cash], 350000);

    await (db.delete(db.operations)..where((o) => o.id.equals(id))).go();
    expect((await accounts.watchBalances().first)[a.cash], 500000);
  });

  test('общий капитал в основной валюте', () async {
    final a = await setUpAccounts();
    await op(OperationType.income, a.usd, 10000); // 100 $

    final rates = RateBook.fromRates([
      ExchangeRate(id: 1, fromCode: 'USD', toCode: 'KGS', rate: 87.45, date: DateTime(2026, 11, 5), isManual: false),
    ]);
    final o = AccountsOverview.build(
      accounts: await db.select(db.accounts).get(),
      balances: await accounts.watchBalances().first,
      currencies: await db.select(db.currencies).get(),
      baseCode: 'KGS',
      rates: rates,
    );
    // 5 000 сом наличными + 0 на карте + 100 $ × 87,45 = 13 745 сом.
    expect(o.capital, 500000 + 874500);
    expect(o.missingRates, isEmpty);
    expect(o.byCurrency.map((t) => (t.currency.code, t.amount)), [('KGS', 500000), ('USD', 10000)]);
    expect(o.active.firstWhere((v) => v.account.id == a.usd).balanceInBase, 874500);
  });

  test('счета вне капитала, архивные и без курса не входят в итог', () async {
    final a = await setUpAccounts();
    await op(OperationType.income, a.usd, 10000);
    await accounts.update((await accounts.getById(a.card))!.copyWith(initialBalance: 300000, includeInTotal: false));
    final eur = await accounts.create(
      name: 'Евро', type: AccountType.cash, currencyCode: 'EUR',
      initialBalance: 5000, color: 0, includeInTotal: true,
    );
    final archived = await accounts.create(
      name: 'Старый', type: AccountType.cash, currencyCode: 'KGS',
      initialBalance: 999900, color: 0, includeInTotal: true,
    );
    await accounts.setArchived(archived, true);

    final o = AccountsOverview.build(
      accounts: await db.select(db.accounts).get(),
      balances: await accounts.watchBalances().first,
      currencies: await db.select(db.currencies).get(),
      baseCode: 'KGS',
      rates: RateBook.empty(),
    );
    expect(o.capital, 500000); // только наличные сомы
    expect(o.missingRates, unorderedEquals(['USD', 'EUR']));
    expect(o.archived.map((v) => v.account.id), [archived]);
    expect(o.active.any((v) => v.account.id == eur), isTrue);
  });

  test('счёт с операциями: hasOperations учитывает и получателя перевода', () async {
    final a = await setUpAccounts();
    expect(await accounts.hasOperations(a.card), isFalse);
    await op(OperationType.transfer, a.cash, 1000, toAccountId: a.card, toAmount: 1000);
    expect(await accounts.hasOperations(a.card), isTrue);
    expect(await accounts.hasOperations(a.cash), isTrue);
  });

  test('валюту со счетами нельзя удалить, свою без счетов — можно', () async {
    expect(await currencies.isUsed('KGS'), isTrue);
    await currencies.add(code: 'GOLD', name: 'Золото', symbol: 'г', decimals: 0);
    expect(await currencies.isUsed('GOLD'), isFalse);

    final rates = RatesRepository(db, RatesApi(), settings);
    await rates.setManual(from: 'GOLD', to: 'KGS', rate: 9000, date: DateTime(2026, 11, 5));
    await currencies.delete('GOLD');
    expect(await currencies.getByCode('GOLD'), isNull);
    expect(await db.select(db.exchangeRates).get(), isEmpty);
  });

  test('загрузка курсов: пересчёт к основной валюте и свои валюты', () async {
    await currencies.add(code: 'GOLD', name: 'Золото', symbol: 'г', decimals: 0);
    final api = FakeRatesApi(UsdRates(DateTime(2026, 11, 5), {
      'USD': 1, 'KGS': 87.5, 'EUR': 0.875, 'RUB': 80, 'KZT': 500,
    }));
    final repo = RatesRepository(db, api, settings);

    final result = await repo.updateFromInternet();
    expect(result.updated, unorderedEquals(['USD', 'EUR', 'RUB', 'KZT']));
    expect(result.notFound, ['GOLD']);
    expect(await settings.ratesLastUpdate(), isNotNull);

    final book = RateBook.fromRates(await db.select(db.exchangeRates).get());
    expect(book.quote('USD', 'KGS')!.rate, closeTo(87.5, 1e-9));
    expect(book.quote('EUR', 'KGS')!.rate, closeTo(100, 1e-9));
    expect(book.quote('KZT', 'KGS')!.rate, closeTo(0.175, 1e-9));

    // Повторная загрузка в тот же день не плодит дубли.
    await repo.updateFromInternet();
    expect((await db.select(db.exchangeRates).get()).length, 4);
  });

  test('ручной курс в тот же день заменяет прежний ручной', () async {
    final repo = RatesRepository(db, RatesApi(), settings);
    final day = DateTime(2026, 11, 5, 15, 30);
    await repo.setManual(from: 'USD', to: 'KGS', rate: 87, date: day);
    await repo.setManual(from: 'USD', to: 'KGS', rate: 88, date: day);
    final all = await db.select(db.exchangeRates).get();
    expect(all.length, 1);
    expect(all.single.rate, 88);
    expect(all.single.date, DateTime(2026, 11, 5));
  });
}
