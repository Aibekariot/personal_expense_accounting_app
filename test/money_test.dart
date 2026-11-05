import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/core/money.dart';

const nbsp = ' ';

void main() {
  group('Money.format', () {
    test('целая сумма без копеек', () {
      expect(Money.format(150000, symbol: 'сом'), '1${nbsp}500$nbspсом');
    });

    test('сумма с дробной частью', () {
      expect(Money.format(150050, symbol: 'сом'), '1${nbsp}500,50$nbspсом');
      expect(Money.format(5, symbol: r'$'), '0,05$nbsp\$');
    });

    test('большие числа группируются по три', () {
      expect(Money.format(123456789000), '1${nbsp}234${nbsp}567${nbsp}890');
    });

    test('знак', () {
      expect(Money.format(-2500), '−25');
      expect(Money.format(2500, signed: true), '+25');
      expect(Money.format(0, signed: true), '0');
    });

    test('валюта без дробной части', () {
      expect(Money.format(1500, decimals: 0), '1${nbsp}500');
    });

    test('можно всегда показывать копейки', () {
      expect(Money.format(1000, trimZeroFraction: false), '10,00');
    });
  });

  group('Money.parse', () {
    test('запятая и точка', () {
      expect(Money.parse('1500,5'), 150050);
      expect(Money.parse('1500.5'), 150050);
      expect(Money.parse('0,05'), 5);
      expect(Money.parse(',5'), 50);
    });

    test('пробелы игнорируются', () {
      expect(Money.parse('1 500'), 150000);
      expect(Money.parse('1${nbsp}500,25'), 150025);
    });

    test('отрицательные', () {
      expect(Money.parse('-10'), -1000);
      expect(Money.parse('−10'), -1000);
    });

    test('некорректный ввод', () {
      expect(Money.parse(''), isNull);
      expect(Money.parse('abc'), isNull);
      expect(Money.parse('1,2,3'), isNull);
      expect(Money.parse('10,555'), isNull); // три знака после запятой
      expect(Money.parse('1234567890123'), isNull); // слишком большое
    });

    test('валюта без дробной части', () {
      expect(Money.parse('1500', decimals: 0), 1500);
      expect(Money.parse('1500,5', decimals: 0), isNull);
    });

    test('format и parse согласованы', () {
      for (final v in [0, 1, 99, 100, 150050, 123456789, -4200]) {
        expect(Money.parse(Money.format(v, trimZeroFraction: false)), v);
      }
    });
  });

  group('Money.convert', () {
    test('доллары в сомы', () {
      // 100 $ по курсу 87,45 = 8 745 сом
      expect(Money.convert(10000, rate: 87.45), 874500);
    });

    test('сомы в доллары с округлением', () {
      // 1 000 сом по курсу 1/87,45 = 11,435... $ → 11,44 $
      expect(Money.convert(100000, rate: 1 / 87.45), 1144);
    });

    test('разное число знаков после запятой', () {
      expect(Money.convert(1500, rate: 2, fromDecimals: 0, toDecimals: 2), 300000);
      expect(Money.convert(300050, rate: 0.5, fromDecimals: 2, toDecimals: 0), 1500);
    });
  });
}
