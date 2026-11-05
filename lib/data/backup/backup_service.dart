import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

/// Ошибка чтения файла резервной копии (текст можно показать пользователю).
class BackupException implements Exception {
  BackupException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Содержимое файла резервной копии, уже проверенное.
class BackupData {
  BackupData._({
    required this.exportedAt,
    required this.currencies,
    required this.rates,
    required this.accounts,
    required this.categories,
    required this.debts,
    required this.operations,
    required this.budgets,
    required this.settings,
  });

  final DateTime? exportedAt;
  final List<Currency> currencies;
  final List<ExchangeRate> rates;
  final List<Account> accounts;
  final List<CategoryEntity> categories;
  final List<Debt> debts;
  final List<Operation> operations;
  final List<Budget> budgets;
  final List<Setting> settings;
}

/// Резервная копия всех данных в файл JSON и восстановление из него.
class BackupService {
  BackupService(this._db);

  final AppDatabase _db;

  static const appId = 'moi-finansy';

  /// Версия формата файла. Меняется, только если меняется сам формат.
  static const formatVersion = 1;

  Future<String> exportJson({DateTime? now}) async {
    List<Map<String, dynamic>> rows(List<DataClass> list) =>
        [for (final r in list) r.toJson()];

    final data = {
      'app': appId,
      'format': formatVersion,
      'schemaVersion': _db.schemaVersion,
      'exportedAt': (now ?? DateTime.now()).toIso8601String(),
      'tables': {
        'currencies': rows(await _db.select(_db.currencies).get()),
        'exchangeRates': rows(await _db.select(_db.exchangeRates).get()),
        'accounts': rows(await _db.select(_db.accounts).get()),
        'categories': rows(await _db.select(_db.categories).get()),
        'debts': rows(await _db.select(_db.debts).get()),
        'operations': rows(await _db.select(_db.operations).get()),
        'budgets': rows(await _db.select(_db.budgets).get()),
        'settings': rows(await _db.select(_db.settings).get()),
      },
    };
    return const JsonEncoder.withIndent(' ').convert(data);
  }

  /// Читает и проверяет файл. Бросает [BackupException], если файл не подходит.
  BackupData parse(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw BackupException('Это не файл резервной копии (файл повреждён или другого формата)');
    }
    if (decoded is! Map<String, dynamic> || decoded['app'] != appId) {
      throw BackupException('Это не файл резервной копии приложения «Мои финансы»');
    }
    final format = decoded['format'];
    final schema = decoded['schemaVersion'];
    if (format is! int || schema is! int) {
      throw BackupException('Файл резервной копии повреждён');
    }
    if (format > formatVersion || schema > _db.schemaVersion) {
      throw BackupException(
        'Копия сделана в более новой версии приложения. Обновите приложение '
        '(перезапустите его) и попробуйте снова.',
      );
    }
    final tables = decoded['tables'];
    if (tables is! Map<String, dynamic>) {
      throw BackupException('Файл резервной копии повреждён');
    }

    List<Map<String, dynamic>> table(String name) {
      final list = tables[name];
      if (list == null) return const [];
      if (list is! List) throw BackupException('Файл повреждён: раздел $name');
      return [for (final r in list) Map<String, dynamic>.from(r as Map)];
    }

    // Копии из старых версий: добавляем поля, которых тогда не было.
    final debts = table('debts');
    if (schema < 2) {
      for (final d in debts) {
        d.putIfAbsent('initialAmount', () => 0);
      }
    }

    try {
      return BackupData._(
        exportedAt: DateTime.tryParse(decoded['exportedAt']?.toString() ?? ''),
        currencies: table('currencies').map(Currency.fromJson).toList(),
        rates: table('exchangeRates').map(ExchangeRate.fromJson).toList(),
        accounts: table('accounts').map(Account.fromJson).toList(),
        categories: table('categories').map(CategoryEntity.fromJson).toList(),
        debts: debts.map(Debt.fromJson).toList(),
        operations: table('operations').map(Operation.fromJson).toList(),
        budgets: table('budgets').map(Budget.fromJson).toList(),
        settings: table('settings').map(Setting.fromJson).toList(),
      );
    } catch (e) {
      throw BackupException('Файл резервной копии повреждён ($e)');
    }
  }

  /// Заменяет ВСЕ данные данными из копии. Всё в одной транзакции:
  /// если что-то пойдёт не так, текущие данные останутся как были.
  Future<void> restore(BackupData data) async {
    if (data.currencies.isEmpty) {
      throw BackupException('В копии нет валют — восстанавливать нечего');
    }
    // Сначала основные категории, потом подкатегории (они ссылаются на основные).
    final categories = [
      ...data.categories.where((c) => c.parentId == null),
      ...data.categories.where((c) => c.parentId != null),
    ];
    try {
      await _db.transaction(() async {
        for (final table in <TableInfo<Table, Object?>>[
          _db.operations,
          _db.budgets,
          _db.debts,
          _db.categories,
          _db.accounts,
          _db.exchangeRates,
          _db.currencies,
          _db.settings,
        ]) {
          await _db.delete(table).go();
        }
        await _db.batch((b) {
          b.insertAll(_db.currencies, data.currencies);
          b.insertAll(_db.settings, data.settings);
          b.insertAll(_db.exchangeRates, data.rates);
          b.insertAll(_db.accounts, data.accounts);
          b.insertAll(_db.categories, categories);
          b.insertAll(_db.debts, data.debts);
          b.insertAll(_db.operations, data.operations);
          b.insertAll(_db.budgets, data.budgets);
        });
      });
    } on BackupException {
      rethrow;
    } catch (e) {
      throw BackupException('Не удалось восстановить: в копии нарушены связи данных ($e)');
    }
  }
}
