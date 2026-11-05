import 'package:intl/intl.dart';

import '../core/formatters.dart';

enum PeriodKind { month, year, all, custom }

/// Период для истории и статистики: [start] включительно, [end] — не включая.
class Period {
  const Period._(this.kind, this.start, this.end);

  factory Period.month(DateTime d) =>
      Period._(PeriodKind.month, DateTime(d.year, d.month), DateTime(d.year, d.month + 1));

  factory Period.year(DateTime d) =>
      Period._(PeriodKind.year, DateTime(d.year), DateTime(d.year + 1));

  factory Period.all() =>
      Period._(PeriodKind.all, DateTime(1900), DateTime(3000));

  /// Свой период: с [from] по [to] включительно.
  factory Period.custom(DateTime from, DateTime to) {
    final a = DateTime(from.year, from.month, from.day);
    final b = DateTime(to.year, to.month, to.day + 1);
    return a.isBefore(b)
        ? Period._(PeriodKind.custom, a, b)
        : Period._(PeriodKind.custom, DateTime(to.year, to.month, to.day),
            DateTime(from.year, from.month, from.day + 1));
  }

  final PeriodKind kind;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  /// Последний день периода.
  DateTime get lastDay => DateTime(end.year, end.month, end.day - 1);

  /// Число дней в периоде.
  int get days => _daysBetween(start, end);

  bool get canStep => kind != PeriodKind.all;

  /// Предыдущий период такой же длины (для «Всё время» — null).
  Period? get previous => switch (kind) {
    PeriodKind.month => Period.month(DateTime(start.year, start.month - 1)),
    PeriodKind.year => Period.year(DateTime(start.year - 1)),
    PeriodKind.all => null,
    PeriodKind.custom => Period._(
        kind,
        DateTime(start.year, start.month, start.day - days),
        start,
      ),
  };

  Period? get next => switch (kind) {
    PeriodKind.month => Period.month(DateTime(start.year, start.month + 1)),
    PeriodKind.year => Period.year(DateTime(start.year + 1)),
    PeriodKind.all => null,
    PeriodKind.custom => Period._(
        kind,
        end,
        DateTime(end.year, end.month, end.day + days),
      ),
  };

  /// Сколько дней периода уже прошло к дате [today] (для средних и прогнозов).
  int daysElapsed(DateTime today) {
    final t = DateTime(today.year, today.month, today.day + 1);
    if (!t.isAfter(start)) return 0;
    return _daysBetween(start, t.isBefore(end) ? t : end);
  }

  String get label => switch (kind) {
    PeriodKind.month => capitalize(DateFormat('LLLL yyyy', 'ru').format(start)),
    PeriodKind.year => '${start.year} год',
    PeriodKind.all => 'Всё время',
    PeriodKind.custom => days == 1
        ? formatDate(start)
        : '${formatDate(start)} – ${formatDate(lastDay)}',
  };

  @override
  bool operator ==(Object other) =>
      other is Period && other.kind == kind && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  static int _daysBetween(DateTime a, DateTime b) =>
      DateTime.utc(b.year, b.month, b.day)
          .difference(DateTime.utc(a.year, a.month, a.day))
          .inDays;
}
