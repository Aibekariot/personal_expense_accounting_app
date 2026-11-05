import 'package:drift/drift.dart';

import '../db/app_database.dart';

class CategoryRepository {
  CategoryRepository(this._db);

  final AppDatabase _db;

  Stream<List<CategoryEntity>> watchAll() => (_db.select(_db.categories)
        ..orderBy([
          (c) => OrderingTerm(expression: c.sortOrder),
          (c) => OrderingTerm(expression: c.id),
        ]))
      .watch();

  Future<CategoryEntity?> getById(int id) =>
      (_db.select(_db.categories)..where((c) => c.id.equals(id)))
          .getSingleOrNull();

  Future<List<CategoryEntity>> children(int parentId) =>
      (_db.select(_db.categories)..where((c) => c.parentId.equals(parentId)))
          .get();

  Future<int> create({
    required String name,
    required CategoryType type,
    int? parentId,
    required String icon,
    required int color,
  }) async {
    final maxOrder = _db.categories.sortOrder.max();
    final query = _db.selectOnly(_db.categories)
      ..addColumns([maxOrder])
      ..where(_db.categories.type.equalsValue(type) &
          (parentId == null
              ? _db.categories.parentId.isNull()
              : _db.categories.parentId.equals(parentId)));
    final last = await query.map((r) => r.read(maxOrder)).getSingle();
    return _db.into(_db.categories).insert(
      CategoriesCompanion.insert(
        name: name,
        type: type,
        parentId: Value(parentId),
        icon: icon,
        color: color,
        sortOrder: Value((last ?? -1) + 1),
      ),
    );
  }

  /// Сохраняет изменения. Категория с подкатегориями не может стать
  /// подкатегорией (вложенность — только два уровня).
  Future<void> update(CategoryEntity category) async {
    if (category.parentId != null) {
      if (category.parentId == category.id) {
        throw ArgumentError('Категория не может быть подкатегорией самой себя');
      }
      if ((await children(category.id)).isNotEmpty) {
        throw ArgumentError(
          'У категории есть подкатегории, поэтому она должна остаться основной',
        );
      }
    }
    await _db.update(_db.categories).replace(category);
  }

  Future<void> setArchived(int id, bool archived) =>
      (_db.update(_db.categories)..where((c) => c.id.equals(id)))
          .write(CategoriesCompanion(isArchived: Value(archived)));

  /// Используется ли категория (или её подкатегории) в операциях или бюджетах.
  /// Такую категорию нельзя удалить — только отправить в архив.
  Future<bool> isUsed(int id) async {
    final ids = [id, ...(await children(id)).map((c) => c.id)];
    final op = await (_db.select(_db.operations)
          ..where((o) => o.categoryId.isIn(ids))
          ..limit(1))
        .getSingleOrNull();
    if (op != null) return true;
    final budget = await (_db.select(_db.budgets)
          ..where((b) => b.categoryId.isIn(ids))
          ..limit(1))
        .getSingleOrNull();
    return budget != null;
  }

  /// Удаляет категорию вместе с подкатегориями. Проверку [isUsed]
  /// делает вызывающий; если категория используется, база не даст удалить.
  Future<void> delete(int id) => _db.transaction(() async {
    await (_db.delete(_db.categories)..where((c) => c.parentId.equals(id))).go();
    await (_db.delete(_db.categories)..where((c) => c.id.equals(id))).go();
  });
}
