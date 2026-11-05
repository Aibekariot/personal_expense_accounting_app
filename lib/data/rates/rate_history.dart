import '../db/app_database.dart';
import 'rate_book.dart';

/// История курсов: быстро даёт справочник курсов на любую дату.
///
/// Нужна для статистики и бюджетов: расход в долларах от 3 октября
/// пересчитывается в сомы по курсу на 3 октября, а не по сегодняшнему.
/// Результат совпадает с `RateBook.fromRates(rates, at: date)`,
/// но считается быстрее и кешируется по дням.
class RateHistory {
  RateHistory(Iterable<ExchangeRate> rates) {
    for (final r in rates) {
      if (r.fromCode == r.toCode || r.rate <= 0 || !r.rate.isFinite) continue;
      _byPair.putIfAbsent((r.fromCode, r.toCode), () => []).add(r);
    }
    for (final list in _byPair.values) {
      // По дате, при равной дате ручной курс и более новая запись — позже.
      list.sort((a, b) {
        final c = a.date.compareTo(b.date);
        if (c != 0) return c;
        if (a.isManual != b.isManual) return a.isManual ? 1 : -1;
        return a.id.compareTo(b.id);
      });
    }
  }

  RateHistory.empty();

  final Map<(String, String), List<ExchangeRate>> _byPair = {};
  final Map<DateTime, RateBook> _cache = {};

  /// Самые свежие курсы.
  late final RateBook latest =
      RateBook.fromRates([for (final list in _byPair.values) list.last]);

  /// Справочник курсов на день [date].
  RateBook at(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return _cache.putIfAbsent(day, () => RateBook.fromRates(_pick(day)));
  }

  Iterable<ExchangeRate> _pick(DateTime day) sync* {
    for (final list in _byPair.values) {
      // Первый курс позже нужного дня.
      var lo = 0, hi = list.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (list[mid].date.isAfter(day)) {
          hi = mid;
        } else {
          lo = mid + 1;
        }
      }
      if (lo > 0) {
        yield list[lo - 1]; // последний не позже дня
      } else {
        // Все курсы позже — берём самый ранний (лучший из записей этого дня).
        var j = 0;
        while (j + 1 < list.length && list[j + 1].date == list[0].date) {
          j++;
        }
        yield list[j];
      }
    }
  }
}
