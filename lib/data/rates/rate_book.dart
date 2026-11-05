import '../../core/money.dart';
import '../db/app_database.dart';

/// Котировка: 1 единица исходной валюты = [rate] единиц целевой.
class Quote {
  const Quote(this.rate, {this.date, this.isManual = false});

  final double rate;

  /// Дата курса (для пересчёта через третью валюту — самая старая из двух).
  final DateTime? date;
  final bool isManual;

  Quote get inverse => Quote(1 / rate, date: date, isManual: isManual);
}

/// Справочник курсов: умеет пересчитывать любую валюту в любую.
///
/// Ищет курс так:
/// 1. прямой (USD→KGS);
/// 2. обратный (KGS→USD, тогда берётся 1/курс);
/// 3. через третью валюту (EUR→USD→KGS).
class RateBook {
  RateBook._(this._quotes);

  /// Пустой справочник: пересчитать можно только валюту саму в себя.
  RateBook.empty() : _quotes = const {};

  /// Строит справочник из записей курсов.
  ///
  /// Для каждой пары берётся последний курс не позже даты [at]
  /// (если [at] не задана — самый свежий). Если курсов до [at] нет —
  /// самый ранний после неё. При одинаковой дате ручной курс важнее загруженного.
  factory RateBook.fromRates(Iterable<ExchangeRate> rates, {DateTime? at}) {
    final best = <(String, String), ExchangeRate>{};
    for (final r in rates) {
      if (r.fromCode == r.toCode || r.rate <= 0 || !r.rate.isFinite) continue;
      final key = (r.fromCode, r.toCode);
      final current = best[key];
      if (current == null || _isBetter(r, current, at)) best[key] = r;
    }
    return RateBook._({
      for (final e in best.entries)
        e.key: Quote(e.value.rate, date: e.value.date, isManual: e.value.isManual),
    });
  }

  final Map<(String, String), Quote> _quotes;

  static bool _isBetter(ExchangeRate a, ExchangeRate b, DateTime? at) {
    if (at != null) {
      final aFits = !a.date.isAfter(at);
      final bFits = !b.date.isAfter(at);
      if (aFits != bFits) return aFits;
      if (!aFits) {
        // Оба курса позже нужной даты — берём ближайший, то есть более ранний.
        final c = a.date.compareTo(b.date);
        if (c != 0) return c < 0;
        return _tieBreak(a, b);
      }
    }
    final c = a.date.compareTo(b.date);
    if (c != 0) return c > 0;
    return _tieBreak(a, b);
  }

  static bool _tieBreak(ExchangeRate a, ExchangeRate b) {
    if (a.isManual != b.isManual) return a.isManual;
    return a.id > b.id;
  }

  /// Курс [from] → [to] или null, если пересчитать нельзя.
  Quote? quote(String from, String to) {
    if (from == to) return const Quote(1);
    final direct = _direct(from, to);
    if (direct != null) return direct;

    Quote? best;
    for (final pivot in _codes()) {
      if (pivot == from || pivot == to) continue;
      final a = _direct(from, pivot);
      if (a == null) continue;
      final b = _direct(pivot, to);
      if (b == null) continue;
      final q = Quote(
        a.rate * b.rate,
        date: _older(a.date, b.date),
        isManual: a.isManual || b.isManual,
      );
      if (best == null || _newer(q.date, best.date)) best = q;
    }
    return best;
  }

  /// Пересчитывает сумму [amount] (в минимальных единицах [from])
  /// в валюту [to]. null — если курса нет.
  int? convert(int amount, Currency from, Currency to) {
    if (from.code == to.code) return amount;
    final q = quote(from.code, to.code);
    if (q == null) return null;
    return Money.convert(
      amount,
      rate: q.rate,
      fromDecimals: from.decimals,
      toDecimals: to.decimals,
    );
  }

  Quote? _direct(String from, String to) {
    final straight = _quotes[(from, to)];
    final reverse = _quotes[(to, from)]?.inverse;
    if (straight == null) return reverse;
    if (reverse == null) return straight;
    // Есть оба направления — берём более свежий.
    if (_newer(reverse.date, straight.date)) return reverse;
    if (_newer(straight.date, reverse.date)) return straight;
    return straight.isManual || !reverse.isManual ? straight : reverse;
  }

  Iterable<String> _codes() => {for (final k in _quotes.keys) ...[k.$1, k.$2]};

  static bool _newer(DateTime? a, DateTime? b) =>
      a != null && (b == null || a.isAfter(b));

  static DateTime? _older(DateTime? a, DateTime? b) {
    if (a == null) return b;
    if (b == null) return a;
    return a.isBefore(b) ? a : b;
  }
}
