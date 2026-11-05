import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/repositories/account_repository.dart';
import 'package:personal_expense_accounting/data/repositories/operation_repository.dart';
import 'package:personal_expense_accounting/domain/operation_filter.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late OperationRepository ops;
  late AccountRepository accounts;
  final nov5 = DateTime(2026, 11, 5);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    ops = OperationRepository(db);
    accounts = AccountRepository(db);
  });
  tearDown(() => db.close());

  group('проверка ввода', () {
    OperationInput input(OperationType type, {int amount = 100, int? cat, int? to, int? toAmount, int? debt}) =>
        OperationInput(
          type: type, date: nov5, accountId: 1, amount: amount,
          categoryId: cat, toAccountId: to, toAmount: toAmount, debtId: debt,
        );

    test('ошибки', () {
      expect(input(OperationType.expense).validate(), 'Выберите категорию');
      expect(input(OperationType.expense, amount: 0, cat: 1).validate(), isNotNull);
      expect(input(OperationType.income, amount: -5, cat: 1).validate(), isNotNull);
      expect(input(OperationType.transfer, to: 1, toAmount: 100).validate(),
          'Счета списания и зачисления совпадают');
      expect(input(OperationType.transfer, to: 2).validate(), isNotNull);
      expect(input(OperationType.adjustment, amount: 0).validate(), isNotNull);
      expect(input(OperationType.debtIn).validate(), 'Не указан долг');
    });

    test('верные данные', () {
      expect(input(OperationType.expense, cat: 1).validate(), isNull);
      expect(input(OperationType.transfer, to: 2, toAmount: 50).validate(), isNull);
      expect(input(OperationType.adjustment, amount: -300).validate(), isNull);
      expect(input(OperationType.debtOut, debt: 1).validate(), isNull);
    });
  });

  test('при записи лишние поля обнуляются, дата — без времени', () async {
    final cash = await accountId(db, 'Наличные');
    final card = await accountId(db, 'Карта');
    final food = await category(db, 'Продукты', CategoryType.expense);
    final id = await ops.save(OperationInput(
      type: OperationType.expense,
      date: DateTime(2026, 11, 5, 18, 45),
      accountId: cash,
      amount: 150000,
      categoryId: food.id,
      toAccountId: card, // лишнее для расхода
      toAmount: 999,
      note: '  молоко  ',
    ));
    final op = (await ops.getById(id))!;
    expect(op.date, nov5);
    expect(op.toAccountId, isNull);
    expect(op.toAmount, isNull);
    expect(op.note, 'молоко');

    expect(() => ops.save(OperationInput(
      type: OperationType.expense, date: nov5, accountId: cash, amount: 100,
    )), throwsArgumentError);
  });

  test('изменение операции пересчитывает баланс', () async {
    final cash = await accountId(db, 'Наличные');
    final food = await category(db, 'Продукты', CategoryType.expense);
    final id = await addOp(db, OperationType.expense, cash, 100000, nov5, categoryId: food.id);
    expect((await accounts.watchBalances().first)[cash], -100000);

    final op = (await ops.getById(id))!;
    await ops.save(
      OperationInput.fromOperation(op.copyWith(amount: 25000)),
      id: id,
    );
    expect((await ops.getById(id))!.amount, 25000);
    expect((await accounts.watchBalances().first)[cash], -25000);
    expect((await db.select(db.operations).get()).length, 1);
  });

  test('корректировка приводит баланс к фактическому', () async {
    final cash = await accountId(db, 'Наличные');
    final diff = await ops.adjustBalance(
      accountId: cash, currentBalance: 0, actualBalance: 1234500, date: nov5,
    );
    expect(diff, 1234500);
    expect((await accounts.watchBalances().first)[cash], 1234500);

    final down = await ops.adjustBalance(
      accountId: cash, currentBalance: 1234500, actualBalance: 1200000, date: nov5,
    );
    expect(down, -34500);
    expect((await accounts.watchBalances().first)[cash], 1200000);

    expect(await ops.adjustBalance(
      accountId: cash, currentBalance: 1200000, actualBalance: 1200000, date: nov5,
    ), 0);
    expect((await db.select(db.operations).get()).length, 2);
  });

  test('фильтр и поиск по истории', () async {
    final cash = await accountId(db, 'Наличные');
    final card = await accountId(db, 'Карта');
    final transport = await category(db, 'Транспорт', CategoryType.expense);
    final taxi = await category(db, 'Такси', CategoryType.expense);
    final salary = await category(db, 'Зарплата', CategoryType.income);

    await addOp(db, OperationType.expense, cash, 35000, nov5, categoryId: taxi.id, note: 'в аэропорт');
    await addOp(db, OperationType.expense, card, 5000, nov5, categoryId: transport.id);
    await addOp(db, OperationType.income, card, 8000000, nov5, categoryId: salary.id);
    await addOp(db, OperationType.transfer, card, 100000, nov5, toAccountId: cash, toAmount: 100000);

    final ledger = await ledgerOf(db);
    List<String> titles(OperationFilter f) =>
        ledger.operations.where(f.matches).map((v) => v.title).toList();

    expect(titles(const OperationFilter()).length, 4);
    expect(titles(const OperationFilter(kinds: {OperationKind.income})), ['Зарплата']);
    // Наличные: расход с них и перевод на них.
    expect(titles(OperationFilter(accountId: cash)), unorderedEquals(['Такси', 'Перевод']));
    // Основная категория включает подкатегории.
    expect(titles(OperationFilter(categoryId: transport.id)), unorderedEquals(['Такси', 'Транспорт']));
    expect(titles(OperationFilter(categoryId: taxi.id)), ['Такси']);
    // Поиск: по комментарию, по родительской категории, по сумме.
    expect(titles(const OperationFilter(query: 'аэроп')), ['Такси']);
    expect(titles(const OperationFilter(query: 'транспорт такси')), ['Такси']);
    expect(titles(const OperationFilter(query: '80000')), ['Зарплата']);
    expect(titles(const OperationFilter(query: 'нет такого')), isEmpty);
  });
}
