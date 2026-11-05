import '../data/db/app_database.dart';

/// Дата повторения номер [index] (с нуля) или null, если такого нет
/// (одноразовая операция уже прошла или после даты окончания).
///
/// Для «каждый месяц 31-го» в коротких месяцах берётся последний день,
/// а в следующих длинных — снова 31-е (день отсчитывается от [startDate]).
DateTime? occurrence(PlannedOperation p, int index) {
  if (index < 0) return null;
  if (p.repeatUnit == RepeatUnit.none && index > 0) return null;
  final s = p.startDate;
  final step = index * (p.repeatEvery < 1 ? 1 : p.repeatEvery);
  final date = switch (p.repeatUnit) {
    RepeatUnit.none => DateTime(s.year, s.month, s.day),
    RepeatUnit.day => DateTime(s.year, s.month, s.day + step),
    RepeatUnit.week => DateTime(s.year, s.month, s.day + 7 * step),
    RepeatUnit.month => _clampDay(s.year, s.month + step, s.day),
    RepeatUnit.year => _clampDay(s.year + step, s.month, s.day),
  };
  final end = p.endDate;
  if (end != null && date.isAfter(DateTime(end.year, end.month, end.day))) return null;
  return date;
}

DateTime _clampDay(int year, int month, int day) {
  final lastDay = DateTime(year, month + 1, 0).day;
  return DateTime(year, month, day > lastDay ? lastDay : day);
}

/// Следующее непроведённое повторение (null — план завершён).
DateTime? nextOccurrence(PlannedOperation p) => occurrence(p, p.doneCount);

bool isFinished(PlannedOperation p) => nextOccurrence(p) == null;

/// Одно предстоящее повторение плана.
class Occurrence {
  const Occurrence(this.plan, this.date, this.index);

  final PlannedOperation plan;
  final DateTime date;

  /// Номер повторения.
  final int index;
}

/// Непроведённые повторения всех планов с датой не позже [to]
/// (просроченные тоже входят). Сортировка — по дате.
List<Occurrence> upcoming(
  Iterable<PlannedOperation> plans, {
  required DateTime to,
  DateTime? from,
  int maxPerPlan = 400,
}) {
  final result = <Occurrence>[];
  for (final p in plans) {
    for (var i = p.doneCount; i < p.doneCount + maxPerPlan; i++) {
      final d = occurrence(p, i);
      if (d == null || d.isAfter(to)) break;
      if (from == null || !d.isBefore(from)) result.add(Occurrence(p, d, i));
    }
  }
  result.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.plan.id.compareTo(b.plan.id);
  });
  return result;
}

/// Как часто: «каждый месяц», «каждые 2 недели», «один раз».
String repeatLabel(RepeatUnit unit, int every) {
  if (unit == RepeatUnit.none) return 'один раз';
  if (every <= 1) {
    return switch (unit) {
      RepeatUnit.day => 'каждый день',
      RepeatUnit.week => 'каждую неделю',
      RepeatUnit.month => 'каждый месяц',
      RepeatUnit.year => 'каждый год',
      RepeatUnit.none => 'один раз',
    };
  }
  final forms = switch (unit) {
    RepeatUnit.day => ('день', 'дня', 'дней'),
    RepeatUnit.week => ('неделю', 'недели', 'недель'),
    RepeatUnit.month => ('месяц', 'месяца', 'месяцев'),
    RepeatUnit.year => ('год', 'года', 'лет'),
    RepeatUnit.none => ('', '', ''),
  };
  return '${every % 10 == 1 && every % 100 != 11 ? 'каждый' : 'каждые'} $every ${plural(every, forms)}';
}

/// Склонение: 1 день, 2 дня, 5 дней.
String plural(int n, (String, String, String) forms) {
  final mod10 = n % 10, mod100 = n % 100;
  if (mod10 == 1 && mod100 != 11) return forms.$1;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return forms.$2;
  return forms.$3;
}

/// Когда платёж относительно сегодня: «сегодня», «завтра», «через 3 дня»,
/// «просрочен на 2 дня».
String dueLabel(DateTime date, DateTime today) {
  final d = DateTime.utc(date.year, date.month, date.day)
      .difference(DateTime.utc(today.year, today.month, today.day))
      .inDays;
  if (d == 0) return 'сегодня';
  if (d == 1) return 'завтра';
  if (d > 1) return 'через $d ${plural(d, ('день', 'дня', 'дней'))}';
  return 'просрочен на ${-d} ${plural(-d, ('день', 'дня', 'дней'))}';
}
