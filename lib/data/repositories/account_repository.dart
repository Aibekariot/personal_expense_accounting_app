import 'package:drift/drift.dart';

import '../db/app_database.dart';

class AccountRepository {
  AccountRepository(this._db);

  final AppDatabase _db;

  Stream<List<Account>> watchAll() => (_db.select(_db.accounts)
        ..orderBy([
          (a) => OrderingTerm(expression: a.sortOrder),
          (a) => OrderingTerm(expression: a.id),
        ]))
      .watch();

  Future<Account?> getById(int id) =>
      (_db.select(_db.accounts)..where((a) => a.id.equals(id)))
          .getSingleOrNull();

  /// Текущие балансы всех счетов: id счёта → баланс в валюте счёта.
  ///
  /// Баланс не хранится, а считается каждый раз:
  /// начальный остаток + доходы − расходы ± переводы ± корректировки ± долги.
  /// Поэтому после правки или удаления любой операции он всегда верный.
  Stream<Map<int, int>> watchBalances() {
    final t = OperationType.values.asNameMap().map((k, _) => MapEntry(k, "'$k'"));
    final sql = '''
      SELECT a.id AS id,
        a.initial_balance
        + COALESCE((
            SELECT SUM(CASE o.type
              WHEN ${t['income']} THEN o.amount
              WHEN ${t['adjustment']} THEN o.amount
              WHEN ${t['debtIn']} THEN o.amount
              WHEN ${t['expense']} THEN -o.amount
              WHEN ${t['transfer']} THEN -o.amount
              WHEN ${t['debtOut']} THEN -o.amount
              ELSE 0 END)
            FROM operations o WHERE o.account_id = a.id), 0)
        + COALESCE((
            SELECT SUM(o.to_amount)
            FROM operations o
            WHERE o.type = ${t['transfer']} AND o.to_account_id = a.id), 0)
        AS balance
      FROM accounts a
    ''';
    return _db
        .customSelect(sql, readsFrom: {_db.accounts, _db.operations})
        .watch()
        .map((rows) => {
              for (final row in rows) row.read<int>('id'): row.read<int>('balance'),
            });
  }

  Future<int> create({
    required String name,
    required AccountType type,
    required String currencyCode,
    required int initialBalance,
    required int color,
    required bool includeInTotal,
  }) async {
    final maxOrder = _db.accounts.sortOrder.max();
    final last = await (_db.selectOnly(_db.accounts)..addColumns([maxOrder]))
        .map((r) => r.read(maxOrder))
        .getSingle();
    return _db.into(_db.accounts).insert(
      AccountsCompanion.insert(
        name: name,
        type: type,
        currencyCode: currencyCode,
        initialBalance: Value(initialBalance),
        color: color,
        includeInTotal: Value(includeInTotal),
        sortOrder: Value((last ?? -1) + 1),
      ),
    );
  }

  Future<void> update(Account account) =>
      _db.update(_db.accounts).replace(account);

  Future<void> setArchived(int id, bool archived) =>
      (_db.update(_db.accounts)..where((a) => a.id.equals(id)))
          .write(AccountsCompanion(isArchived: Value(archived)));

  /// Есть ли операции по счёту (как источник или как получатель перевода).
  /// Счёт с операциями нельзя удалить и нельзя сменить у него валюту.
  Future<bool> hasOperations(int id) async {
    final op = await (_db.select(_db.operations)
          ..where((o) => o.accountId.equals(id) | o.toAccountId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return op != null;
  }

  /// Удаляет счёт (без операций — это проверяет вызывающий) вместе с его планами.
  Future<void> delete(int id) => _db.transaction(() async {
    await (_db.delete(_db.plannedOperations)
          ..where((p) => p.accountId.equals(id) | p.toAccountId.equals(id)))
        .go();
    await (_db.delete(_db.accounts)..where((a) => a.id.equals(id))).go();
  });
}
