import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'seed.dart';
import 'tables.dart';

export 'tables.dart';

part 'app_database.g.dart';

/// Ключи таблицы настроек.
abstract final class SettingKeys {
  static const baseCurrency = 'base_currency';
  static const ratesAutoUpdate = 'rates_auto_update';
  static const ratesLastUpdate = 'rates_last_update';
  static const lastAccountId = 'last_account_id';
  static const lastBackup = 'last_backup';
  static const backupSnoozeUntil = 'backup_snooze_until';
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedDefaults(this);
    },
    onUpgrade: (m, from, to) async {
      // v2: начальная сумма долга (долги, которые были до начала учёта).
      if (from < 2) await m.addColumn(debts, debts.initialAmount);
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
