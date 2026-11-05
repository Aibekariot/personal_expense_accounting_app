import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/data/backup/backup_service.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/repositories/operation_repository.dart';
import 'package:personal_expense_accounting/domain/calculator.dart';
import 'package:personal_expense_accounting/domain/operation_filter.dart';
import 'package:personal_expense_accounting/domain/payees.dart';

import 'helpers.dart';

void main() {
  group('калькулятор', () {
    int? calc(String e, {int decimals = 2}) => evaluateAmount(e, decimals: decimals);

    test('простые суммы и порядок действий', () {
      expect(calc('350'), 35000);
      expect(calc('350+120'), 47000);
      expect(calc('1500−200,5'), 129950);
      expect(calc('100+50×2'), 20000); // сначала умножение
      expect(calc('1000÷3'), 33333); // 333,33
      expect(calc('2÷3'), 67); // 0,666… → 0,67
      expect(calc('10,5×3'), 3150);
      expect(calc('−300'), -30000);
      expect(calc('0,1+0,2'), 30); // без ошибок double
    });

    test('неполные и неверные выражения', () {
      expect(calc(''), isNull);
      expect(calc('350+'), isNull);
      expect(calc('5÷0'), isNull);
      expect(calc('1+++2'), isNull);
      expect(calc('9999999999999'), isNull); // больше 12 цифр
    });

    test('валюта без копеек', () {
      expect(calc('7÷2', decimals: 0), 4); // 3,5 → 4
      expect(calc('10', decimals: 0), 10);
    });

    test('клавиатура', () {
      String type(String keys, {int decimals = 2, bool negative = false}) {
        var e = '';
        for (final k in keys.split(' ')) {
          e = pressKey(e, k, decimals: decimals, allowNegative: negative);
        }
        return e;
      }

      expect(type('3 5 0 + 1 2 0'), '350+120');
      expect(type('3 5 0 + × 2'), '350×2'); // действие заменяется
      expect(type(', 5'), '0,5');
      expect(type('1 , 2 3 4'), '1,23'); // не больше 2 знаков после запятой
      expect(type('1 , ,'), '1,');
      expect(type('0 0 7'), '7');
      expect(type('1 2 ⌫'), '1');
      expect(type('5 + 5 C'), '');
      expect(type('3 5 0 + 1 2 0 ='), '470');
      expect(type('1 0 ÷ 4 ='), '2,50');
      expect(type('+ 5'), '5'); // нельзя начать с действия
      expect(type('− 5', negative: true), '−5'); // корректировка: можно с минуса
      expect(type('1 , 5', decimals: 0), '15'); // запятая недоступна
      expect(formatExpression('1500+350,5'), '1 500 + 350,5');
    });
  });

  group('получатели', () {
    late AppDatabase db;
    final nov = DateTime(2026, 11, 1);

    setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> buy(String payee, String category, int day, {OperationType type = OperationType.expense}) async {
      final cat = await (db.select(db.categories)
            ..where((c) => c.name.equals(category)))
          .get();
      final cash = await accountId(db, 'Наличные');
      await OperationRepository(db).save(OperationInput(
        type: type,
        date: DateTime(2026, 11, day),
        accountId: cash,
        amount: 10000,
        categoryId: cat.first.id,
        payee: payee,
      ));
    }

    test('пробелы в имени убираются, у переводов получателя нет', () async {
      await buy('  Глобус   ЦУМ ', 'Продукты', 1);
      final ops = await db.select(db.operations).get();
      expect(ops.single.payee, 'Глобус ЦУМ');
      final card = await accountId(db, 'Карта');
      await OperationRepository(db).save(OperationInput(
        type: OperationType.transfer, date: nov, accountId: ops.single.accountId,
        amount: 100, toAccountId: card, toAmount: 100, payee: 'Глобус',
      ));
      expect((await db.select(db.operations).get()).last.payee, '');
    });

    test('подсказки и категория по истории', () async {
      await buy('Глобус', 'Продукты', 1);
      await buy('Глобус', 'Продукты', 2);
      await buy('Глобус', 'Кафе и рестораны', 3);
      await buy('Гипермаркет Фрунзе', 'Продукты', 4);
      await buy('Народный', 'Продукты', 5);
      await buy('Работа', 'Зарплата', 5, type: OperationType.income);

      final l = await ledgerOf(db);
      expect(payeeSuggestions(l, OperationType.expense, 'г'), ['Глобус', 'Гипермаркет Фрунзе']);
      expect(payeeSuggestions(l, OperationType.expense, 'фрун'), ['Гипермаркет Фрунзе']);
      expect(payeeSuggestions(l, OperationType.expense, ''), ['Глобус', 'Народный', 'Гипермаркет Фрунзе']);
      expect(payeeSuggestions(l, OperationType.income, ''), ['Работа']);
      // Полностью введённое имя не подсказываем повторно.
      expect(payeeSuggestions(l, OperationType.expense, 'глобус'), isEmpty);

      final products = (await category(db, 'Продукты', CategoryType.expense)).id;
      expect(suggestCategory(l, 'глобус', OperationType.expense), products); // 2 из 3
      expect(suggestCategory(l, 'Новый магазин', OperationType.expense), isNull);

      final stats = payeeStats(l);
      expect(stats.first.name, 'Глобус');
      expect(stats.first.count, 3);
      expect(stats.first.expense, 30000);
    });

    test('переименование объединяет получателей; фильтр по получателю', () async {
      await buy('Глобус', 'Продукты', 1);
      await buy('глобус цум', 'Продукты', 2);
      final changed = await OperationRepository(db).renamePayee('глобус цум', 'Глобус');
      expect(changed, 1);
      final l = await ledgerOf(db);
      expect(payeeStats(l).single.count, 2);
      expect(l.operations.where(const OperationFilter(payee: 'Глобус').matches).length, 2);
      expect(l.operations.first.headline, 'Глобус');
      expect(l.operations.first.details, 'Продукты · Наличные');
    });

    test('копия из версии 2 (без получателей) читается', () async {
      await buy('Глобус', 'Продукты', 1);
      final json = jsonDecode(await BackupService(db).exportJson()) as Map<String, dynamic>;
      json['schemaVersion'] = 2;
      for (final o in (json['tables'] as Map)['operations'] as List) {
        (o as Map).remove('payee');
      }
      final target = AppDatabase(NativeDatabase.memory());
      final service = BackupService(target);
      await service.restore(service.parse(jsonEncode(json)));
      expect((await target.select(target.operations).get()).single.payee, '');
      await target.close();
    });
  });
}
