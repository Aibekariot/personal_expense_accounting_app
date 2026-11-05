/// Работа с денежными суммами.
///
/// Все суммы в приложении — целые числа в минимальных единицах валюты
/// (тыйыны, центы): 1 500,50 сом = 150050. Так нет ошибок округления,
/// как с double (где 0.1 + 0.2 != 0.3).
abstract final class Money {
  static const _nbsp = ' ';

  /// Максимум цифр в целой части — чтобы не выйти за точность int в браузере.
  static const _maxWholeDigits = 12;

  /// 10^[decimals]: сколько минимальных единиц в одной целой.
  static int factor(int decimals) {
    var f = 1;
    for (var i = 0; i < decimals; i++) {
      f *= 10;
    }
    return f;
  }

  /// Форматирует сумму: `150050` → `1 500,50 сом`.
  ///
  /// [signed] — показывать `+` у положительных сумм.
  /// [trimZeroFraction] — не показывать `,00` у целых сумм.
  static String format(
    int minor, {
    int decimals = 2,
    String? symbol,
    bool signed = false,
    bool trimZeroFraction = true,
  }) {
    final f = factor(decimals);
    final abs = minor.abs();
    final whole = abs ~/ f;
    final frac = abs % f;

    final buf = StringBuffer();
    if (minor < 0) {
      buf.write('−');
    } else if (signed && minor > 0) {
      buf.write('+');
    }
    buf.write(_groupThousands(whole));
    if (decimals > 0 && !(trimZeroFraction && frac == 0)) {
      buf
        ..write(',')
        ..write(frac.toString().padLeft(decimals, '0'));
    }
    if (symbol != null && symbol.isNotEmpty) {
      buf
        ..write(_nbsp)
        ..write(symbol);
    }
    return buf.toString();
  }

  /// Разбирает введённую сумму: `"1 500,5"` → `150050`.
  ///
  /// Понимает запятую и точку как десятичный разделитель, пробелы игнорирует.
  /// Возвращает null, если ввод некорректен или знаков после запятой
  /// больше, чем допускает валюта.
  static int? parse(String input, {int decimals = 2}) {
    var s = input.replaceAll(RegExp(r'[\s  ]'), '').replaceAll(',', '.');
    var negative = false;
    if (s.startsWith('-') || s.startsWith('−')) {
      negative = true;
      s = s.substring(1);
    }
    final match = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(s);
    if (match == null) return null;

    final wholeStr = match.group(1)!;
    final fracStr = match.group(2) ?? '';
    if (wholeStr.isEmpty && fracStr.isEmpty) return null;
    if (fracStr.length > decimals) return null;
    if (wholeStr.length > _maxWholeDigits) return null;

    final whole = wholeStr.isEmpty ? 0 : int.parse(wholeStr);
    final frac = fracStr.isEmpty ? 0 : int.parse(fracStr.padRight(decimals, '0'));
    final result = whole * factor(decimals) + frac;
    return negative ? -result : result;
  }

  /// Пересчитывает сумму в другую валюту по курсу
  /// (1 единица исходной валюты = [rate] единиц целевой).
  /// Результат округляется до целых минимальных единиц (половина — от нуля).
  static int convert(
    int minor, {
    required double rate,
    int fromDecimals = 2,
    int toDecimals = 2,
  }) {
    return (minor * rate * factor(toDecimals) / factor(fromDecimals)).round();
  }

  static String _groupThousands(int n) {
    final s = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) out.write(_nbsp);
      out.write(s[i]);
    }
    return out.toString();
  }
}
