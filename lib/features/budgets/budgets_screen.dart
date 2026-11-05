import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/async_utils.dart';
import '../../core/formatters.dart';
import '../../core/widgets/category_avatar.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/period_bar.dart';
import '../../data/providers.dart';
import '../../domain/budgets.dart';
import '../../domain/providers.dart';

final _progressProvider = Provider<AsyncValue<List<BudgetProgress>>>((ref) {
  final ledger = ref.watch(ledgerProvider);
  final budgets = ref.watch(budgetsProvider);
  final month = ref.watch(budgetsMonthProvider);
  return combineAsync(
    [ledger, budgets],
    () => allBudgetProgress(ledger.requireValue, budgets.requireValue, month),
  );
});

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(_progressProvider);
    final month = ref.watch(budgetsMonthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Бюджеты')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.budgetNew),
        icon: const Icon(Icons.add),
        label: const Text('Бюджет'),
      ),
      body: progress.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            PeriodBar(
              period: month,
              monthsOnly: true,
              onChanged: ref.read(budgetsMonthProvider.notifier).select,
            ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: EmptyState(
                  icon: Icons.track_changes,
                  title: 'Бюджетов пока нет',
                  subtitle: 'Бюджет — это лимит расходов на месяц по категории. '
                      'Например, «Кафе — не больше 5 000 сом в месяц». '
                      'Приложение покажет, сколько осталось, и предупредит о перерасходе.',
                ),
              ),
            for (final p in list) _BudgetCard(progress: p),
          ],
        ),
      ),
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.progress});

  final BudgetProgress progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final p = progress;
    final c = p.currency;
    final category = p.category;
    final barColor = p.isOver
        ? colors.expense
        : p.ratio >= 0.8 || p.forecastOver
            ? Colors.orange
            : colors.income;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final hints = <String>[
      if (p.dailyAllowance != null) 'Можно тратить ≈ ${c.formatRounded(p.dailyAllowance!)} в день',
      if (p.forecast != null && !p.isOver)
        p.forecastOver
            ? 'При таком темпе к концу месяца ≈ ${c.formatRounded(p.forecast!)} — перерасход'
            : 'Прогноз на месяц ≈ ${c.formatRounded(p.forecast!)}',
      if (p.unconverted.isNotEmpty) 'Не учтено расходов без курса: ${p.unconverted.length}',
    ];

    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push(Routes.budgetEdit(p.budget.id)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryAvatar(
                    icon: categoryIcon(category?.icon ?? 'more'),
                    color: Color(category?.color ?? 0xFF757575),
                    radius: 18,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(category?.name ?? 'Категория удалена', style: theme.textTheme.titleMedium),
                  ),
                  Text(formatPercent(p.ratio), style: theme.textTheme.titleMedium?.copyWith(color: barColor)),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p.ratio.clamp(0, 1).toDouble(),
                  minHeight: 8,
                  color: barColor,
                  backgroundColor: barColor.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: Text('${c.format(p.spent)} из ${c.format(p.limit)}')),
                  Text(
                    p.isOver ? 'Перерасход ${c.format(-p.remaining)}' : 'Осталось ${c.format(p.remaining)}',
                    style: TextStyle(color: p.isOver ? colors.expense : null, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              for (final h in hints) ...[
                const SizedBox(height: 4),
                Text(h, style: muted),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
