import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/formatters.dart';
import '../../core/widgets/category_avatar.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../domain/ledger.dart';
import '../../domain/schedule.dart';

/// Подпись плана: получатель, иначе категория или «Перевод».
String planTitle(Ledger l, PlannedOperation p) {
  if (p.payee.isNotEmpty) return p.payee;
  if (p.type == OperationType.transfer) {
    return 'Перевод → ${l.accounts[p.toAccountId]?.name ?? '?'}';
  }
  return l.categories[p.categoryId]?.name ?? 'Без категории';
}

/// Сумма плана со знаком: «−25 000 сом», «+60 000 сом».
String planAmount(Ledger l, PlannedOperation p) {
  final c = l.currency(l.accounts[p.accountId]?.currencyCode ?? l.base.code);
  return switch (p.type) {
    OperationType.income => c.format(p.amount, signed: true),
    OperationType.expense => c.format(-p.amount),
    _ => c.format(p.amount),
  };
}

Color? planAmountColor(BuildContext context, PlannedOperation p) {
  final colors = MoneyColors.of(context);
  return switch (p.type) {
    OperationType.income => colors.income,
    OperationType.expense => colors.expense,
    _ => null,
  };
}

Widget planAvatar(BuildContext context, Ledger l, PlannedOperation p, {double radius = 20}) {
  final c = l.categories[p.categoryId];
  return CategoryAvatar(
    icon: p.type == OperationType.transfer ? Icons.swap_horiz : categoryIcon(c?.icon ?? 'more'),
    color: p.type == OperationType.transfer ? MoneyColors.of(context).neutral : Color(c?.color ?? 0xFF757575),
    radius: radius,
  );
}

/// Провести повторение: дата — плановая, если она уже прошла, иначе сегодня
/// (заплатили раньше срока).
Future<void> confirmOccurrence(BuildContext context, WidgetRef ref, Occurrence o) async {
  final today = dayOf(DateTime.now());
  final date = o.date.isAfter(today) ? today : o.date;
  try {
    await ref.read(planRepositoryProvider).confirm(o.plan, date: date);
    if (context.mounted) showSnack(context, 'Проведено: ${formatDate(date)}');
  } catch (e) {
    if (context.mounted) showSnack(context, 'Не удалось провести: $e');
  }
}

/// Предстоящий платёж: «Провести» (как запланировано), «Пропустить»,
/// нажатие — открыть форму и поправить сумму перед проведением.
class UpcomingTile extends ConsumerWidget {
  const UpcomingTile({super.key, required this.occurrence, required this.ledger});

  final Occurrence occurrence;
  final Ledger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final o = occurrence;
    final p = o.plan;
    final today = dayOf(DateTime.now());
    final overdue = o.date.isBefore(today);
    // Провести/пропустить можно только ближайшее повторение плана.
    final isNext = o.index == p.doneCount;

    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 4),
      leading: planAvatar(context, ledger, p),
      title: Text(planTitle(ledger, p), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${formatShortDate(o.date)} · ${dueLabel(o.date, today)}',
        style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            planAmount(ledger, p),
            style: theme.textTheme.titleSmall?.copyWith(color: planAmountColor(context, p)),
          ),
          if (isNext) ...[
            IconButton(
              tooltip: 'Пропустить',
              icon: const Icon(Icons.redo),
              onPressed: () async {
                await ref.read(planRepositoryProvider).skip(p);
                if (context.mounted) showSnack(context, 'Пропущено');
              },
            ),
            IconButton.filledTonal(
              tooltip: 'Провести',
              icon: const Icon(Icons.check),
              onPressed: () => confirmOccurrence(context, ref, o),
            ),
          ],
        ],
      ),
      onTap: isNext
          ? () => context.push(Routes.operationNew(planId: p.id))
          : () => context.push(Routes.planEdit(p.id)),
    );
  }
}
