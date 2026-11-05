import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  test('при первом запуске создаются валюты, счета и категории', () async {
    final currencies = await db.select(db.currencies).get();
    expect(currencies.map((c) => c.code), containsAll(['KGS', 'USD']));

    final base = await (db.select(db.settings)
          ..where((s) => s.key.equals(SettingKeys.baseCurrency)))
        .getSingle();
    expect(base.value, 'KGS');

    final accounts = await db.select(db.accounts).get();
    expect(accounts.map((a) => a.name), ['Наличные', 'Карта']);

    final categories = await db.select(db.categories).get();
    final expense = categories.where((c) => c.type == CategoryType.expense);
    final income = categories.where((c) => c.type == CategoryType.income);
    expect(expense, isNotEmpty);
    expect(income, isNotEmpty);

    // Подкатегории ссылаются на существующих родителей.
    final ids = categories.map((c) => c.id).toSet();
    final children = categories.where((c) => c.parentId != null);
    expect(children, isNotEmpty);
    expect(children.every((c) => ids.contains(c.parentId)), isTrue);
  });

  test('связи между таблицами проверяются', () async {
    // Счёт с несуществующей валютой создать нельзя.
    await expectLater(
      db.into(db.accounts).insert(
        AccountsCompanion.insert(
          name: 'Тест',
          type: AccountType.cash,
          currencyCode: 'XXX',
          color: 0,
        ),
      ),
      throwsA(isA<SqliteException>()),
    );
  });

  test('перевод хранит обе суммы', () async {
    final usd = await db.into(db.accounts).insert(
      AccountsCompanion.insert(
        name: 'Наличные \$',
        type: AccountType.cash,
        currencyCode: 'USD',
        color: 0,
      ),
    );
    final kgs = (await db.select(db.accounts).get()).first.id;

    // Обмен: 100 $ → 8 745 сом.
    final id = await db.into(db.operations).insert(
      OperationsCompanion.insert(
        type: OperationType.transfer,
        date: DateTime(2026, 11, 5),
        accountId: usd,
        amount: 10000,
        toAccountId: Value(kgs),
        toAmount: const Value(874500),
      ),
    );

    final op = await (db.select(db.operations)..where((o) => o.id.equals(id)))
        .getSingle();
    expect(op.type, OperationType.transfer);
    expect(op.amount, 10000);
    expect(op.toAmount, 874500);
    expect(op.categoryId, isNull);
  });
}
