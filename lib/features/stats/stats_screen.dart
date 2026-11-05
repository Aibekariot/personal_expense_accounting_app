import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/period_bar.dart';
import '../../data/db/app_database.dart';
import '../../domain/ledger.dart';
import '../../domain/operation_filter.dart';
import '../../domain/period.dart';
import '../../domain/providers.dart';
import '../../domain/stats.dart';
import '../operations/operation_tile.dart';
import 'charts.dart';

class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  CategoryType _type = CategoryType.expense;

  /// Открытая категория (показываются её подкатегории).
  int? _parentId;

  /// Показать операции категории в истории за тот же период.
  void _openOperations(Period period, CategorySlice s) {
    final category = s.category;
    if (category == null) return;
    ref.read(operationsPeriodProvider.notifier).select(period);
    ref.read(operationFilterProvider.notifier).set(OperationFilter(
      kinds: {_type == CategoryType.expense ? OperationKind.expense : OperationKind.income},
      categoryId: category.id,
    ));
    context.go(Routes.operations);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final period = ref.watch(statsPeriodProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Аналитика')),
      body: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
        data: (l) {
          if (l.operations.isEmpty) {
            return const EmptyState(
              icon: Icons.pie_chart_outline,
              title: 'Пока нечего показать',
              subtitle: 'Добавьте несколько расходов и доходов — здесь появятся '
                  'графики по категориям и месяцам.',
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              PeriodBar(
                period: period,
                onChanged: (p) {
                  ref.read(statsPeriodProvider.notifier).select(p);
                },
              ),
              _SummaryCard(ledger: l, period: period),
              _categoriesCard(l, period),
              _MonthlyCard(ledger: l, period: period),
              _CapitalCard(ledger: l, period: period),
              _TopExpensesCard(ledger: l, period: period),
            ],
          );
        },
      ),
    );
  }

  Widget _categoriesCard(Ledger l, Period period) {
    final theme = Theme.of(context);
    final parent = l.categories[_parentId];
    final slices = categoryBreakdown(l, period, type: _type, parentId: parent?.id);
    final total = slices.fold(0, (s, e) => s + e.amount);
    final hasChildren = {
      for (final c in l.categories.values)
        if (c.parentId != null) c.parentId!,
    };
    Color colorOf(CategorySlice s) {
      final c = s.category;
      if (c == null) return MoneyColors.of(context).neutral;
      // Внутри категории все подкатегории одного цвета — различаем яркостью.
      if (parent != null) {
        final i = slices.indexOf(s);
        return Color(c.color).withValues(alpha: math.max(0.35, 1 - i * 0.15));
      }
      return Color(c.color);
    }

    return _Section(
      title: parent == null ? 'По категориям' : parent.name,
      leading: parent == null
          ? null
          : IconButton(
              tooltip: 'Все категории',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _parentId = null),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<CategoryType>(
            segments: const [
              ButtonSegment(value: CategoryType.expense, label: Text('Расходы')),
              ButtonSegment(value: CategoryType.income, label: Text('Доходы')),
            ],
            selected: {_type},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _type = s.first;
              _parentId = null;
            }),
          ),
          if (slices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                _type == CategoryType.expense ? 'Расходов за период нет' : 'Доходов за период нет',
                textAlign: TextAlign.center,
              ),
            )
          else ...[
            const SizedBox(height: 16),
            CategoryDonut(
              slices: slices,
              colorOf: colorOf,
              centerLabel: _type == CategoryType.expense ? 'Расходы' : 'Доходы',
              centerValue: l.base.format(total),
            ),
            const SizedBox(height: 8),
            for (final s in slices)
              _SliceTile(
                slice: s,
                color: colorOf(s),
                base: l.base,
                type: _type,
                canDrill: parent == null && s.category != null && hasChildren.contains(s.category!.id),
                onDrill: () => setState(() => _parentId = s.category!.id),
                onOpen: s.category == null ? null : () => _openOperations(period, s),
              ),
            if (period.previous != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  period.contains(DateTime.now())
                      ? '▲▼ — к тому же числу прошлого периода. Нажмите на категорию, чтобы увидеть операции.'
                      : '▲▼ — к прошлому периоду. Нажмите на категорию, чтобы увидеть операции.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.leading, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ?leading,
                Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              ],
            ),
            if (subtitle != null)
              Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.ledger, required this.period});

  final Ledger ledger;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final base = ledger.base;
    final t = PeriodTotals.of(ledger.inPeriod(period));
    final now = DateTime.now();

    // Сколько дней считать для среднего.
    int days;
    if (period.kind == PeriodKind.all) {
      final first = ledger.operations.isEmpty ? now : ledger.operations.last.date;
      days = Period.custom(first, now).days;
    } else {
      days = period.contains(now) ? period.daysElapsed(now) : period.days;
    }
    days = math.max(days, 1);
    final forecast = period.kind == PeriodKind.month && period.contains(now)
        ? forecastMonth(
            spent: t.expense,
            days: period.days,
            elapsed: days,
            previousMonths: previousMonthSums(ledger, period, (ops) => PeriodTotals.of(ops).expense),
          )
        : null;

    Widget cell(String label, String value, Color? color) => Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: theme.textTheme.titleMedium?.copyWith(color: color)),
          ),
        ],
      ),
    );
    final lines = <String>[
      if (t.savingsRate != null)
        t.net >= 0
            ? 'Отложено ${formatPercent(t.savingsRate!)} дохода'
            : 'Расходы больше доходов на ${base.format(-t.net)}',
      'В среднем в день ≈ ${base.formatRounded(t.expense ~/ days)}',
      if (forecast != null) 'Прогноз расходов на месяц ≈ ${base.formatRounded(forecast)}',
      if (t.unconverted.isNotEmpty)
        'Не учтено операций без курса валюты: ${t.unconverted.length} (укажите курс в «Валюты и курсы»)',
    ];

    return Card.filled(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                cell('Доходы', base.format(t.income), colors.income),
                cell('Расходы', base.format(t.expense), colors.expense),
                cell('Итого', base.format(t.net, signed: true), null),
              ],
            ),
            const SizedBox(height: 12),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(line, style: theme.textTheme.bodyMedium),
              ),
          ],
        ),
      ),
    );
  }
}

class _SliceTile extends StatelessWidget {
  const _SliceTile({
    required this.slice,
    required this.color,
    required this.base,
    required this.type,
    required this.canDrill,
    required this.onDrill,
    required this.onOpen,
  });

  final CategorySlice slice;
  final Color color;
  final Currency base;
  final CategoryType type;
  final bool canDrill;
  final VoidCallback onDrill;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = slice;
    final name = s.category == null
        ? 'Без категории'
        : s.isParentItself
            ? '${s.category!.name} (без подкатегории)'
            : s.category!.name;
    final change = s.change;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final changeText = change == null
        ? (s.previousAmount == 0 ? 'новое' : null)
        : '${change >= 0 ? '▲' : '▼'} ${formatPercent(change.abs())}';

    return InkWell(
      onTap: canDrill ? onDrill : onOpen,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(
                categoryIcon(s.category?.icon ?? 'more'),
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    [
                      formatPercent(s.share),
                      '${s.count} опер.',
                      ?changeText,
                    ].join(' · '),
                    style: muted,
                  ),
                ],
              ),
            ),
            Text(base.format(s.amount), style: theme.textTheme.titleSmall),
            Icon(canDrill ? Icons.expand_more : Icons.chevron_right, size: 20, color: theme.colorScheme.outline),
          ],
        ),
      ),
    );
  }
}

class _MonthlyCard extends StatelessWidget {
  const _MonthlyCard({required this.ledger, required this.period});

  final Ledger ledger;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last = period.kind == PeriodKind.all || period.end.isAfter(now) ? now : period.lastDay;
    final points = monthlyTotals(ledger, DateTime(last.year, last.month), 6);
    if (points.every((p) => p.income == 0 && p.expense == 0)) return const SizedBox.shrink();
    return _Section(
      title: 'По месяцам',
      subtitle: 'Последние 6 месяцев, в ${ledger.base.code}',
      child: MonthlyBars(points: points, base: ledger.base),
    );
  }
}

class _CapitalCard extends StatelessWidget {
  const _CapitalCard({required this.ledger, required this.period});

  final Ledger ledger;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final last = period.kind == PeriodKind.all || period.end.isAfter(now) ? now : period.lastDay;
    final points = capitalHistory(ledger, DateTime(last.year, last.month), 12, now: now);
    // Показываем с первого месяца, где были деньги.
    final start = points.indexWhere((p) => p.amount != 0);
    if (start < 0 || points.length - start < 2) return const SizedBox.shrink();
    final shown = points.sublist(start);
    final incomplete = shown.any((p) => !p.complete);
    return _Section(
      title: 'Капитал',
      subtitle: 'На конец каждого месяца, по курсу на ту дату'
          '${incomplete ? '. Часть счетов без курса не учтена' : ''}',
      child: CapitalLine(points: shown, base: ledger.base),
    );
  }
}

class _TopExpensesCard extends StatelessWidget {
  const _TopExpensesCard({required this.ledger, required this.period});

  final Ledger ledger;
  final Period period;

  @override
  Widget build(BuildContext context) {
    final top = topExpenses(ledger, period);
    if (top.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: 'Крупнейшие расходы',
      child: Column(
        children: [
          for (final v in top)
            OperationTile(
              view: v,
              base: ledger.base,
              showDate: true,
              onTap: () => context.push(Routes.operationEdit(v.op.id)),
            ),
        ],
      ),
    );
  }
}
