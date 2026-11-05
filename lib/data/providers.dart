import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backup/backup_service.dart';
import 'db/app_database.dart';
import 'db/database_provider.dart';
import 'rates/rate_book.dart';
import 'rates/rate_history.dart';
import 'rates/rates_api.dart';
import 'repositories/account_repository.dart';
import 'repositories/budget_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/currency_repository.dart';
import 'repositories/debt_repository.dart';
import 'repositories/operation_repository.dart';
import 'repositories/plan_repository.dart';
import 'repositories/rates_repository.dart';
import 'repositories/settings_repository.dart';

// --- Репозитории ---

final settingsRepositoryProvider =
    Provider((ref) => SettingsRepository(ref.watch(databaseProvider)));

final currencyRepositoryProvider =
    Provider((ref) => CurrencyRepository(ref.watch(databaseProvider)));

final ratesApiProvider = Provider((ref) => RatesApi());

final ratesRepositoryProvider = Provider(
  (ref) => RatesRepository(
    ref.watch(databaseProvider),
    ref.watch(ratesApiProvider),
    ref.watch(settingsRepositoryProvider),
  ),
);

final accountRepositoryProvider =
    Provider((ref) => AccountRepository(ref.watch(databaseProvider)));

final operationRepositoryProvider =
    Provider((ref) => OperationRepository(ref.watch(databaseProvider)));

final categoryRepositoryProvider =
    Provider((ref) => CategoryRepository(ref.watch(databaseProvider)));

final budgetRepositoryProvider =
    Provider((ref) => BudgetRepository(ref.watch(databaseProvider)));

final debtRepositoryProvider = Provider(
  (ref) => DebtRepository(
    ref.watch(databaseProvider),
    ref.watch(operationRepositoryProvider),
  ),
);

final planRepositoryProvider = Provider(
  (ref) => PlanRepository(
    ref.watch(databaseProvider),
    ref.watch(operationRepositoryProvider),
  ),
);

final backupServiceProvider =
    Provider((ref) => BackupService(ref.watch(databaseProvider)));

// --- Данные, которые обновляются сами при изменении базы ---

final currenciesProvider = StreamProvider<List<Currency>>(
  (ref) => ref.watch(currencyRepositoryProvider).watchAll(),
);

final baseCurrencyCodeProvider = StreamProvider<String>(
  (ref) => ref.watch(settingsRepositoryProvider).watchBaseCurrency(),
);

final ratesProvider = StreamProvider<List<ExchangeRate>>(
  (ref) => ref.watch(ratesRepositoryProvider).watchAll(),
);

/// История курсов: курс на любую дату (для статистики и бюджетов).
final rateHistoryProvider = Provider<AsyncValue<RateHistory>>(
  (ref) => ref.watch(ratesProvider).whenData(RateHistory.new),
);

/// Справочник самых свежих курсов.
final rateBookProvider = Provider<AsyncValue<RateBook>>(
  (ref) => ref.watch(rateHistoryProvider).whenData((h) => h.latest),
);

final ratesAutoUpdateProvider = StreamProvider<bool>(
  (ref) => ref.watch(settingsRepositoryProvider).watchRatesAutoUpdate(),
);

final ratesLastUpdateProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchRatesLastUpdate(),
);

final accountsProvider = StreamProvider<List<Account>>(
  (ref) => ref.watch(accountRepositoryProvider).watchAll(),
);

final accountBalancesProvider = StreamProvider<Map<int, int>>(
  (ref) => ref.watch(accountRepositoryProvider).watchBalances(),
);

final operationsProvider = StreamProvider<List<Operation>>(
  (ref) => ref.watch(operationRepositoryProvider).watchAll(),
);

final categoriesProvider = StreamProvider<List<CategoryEntity>>(
  (ref) => ref.watch(categoryRepositoryProvider).watchAll(),
);

final budgetsProvider = StreamProvider<List<Budget>>(
  (ref) => ref.watch(budgetRepositoryProvider).watchAll(),
);

final debtsProvider = StreamProvider<List<Debt>>(
  (ref) => ref.watch(debtRepositoryProvider).watchAll(),
);

final lastBackupProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchLastBackup(),
);

final backupSnoozeUntilProvider = StreamProvider<DateTime?>(
  (ref) => ref.watch(settingsRepositoryProvider).watchBackupSnoozeUntil(),
);

final plansProvider = StreamProvider<List<PlannedOperation>>(
  (ref) => ref.watch(planRepositoryProvider).watchAll(),
);
