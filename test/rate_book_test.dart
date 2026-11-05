import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/data/db/app_database.dart';
import 'package:personal_expense_accounting/data/rates/rate_book.dart';
import 'package:personal_expense_accounting/data/rates/rates_api.dart';

var _id = 0;
ExchangeRate rate(String from, String to, double r, DateTime date, {bool manual = false}) =>
    ExchangeRate(id: ++_id, fromCode: from, toCode: to, rate: r, date: date, isManual: manual);

const kgs = Currency(code: 'KGS', name: 'Сом', symbol: 'сом', decimals: 2, sortOrder: 0);
const usd = Currency(code: 'USD', name: 'Доллар', symbol: r'$', decimals: 2, sortOrder: 1);
const gold = Currency(code: 'GOLD', name: 'Золото', symbol: 'г', decimals: 0, sortOrder: 2);

void main() {
  final nov4 = DateTime(2026, 11, 4);
  final nov5 = DateTime(2026, 11, 5);

  test('валюта сама в себя — курс 1', () {
    expect(RateBook.empty().quote('KGS', 'KGS')!.rate, 1);
    expect(RateBook.empty().quote('USD', 'KGS'), isNull);
  });

  test('прямой и обратный курс', () {
    final book = RateBook.fromRates([rate('USD', 'KGS', 87.5, nov5)]);
    expect(book.quote('USD', 'KGS')!.rate, 87.5);
    expect(book.quote('KGS', 'USD')!.rate, closeTo(1 / 87.5, 1e-12));
  });

  test('берётся самый свежий курс', () {
    final book = RateBook.fromRates([
      rate('USD', 'KGS', 87.0, nov4),
      rate('USD', 'KGS', 88.0, nov5),
    ]);
    expect(book.quote('USD', 'KGS')!.rate, 88.0);
  });

  test('в один день ручной курс важнее загруженного', () {
    final book = RateBook.fromRates([
      rate('USD', 'KGS', 87.45, nov5, manual: true),
      rate('USD', 'KGS', 87.60, nov5),
    ]);
    final q = book.quote('USD', 'KGS')!;
    expect(q.rate, 87.45);
    expect(q.isManual, isTrue);
  });

  test('курс на дату: последний не позже этой даты', () {
    final rates = [
      rate('USD', 'KGS', 86.0, DateTime(2026, 10, 1)),
      rate('USD', 'KGS', 87.0, DateTime(2026, 10, 15)),
      rate('USD', 'KGS', 88.0, DateTime(2026, 11, 1)),
    ];
    expect(RateBook.fromRates(rates, at: DateTime(2026, 10, 20)).quote('USD', 'KGS')!.rate, 87.0);
    // Раньше всех курсов — берётся самый ранний.
    expect(RateBook.fromRates(rates, at: DateTime(2026, 9, 1)).quote('USD', 'KGS')!.rate, 86.0);
  });

  test('пересчёт через третью валюту', () {
    // 1 EUR = 1,1 USD; 1 USD = 87,5 KGS → 1 EUR = 96,25 KGS.
    final book = RateBook.fromRates([
      rate('EUR', 'USD', 1.1, nov5),
      rate('USD', 'KGS', 87.5, nov5),
    ]);
    expect(book.quote('EUR', 'KGS')!.rate, closeTo(96.25, 1e-9));
    expect(book.quote('KGS', 'EUR')!.rate, closeTo(1 / 96.25, 1e-12));
  });

  test('если курсы есть в обе стороны — берётся более свежий', () {
    final book = RateBook.fromRates([
      rate('USD', 'KGS', 87.0, nov4),
      rate('KGS', 'USD', 1 / 90.0, nov5),
    ]);
    expect(book.quote('USD', 'KGS')!.rate, closeTo(90.0, 1e-9));
  });

  test('convert учитывает знаки после запятой', () {
    final book = RateBook.fromRates([
      rate('USD', 'KGS', 87.45, nov5),
      rate('GOLD', 'KGS', 9000, nov5, manual: true),
    ]);
    expect(book.convert(10000, usd, kgs), 874500); // 100 $ = 8 745 сом
    expect(book.convert(3, gold, kgs), 2700000); // 3 г = 27 000 сом
    expect(book.convert(500, kgs, kgs), 500);
    expect(RateBook.empty().convert(100, usd, kgs), isNull);
  });

  test('разбор ответа источника курсов', () {
    final r = RatesApi.parse('{"date":"2026-11-05","usd":{"kgs":87.45,"eur":0.92,"bad":"x","zero":0}}');
    expect(r.date, DateTime(2026, 11, 5));
    expect(r.rates['KGS'], 87.45);
    expect(r.rates['EUR'], 0.92);
    expect(r.rates['USD'], 1);
    expect(r.rates.containsKey('BAD'), isFalse);
    expect(r.rates.containsKey('ZERO'), isFalse);
  });
}
