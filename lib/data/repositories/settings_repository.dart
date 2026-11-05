import '../db/app_database.dart';

/// Настройки приложения в таблице "ключ — значение".
class SettingsRepository {
  SettingsRepository(this._db);

  final AppDatabase _db;

  Stream<String?> watch(String key) =>
      (_db.select(_db.settings)..where((s) => s.key.equals(key)))
          .watchSingleOrNull()
          .map((s) => s?.value);

  Future<String?> get(String key) async =>
      (await (_db.select(_db.settings)..where((s) => s.key.equals(key)))
              .getSingleOrNull())
          ?.value;

  Future<void> set(String key, String value) => _db
      .into(_db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  // --- Основная валюта ---

  Stream<String> watchBaseCurrency() =>
      watch(SettingKeys.baseCurrency).map((v) => v ?? 'KGS');

  Future<String> baseCurrency() async =>
      await get(SettingKeys.baseCurrency) ?? 'KGS';

  Future<void> setBaseCurrency(String code) =>
      set(SettingKeys.baseCurrency, code);

  // --- Автообновление курсов ---

  Stream<bool> watchRatesAutoUpdate() =>
      watch(SettingKeys.ratesAutoUpdate).map((v) => v != 'false');

  Future<bool> ratesAutoUpdate() async =>
      await get(SettingKeys.ratesAutoUpdate) != 'false';

  Future<void> setRatesAutoUpdate(bool value) =>
      set(SettingKeys.ratesAutoUpdate, value.toString());

  Stream<DateTime?> watchRatesLastUpdate() =>
      watch(SettingKeys.ratesLastUpdate)
          .map((v) => v == null ? null : DateTime.tryParse(v));

  Future<DateTime?> ratesLastUpdate() async {
    final v = await get(SettingKeys.ratesLastUpdate);
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<void> setRatesLastUpdate(DateTime value) =>
      set(SettingKeys.ratesLastUpdate, value.toIso8601String());

  // --- Последний выбранный счёт (подставляется в новую операцию) ---

  Future<int?> lastAccountId() async =>
      int.tryParse(await get(SettingKeys.lastAccountId) ?? '');

  Future<void> setLastAccountId(int id) =>
      set(SettingKeys.lastAccountId, id.toString());

  // --- Резервная копия ---

  Stream<DateTime?> watchLastBackup() => watch(SettingKeys.lastBackup)
      .map((v) => v == null ? null : DateTime.tryParse(v));

  Future<void> setLastBackup(DateTime value) =>
      set(SettingKeys.lastBackup, value.toIso8601String());

  Stream<DateTime?> watchBackupSnoozeUntil() =>
      watch(SettingKeys.backupSnoozeUntil)
          .map((v) => v == null ? null : DateTime.tryParse(v));

  Future<void> setBackupSnoozeUntil(DateTime value) =>
      set(SettingKeys.backupSnoozeUntil, value.toIso8601String());
}
