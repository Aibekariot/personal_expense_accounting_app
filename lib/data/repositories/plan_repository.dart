import 'package:drift/drift.dart';

import '../../domain/schedule.dart';
import '../db/app_database.dart';
import 'operation_repository.dart';

/// Данные плана из формы.
class PlanInput {
  const PlanInput({
    required this.type,
    required this.accountId,
    required this.amount,
    required this.startDate,
    required this.repeatUnit,
    this.repeatEvery = 1,
    this.endDate,
    this.categoryId,
    this.toAccountId,
    this.toAmount,
    this.payee = '',
    this.note = '',
    this.autoConfirm = false,
  });

  final OperationType type;
  final int accountId;
  final int amount;
  final DateTime startDate;
  final RepeatUnit repeatUnit;
  final int repeatEvery;
  final DateTime? endDate;
  final int? categoryId;
  final int? toAccountId;
  final int? toAmount;
  final String payee;
  final String note;
  final bool autoConfirm;

  /// Операция для повторения на дату [date].
  OperationInput toOperation(DateTime date) => OperationInput(
    type: type,
    date: date,
    accountId: accountId,
    amount: amount,
    categoryId: categoryId,
    toAccountId: toAccountId,
    toAmount: toAmount,
    payee: payee,
    note: note,
  );

  String? validate() {
    if (type != OperationType.expense &&
        type != OperationType.income &&
        type != OperationType.transfer) {
      return 'Планировать можно расход, доход или перевод';
    }
    if (repeatEvery < 1) return 'Интервал повтора должен быть не меньше 1';
    if (endDate != null && endDate!.isBefore(DateTime(startDate.year, startDate.month, startDate.day))) {
      return 'Дата окончания раньше первого платежа';
    }
    return toOperation(startDate).validate();
  }
}

PlanInput planInputOf(PlannedOperation p) => PlanInput(
  type: p.type,
  accountId: p.accountId,
  amount: p.amount,
  startDate: p.startDate,
  repeatUnit: p.repeatUnit,
  repeatEvery: p.repeatEvery,
  endDate: p.endDate,
  categoryId: p.categoryId,
  toAccountId: p.toAccountId,
  toAmount: p.toAmount,
  payee: p.payee,
  note: p.note,
  autoConfirm: p.autoConfirm,
);

class PlanRepository {
  PlanRepository(this._db, this._operations);

  final AppDatabase _db;
  final OperationRepository _operations;

  Stream<List<PlannedOperation>> watchAll() =>
      (_db.select(_db.plannedOperations)..orderBy([(p) => OrderingTerm(expression: p.id)])).watch();

  Future<PlannedOperation?> getById(int id) =>
      (_db.select(_db.plannedOperations)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Создаёт план или меняет существующий. При изменении уже проведённые
  /// повторения остаются в истории; если изменилась дата начала или правило
  /// повтора — отсчёт начинается заново с новой даты.
  Future<int> save(PlanInput input, {int? id}) async {
    final error = input.validate();
    if (error != null) throw ArgumentError(error);
    final op = input.toOperation(input.startDate).toCompanion();
    final data = PlannedOperationsCompanion(
      type: Value(input.type),
      accountId: Value(input.accountId),
      amount: Value(input.amount),
      categoryId: op.categoryId,
      toAccountId: op.toAccountId,
      toAmount: op.toAmount,
      payee: op.payee,
      note: op.note,
      startDate: Value(DateTime(input.startDate.year, input.startDate.month, input.startDate.day)),
      repeatUnit: Value(input.repeatUnit),
      repeatEvery: Value(input.repeatEvery),
      endDate: Value(input.endDate == null
          ? null
          : DateTime(input.endDate!.year, input.endDate!.month, input.endDate!.day)),
      autoConfirm: Value(input.autoConfirm),
    );
    if (id == null) return _db.into(_db.plannedOperations).insert(data);

    final old = await getById(id);
    final scheduleChanged = old == null ||
        old.startDate != data.startDate.value ||
        old.repeatUnit != input.repeatUnit ||
        old.repeatEvery != input.repeatEvery;
    await (_db.update(_db.plannedOperations)..where((p) => p.id.equals(id))).write(
      scheduleChanged ? data.copyWith(doneCount: const Value(0)) : data,
    );
    return id;
  }

  Future<void> delete(int id) =>
      (_db.delete(_db.plannedOperations)..where((p) => p.id.equals(id))).go();

  /// Отметить следующее повторение как выполненное (операция уже записана
  /// отдельно — например, через форму с изменённой суммой).
  Future<void> markDone(int id) => _db.customUpdate(
    'UPDATE planned_operations SET done_count = done_count + 1 WHERE id = ?',
    variables: [Variable.withInt(id)],
    updates: {_db.plannedOperations},
  );

  /// Провести следующее повторение: записать операцию на дату [date]
  /// (по умолчанию — дата повторения). Возвращает id операции.
  Future<int> confirm(PlannedOperation plan, {DateTime? date}) => _db.transaction(() async {
    final due = nextOccurrence(plan);
    if (due == null) throw StateError('План уже завершён');
    final id = await _operations.save(planInputOf(plan).toOperation(date ?? due));
    await markDone(plan.id);
    return id;
  });

  /// Пропустить следующее повторение (без операции).
  Future<void> skip(PlannedOperation plan) => markDone(plan.id);

  /// Проводит все просроченные повторения планов с автопроведением —
  /// каждое своей датой. Возвращает число записанных операций.
  Future<int> processAuto(DateTime today) async {
    final day = DateTime(today.year, today.month, today.day);
    final plans = await (_db.select(_db.plannedOperations)..where((p) => p.autoConfirm.equals(true))).get();
    var created = 0;
    for (var plan in plans) {
      // Не больше 400 за раз — на случай очень частого повтора.
      for (var i = 0; i < 400; i++) {
        final due = nextOccurrence(plan);
        if (due == null || due.isAfter(day)) break;
        await confirm(plan);
        created++;
        plan = plan.copyWith(doneCount: plan.doneCount + 1);
      }
    }
    return created;
  }
}
