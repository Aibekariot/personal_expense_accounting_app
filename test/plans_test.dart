import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/data/backup/backup_service.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/repositories/account_repository.dart';
import 'package:personal_expense_accounting/data/repositories/budget_repository.dart';
import 'package:personal_expense_accounting/data/repositories/operation_repository.dart';
import 'package:personal_expense_accounting/data/repositories/plan_repository.dart';
import 'package:personal_expense_accounting/domain/budgets.dart';
import 'package:personal_expense_accounting/domain/forecast.dart';
import 'package:personal_expense_accounting/domain/period.dart';
import 'package:personal_expense_accounting/domain/schedule.dart';

import 'helpers.dart';

PlannedOperation plan({
  required DateTime start,
  RepeatUnit unit = RepeatUnit.month,
  int every = 1,
  DateTime? end,
  int done = 0,
}) =>
    PlannedOperation(
      id: 1, type: OperationType.expense, accountId: 1, amount: 100,
      payee: '', note: '', startDate: start, repeatUnit: unit, repeatEvery: every,
      endDate: end, doneCount: done, autoConfirm: false, createdAt: start,
    );

void main() {
  group('даты повторений', () {
    test('каждый месяц 31-го: в коротких месяцах — последний день', () {
      final p = plan(start: DateTime(2026, 1, 31));
      expect([for (var i = 0; i < 4; i++) occurrence(p, i)], [
        DateTime(2026, 1, 31), DateTime(2026, 2, 28), DateTime(2026, 3, 31), DateTime(2026, 4, 30),
      ]);
    });

    test('недели, дни, годы, интервал и окончание', () {
      expect(occurrence(plan(start: DateTime(2026, 11, 2), unit: RepeatUnit.week, every: 2), 3),
          DateTime(2026, 12, 14));
      expect(occurrence(plan(start: DateTime(2026, 12, 30), unit: RepeatUnit.day), 3), DateTime(2027, 1, 2));
      expect(occurrence(plan(start: DateTime(2028, 2, 29), unit: RepeatUnit.year), 1), DateTime(2029, 2, 28));
      final limited = plan(start: DateTime(2026, 1, 10), end: DateTime(2026, 3, 10));
      expect(occurrence(limited, 2), DateTime(2026, 3, 10));
      expect(occurrence(limited, 3), isNull);
      final once = plan(start: DateTime(2026, 5, 1), unit: RepeatUnit.none);
      expect(occurrence(once, 0), DateTime(2026, 5, 1));
      expect(isFinished(plan(start: DateTime(2026, 5, 1), unit: RepeatUnit.none, done: 1)), isTrue);
    });

    test('ближайшие повторения и подписи', () {
      final p = plan(start: DateTime(2026, 11, 1), unit: RepeatUnit.week, done: 1);
      final list = upcoming([p], to: DateTime(2026, 11, 30));
      expect(list.map((o) => o.date), [
        DateTime(2026, 11, 8), DateTime(2026, 11, 15), DateTime(2026, 11, 22), DateTime(2026, 11, 29),
      ]);
      expect(repeatLabel(RepeatUnit.month, 1), 'каждый месяц');
      expect(repeatLabel(RepeatUnit.week, 2), 'каждые 2 недели');
      expect(repeatLabel(RepeatUnit.day, 5), 'каждые 5 дней');
      expect(repeatLabel(RepeatUnit.month, 21), 'каждый 21 месяц');
      final today = DateTime(2026, 11, 6);
      expect(dueLabel(DateTime(2026, 11, 6), today), 'сегодня');
      expect(dueLabel(DateTime(2026, 11, 9), today), 'через 3 дня');
      expect(dueLabel(DateTime(2026, 11, 1), today), 'просрочен на 5 дней');
    });
  });

  group('планы в базе', () {
    late AppDatabase db;
    late PlanRepository plans;
    late int cash;
    late int rent;

    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      plans = PlanRepository(db, OperationRepository(db));
      cash = await accountId(db, 'Наличные');
      rent = (await category(db, 'Аренда', CategoryType.expense)).id;
    });
    tearDown(() => db.close());

    Future<PlannedOperation> makeRent({bool auto = false}) async {
      final id = await plans.save(PlanInput(
        type: OperationType.expense, accountId: cash, amount: 2500000,
        startDate: DateTime(2026, 10, 3), repeatUnit: RepeatUnit.month,
        categoryId: rent, payee: 'Хозяйка', autoConfirm: auto,
      ));
      return (await plans.getById(id))!;
    }

    test('провести и пропустить', () async {
      var p = await makeRent();
      await plans.confirm(p);
      p = (await plans.getById(p.id))!;
      expect(p.doneCount, 1);
      final op = (await db.select(db.operations).get()).single;
      expect((op.date, op.amount, op.payee, op.categoryId), (DateTime(2026, 10, 3), 2500000, 'Хозяйка', rent));

      await plans.skip(p);
      p = (await plans.getById(p.id))!;
      expect(nextOccurrence(p), DateTime(2026, 12, 3));
      expect((await db.select(db.operations).get()).length, 1);
    });

    test('автопроведение — каждое повторение своей датой', () async {
      await makeRent(auto: true);
      final created = await plans.processAuto(DateTime(2026, 12, 5));
      expect(created, 3); // 3 октября, 3 ноября, 3 декабря
      final dates = (await db.select(db.operations).get()).map((o) => o.date);
      expect(dates, [DateTime(2026, 10, 3), DateTime(2026, 11, 3), DateTime(2026, 12, 3)]);
      expect(await plans.processAuto(DateTime(2026, 12, 5)), 0); // повторно — ничего
    });

    test('изменение расписания начинает отсчёт заново', () async {
      var p = await makeRent();
      await plans.confirm(p);
      await plans.save(planInputOf(p), id: p.id); // без изменений — счётчик тот же
      expect((await plans.getById(p.id))!.doneCount, 1);
      await plans.save(
        PlanInput(type: p.type, accountId: cash, amount: p.amount, categoryId: rent,
            startDate: DateTime(2027, 1, 5), repeatUnit: RepeatUnit.month),
        id: p.id,
      );
      p = (await plans.getById(p.id))!;
      expect((p.doneCount, nextOccurrence(p)), (0, DateTime(2027, 1, 5)));
    });

    test('неверный план не сохраняется', () async {
      expect(() => plans.save(PlanInput(
        type: OperationType.expense, accountId: cash, amount: 100,
        startDate: DateTime(2026, 11, 1), repeatUnit: RepeatUnit.month,
      )), throwsArgumentError); // без категории
      expect(() => plans.save(PlanInput(
        type: OperationType.adjustment, accountId: cash, amount: 100,
        startDate: DateTime(2026, 11, 1), repeatUnit: RepeatUnit.month,
      )), throwsArgumentError);
    });

    test('удаление счёта удаляет его планы', () async {
      final usd = await addAccount(db, 'Доллары', 'USD');
      final travel = (await category(db, 'Путешествия', CategoryType.expense)).id;
      await plans.save(PlanInput(
        type: OperationType.expense, accountId: usd, amount: 100,
        startDate: DateTime(2026, 11, 1), repeatUnit: RepeatUnit.none, categoryId: travel,
      ));
      await AccountRepository(db).delete(usd);
      expect(await db.select(db.plannedOperations).get(), isEmpty);
    });

    test('прогноз капитала: зарплата, аренда, просроченное — сегодня', () async {
      final card = await accountId(db, 'Карта');
      final salary = (await category(db, 'Зарплата', CategoryType.income)).id;
      await makeRent(); // 3-го числа, октябрь не проведён — просрочен
      await plans.save(PlanInput(
        type: OperationType.income, accountId: card, amount: 6000000,
        startDate: DateTime(2026, 11, 10), repeatUnit: RepeatUnit.month, categoryId: salary,
      ));
      final l = await ledgerOf(db);
      final f = balanceForecast(
        ledger: l, plans: await db.select(db.plannedOperations).get(),
        startCapital: 1000000, today: DateTime(2026, 11, 6), days: 30,
      );
      // Сегодня: 10 000 − аренда за октябрь и ноябрь (просрочены) = −40 000.
      expect(f.points.first.capital, 1000000 - 2 * 2500000);
      expect(f.lowest.capital, -4000000);
      // 10 ноября +60 000; 3 декабря ещё аренда.
      expect(f.points[4].capital, -4000000 + 6000000);
      expect(f.last.capital, -4000000 + 6000000 - 2500000);
      expect(f.incomplete, isFalse);
    });

    test('бюджет: план дохода и ожидаемые платежи', () async {
      final card = await accountId(db, 'Карта');
      final salary = (await category(db, 'Зарплата', CategoryType.income)).id;
      await BudgetRepository(db).save(categoryId: salary, monthlyLimit: 12000000, currencyCode: 'KGS');
      await BudgetRepository(db).save(categoryId: rent, monthlyLimit: 2500000, currencyCode: 'KGS');
      await addOp(db, OperationType.income, card, 6000000, DateTime(2026, 11, 1), categoryId: salary);
      await plans.save(PlanInput(
        type: OperationType.income, accountId: card, amount: 6000000,
        startDate: DateTime(2026, 11, 15), repeatUnit: RepeatUnit.month, categoryId: salary,
      ));
      await makeRent(); // ноябрьская аренда ещё не проведена

      final l = await ledgerOf(db);
      final allPlans = await db.select(db.plannedOperations).get();
      final list = allBudgetProgress(l, await db.select(db.budgets).get(), Period.month(DateTime(2026, 11)),
          now: DateTime(2026, 11, 6), plans: allPlans);
      final income = list.firstWhere((p) => p.isIncome);
      expect((income.spent, income.expected, income.limit), (6000000, 6000000, 12000000));
      final rentBudget = list.firstWhere((p) => !p.isIncome);
      expect((rentBudget.spent, rentBudget.expected), (0, 2500000));
    });

    test('планы попадают в резервную копию', () async {
      await makeRent();
      final json = await BackupService(db).exportJson();
      final target = AppDatabase(NativeDatabase.memory());
      final service = BackupService(target);
      await service.restore(service.parse(json));
      expect((await target.select(target.plannedOperations).get()).single.payee, 'Хозяйка');

      // Копия из версии 3 — без раздела планов.
      final old = jsonDecode(json) as Map<String, dynamic>;
      old['schemaVersion'] = 3;
      (old['tables'] as Map).remove('plannedOperations');
      await service.restore(service.parse(jsonEncode(old)));
      expect(await target.select(target.plannedOperations).get(), isEmpty);
      await target.close();
    });
  });
}
