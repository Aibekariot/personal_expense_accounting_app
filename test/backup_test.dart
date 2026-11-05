import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/data/backup/backup_service.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/repositories/budget_repository.dart';
import 'package:personal_expense_accounting/data/repositories/debt_repository.dart';
import 'package:personal_expense_accounting/data/repositories/operation_repository.dart';
import 'package:personal_expense_accounting/domain/csv_export.dart';

import 'helpers.dart';

/// Всё содержимое базы в виде, удобном для сравнения.
Future<Map<String, List<Map<String, dynamic>>>> dump(AppDatabase db) async {
  List<Map<String, dynamic>> rows(List<dynamic> list) =>
      [for (final r in list) (r as dynamic).toJson() as Map<String, dynamic>];
  return {
    'currencies': rows(await db.select(db.currencies).get()),
    'rates': rows(await db.select(db.exchangeRates).get()),
    'accounts': rows(await db.select(db.accounts).get()),
    'categories': rows(await db.select(db.categories).get()),
    'debts': rows(await db.select(db.debts).get()),
    'operations': rows(await db.select(db.operations).get()),
    'budgets': rows(await db.select(db.budgets).get()),
    'settings': rows(await db.select(db.settings).get()),
  };
}

void main() {
  late AppDatabase source;
  late AppDatabase target;
  final nov5 = DateTime(2026, 11, 5);

  setUpAll(() async {
    await initializeDateFormatting('ru');
    // В тесте две базы одновременно — это нормально.
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });

  setUp(() async {
    source = AppDatabase(NativeDatabase.memory());
    target = AppDatabase(NativeDatabase.memory());

    // Наполняем исходную базу всеми видами данных.
    final cash = await accountId(source, 'Наличные');
    final usd = await addAccount(source, 'Доллары', 'USD', initial: 10000);
    await addRate(source, 'USD', 87.45, nov5);
    final taxi = await category(source, 'Такси', CategoryType.expense);
    await addOp(source, OperationType.expense, cash, 35000, nov5, categoryId: taxi.id, note: 'в "аэропорт"; ночью');
    await addOp(source, OperationType.transfer, usd, 1000, nov5, toAccountId: cash, toAmount: 87450);
    final debt = await DebtRepository(source, OperationRepository(source)).create(
      personName: 'Азамат', direction: DebtDirection.theyOwe, currencyCode: 'KGS',
      amount: 100000, accountId: cash, date: nov5, dueDate: DateTime(2026, 12, 1),
    );
    await addOp(source, OperationType.debtIn, cash, 40000, nov5, debtId: debt);
    await BudgetRepository(source).save(categoryId: taxi.id, monthlyLimit: 500000, currencyCode: 'KGS');
    await source.into(source.settings).insertOnConflictUpdate(
        SettingsCompanion.insert(key: SettingKeys.baseCurrency, value: 'USD'));
  });

  tearDown(() async {
    await source.close();
    await target.close();
  });

  test('копия → восстановление: данные совпадают полностью', () async {
    final json = await BackupService(source).exportJson();
    // В целевой базе — свои данные, они должны замениться.
    await addAccount(target, 'Лишний', 'KGS');

    final service = BackupService(target);
    final data = service.parse(json);
    expect(data.operations.length, 4);
    expect(data.exportedAt, isNotNull);
    await service.restore(data);

    expect(await dump(target), await dump(source));
    final names = (await target.select(target.accounts).get()).map((a) => a.name);
    expect(names, isNot(contains('Лишний')));
  });

  test('чужой или повреждённый файл не принимается', () {
    final service = BackupService(target);
    expect(() => service.parse('не json'), throwsA(isA<BackupException>()));
    expect(() => service.parse('{"app":"other"}'), throwsA(isA<BackupException>()));
    expect(
      () => service.parse(jsonEncode({'app': BackupService.appId, 'format': 99, 'schemaVersion': 1, 'tables': {}})),
      throwsA(isA<BackupException>().having((e) => e.message, 'message', contains('более новой версии'))),
    );
  });

  test('при ошибке в копии текущие данные не теряются', () async {
    final json = jsonDecode(await BackupService(source).exportJson()) as Map<String, dynamic>;
    // Операция ссылается на несуществующий счёт.
    ((json['tables'] as Map)['operations'] as List).first['accountId'] = 999;
    final before = await dump(target);

    final service = BackupService(target);
    await expectLater(service.restore(service.parse(jsonEncode(json))), throwsA(isA<BackupException>()));
    expect(await dump(target), before);
  });

  test('копия из версии 1 (без начальной суммы долга) читается', () async {
    final json = jsonDecode(await BackupService(source).exportJson()) as Map<String, dynamic>;
    json['schemaVersion'] = 1;
    for (final d in (json['tables'] as Map)['debts'] as List) {
      (d as Map).remove('initialAmount');
    }
    final service = BackupService(target);
    final data = service.parse(jsonEncode(json));
    expect(data.debts.single.initialAmount, 0);
    await service.restore(data);
    expect((await target.select(target.debts).get()).single.personName, 'Азамат');
  });

  test('CSV для Excel', () async {
    final ledger = await ledgerOf(source);
    final csv = operationsToCsv(ledger, ledger.operations);
    final lines = csv.split('\r\n');
    expect(csv.startsWith('﻿'), isTrue);
    expect(lines.first, contains('Дата;Тип;Счёт;Сумма'));
    expect(lines.length, 1 + 4 + 1); // заголовок, 4 операции, пустая строка в конце
    final taxi = lines.firstWhere((l) => l.contains('Такси'));
    expect(taxi, contains('-350;KGS;Транспорт;Такси'));
    expect(taxi, contains('"в ""аэропорт""; ночью"'));
    expect(lines.firstWhere((l) => l.contains('Перевод')), contains('10;USD;;;Наличные;874,50;KGS'));
  });
}
