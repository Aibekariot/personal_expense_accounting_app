import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/rates/rate_book.dart';
import 'package:personal_expense_accounting/data/rates/rate_history.dart';
import 'package:personal_expense_accounting/domain/period.dart';
import 'package:personal_expense_accounting/domain/stats.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;

  setUpAll(() => initializeDateFormatting('ru'));
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('период', () {
    test('месяц: подпись, соседние месяцы, дни', () {
      final p = Period.month(DateTime(2026, 11, 17));
      expect(p.label, 'Ноябрь 2026');
      expect(p.days, 30);
      expect(p.contains(DateTime(2026, 11, 30, 23)), isTrue);
      expect(p.contains(DateTime(2026, 12, 1)), isFalse);
      expect(p.next!.label, 'Декабрь 2026');
      expect(p.next!.next!.label, 'Январь 2027');
      expect(Period.month(DateTime(2026, 1)).previous!.label, 'Декабрь 2025');
      expect(p.daysElapsed(DateTime(2026, 11, 5, 10)), 5);
      expect(p.daysElapsed(DateTime(2026, 12, 20)), 30);
      expect(p.daysElapsed(DateTime(2026, 10, 20)), 0);
    });

    test('свой период и год', () {
      final p = Period.custom(DateTime(2026, 11, 10), DateTime(2026, 11, 1));
      expect(p.start, DateTime(2026, 11, 1));
      expect(p.days, 10);
      expect(p.previous!.start, DateTime(2026, 10, 22));
      expect(p.label, '01.11.2026 – 10.11.2026');
      expect(Period.year(DateTime(2026, 5)).days, 365);
      expect(Period.all().previous, isNull);
    });
  });

  test('история курсов совпадает с прямым расчётом на любую дату', () {
    final rnd = Random(42);
    var id = 0;
    final rates = [
      for (var i = 0; i < 300; i++)
        ExchangeRate(
          id: ++id,
          fromCode: ['USD', 'EUR', 'KGS'][rnd.nextInt(3)],
          toCode: ['KGS', 'USD'][rnd.nextInt(2)],
          rate: 1 + rnd.nextDouble() * 100,
          date: DateTime(2026, 1 + rnd.nextInt(6), 1 + rnd.nextInt(28)),
          isManual: rnd.nextBool(),
        ),
    ];
    final history = RateHistory(rates);
    for (var m = 0; m < 9; m++) {
      for (final d in [1, 15, 28]) {
        final at = DateTime(2025, 12 + m, d);
        final expected = RateBook.fromRates(rates, at: at);
        final actual = history.at(at);
        for (final pair in [('USD', 'KGS'), ('EUR', 'KGS'), ('KGS', 'USD'), ('EUR', 'USD')]) {
          expect(actual.quote(pair.$1, pair.$2)?.rate, expected.quote(pair.$1, pair.$2)?.rate,
              reason: '$pair на $at');
        }
      }
    }
    expect(history.latest.quote('USD', 'KGS')?.rate, RateBook.fromRates(rates).quote('USD', 'KGS')?.rate);
  });

  group('итоги и категории', () {
    late int cash, usd;
    late CategoryEntity food, transport, taxi, salary;
    final oct10 = DateTime(2026, 10, 10);
    final nov3 = DateTime(2026, 11, 3);
    final nov20 = DateTime(2026, 11, 20);

    setUp(() async {
      cash = await accountId(db, 'Наличные');
      usd = await addAccount(db, 'Доллары', 'USD');
      food = await category(db, 'Продукты', CategoryType.expense);
      transport = await category(db, 'Транспорт', CategoryType.expense);
      taxi = await category(db, 'Такси', CategoryType.expense);
      salary = await category(db, 'Зарплата', CategoryType.income);
      await addRate(db, 'USD', 85, DateTime(2026, 10, 1));
      await addRate(db, 'USD', 90, DateTime(2026, 11, 15));

      await addOp(db, OperationType.expense, cash, 300000, oct10, categoryId: food.id);
      await addOp(db, OperationType.income, cash, 5000000, nov3, categoryId: salary.id);
      await addOp(db, OperationType.expense, cash, 200000, nov3, categoryId: food.id);
      await addOp(db, OperationType.expense, cash, 50000, nov3, categoryId: taxi.id);
      await addOp(db, OperationType.expense, cash, 30000, nov20, categoryId: transport.id);
      // 10 $ 3 ноября — по курсу 85, 10 $ 20 ноября — по курсу 90.
      await addOp(db, OperationType.expense, usd, 1000, nov3, categoryId: food.id);
      await addOp(db, OperationType.expense, usd, 1000, nov20, categoryId: food.id);
      // Не доходы и не расходы:
      await addOp(db, OperationType.transfer, cash, 100000, nov3, toAccountId: usd, toAmount: 1100);
      await addOp(db, OperationType.adjustment, cash, -7000, nov3);
    });

    test('итоги за месяц: курс на дату операции, переводы не считаются', () async {
      final ledger = await ledgerOf(db);
      final t = PeriodTotals.of(ledger.inPeriod(Period.month(nov3)));
      expect(t.income, 5000000);
      expect(t.expense, 200000 + 50000 + 30000 + 85000 + 90000);
      expect(t.net, 5000000 - 455000);
      expect(t.savingsRate, closeTo(1 - 455000 / 5000000, 1e-9));
      expect(t.unconverted, isEmpty);
    });

    test('без курса операция не теряется, а попадает в список «без курса»', () async {
      final eur = await addAccount(db, 'Евро', 'EUR');
      await addOp(db, OperationType.expense, eur, 500, nov3, categoryId: food.id);
      final t = PeriodTotals.of((await ledgerOf(db)).inPeriod(Period.month(nov3)));
      expect(t.unconverted.single.op.amount, 500);
      expect(t.expense, 455000);
    });

    test('разбивка по категориям: подкатегории входят в родителя', () async {
      final ledger = await ledgerOf(db);
      // Ноябрь уже закончился — сравнение со всем октябрём.
      final slices = categoryBreakdown(ledger, Period.month(nov3),
          type: CategoryType.expense, now: DateTime(2026, 12, 1));
      expect(slices.map((s) => (s.category!.name, s.amount)), [
        ('Продукты', 200000 + 85000 + 90000),
        ('Транспорт', 50000 + 30000),
      ]);
      expect(slices.fold(0.0, (s, e) => s + e.share), closeTo(1, 1e-9));
      // Сравнение с октябрём: продукты были 3 000 сом.
      expect(slices.first.previousAmount, 300000);
      expect(slices.first.change, closeTo(375000 / 300000 - 1, 1e-9));
      expect(slices.last.previousAmount, 0);
      expect(slices.last.change, isNull);

      final inside = categoryBreakdown(ledger, Period.month(nov3),
          type: CategoryType.expense, parentId: transport.id, now: DateTime(2026, 12, 1));
      expect(inside.map((s) => (s.category!.name, s.amount, s.isParentItself)), [
        ('Такси', 50000, false),
        ('Транспорт', 30000, true),
      ]);
    });

    test('идущий месяц сравнивается с тем же числом прошлого', () async {
      final ledger = await ledgerOf(db);
      // 5 ноября: сравнение с 1–5 октября, где расходов не было (продукты были 10-го).
      final slices = categoryBreakdown(ledger, Period.month(nov3),
          type: CategoryType.expense, now: DateTime(2026, 11, 5));
      expect(slices.first.previousAmount, 0);
      final p = comparisonPeriod(Period.month(nov3), DateTime(2026, 11, 5))!;
      expect((p.start, p.lastDay), (DateTime(2026, 10, 1), DateTime(2026, 10, 5)));
      expect(comparisonPeriod(Period.month(nov3), DateTime(2026, 12, 1)), Period.month(DateTime(2026, 10)));
    });

    test('по месяцам', () async {
      final points = monthlyTotals(await ledgerOf(db), DateTime(2026, 11), 3);
      expect(points.map((p) => p.month), [DateTime(2026, 9), DateTime(2026, 10), DateTime(2026, 11)]);
      expect(points.map((p) => p.expense), [0, 300000, 455000]);
      expect(points.map((p) => p.income), [0, 0, 5000000]);
    });

    test('крупнейшие расходы', () async {
      final top = topExpenses(await ledgerOf(db), Period.month(nov3), limit: 2);
      expect(top.map((v) => v.baseAmount), [200000, 90000]);
    });
  });

  test('прогноз на месяц', () {
    // История есть: потрачено 30 000 за 5 дней (аренда), обычно 60 000 в месяц.
    expect(forecastMonth(spent: 3000000, days: 30, elapsed: 5, previousMonths: [6000000, 6000000]),
        3000000 + 5000000);
    // Истории нет: в первую неделю не гадаем, потом — по темпу.
    expect(forecastMonth(spent: 100000, days: 30, elapsed: 5), isNull);
    expect(forecastMonth(spent: 100000, days: 30, elapsed: 10), 300000);
    // Месяц закончился — прогноз не нужен.
    expect(forecastMonth(spent: 100000, days: 30, elapsed: 30), isNull);
  });

  test('капитал по месяцам: по курсу на конец месяца, с даты начала учёта', () async {
    final cash = await accountId(db, 'Наличные');
    // Учёт начат 1 сентября, долларовый счёт заведён 15 октября.
    await db.update(db.accounts).write(AccountsCompanion(createdAt: Value(DateTime(2026, 9, 1))));
    await (db.update(db.accounts)..where((a) => a.id.equals(cash)))
        .write(const AccountsCompanion(initialBalance: Value(1000000)));
    final usd = await addAccount(db, 'Доллары', 'USD', initial: 10000); // 100 $
    await (db.update(db.accounts)..where((a) => a.id.equals(usd)))
        .write(AccountsCompanion(createdAt: Value(DateTime(2026, 10, 15))));
    await addRate(db, 'USD', 85, DateTime(2026, 10, 1));
    await addRate(db, 'USD', 90, DateTime(2026, 11, 1));
    final salary = await category(db, 'Зарплата', CategoryType.income);
    await addOp(db, OperationType.income, cash, 500000, DateTime(2026, 10, 20), categoryId: salary.id);

    final points = capitalHistory(await ledgerOf(db), DateTime(2026, 11), 3, now: DateTime(2026, 11, 5));
    expect(points.map((p) => p.month), [DateTime(2026, 9), DateTime(2026, 10), DateTime(2026, 11)]);
    expect(points[0].amount, 1000000); // только наличные
    expect(points[1].amount, 1000000 + 500000 + 850000); // + доллары по 85
    expect(points[2].amount, 1000000 + 500000 + 900000); // доллары по 90
    expect(points.every((p) => p.complete), isTrue);
  });
}
