import '../core/money.dart';

/// Калькулятор в поле суммы: «350+120», «1500×3», «10000÷4».
///
/// Считает точно (дробями из целых чисел, без double), результат
/// округляется до минимальных единиц валюты (тыйыны, центы).

const _plus = '+';
const _minus = '−';
const _times = '×';
const _divide = '÷';
const operators = {_plus, _minus, _times, _divide};

/// Точная дробь n/d.
class _Fraction {
  _Fraction(BigInt n, BigInt d)
      : n = d.isNegative ? -n : n,
        d = d.abs();

  final BigInt n;
  final BigInt d;

  _Fraction operator +(_Fraction o) => _Fraction(n * o.d + o.n * d, d * o.d);
  _Fraction operator -(_Fraction o) => _Fraction(n * o.d - o.n * d, d * o.d);
  _Fraction operator *(_Fraction o) => _Fraction(n * o.n, d * o.d);
  _Fraction? divide(_Fraction o) => o.n == BigInt.zero ? null : _Fraction(n * o.d, d * o.n);

  /// В минимальные единицы с округлением «половина — от нуля».
  BigInt toMinor(int decimals) {
    final scaled = n * BigInt.from(Money.factor(decimals));
    final q = scaled ~/ d;
    final r = scaled.remainder(d).abs() * BigInt.two;
    if (r >= d) return scaled.isNegative ? q - BigInt.one : q + BigInt.one;
    return q;
  }
}

/// Есть ли в выражении действие (а не просто число).
bool hasOperator(String expr) {
  final body = expr.startsWith(_minus) ? expr.substring(1) : expr;
  return body.split('').any(operators.contains);
}

/// Вычисляет выражение. Возвращает сумму в минимальных единицах или null,
/// если выражение неполное или неверное (например, деление на ноль).
int? evaluateAmount(String expr, {required int decimals}) {
  final s = expr
      .replaceAll(RegExp(r'\s'), '')
      .replaceAll('-', _minus)
      .replaceAll('*', _times)
      .replaceAll('/', _divide)
      .replaceAll('.', ',');
  if (s.isEmpty) return null;

  // Разбор: [число, действие, число, действие, ...]
  final tokens = <Object>[];
  var i = 0;
  var negative = false;
  if (s.startsWith(_minus)) {
    negative = true;
    i = 1;
  }
  while (i < s.length) {
    final m = RegExp(r'(\d*)(?:,(\d*))?').matchAsPrefix(s, i);
    final whole = m?.group(1) ?? '';
    final frac = m?.group(2) ?? '';
    if (m == null || (whole.isEmpty && frac.isEmpty)) return null;
    final digits = BigInt.parse('$whole$frac'.isEmpty ? '0' : '$whole$frac');
    var value = _Fraction(digits, BigInt.from(10).pow(frac.length));
    if (negative) {
      value = _Fraction(-value.n, value.d);
      negative = false;
    }
    tokens.add(value);
    i = m.end;
    if (i == s.length) break;
    final op = s[i];
    if (!operators.contains(op)) return null;
    tokens.add(op);
    i++;
    if (i == s.length) return null; // «350+» — выражение не закончено
  }

  // Сначала × и ÷, потом + и −.
  final sums = <Object>[tokens.first];
  for (var k = 1; k < tokens.length; k += 2) {
    final op = tokens[k] as String;
    final right = tokens[k + 1] as _Fraction;
    if (op == _times || op == _divide) {
      final left = sums.removeLast() as _Fraction;
      final r = op == _times ? left * right : left.divide(right);
      if (r == null) return null;
      sums.add(r);
    } else {
      sums
        ..add(op)
        ..add(right);
    }
  }
  var result = sums.first as _Fraction;
  for (var k = 1; k < sums.length; k += 2) {
    final right = sums[k + 1] as _Fraction;
    result = sums[k] == _plus ? result + right : result - right;
  }

  final minor = result.toMinor(decimals);
  // Не больше 12 цифр в целой части — как при обычном вводе.
  if (minor.abs() >= BigInt.from(10).pow(12 + decimals)) return null;
  return minor.toInt();
}

/// Нажатие клавиши на экранной клавиатуре: возвращает новое выражение.
///
/// Клавиши: цифры, `,`, действия `+ − × ÷`, `⌫` (стереть), `C` (очистить),
/// `=` (посчитать). [allowNegative] — можно начать с минуса (корректировка).
String pressKey(String expr, String key, {required int decimals, bool allowNegative = false}) {
  final last = expr.isEmpty ? '' : expr[expr.length - 1];
  // Текущее (последнее) число в выражении.
  final lastNumber = RegExp(r'[\d,]*$').firstMatch(expr)!.group(0)!;

  switch (key) {
    case 'C':
      return '';
    case '⌫':
      return expr.isEmpty ? '' : expr.substring(0, expr.length - 1);
    case '=':
      final v = evaluateAmount(expr, decimals: decimals);
      return v == null ? expr : Money.toEditable(v, decimals: decimals).replaceAll('-', _minus);
    case ',':
      if (decimals == 0 || lastNumber.contains(',')) return expr;
      return lastNumber.isEmpty ? '${expr}0,' : '$expr,';
  }
  if (operators.contains(key)) {
    if (expr.isEmpty) return key == _minus && allowNegative ? _minus : expr;
    if (expr == _minus) return expr;
    if (operators.contains(last)) return '${expr.substring(0, expr.length - 1)}$key';
    if (last == ',') return '${expr.substring(0, expr.length - 1)}$key';
    return '$expr$key';
  }
  if (RegExp(r'^\d$').hasMatch(key)) {
    final comma = lastNumber.indexOf(',');
    if (comma >= 0 && lastNumber.length - comma - 1 >= decimals) return expr;
    // Без лишних нулей впереди: «0» + «5» = «5».
    if (lastNumber == '0') return '${expr.substring(0, expr.length - 1)}$key';
    if (comma < 0 && lastNumber.length >= 12) return expr;
    return '$expr$key';
  }
  return expr;
}

/// Выражение для показа: «1500+350» → «1 500 + 350».
String formatExpression(String expr) {
  final buf = StringBuffer();
  for (final part in RegExp(r'[\d,]+|.').allMatches(expr).map((m) => m.group(0)!)) {
    if (operators.contains(part)) {
      buf.write(buf.isEmpty ? part : ' $part ');
    } else if (RegExp(r'^\d').hasMatch(part)) {
      final comma = part.indexOf(',');
      final whole = comma < 0 ? part : part.substring(0, comma);
      final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
      buf.write(comma < 0 ? grouped : '$grouped${part.substring(comma)}');
    } else {
      buf.write(part);
    }
  }
  return buf.toString();
}
