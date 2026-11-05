import 'package:drift/drift.dart';

import 'app_database.dart';

/// Начальные данные при первом запуске: валюты, счета, категории.
/// Пользователь может всё переименовать, удалить или добавить своё.
Future<void> seedDefaults(AppDatabase db) async {
  await db.batch((b) {
    b.insertAll(db.currencies, [
      _currency('KGS', 'Кыргызский сом', 'сом', 0),
      _currency('USD', 'Доллар США', r'$', 1),
      _currency('EUR', 'Евро', '€', 2),
      _currency('RUB', 'Российский рубль', '₽', 3),
      _currency('KZT', 'Казахстанский тенге', '₸', 4),
    ]);

    b.insert(
      db.settings,
      SettingsCompanion.insert(key: SettingKeys.baseCurrency, value: 'KGS'),
    );

    b.insertAll(db.accounts, [
      AccountsCompanion.insert(
        name: 'Наличные',
        type: AccountType.cash,
        currencyCode: 'KGS',
        color: 0xFF43A047,
        sortOrder: const Value(0),
      ),
      AccountsCompanion.insert(
        name: 'Карта',
        type: AccountType.card,
        currencyCode: 'KGS',
        color: 0xFF1E88E5,
        sortOrder: const Value(1),
      ),
    ]);
  });

  var order = 0;
  for (final c in _expenseCategories) {
    await _insertCategory(db, c, CategoryType.expense, order++);
  }
  order = 0;
  for (final c in _incomeCategories) {
    await _insertCategory(db, c, CategoryType.income, order++);
  }
}

CurrenciesCompanion _currency(String code, String name, String symbol, int order) =>
    CurrenciesCompanion.insert(
      code: code,
      name: name,
      symbol: symbol,
      sortOrder: Value(order),
    );

Future<void> _insertCategory(
  AppDatabase db,
  _Cat c,
  CategoryType type,
  int order,
) async {
  final parentId = await db.into(db.categories).insert(
    CategoriesCompanion.insert(
      name: c.name,
      type: type,
      icon: c.icon,
      color: c.color,
      sortOrder: Value(order),
    ),
  );
  var childOrder = 0;
  for (final child in c.children) {
    await db.into(db.categories).insert(
      CategoriesCompanion.insert(
        name: child,
        type: type,
        parentId: Value(parentId),
        icon: c.icon,
        color: c.color,
        sortOrder: Value(childOrder++),
      ),
    );
  }
}

class _Cat {
  const _Cat(this.name, this.icon, this.color, [this.children = const []]);
  final String name;
  final String icon;
  final int color;
  final List<String> children;
}

const _expenseCategories = [
  _Cat('Продукты', 'shopping_cart', 0xFF43A047),
  _Cat('Кафе и рестораны', 'restaurant', 0xFFFB8C00),
  _Cat('Транспорт', 'directions_bus', 0xFF1E88E5, ['Такси', 'Общественный транспорт']),
  _Cat('Авто', 'directions_car', 0xFF546E7A, ['Топливо', 'Обслуживание и ремонт']),
  _Cat('Дом и ЖКХ', 'home', 0xFF8D6E63, ['Аренда', 'Коммунальные услуги']),
  _Cat('Связь и интернет', 'wifi', 0xFF00ACC1),
  _Cat('Здоровье', 'medical', 0xFFE53935, ['Аптека', 'Врачи']),
  _Cat('Одежда и обувь', 'checkroom', 0xFF8E24AA),
  _Cat('Красота и уход', 'spa', 0xFFEC407A),
  _Cat('Развлечения', 'movie', 0xFF5E35B1),
  _Cat('Подписки', 'subscriptions', 0xFF3949AB),
  _Cat('Образование', 'school', 0xFF00897B),
  _Cat('Дети', 'child_care', 0xFFFDD835),
  _Cat('Подарки', 'gift', 0xFFD81B60),
  _Cat('Путешествия', 'flight', 0xFF039BE5),
  _Cat('Прочее', 'more', 0xFF757575),
];

const _incomeCategories = [
  _Cat('Зарплата', 'work', 0xFF43A047),
  _Cat('Подработка', 'handyman', 0xFF7CB342),
  _Cat('Подарки', 'gift', 0xFFD81B60),
  _Cat('Проценты и кэшбэк', 'savings', 0xFF00897B),
  _Cat('Прочее', 'more', 0xFF757575),
];
