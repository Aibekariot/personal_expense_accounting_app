import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'seed.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Ключи таблицы настроек.
abstract final class SettingKeys {
  static const baseCurrency = 'base_currency';
}

@DriftDatabase(
  tables: [
    Currencies,
    ExchangeRates,
    Accounts,
    Categories,
    Debts,
    Operations,
    Budgets,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// [executor] можно передать в тестах (например, базу в памяти).
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDefaults(this);
    },
    beforeOpen: (details) async {
      // Без этого SQLite не проверяет связи между таблицами.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'finance',
      // В браузере база работает через WebAssembly. Файлы лежат в web/,
      // их версии должны совпадать с версиями пакетов sqlite3 и drift.
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
    );
  }
}
