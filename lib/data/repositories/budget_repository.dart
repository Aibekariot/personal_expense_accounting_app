import 'package:drift/drift.dart';

import '../db/app_database.dart';

class BudgetRepository {
  BudgetRepository(this._db);

  final AppDatabase _db;

  Stream<List<Budget>> watchAll() =>
      (_db.select(_db.budgets)..orderBy([(b) => OrderingTerm(expression: b.id)]))
          .watch();

  Future<Budget?> getById(int id) =>
      (_db.select(_db.budgets)..where((b) => b.id.equals(id))).getSingleOrNull();

  /// Создаёт бюджет или меняет существующий бюджет этой категории
  /// (у категории может быть только один бюджет).
  Future<void> save({
    int? id,
    required int categoryId,
    required int monthlyLimit,
    required String currencyCode,
  }) async {
    if (monthlyLimit <= 0) throw ArgumentError('Лимит должен быть больше нуля');
    await _db.transaction(() async {
      if (id != null) {
        await (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();
      }
      await _db.into(_db.budgets).insert(
        BudgetsCompanion.insert(
          id: id == null ? const Value.absent() : Value(id),
          categoryId: categoryId,
          monthlyLimit: monthlyLimit,
          currencyCode: currencyCode,
        ),
        onConflict: DoUpdate(
          (_) => BudgetsCompanion(
            monthlyLimit: Value(monthlyLimit),
            currencyCode: Value(currencyCode),
          ),
          target: [_db.budgets.categoryId],
        ),
      );
    });
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();
}
