import '../data/db/app_database.dart';
import 'ledger.dart';
import 'period.dart';

/// Получатель или плательщик со статистикой.
class PayeeStat {
  PayeeStat(this.name);

  final String name;
  int count = 0;
  DateTime? lastUsed;

  /// Расходы и доходы в основной валюте.
  int expense = 0;
  int income = 0;
}

/// Все получатели (из операций с непустым получателем), частые — сверху.
List<PayeeStat> payeeStats(Ledger ledger, {Period? period}) {
  final byName = <String, PayeeStat>{};
  for (final v in ledger.operations) {
    if (v.payee.isEmpty || (!v.isExpense && !v.isIncome)) continue;
    if (period != null && !period.contains(v.date)) continue;
    final s = byName.putIfAbsent(v.payee, () => PayeeStat(v.payee));
    s.count++;
    if (s.lastUsed == null || v.date.isAfter(s.lastUsed!)) s.lastUsed = v.date;
    if (v.baseAmount != null) {
      if (v.isExpense) {
        s.expense += v.baseAmount!;
      } else {
        s.income += v.baseAmount!;
      }
    }
  }
  return byName.values.toList()
    ..sort((a, b) {
      final c = b.count.compareTo(a.count);
      return c != 0 ? c : b.lastUsed!.compareTo(a.lastUsed!);
    });
}

/// Подсказки при вводе получателя: сначала начинающиеся с введённого,
/// потом содержащие его; среди них — частые и недавние.
/// [type] — расход или доход (у них разные получатели).
List<String> payeeSuggestions(
  Ledger ledger,
  OperationType type,
  String query, {
  int limit = 6,
}) {
  final stats = <String, (int, DateTime)>{};
  for (final v in ledger.operations) {
    if (v.payee.isEmpty || v.type != type) continue;
    final (count, last) = stats[v.payee] ?? (0, v.date);
    stats[v.payee] = (count + 1, v.date.isAfter(last) ? v.date : last);
  }
  final q = query.trim().toLowerCase();
  int rank(String name) {
    if (q.isEmpty) return 0;
    final n = name.toLowerCase();
    if (n.startsWith(q)) return 0;
    if (n.split(' ').any((w) => w.startsWith(q))) return 1;
    return n.contains(q) ? 2 : 3;
  }

  final names = stats.keys.where((n) => rank(n) < 3 && n.toLowerCase() != q).toList()
    ..sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final c = stats[b]!.$1.compareTo(stats[a]!.$1);
      return c != 0 ? c : stats[b]!.$2.compareTo(stats[a]!.$2);
    });
  return names.take(limit).toList();
}

/// Категория для получателя: та, что чаще всего выбиралась в последних
/// 10 операциях с ним (при равенстве — более поздняя). null — получатель новый.
int? suggestCategory(Ledger ledger, String payee, OperationType type) {
  final name = payee.trim().toLowerCase();
  if (name.isEmpty) return null;
  // ledger.operations — новые сверху.
  final recent = ledger.operations
      .where((v) => v.type == type && v.op.categoryId != null && v.payee.toLowerCase() == name)
      .take(10)
      .toList();
  if (recent.isEmpty) return null;
  final counts = <int, int>{};
  for (final v in recent) {
    counts[v.op.categoryId!] = (counts[v.op.categoryId!] ?? 0) + 1;
  }
  final best = counts.values.reduce((a, b) => a > b ? a : b);
  return recent.firstWhere((v) => counts[v.op.categoryId!] == best).op.categoryId;
}
