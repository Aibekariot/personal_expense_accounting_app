import 'dart:convert';

import 'package:http/http.dart' as http;

/// Курсы всех валют к доллару на дату: 1 USD = rates[код].
class UsdRates {
  const UsdRates(this.date, this.rates);

  final DateTime date;
  final Map<String, double> rates;
}

class RatesApiException implements Exception {
  const RatesApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Загрузка курсов из бесплатного открытого источника
/// (github.com/fawazahmed0/exchange-api): без ключа, обновляется ежедневно,
/// разрешает запросы из браузера, есть сом (KGS).
class RatesApi {
  RatesApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _urls = [
    'https://latest.currency-api.pages.dev/v1/currencies/usd.json',
    'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.json',
  ];

  /// Пробует источники по очереди, пока один не ответит.
  Future<UsdRates> fetchUsdRates() async {
    Object? lastError;
    for (final url in _urls) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 10));
        if (response.statusCode != 200) {
          lastError = 'HTTP ${response.statusCode}';
          continue;
        }
        return parse(utf8.decode(response.bodyBytes));
      } catch (e) {
        lastError = e;
      }
    }
    throw RatesApiException('Не удалось загрузить курсы: $lastError');
  }

  /// Разбирает ответ вида `{"date": "2026-11-05", "usd": {"kgs": 87.45, ...}}`.
  static UsdRates parse(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final date = DateTime.parse(json['date'] as String);
    final raw = json['usd'] as Map<String, dynamic>;
    final rates = <String, double>{
      for (final e in raw.entries)
        if (e.value is num && (e.value as num) > 0)
          e.key.toUpperCase(): (e.value as num).toDouble(),
    };
    rates['USD'] = 1;
    return UsdRates(DateTime(date.year, date.month, date.day), rates);
  }
}
