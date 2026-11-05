import '../data/db/app_database.dart';
import 'ledger.dart';

/// Вид операции для фильтра (оба направления долга — один вид).
enum OperationKind {
  expense('Расходы'),
  income('Доходы'),
  transfer('Переводы'),
  adjustment('Корректировки'),
  debt('Долги');

  const OperationKind(this.label);
  final String label;

  static OperationKind of(OperationType t) => switch (t) {
    OperationType.expense => expense,
    OperationType.income => income,
    OperationType.transfer => transfer,
    OperationType.adjustment => adjustment,
    OperationType.debtIn || OperationType.debtOut => debt,
  };
}

/// Фильтр истории операций.
class OperationFilter {
  const OperationFilter({
    this.kinds = const {},
    this.accountId,
    this.categoryId,
    this.payee,
    this.query = '',
  });

  /// Пусто — все виды.
  final Set<OperationKind> kinds;
  final int? accountId;

  /// Категория; для основной категории подходят и её подкатегории.
  final int? categoryId;

  /// Получатель / плательщик (точное совпадение).
  final String? payee;
  final String query;

  /// Включены ли фильтры (кроме поиска).
  bool get hasFilters =>
      kinds.isNotEmpty || accountId != null || categoryId != null || payee != null;

  bool get isEmpty => !hasFilters && query.trim().isEmpty;

  OperationFilter copyWith({
    Set<OperationKind>? kinds,
    int? Function()? accountId,
    int? Function()? categoryId,
    String? Function()? payee,
    String? query,
  }) =>
      OperationFilter(
        kinds: kinds ?? this.kinds,
        accountId: accountId == null ? this.accountId : accountId(),
        categoryId: categoryId == null ? this.categoryId : categoryId(),
        payee: payee == null ? this.payee : payee(),
        query: query ?? this.query,
      );

  bool matches(OperationView v) {
    if (kinds.isNotEmpty && !kinds.contains(OperationKind.of(v.type))) {
      return false;
    }
    if (accountId != null &&
        v.op.accountId != accountId &&
        v.op.toAccountId != accountId) {
      return false;
    }
    if (categoryId != null &&
        v.op.categoryId != categoryId &&
        v.category?.parentId != categoryId) {
      return false;
    }
    if (payee != null && v.payee != payee) return false;
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.every(v.searchText.contains);
  }
}
