import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_utils.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/rates/rate_book.dart';

/// Счёт вместе с валютой и текущим балансом.
class AccountView {
  const AccountView({
    required this.account,
    required this.currency,
    required this.balance,
    required this.balanceInBase,
  });

  final Account account;
  final Currency currency;

  /// Баланс в валюте счёта.
  final int balance;

  /// Баланс в основной валюте (null — нет курса).
  final int? balanceInBase;
}

/// Сумма по одной валюте (сколько всего долларов, сколько сомов).
class CurrencyTotal {
  const CurrencyTotal(this.currency, this.amount);

  final Currency currency;
  final int amount;
}

/// Всё, что нужно экрану «Счета».
class AccountsOverview {
  const AccountsOverview({
    required this.base,
    required this.active,
    required this.archived,
    required this.capital,
    required this.byCurrency,
    required this.missingRates,
  });

  final Currency base;
  final List<AccountView> active;
  final List<AccountView> archived;

  /// Общий капитал в основной валюте: активные счета с «учитывать в капитале».
  final int capital;

  /// Тот же капитал, но по валютам, без пересчёта.
  final List<CurrencyTotal> byCurrency;

  /// Валюты без курса к основной — они не вошли в [capital].
  final List<String> missingRates;

  factory AccountsOverview.build({
    required List<Account> accounts,
    required Map<int, int> balances,
    required List<Currency> currencies,
    required String baseCode,
    required RateBook rates,
  }) {
    final byCode = {for (final c in currencies) c.code: c};
    Currency currencyOf(String code) =>
        byCode[code] ??
        Currency(code: code, name: code, symbol: code, decimals: 2, sortOrder: 0);
    final base = currencyOf(baseCode);

    final active = <AccountView>[];
    final archived = <AccountView>[];
    final totals = <String, int>{};

    for (final a in accounts) {
      final currency = currencyOf(a.currencyCode);
      final balance = balances[a.id] ?? a.initialBalance;
      final view = AccountView(
        account: a,
        currency: currency,
        balance: balance,
        balanceInBase: rates.convert(balance, currency, base),
      );
      if (a.isArchived) {
        archived.add(view);
      } else {
        active.add(view);
        if (a.includeInTotal) {
          totals[a.currencyCode] = (totals[a.currencyCode] ?? 0) + balance;
        }
      }
    }

    var capital = 0;
    final missing = <String>[];
    for (final e in totals.entries) {
      final converted = rates.convert(e.value, currencyOf(e.key), base);
      if (converted == null) {
        missing.add(e.key);
      } else {
        capital += converted;
      }
    }

    // Основная валюта первой, остальные — в порядке справочника валют.
    final order = [baseCode, ...currencies.map((c) => c.code).where((c) => c != baseCode)];
    final byCurrency = [
      for (final code in order)
        if (totals.containsKey(code)) CurrencyTotal(currencyOf(code), totals[code]!),
    ];

    return AccountsOverview(
      base: base,
      active: active,
      archived: archived,
      capital: capital,
      byCurrency: byCurrency,
      missingRates: missing,
    );
  }
}

final accountsOverviewProvider = Provider<AsyncValue<AccountsOverview>>((ref) {
  final accounts = ref.watch(accountsProvider);
  final balances = ref.watch(accountBalancesProvider);
  final currencies = ref.watch(currenciesProvider);
  final base = ref.watch(baseCurrencyCodeProvider);
  final rates = ref.watch(rateBookProvider);
  return combineAsync(
    [accounts, balances, currencies, base, rates],
    () => AccountsOverview.build(
      accounts: accounts.requireValue,
      balances: balances.requireValue,
      currencies: currencies.requireValue,
      baseCode: base.requireValue,
      rates: rates.requireValue,
    ),
  );
});
