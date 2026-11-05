import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../rates/rates_api.dart';
import 'settings_repository.dart';

/// Итог загрузки курсов из интернета.
class RatesUpdateResult {
  const RatesUpdateResult({required this.updated, required this.notFound});

  /// Валюты, для которых курс обновлён.
  final List<String> updated;

  /// Валюты, которых нет в источнике (свои валюты) — им нужен ручной курс.
  final List<String> notFound;
}

class RatesRepository {
  RatesRepository(this._db, this._api, this._settings);

  final AppDatabase _db;
  final RatesApi _api;
  final SettingsRepository _settings;

  /// Как часто обновлять курсы автоматически.
  static const autoUpdateInterval = Duration(hours: 6);

  Stream<List<ExchangeRate>> watchAll() =>
      _db.select(_db.exchangeRates).watch();

  /// Ручной курс: 1 [from] = [rate] [to] на дату [date].
  /// Заменяет ручной курс этой пары на ту же дату, если он был.
  Future<void> setManual({
    required String from,
    required String to,
    required double rate,
    required DateTime date,
  }) {
    final day = DateTime(date.year, date.month, date.day);
    return _db.transaction(() async {
      await (_db.delete(_db.exchangeRates)
            ..where(
              (r) =>
                  r.fromCode.equals(from) &
                  r.toCode.equals(to) &
                  r.date.equals(day) &
                  r.isManual.equals(true),
            ))
          .go();
      await _db.into(_db.exchangeRates).insert(
        ExchangeRatesCompanion.insert(
          fromCode: from,
          toCode: to,
          rate: rate,
          date: day,
          isManual: const Value(true),
        ),
      );
    });
  }

  Future<void> deleteRate(int id) =>
      (_db.delete(_db.exchangeRates)..where((r) => r.id.equals(id))).go();

  /// Загружает курсы из интернета для всех валют пользователя
  /// (относительно основной валюты) и сохраняет их.
  Future<RatesUpdateResult> updateFromInternet() async {
    final usd = await _api.fetchUsdRates();
    final base = await _settings.baseCurrency();
    final codes = (await _db.select(_db.currencies).get()).map((c) => c.code);

    final baseRate = usd.rates[base];
    if (baseRate == null) {
      throw RatesApiException(
        'Основной валюты $base нет в источнике курсов — курсы нужно вводить вручную',
      );
    }

    final updated = <String>[];
    final notFound = <String>[];
    await _db.transaction(() async {
      for (final code in codes) {
        if (code == base) continue;
        final codeRate = usd.rates[code];
        if (codeRate == null) {
          notFound.add(code);
          continue;
        }
        // 1 code = (сколько base за 1 USD) / (сколько code за 1 USD) base.
        final rate = baseRate / codeRate;
        await (_db.delete(_db.exchangeRates)
              ..where(
                (r) =>
                    r.fromCode.equals(code) &
                    r.toCode.equals(base) &
                    r.date.equals(usd.date) &
                    r.isManual.equals(false),
              ))
            .go();
        await _db.into(_db.exchangeRates).insert(
          ExchangeRatesCompanion.insert(
            fromCode: code,
            toCode: base,
            rate: rate,
            date: usd.date,
          ),
        );
        updated.add(code);
      }
    });
    await _settings.setRatesLastUpdate(DateTime.now());
    return RatesUpdateResult(updated: updated, notFound: notFound);
  }

  /// Тихо обновляет курсы при запуске, если включено автообновление
  /// и с прошлого обновления прошло больше [autoUpdateInterval].
  /// Ошибки (например, нет интернета) игнорируются.
  Future<void> updateIfStale() async {
    try {
      if (!await _settings.ratesAutoUpdate()) return;
      final last = await _settings.ratesLastUpdate();
      if (last != null && DateTime.now().difference(last) < autoUpdateInterval) {
        return;
      }
      await updateFromInternet();
    } catch (_) {
      // Нет интернета — не страшно, используем последние сохранённые курсы.
    }
  }
}
