import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/repositories/account_repository.dart';
import 'package:personal_expense_accounting/data/repositories/budget_repository.dart';
import 'package:personal_expense_accounting/data/repositories/category_repository.dart';
import 'package:personal_expense_accounting/data/repositories/debt_repository.dart';
import 'package:personal_expense_accounting/data/repositories/operation_repository.dart';
import 'package:personal_expense_accounting/domain/budgets.dart';
import 'package:personal_expense_accounting/domain/debts.dart';
import 'package:personal_expense_accounting/domain/period.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late DebtRepository debts;
  late AccountRepository accounts;
  final nov5 = DateTime(2026, 11, 5);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    debts = DebtRepository(db, OperationRepository(db));
    accounts = AccountRepository(db);
  });
  tearDown(() => db.close());

  Future<DebtView> viewOf(int id) async {
    final ledger = await ledgerOf(db);
    return debtView(ledger, ledger.debts[id]!);
  }

  group('долги', () {
    test('дал в долг с карты, вернули частями — в том числе в долларах', () async {
      final card = await accountId(db, 'Карта');
      final usd = await addAccount(db, 'Доллары', 'USD');
      final id = await debts.create(
        personName: 'Азамат', direction: DebtDirection.theyOwe,
        currencyCode: 'KGS', amount: 1000000, accountId: card, date: nov5,
      );
      // С карты ушло 10 000 сом.
      expect((await accounts.watchBalances().first)[card], -1000000);

      await addOp(db, OperationType.debtIn, card, 300000, nov5, debtId: id);
      // Вернул 50 $, договорились считать как 4 400 сом.
      await addOp(db, OperationType.debtIn, usd, 5000, nov5, debtId: id, debtAmount: 440000);

      final v = await viewOf(id);
      expect(v.total, 1000000);
      expect(v.repaid, 740000);
      expect(v.remaining, 260000);
      expect(v.operations.length, 3);
      expect((await accounts.watchBalances().first)[usd], 5000);

      final ledger = await ledgerOf(db);
      expect(ledger.operations.map((o) => o.title),
          containsAll(['Дал в долг: Азамат', 'Мне вернули долг: Азамат']));
    });

    test('взял в долг и вернул; старый долг без движения денег', () async {
      final cash = await accountId(db, 'Наличные');
      final borrowed = await debts.create(
        personName: 'Банк', direction: DebtDirection.iOwe,
        currencyCode: 'KGS', amount: 5000000, accountId: cash, date: nov5,
      );
      await addOp(db, OperationType.debtOut, cash, 1000000, nov5, debtId: borrowed);
      expect((await viewOf(borrowed)).remaining, 4000000);
      expect((await accounts.watchBalances().first)[cash], 4000000);

      // Долг с прошлого года: деньги через счета не проходили.
      final old = await debts.create(
        personName: 'Брат', direction: DebtDirection.theyOwe,
        currencyCode: 'USD', amount: 20000,
      );
      final v = await viewOf(old);
      expect(v.remaining, 20000);
      expect(v.operations, isEmpty);
      expect((await accounts.watchBalances().first)[cash], 4000000);

      final totals = DebtTotals.of([await viewOf(borrowed), v]);
      expect(totals.iOwe, {'KGS': 4000000});
      expect(totals.theyOwe, {'USD': 20000});
    });

    test('удаление долга удаляет его операции и возвращает балансы', () async {
      final cash = await accountId(db, 'Наличные');
      final id = await debts.create(
        personName: 'Друг', direction: DebtDirection.theyOwe,
        currencyCode: 'KGS', amount: 50000, accountId: cash,
      );
      expect(await debts.hasOperations(id), isTrue);
      await debts.delete(id);
      expect(await db.select(db.operations).get(), isEmpty);
      expect((await accounts.watchBalances().first)[cash], 0);
    });

    test('просрочка', () async {
      final id = await debts.create(
        personName: 'Друг', direction: DebtDirection.theyOwe,
        currencyCode: 'KGS', amount: 50000, dueDate: DateTime(2026, 11, 1),
      );
      final v = await viewOf(id);
      expect(v.isOverdue(DateTime(2026, 11, 1)), isFalse);
      expect(v.isOverdue(DateTime(2026, 11, 2)), isTrue);
    });
  });

  group('бюджеты', () {
    test('учитывают подкатегории и валюту, прогноз и дневной лимит', () async {
      final cash = await accountId(db, 'Наличные');
      final usd = await addAccount(db, 'Доллары', 'USD');
      await addRate(db, 'USD', 90, DateTime(2026, 11, 1));
      final transport = await category(db, 'Транспорт', CategoryType.expense);
      final taxi = await category(db, 'Такси', CategoryType.expense);
      final food = await category(db, 'Продукты', CategoryType.expense);

      final repo = BudgetRepository(db);
      await repo.save(categoryId: transport.id, monthlyLimit: 600000, currencyCode: 'KGS');
      await addOp(db, OperationType.expense, cash, 100000, DateTime(2026, 11, 2), categoryId: transport.id);
      await addOp(db, OperationType.expense, cash, 100000, DateTime(2026, 11, 4), categoryId: taxi.id);
      await addOp(db, OperationType.expense, usd, 1000, DateTime(2026, 11, 5), categoryId: taxi.id); // 900 сом
      await addOp(db, OperationType.expense, cash, 999900, DateTime(2026, 11, 5), categoryId: food.id); // не транспорт
      await addOp(db, OperationType.expense, cash, 999900, DateTime(2026, 10, 30), categoryId: taxi.id); // октябрь

      final budget = (await db.select(db.budgets).get()).single;
      final p = budgetProgress(await ledgerOf(db), budget, Period.month(DateTime(2026, 11)),
          now: DateTime(2026, 11, 5, 12));
      expect(p.spent, 290000);
      expect(p.remaining, 310000);
      expect(p.isOver, isFalse);
      // Прогноз: уже 2 900 сом + средний октябрь (9 999 сом) за оставшиеся 25 из 30 дней.
      expect(p.forecast, 290000 + 999900 * 25 ~/ 30);
      expect(p.forecastOver, isTrue);
      expect(p.daysLeft, 26);
      expect(p.dailyAllowance, 310000 ~/ 26);

      // Прошлый месяц: без прогноза.
      final oct = budgetProgress(await ledgerOf(db), budget, Period.month(DateTime(2026, 10)),
          now: DateTime(2026, 11, 5));
      expect(oct.spent, 999900);
      expect(oct.isOver, isTrue);
      expect(oct.forecast, isNull);
      expect(oct.dailyAllowance, isNull);
    });

    test('у категории один бюджет: повторное сохранение меняет лимит', () async {
      final food = await category(db, 'Продукты', CategoryType.expense);
      final repo = BudgetRepository(db);
      await repo.save(categoryId: food.id, monthlyLimit: 100, currencyCode: 'KGS');
      await repo.save(categoryId: food.id, monthlyLimit: 200, currencyCode: 'USD');
      final all = await db.select(db.budgets).get();
      expect(all.single.monthlyLimit, 200);
      expect(all.single.currencyCode, 'USD');
      expect(() => repo.save(categoryId: food.id, monthlyLimit: 0, currencyCode: 'KGS'),
          throwsArgumentError);
    });
  });

  group('категории', () {
    test('используемую нельзя удалить; неиспользуемая удаляется с подкатегориями', () async {
      final repo = CategoryRepository(db);
      final transport = await category(db, 'Транспорт', CategoryType.expense);
      final taxi = await category(db, 'Такси', CategoryType.expense);
      final cash = await accountId(db, 'Наличные');
      expect(await repo.isUsed(transport.id), isFalse);
      await addOp(db, OperationType.expense, cash, 100, nov5, categoryId: taxi.id);
      // Используется подкатегория — значит и вся категория.
      expect(await repo.isUsed(transport.id), isTrue);

      final pets = await repo.create(name: 'Питомцы', type: CategoryType.expense, icon: 'pets', color: 0);
      final food = await repo.create(name: 'Корм', type: CategoryType.expense, parentId: pets, icon: 'pets', color: 0);
      expect((await repo.getById(food))!.sortOrder, 0);
      await repo.delete(pets);
      expect(await repo.getById(pets), isNull);
      expect(await repo.getById(food), isNull);
    });

    test('категория с подкатегориями не может стать подкатегорией', () async {
      final repo = CategoryRepository(db);
      final transport = await category(db, 'Транспорт', CategoryType.expense);
      final food = await category(db, 'Продукты', CategoryType.expense);
      expect(() => repo.update(transport.copyWith(parentId: Value(food.id))), throwsArgumentError);
      await repo.update(food.copyWith(parentId: Value(transport.id)));
      expect((await repo.getById(food.id))!.parentId, transport.id);
    });
  });
}
