import 'package:drift/drift.dart';

import '../db/app_database.dart';
import 'operation_repository.dart';

class DebtRepository {
  DebtRepository(this._db, this._operations);

  final AppDatabase _db;
  final OperationRepository _operations;

  Stream<List<Debt>> watchAll() => (_db.select(_db.debts)
        ..orderBy([(d) => OrderingTerm.desc(d.createdAt), (d) => OrderingTerm.desc(d.id)]))
      .watch();

  Future<Debt?> getById(int id) =>
      (_db.select(_db.debts)..where((d) => d.id.equals(id))).getSingleOrNull();

  /// Новый долг.
  ///
  /// Если указан [accountId], деньги прошли через счёт: создаётся операция
  /// на [amount] в валюте этого счёта (дал в долг — списание, взял — зачисление),
  /// и валюта долга = валюта счёта. Иначе [amount] — долг, который был
  /// ещё до начала учёта, в валюте [currencyCode].
  Future<int> create({
    required String personName,
    required DebtDirection direction,
    required String currencyCode,
    required int amount,
    int? accountId,
    DateTime? date,
    DateTime? dueDate,
    String note = '',
  }) {
    if (amount <= 0) throw ArgumentError('Сумма долга должна быть больше нуля');
    return _db.transaction(() async {
      final debtId = await _db.into(_db.debts).insert(
        DebtsCompanion.insert(
          personName: personName,
          direction: direction,
          currencyCode: currencyCode,
          initialAmount: Value(accountId == null ? amount : 0),
          dueDate: Value(dueDate),
          note: Value(note),
        ),
      );
      if (accountId != null) {
        await _operations.save(OperationInput(
          type: direction == DebtDirection.theyOwe
              ? OperationType.debtOut
              : OperationType.debtIn,
          date: date ?? DateTime.now(),
          accountId: accountId,
          amount: amount,
          debtId: debtId,
        ));
      }
      return debtId;
    });
  }

  Future<void> update(Debt debt) => _db.update(_db.debts).replace(debt);

  Future<void> setClosed(int id, bool closed) =>
      (_db.update(_db.debts)..where((d) => d.id.equals(id)))
          .write(DebtsCompanion(isClosed: Value(closed)));

  Future<bool> hasOperations(int id) async {
    final op = await (_db.select(_db.operations)
          ..where((o) => o.debtId.equals(id))
          ..limit(1))
        .getSingleOrNull();
    return op != null;
  }

  /// Удаляет долг вместе с его операциями (балансы счетов пересчитаются).
  Future<void> delete(int id) => _db.transaction(() async {
    await (_db.delete(_db.operations)..where((o) => o.debtId.equals(id))).go();
    await (_db.delete(_db.debts)..where((d) => d.id.equals(id))).go();
  });
}
