import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Данные операции из формы. Проверяются перед записью в базу,
/// поэтому в базу не попадёт, например, перевод без счёта-получателя.
class OperationInput {
  const OperationInput({
    required this.type,
    required this.date,
    required this.accountId,
    required this.amount,
    this.categoryId,
    this.toAccountId,
    this.toAmount,
    this.debtId,
    this.debtAmount,
    this.note = '',
    this.payee = '',
  });

  factory OperationInput.fromOperation(Operation o) => OperationInput(
    type: o.type,
    date: o.date,
    accountId: o.accountId,
    amount: o.amount,
    categoryId: o.categoryId,
    toAccountId: o.toAccountId,
    toAmount: o.toAmount,
    debtId: o.debtId,
    debtAmount: o.debtAmount,
    note: o.note,
    payee: o.payee,
  );

  final OperationType type;
  final DateTime date;
  final int accountId;

  /// Сумма в валюте счёта [accountId].
  final int amount;
  final int? categoryId;
  final int? toAccountId;

  /// Сумма в валюте счёта-получателя (для перевода).
  final int? toAmount;
  final int? debtId;

  /// Сумма в валюте долга, если она отличается от валюты счёта.
  final int? debtAmount;
  final String note;

  /// Получатель (для расхода) или плательщик (для дохода).
  final String payee;

  /// Текст ошибки или null, если всё верно.
  String? validate() {
    switch (type) {
      case OperationType.expense || OperationType.income:
        if (amount <= 0) return 'Сумма должна быть больше нуля';
        if (categoryId == null) return 'Выберите категорию';
      case OperationType.transfer:
        if (amount <= 0) return 'Сумма должна быть больше нуля';
        if (toAccountId == null) return 'Выберите счёт, на который перевод';
        if (toAccountId == accountId) return 'Счета списания и зачисления совпадают';
        if (toAmount == null || toAmount! <= 0) {
          return 'Сумма зачисления должна быть больше нуля';
        }
      case OperationType.adjustment:
        if (amount == 0) return 'Сумма корректировки не может быть нулевой';
      case OperationType.debtOut || OperationType.debtIn:
        if (amount <= 0) return 'Сумма должна быть больше нуля';
        if (debtId == null) return 'Не указан долг';
        if (debtAmount != null && debtAmount! <= 0) {
          return 'Сумма в валюте долга должна быть больше нуля';
        }
    }
    return null;
  }

  /// Поля для записи: лишние для этого типа поля обнуляются.
  OperationsCompanion toCompanion() {
    final isCategorized =
        type == OperationType.expense || type == OperationType.income;
    final isTransfer = type == OperationType.transfer;
    final isDebt = type == OperationType.debtOut || type == OperationType.debtIn;
    return OperationsCompanion(
      type: Value(type),
      date: Value(DateTime(date.year, date.month, date.day)),
      accountId: Value(accountId),
      amount: Value(amount),
      categoryId: Value(isCategorized ? categoryId : null),
      toAccountId: Value(isTransfer ? toAccountId : null),
      toAmount: Value(isTransfer ? toAmount : null),
      debtId: Value(isDebt ? debtId : null),
      debtAmount: Value(isDebt ? debtAmount : null),
      note: Value(note.trim()),
      payee: Value(isCategorized ? normalizePayee(payee) : ''),
    );
  }
}

/// Имя получателя без лишних пробелов: «  Глобус   ЦУМ » → «Глобус ЦУМ».
String normalizePayee(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

class OperationRepository {
  OperationRepository(this._db);

  final AppDatabase _db;

  /// Все операции: новые сверху.
  Stream<List<Operation>> watchAll() => (_db.select(_db.operations)
        ..orderBy([
          (o) => OrderingTerm.desc(o.date),
          (o) => OrderingTerm.desc(o.createdAt),
          (o) => OrderingTerm.desc(o.id),
        ]))
      .watch();

  Future<Operation?> getById(int id) =>
      (_db.select(_db.operations)..where((o) => o.id.equals(id)))
          .getSingleOrNull();

  /// Создаёт операцию ([id] == null) или изменяет существующую.
  /// Возвращает id. Бросает [ArgumentError], если данные неверны.
  Future<int> save(OperationInput input, {int? id}) async {
    final error = input.validate();
    if (error != null) throw ArgumentError(error);
    final data = input.toCompanion();
    if (id == null) {
      return _db.into(_db.operations).insert(data);
    }
    await (_db.update(_db.operations)..where((o) => o.id.equals(id)))
        .write(data.copyWith(updatedAt: Value(DateTime.now())));
    return id;
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.operations)..where((o) => o.id.equals(id))).go();

  /// Переименовывает получателя во всех операциях. Если новое имя уже
  /// есть — получатели объединяются. Возвращает число изменённых операций.
  Future<int> renamePayee(String from, String to) {
    final name = normalizePayee(to);
    if (name.isEmpty) throw ArgumentError('Введите имя');
    return (_db.update(_db.operations)..where((o) => o.payee.equals(from)))
        .write(OperationsCompanion(payee: Value(name)));
  }

  /// Корректировка: приводит баланс счёта к фактическому.
  /// Создаёт операцию на разницу. Возвращает разницу (0 — менять нечего).
  Future<int> adjustBalance({
    required int accountId,
    required int currentBalance,
    required int actualBalance,
    required DateTime date,
    String note = '',
  }) async {
    final diff = actualBalance - currentBalance;
    if (diff == 0) return 0;
    await save(OperationInput(
      type: OperationType.adjustment,
      date: date,
      accountId: accountId,
      amount: diff,
      note: note,
    ));
    return diff;
  }
}
