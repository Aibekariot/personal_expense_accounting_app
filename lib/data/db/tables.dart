import 'package:drift/drift.dart';

// ВАЖНО: все денежные суммы хранятся ЦЕЛЫМИ числами в минимальных единицах
// валюты (тыйыны, центы). 1 500,50 сом = 150050. Никаких double для денег.

enum AccountType {
  cash,
  card,
  deposit,
  other,

  /// Кредит, ипотека, рассрочка: баланс обычно отрицательный.
  credit,
}

enum CategoryType { expense, income }

enum OperationType {
  /// Расход: деньги ушли со счёта, попадает в статистику расходов.
  expense,

  /// Доход: деньги пришли на счёт, попадает в статистику доходов.
  income,

  /// Перевод между своими счетами (в т.ч. обмен валют).
  /// Не расход и не доход. Хранит обе суммы: [Operations.amount] — сколько
  /// ушло со счёта-источника, [Operations.toAmount] — сколько пришло.
  transfer,

  /// Корректировка баланса: реальная сумма не совпала с приложением.
  /// Сумма со знаком (+/−). В статистику расходов/доходов не попадает.
  adjustment,

  /// Деньги ушли по долгу: дал в долг или вернул свой долг.
  debtOut,

  /// Деньги пришли по долгу: взял в долг или мне вернули.
  debtIn,
}

/// Как часто повторяется плановая операция.
enum RepeatUnit {
  /// Один раз.
  none,
  day,
  week,
  month,
  year,
}

/// Направление долга.
enum DebtDirection {
  /// Мне должны (я дал в долг).
  theyOwe,

  /// Я должен (я взял в долг).
  iOwe,
}

@DataClassName('Currency')
class Currencies extends Table {
  /// Код валюты: KGS, USD или любой свой (до 10 символов).
  TextColumn get code => text().withLength(min: 1, max: 10)();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get symbol => text().withLength(min: 1, max: 10)();

  /// Знаков после запятой (обычно 2; для валют без дробной части — 0).
  IntColumn get decimals => integer().withDefault(const Constant(2))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {code};
}

/// Курс валют на дату: 1 [fromCode] = [rate] [toCode].
@DataClassName('ExchangeRate')
@TableIndex(name: 'rates_pair_date', columns: {#fromCode, #toCode, #date})
class ExchangeRates extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get fromCode => text().references(Currencies, #code)();
  TextColumn get toCode => text().references(Currencies, #code)();
  // Курс — это коэффициент, а не сумма денег, поэтому double здесь допустим.
  // Результат пересчёта всегда округляется до целых минимальных единиц.
  RealColumn get rate => real()();

  /// День, на который действует курс (время = 00:00).
  DateTimeColumn get date => dateTime()();

  /// true — введён вручную (имеет приоритет), false — загружен из интернета.
  BoolColumn get isManual => boolean().withDefault(const Constant(false))();
}

@DataClassName('Account')
class Accounts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get type => textEnum<AccountType>()();
  TextColumn get currencyCode => text().references(Currencies, #code)();

  /// Остаток на момент начала учёта. Текущий баланс НЕ хранится —
  /// он всегда вычисляется: начальный остаток + все операции по счёту.
  IntColumn get initialBalance => integer().withDefault(const Constant(0))();
  IntColumn get color => integer()();

  /// Учитывать ли счёт в общем капитале.
  BoolColumn get includeInTotal =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

// Имя класса не "Category", чтобы не конфликтовать с аннотацией Category
// из package:flutter/foundation.dart.
@DataClassName('CategoryEntity')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 50)();
  TextColumn get type => textEnum<CategoryType>()();

  /// Родительская категория (для подкатегорий), null — категория верхнего уровня.
  IntColumn get parentId => integer().nullable().references(Categories, #id)();

  /// Ключ иконки из lib/core/app_icons.dart.
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
}

@DataClassName('Debt')
class Debts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get personName => text().withLength(min: 1, max: 50)();
  TextColumn get direction => textEnum<DebtDirection>()();

  /// Валюта долга. Остаток долга НЕ хранится — он вычисляется
  /// из связанных операций debtOut / debtIn.
  TextColumn get currencyCode => text().references(Currencies, #code)();

  /// Сумма долга, который был ещё до начала учёта (деньги через счета
  /// в приложении не проходили). Обычно 0.
  IntColumn get initialAmount => integer().withDefault(const Constant(0))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  BoolColumn get isClosed => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DataClassName('Operation')
@TableIndex(name: 'operations_date', columns: {#date})
@TableIndex(name: 'operations_account', columns: {#accountId})
@TableIndex(name: 'operations_to_account', columns: {#toAccountId})
@TableIndex(name: 'operations_category', columns: {#categoryId})
@TableIndex(name: 'operations_debt', columns: {#debtId})
class Operations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get type => textEnum<OperationType>()();
  DateTimeColumn get date => dateTime()();
  IntColumn get accountId => integer().references(Accounts, #id)();

  /// Сумма в валюте счёта [accountId], в минимальных единицах.
  /// Всегда > 0, кроме [OperationType.adjustment] (может быть отрицательной).
  IntColumn get amount => integer()();

  /// Категория — только для расходов и доходов.
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();

  /// Для перевода: счёт-получатель и сумма в его валюте.
  IntColumn get toAccountId =>
      integer().nullable().references(Accounts, #id)();
  IntColumn get toAmount => integer().nullable()();

  /// Для операций по долгу: долг и сумма в валюте долга
  /// (null — валюта совпадает с валютой счёта, сумма = [amount]).
  IntColumn get debtId => integer().nullable().references(Debts, #id)();
  IntColumn get debtAmount => integer().nullable()();

  TextColumn get note => text().withDefault(const Constant(''))();

  /// Получатель (магазин, кафе) для расхода или плательщик для дохода.
  /// Пустая строка — не указан. Отдельной таблицы нет: список получателей
  /// собирается из операций, переименование — замена во всех операциях.
  TextColumn get payee => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

/// Плановая (в том числе регулярная) операция: аренда, зарплата, подписка.
///
/// Даты повторений не хранятся — они вычисляются из [startDate] и правила
/// повтора (lib/domain/schedule.dart). [doneCount] — сколько повторений уже
/// проведено или пропущено; следующее — повторение номер [doneCount].
@DataClassName('PlannedOperation')
class PlannedOperations extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Только расход, доход или перевод.
  TextColumn get type => textEnum<OperationType>()();
  IntColumn get accountId => integer().references(Accounts, #id)();
  IntColumn get amount => integer()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get toAccountId =>
      integer().nullable().references(Accounts, #id)();
  IntColumn get toAmount => integer().nullable()();
  TextColumn get payee => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();

  /// Дата первого повторения (00:00).
  DateTimeColumn get startDate => dateTime()();
  TextColumn get repeatUnit => textEnum<RepeatUnit>()();

  /// Каждые N единиц: каждые 2 недели, каждые 3 месяца.
  IntColumn get repeatEvery => integer().withDefault(const Constant(1))();

  /// Последний день, когда может быть повторение (null — без окончания).
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get doneCount => integer().withDefault(const Constant(0))();

  /// Проводить автоматически в день платежа (при открытии приложения).
  BoolColumn get autoConfirm => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Месячный лимит расходов по категории.
@DataClassName('Budget')
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get categoryId =>
      integer().references(Categories, #id).unique()();
  IntColumn get monthlyLimit => integer()();
  TextColumn get currencyCode => text().references(Currencies, #code)();
}

/// Простые настройки "ключ — значение".
@DataClassName('Setting')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
