import 'package:drift/drift.dart';

import '../db/app_database.dart';

class CurrencyRepository {
  CurrencyRepository(this._db);

  final AppDatabase _db;

  Stream<List<Currency>> watchAll() => (_db.select(_db.currencies)
        ..orderBy([
          (c) => OrderingTerm(expression: c.sortOrder),
          (c) => OrderingTerm(expression: c.code),
        ]))
      .watch();

  Future<Currency?> getByCode(String code) =>
      (_db.select(_db.currencies)..where((c) => c.code.equals(code)))
          .getSingleOrNull();

  Future<void> add({
    required String code,
    required String name,
    required String symbol,
    required int decimals,
  }) async {
    final maxOrder = _db.currencies.sortOrder.max();
    final last = await (_db.selectOnly(_db.currencies)..addColumns([maxOrder]))
        .map((r) => r.read(maxOrder))
        .getSingle();
    await _db.into(_db.currencies).insert(
      CurrenciesCompanion.insert(
        code: code,
        name: name,
        symbol: symbol,
        decimals: Value(decimals),
        sortOrder: Value((last ?? 0) + 1),
      ),
    );
  }

  Future<void> update(Currency currency) =>
      _db.update(_db.currencies).replace(currency);

  /// Используется ли валюта счетами, долгами или бюджетами.
  /// Такую валюту нельзя удалить, и у неё нельзя менять число знаков
  /// после запятой (иначе испортятся уже записанные суммы).
  Future<bool> isUsed(String code) async {
    final account = await (_db.select(_db.accounts)
          ..where((a) => a.currencyCode.equals(code))
          ..limit(1))
        .getSingleOrNull();
    if (account != null) return true;
    final debt = await (_db.select(_db.debts)
          ..where((d) => d.currencyCode.equals(code))
          ..limit(1))
        .getSingleOrNull();
    if (debt != null) return true;
    final budget = await (_db.select(_db.budgets)
          ..where((b) => b.currencyCode.equals(code))
          ..limit(1))
        .getSingleOrNull();
    return budget != null;
  }

  /// Удаляет валюту вместе с её курсами. Проверку [isUsed] делает вызывающий.
  Future<void> delete(String code) => _db.transaction(() async {
    await (_db.delete(_db.exchangeRates)
          ..where((r) => r.fromCode.equals(code) | r.toCode.equals(code)))
        .go();
    await (_db.delete(_db.currencies)..where((c) => c.code.equals(code))).go();
  });
}
