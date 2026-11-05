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
import '../../domain/ledger.dart';
import '../../domain/providers.dart';

final _progressProvider = Provider<AsyncValue<(Ledger, List<BudgetProgress>)>>((ref) {
  final ledger = ref.watch(ledgerProvider);
  final budgets = ref.watch(budgetsProvider);
  final plans = ref.watch(plansProvider);
  final month = ref.watch(budgetsMonthProvider);
  return combineAsync(
    [ledger, budgets, plans],
    () => (
      ledger.requireValue,
      allBudgetProgress(ledger.requireValue, budgets.requireValue, month, plans: plans.requireValue),
    ),
  );
});

/// Бюджет на месяц: план и факт по доходам и расходам.
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(_progressProvider);
    final month = ref.watch(budgetsMonthProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Бюджет')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.budgetNew),
        icon: const Icon(Icons.add),
        label: const Text('Статья'),
      ),
      body: progress.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (d) {
          final (ledger, list) = d;
          final income = list.where((p) => p.isIncome).toList();
          final expense = list.where((p) => !p.isIncome).toList();
          return ListView(
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
                    title: 'Бюджет не задан',
                    subtitle: 'Задайте план на месяц: сколько хотите тратить по категориям '
                        '(«Кафе — не больше 5 000 сом») и сколько ожидаете дохода. '
                        'Приложение покажет план и факт, сколько можно тратить в день '
                        'и предупредит о перерасходе.',
                  ),
                )
              else ...[
                _SummaryCard(ledger: ledger, income: income, expense: expense),
                if (income.isNotEmpty) ...[
                  const _Header('Доходы'),
                  for (final p in income) _BudgetCard(progress: p),
                ],
                if (expense.isNotEmpty) ...[
                  const _Header('Расходы'),
                  for (final p in expense) _BudgetCard(progress: p),
                ],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

/// Итог месяца: план и факт доходов и расходов в основной валюте.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.ledger, required this.income, required this.expense});

  final Ledger ledger;
  final List<BudgetProgress> income;
  final List<BudgetProgress> expense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final base = ledger.base;
    int toBase(BudgetProgress p, int v) =>
        ledger.rates.latest.convert(v, p.currency, base) ?? 0;
    int sum(List<BudgetProgress> list, int Function(BudgetProgress) f) =>
        list.fold(0, (s, p) => s + toBase(p, f(p)));

    final planIn = sum(income, (p) => p.limit), factIn = sum(income, (p) => p.spent);
    final planOut = sum(expense, (p) => p.limit), factOut = sum(expense, (p) => p.spent);

    Widget row(String label, int fact, int plan, Color color) => Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(base.format(fact), style: theme.textTheme.titleSmall?.copyWith(color: color)),
          Text('  из ${base.format(plan)}', style: theme.textTheme.bodySmall),
        ],
      ),
    );

    return Card.filled(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('План на месяц', style: theme.textTheme.titleMedium),
            if (income.isNotEmpty) row('Доходы', factIn, planIn, colors.income),
            if (expense.isNotEmpty) row('Расходы', factOut, planOut, colors.expense),
            if (income.isNotEmpty && expense.isNotEmpty) ...[
              const Divider(height: 20),
              Text(
                planIn >= planOut
                    ? 'По плану останется ${base.format(planIn - planOut)}'
                    : 'По плану расходы больше доходов на ${base.format(planOut - planIn)}',
                style: theme.textTheme.bodyMedium,
              ),
            ],
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
    // Для дохода больше плана — хорошо, для расхода — плохо.
    final barColor = p.isIncome
        ? colors.income
        : p.isOver
            ? colors.expense
            : p.ratio >= 0.8 || p.forecastOver
                ? Colors.orange
                : colors.income;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final hints = <String>[
      if (p.expected > 0)
        '${p.isIncome ? 'Ожидается ещё' : 'Запланировано ещё'} ${c.format(p.expected)} по регулярным платежам',
      if (!p.isIncome && p.dailyAllowance != null)
        'Можно тратить ≈ ${c.formatRounded(p.dailyAllowance!)} в день',
      if (!p.isIncome && p.forecast != null && !p.isOver)
        p.forecastOver
            ? 'При таком темпе к концу месяца ≈ ${c.formatRounded(p.forecast!)} — перерасход'
            : 'Прогноз на месяц ≈ ${c.formatRounded(p.forecast!)}',
      if (p.unconverted.isNotEmpty) 'Не учтено операций без курса: ${p.unconverted.length}',
    ];
    final status = p.isIncome
        ? (p.remaining > 0 ? 'Ещё ${c.format(p.remaining)}' : 'План выполнен')
        : (p.isOver ? 'Перерасход ${c.format(-p.remaining)}' : 'Осталось ${c.format(p.remaining)}');

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
                    status,
                    style: TextStyle(
                      color: !p.isIncome && p.isOver ? colors.expense : null,
                      fontWeight: FontWeight.w500,
                    ),
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
