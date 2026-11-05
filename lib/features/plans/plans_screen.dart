import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/async_utils.dart';
import '../../core/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/period_bar.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../domain/forecast.dart';
import '../../domain/ledger.dart';
import '../../domain/period.dart';
import '../../domain/providers.dart';
import '../../domain/schedule.dart';
import '../accounts/accounts_overview.dart';
import '../operations/operation_tile.dart';
import '../stats/charts.dart';
import 'upcoming_tile.dart';

/// Регулярные платежи: прогноз, список планов и календарь.
class PlansScreen extends ConsumerWidget {
  const PlansScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    final plans = ref.watch(plansProvider);
    final data = combineAsync([ledger, plans], () => (ledger.requireValue, plans.requireValue));

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Регулярные платежи'),
          bottom: const TabBar(tabs: [Tab(text: 'Список'), Tab(text: 'Календарь')]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.push(Routes.planNew()),
          icon: const Icon(Icons.add),
          label: const Text('План'),
        ),
        body: data.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Ошибка: $e')),
          data: (d) => TabBarView(
            children: [
              _PlansList(ledger: d.$1, plans: d.$2),
              _PlanCalendar(ledger: d.$1, plans: d.$2),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlansList extends StatelessWidget {
  const _PlansList({required this.ledger, required this.plans});

  final Ledger ledger;
  final List<PlannedOperation> plans;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = dayOf(DateTime.now());
    final active = plans.where((p) => !isFinished(p)).toList()
      ..sort((a, b) => nextOccurrence(a)!.compareTo(nextOccurrence(b)!));
    final finished = plans.where(isFinished).toList();

    if (plans.isEmpty) {
      return const EmptyState(
        icon: Icons.event_repeat,
        title: 'Планов пока нет',
        subtitle: 'Добавьте то, что повторяется: аренду, зарплату, интернет, подписки. '
            'Приложение напомнит о платеже в ленте и покажет, сколько денег '
            'останется через месяц.',
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        _ForecastCard(ledger: ledger, plans: active),
        for (final p in active)
          ListTile(
            leading: planAvatar(context, ledger, p),
            title: Text(planTitle(ledger, p), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              [
                repeatLabel(p.repeatUnit, p.repeatEvery),
                'следующий ${formatShortDate(nextOccurrence(p)!)} (${dueLabel(nextOccurrence(p)!, today)})',
                if (p.autoConfirm) 'авто',
              ].join(' · '),
              style: nextOccurrence(p)!.isBefore(today) ? TextStyle(color: theme.colorScheme.error) : null,
            ),
            trailing: Text(
              planAmount(ledger, p),
              style: theme.textTheme.titleSmall?.copyWith(color: planAmountColor(context, p)),
            ),
            onTap: () => context.push(Routes.planEdit(p.id)),
          ),
        if (finished.isNotEmpty)
          ExpansionTile(
            leading: const Icon(Icons.task_alt),
            title: Text('Завершённые (${finished.length})'),
            children: [
              for (final p in finished)
                ListTile(
                  leading: planAvatar(context, ledger, p),
                  title: Text(planTitle(ledger, p)),
                  subtitle: Text(repeatLabel(p.repeatUnit, p.repeatEvery)),
                  trailing: Text(planAmount(ledger, p)),
                  onTap: () => context.push(Routes.planEdit(p.id)),
                ),
            ],
          ),
      ],
    );
  }
}

/// Прогноз капитала по планам на 30 или 90 дней.
class _ForecastCard extends ConsumerStatefulWidget {
  const _ForecastCard({required this.ledger, required this.plans});

  final Ledger ledger;
  final List<PlannedOperation> plans;

  @override
  ConsumerState<_ForecastCard> createState() => _ForecastCardState();
}

class _ForecastCardState extends ConsumerState<_ForecastCard> {
  int _days = 30;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(accountsOverviewProvider).value;
    if (overview == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final base = widget.ledger.base;
    final f = balanceForecast(
      ledger: widget.ledger,
      plans: widget.plans,
      startCapital: overview.capital,
      today: DateTime.now(),
      days: _days,
    );
    final low = f.lowest;

    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text('Прогноз капитала', style: theme.textTheme.titleMedium)),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 30, label: Text('30 дн')),
                    ButtonSegment(value: 90, label: Text('90 дн')),
                  ],
                  selected: {_days},
                  showSelectedIcon: false,
                  style: const ButtonStyle(visualDensity: VisualDensity.compact),
                  onSelectionChanged: (s) => setState(() => _days = s.first),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Сейчас: ${base.format(overview.capital)}'),
            Text(
              'Через $_days дней: ${base.format(f.last.capital)}',
              style: theme.textTheme.titleMedium,
            ),
            if (low.capital < f.last.capital && low.capital < overview.capital)
              Text(
                'Меньше всего денег будет ${formatShortDate(low.day)}: ${base.format(low.capital)}',
                style: TextStyle(color: low.capital < 0 ? colors.expense : null),
              ),
            if (f.incomplete)
              Text(
                'Часть планов не учтена: нет курса валюты',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
              ),
            const SizedBox(height: 12),
            ForecastLine(
              days: [for (final p in f.points) p.day],
              values: [for (final p in f.points) p.capital],
              base: base,
            ),
            const SizedBox(height: 4),
            Text(
              'Считается по плановым операциям от текущего капитала. '
              'Обычные траты (продукты, кафе) в прогноз не входят.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthNotifier extends PeriodNotifier {}

final _calendarMonthProvider = NotifierProvider<PeriodNotifier, Period>(_MonthNotifier.new);

/// Календарь: плановые платежи и фактические операции по дням.
class _PlanCalendar extends ConsumerStatefulWidget {
  const _PlanCalendar({required this.ledger, required this.plans});

  final Ledger ledger;
  final List<PlannedOperation> plans;

  @override
  ConsumerState<_PlanCalendar> createState() => _PlanCalendarState();
}

class _PlanCalendarState extends ConsumerState<_PlanCalendar> {
  DateTime _selected = dayOf(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = MoneyColors.of(context);
    final l = widget.ledger;
    final month = ref.watch(_calendarMonthProvider);
    final today = dayOf(DateTime.now());

    final planned = <DateTime, List<Occurrence>>{};
    for (final o in upcoming(widget.plans.where((p) => !isFinished(p)),
        from: month.start, to: month.lastDay)) {
      planned.putIfAbsent(o.date, () => []).add(o);
    }
    final actual = <DateTime, List<OperationView>>{};
    for (final v in l.inPeriod(month)) {
      actual.putIfAbsent(dayOf(v.date), () => []).add(v);
    }

    // Сетка с понедельника.
    final first = month.start;
    final leading = first.weekday - 1;
    final cells = [
      for (var i = 0; i < leading; i++) null,
      for (var d = 0; d < month.days; d++) DateTime(first.year, first.month, first.day + d),
    ];
    final selected = month.contains(_selected) ? _selected : null;

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      children: [
        PeriodBar(
          period: month,
          monthsOnly: true,
          onChanged: ref.read(_calendarMonthProvider.notifier).select,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Column(
            children: [
              Row(
                children: [
                  for (final w in const ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'])
                    Expanded(
                      child: Center(
                        child: Text(w, style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 0.9,
                children: [
                  for (final day in cells)
                    if (day == null)
                      const SizedBox.shrink()
                    else
                      _DayCell(
                        day: day,
                        isToday: day == today,
                        isSelected: day == selected,
                        hasExpense: planned[day]?.any((o) => o.plan.type == OperationType.expense) ?? false,
                        hasIncome: planned[day]?.any((o) => o.plan.type == OperationType.income) ?? false,
                        hasOther: planned[day]?.any((o) => o.plan.type == OperationType.transfer) ?? false,
                        hasActual: actual.containsKey(day),
                        expenseColor: colors.chartExpense,
                        incomeColor: colors.chartIncome,
                        onTap: () => setState(() => _selected = day),
                      ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                children: [
                  _Legend(color: colors.chartExpense, label: 'плановый расход'),
                  _Legend(color: colors.chartIncome, label: 'плановый доход'),
                  _Legend(color: scheme.outline, label: 'были операции', hollow: true),
                ],
              ),
            ],
          ),
        ),
        if (selected != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              capitalize(formatDayHeader(selected)),
              style: theme.textTheme.titleMedium,
            ),
          ),
          for (final o in planned[selected] ?? const <Occurrence>[])
            UpcomingTile(occurrence: o, ledger: l),
          for (final v in actual[selected] ?? const <OperationView>[])
            OperationTile(
              view: v,
              base: l.base,
              onTap: () => context.push(Routes.operationEdit(v.op.id)),
            ),
          if ((planned[selected] ?? const []).isEmpty && (actual[selected] ?? const []).isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('В этот день ничего нет'),
            ),
        ],
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isToday,
    required this.isSelected,
    required this.hasExpense,
    required this.hasIncome,
    required this.hasOther,
    required this.hasActual,
    required this.expenseColor,
    required this.incomeColor,
    required this.onTap,
  });

  final DateTime day;
  final bool isToday;
  final bool isSelected;
  final bool hasExpense;
  final bool hasIncome;
  final bool hasOther;
  final bool hasActual;
  final Color expenseColor;
  final Color incomeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Widget dot(Color c, {bool hollow = false}) => Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.symmetric(horizontal: 1),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? null : c,
        border: hollow ? Border.all(color: c, width: 1.5) : null,
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? scheme.primaryContainer : null,
          borderRadius: BorderRadius.circular(10),
          border: isToday ? Border.all(color: scheme.primary, width: 1.5) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${day.day}',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isToday ? FontWeight.bold : null,
                color: day.weekday >= 6 ? scheme.error.withValues(alpha: 0.8) : null,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              height: 8,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (hasExpense) dot(expenseColor),
                  if (hasIncome) dot(incomeColor),
                  if (hasOther) dot(scheme.onSurfaceVariant),
                  if (hasActual) dot(scheme.outline, hollow: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.hollow = false});

  final Color color;
  final String label;
  final bool hollow;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    spacing: 4,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: hollow ? null : color,
          border: hollow ? Border.all(color: color, width: 1.5) : null,
        ),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}
