import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../core/widgets/balance_title.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/quick_add_fab.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../domain/ledger.dart';
import '../../domain/operation_filter.dart';
import '../../domain/period.dart';
import '../../domain/providers.dart';
import '../../domain/schedule.dart';
import '../../domain/stats.dart';
import '../plans/upcoming_tile.dart';
import 'filter_sheet.dart';
import 'operation_tile.dart';

/// Лента операций: вся история по дням с итогами месяцев, будущие платежи,
/// поиск и фильтры.
class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  final _search = TextEditingController();
  bool _searching = false;

  /// Вкладка «Будущие» (плановые платежи) вместо истории.
  bool _future = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _closeSearch() {
    _search.clear();
    ref.read(operationFilterProvider.notifier).setQuery('');
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final period = ref.watch(operationsPeriodProvider);
    final filter = ref.watch(operationFilterProvider);
    final filtered = filter.hasFilters || period.kind != PeriodKind.all;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Категория, получатель, сумма…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
                onChanged: ref.read(operationFilterProvider.notifier).setQuery,
              )
            : const BalanceTitle(),
        actions: [
          if (_searching)
            IconButton(tooltip: 'Закрыть поиск', icon: const Icon(Icons.close), onPressed: _closeSearch)
          else
            IconButton(
              tooltip: 'Поиск',
              icon: const Icon(Icons.search),
              onPressed: () => setState(() {
                _searching = true;
                _future = false;
              }),
            ),
          IconButton(
            tooltip: 'Фильтр',
            onPressed: ledger.hasValue ? () => showFilterSheet(context, ref, ledger.requireValue) : null,
            icon: Badge(isLabelVisible: filtered, child: const Icon(Icons.tune)),
          ),
        ],
      ),
      floatingActionButton: const QuickAddFab(),
      body: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
        data: (l) => _future && !_searching
            ? _FutureList(
                ledger: l,
                switcher: _ModeSwitch(future: true, onChanged: (f) => setState(() => _future = f)),
              )
            : _History(
                ledger: l,
                period: period,
                filter: filter,
                switcher: _searching
                    ? null
                    : _ModeSwitch(future: false, onChanged: (f) => setState(() => _future = f)),
              ),
      ),
    );
  }
}

/// Переключатель «История / Будущие».
class _ModeSwitch extends ConsumerWidget {
  const _ModeSwitch({required this.future, required this.onChanged});

  final bool future;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider).value ?? const [];
    final today = dayOf(DateTime.now());
    final soon = upcoming(plans, to: DateTime(today.year, today.month + 1, today.day))
        .where((o) => o.index == o.plan.doneCount)
        .length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        spacing: 8,
        children: [
          ChoiceChip(
            avatar: const Icon(Icons.history, size: 18),
            label: const Text('История'),
            selected: !future,
            showCheckmark: false,
            onSelected: (_) => onChanged(false),
          ),
          ChoiceChip(
            avatar: const Icon(Icons.event_outlined, size: 18),
            label: Text(soon > 0 ? 'Будущие · $soon' : 'Будущие'),
            selected: future,
            showCheckmark: false,
            onSelected: (_) => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.ledger, required this.period, required this.filter, required this.switcher});

  final Ledger ledger;
  final Period period;
  final OperationFilter filter;
  final Widget? switcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searching = filter.query.trim().isNotEmpty;
    final filtered = filter.hasFilters || period.kind != PeriodKind.all;
    // Поиск — по всей истории; иначе — за выбранный период (по умолчанию всё время).
    final source = searching ? ledger.operations : ledger.inPeriod(period);
    final ops = source.where(filter.matches).toList();

    final header = <Widget>[
      ?switcher,
      if (filtered) _ActiveFilters(ledger: ledger, filter: filter, period: period),
      const _BackupReminder(),
      if (!searching && !filtered) _DueNow(ledger: ledger),
      if (searching)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Найдено: ${ops.length}'),
        )
      else if (filtered && ops.isNotEmpty)
        _SummaryCard(totals: PeriodTotals.of(ops), base: ledger.base),
    ];

    if (ops.isEmpty) {
      final noData = ledger.operations.isEmpty;
      return ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ...header,
          const SizedBox(height: 48),
          EmptyState(
            icon: noData ? Icons.receipt_long_outlined : Icons.search_off,
            title: noData ? 'Пока нет операций' : 'Ничего не найдено',
            subtitle: noData
                ? 'Нажмите «+», чтобы записать первый расход или доход'
                : 'Попробуйте изменить поиск или сбросить фильтр',
          ),
        ],
      );
    }

    // Список: заголовок месяца с итогами, дни, операции.
    final items = <Object>[];
    DateTime? month, day;
    final monthOps = <DateTime, List<OperationView>>{};
    final dayOps = <DateTime, List<OperationView>>{};
    for (final v in ops) {
      final m = DateTime(v.date.year, v.date.month);
      final d = dayOf(v.date);
      monthOps.putIfAbsent(m, () => []).add(v);
      dayOps.putIfAbsent(d, () => []).add(v);
      if (m != month) {
        month = m;
        items.add(_MonthKey(m));
      }
      if (d != day) {
        day = d;
        items.add(d);
      }
      items.add(v);
    }
    final monthTotals = {for (final e in monthOps.entries) e.key: PeriodTotals.of(e.value)};
    final dayTotals = {for (final e in dayOps.entries) e.key: PeriodTotals.of(e.value)};

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: header.length + items.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final item = items[i - header.length];
        if (item is _MonthKey) {
          return _MonthHeader(month: item.month, totals: monthTotals[item.month]!, base: ledger.base);
        }
        if (item is DateTime) {
          return _DayHeader(day: item, totals: dayTotals[item]!, base: ledger.base);
        }
        final v = item as OperationView;
        return OperationTile(
          view: v,
          base: ledger.base,
          onTap: () => context.push(Routes.operationEdit(v.op.id)),
        );
      },
    );
  }
}

class _MonthKey {
  const _MonthKey(this.month);
  final DateTime month;
}

/// Будущие платежи по регулярным планам на два месяца вперёд.
class _FutureList extends ConsumerWidget {
  const _FutureList({required this.ledger, required this.switcher});

  final Ledger ledger;
  final Widget switcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider).value ?? const [];
    final today = dayOf(DateTime.now());
    final list = upcoming(plans, to: DateTime(today.year, today.month + 2, today.day));
    if (list.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          switcher,
          const SizedBox(height: 48),
          const EmptyState(
            icon: Icons.event_repeat,
            title: 'Будущих платежей нет',
            subtitle: 'Здесь будут ближайшие регулярные платежи и поступления: '
                'аренда, зарплата, подписки.',
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.tonalIcon(
              onPressed: () => context.push(Routes.planNew()),
              icon: const Icon(Icons.add),
              label: const Text('Добавить регулярный платёж'),
            ),
          ),
        ],
      );
    }
    final children = <Widget>[switcher];
    DateTime? day;
    for (final o in list) {
      final d = o.date.isBefore(today) ? today : o.date;
      if (d != day) {
        day = d;
        children.add(_DayHeader(day: d, base: ledger.base, label: o.date.isBefore(today) ? 'Просрочено' : null));
      }
      children.add(UpcomingTile(occurrence: o, ledger: ledger));
    }
    return ListView(padding: const EdgeInsets.only(bottom: 96), children: children);
  }
}

/// Платежи на сегодня и просроченные — прямо в истории.
class _DueNow extends ConsumerWidget {
  const _DueNow({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider).value ?? const [];
    final due = [
      for (final o in upcoming(plans, to: dayOf(DateTime.now())))
        if (o.index == o.plan.doneCount) o,
    ];
    if (due.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text('Платежи на сегодня', style: theme.textTheme.titleSmall),
          ),
          for (final o in due) UpcomingTile(occurrence: o, ledger: ledger),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totals, required this.base});

  final PeriodTotals totals;
  final Currency base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
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
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            cell('Доходы', base.format(totals.income), colors.income),
            cell('Расходы', base.format(totals.expense), colors.expense),
            cell('Итого', base.format(totals.net, signed: true), null),
          ],
        ),
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.totals, required this.base});

  final DateTime month;
  final PeriodTotals totals;
  final Currency base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final small = theme.textTheme.labelMedium;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: Text(formatMonthFull(month), style: theme.textTheme.titleSmall)),
          if (totals.income > 0) Text('+${base.formatRounded(totals.income)}', style: small?.copyWith(color: colors.income)),
          if (totals.income > 0 && totals.expense > 0) const SizedBox(width: 10),
          if (totals.expense > 0) Text('−${base.formatRounded(totals.expense)}', style: small?.copyWith(color: colors.expense)),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.base, this.totals, this.label});

  final DateTime day;
  final PeriodTotals? totals;
  final Currency base;

  /// Подпись вместо даты («Просрочено»).
  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600);
    final t = totals;
    final hasMoney = t != null && (t.income != 0 || t.expense != 0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(child: Text(label ?? capitalize(formatDayHeader(day)), style: style)),
          if (hasMoney)
            Text(
              base.format(t.net, signed: true),
              style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.ledger, required this.filter, required this.period});

  final Ledger ledger;
  final OperationFilter filter;
  final Period period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(operationFilterProvider.notifier);
    final account = ledger.accounts[filter.accountId];
    final category = ledger.categories[filter.categoryId];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        spacing: 8,
        children: [
          if (period.kind != PeriodKind.all)
            InputChip(
              avatar: const Icon(Icons.date_range, size: 18),
              label: Text(period.label),
              onDeleted: () => ref.read(operationsPeriodProvider.notifier).select(Period.all()),
            ),
          for (final k in filter.kinds)
            InputChip(
              label: Text(k.label),
              onDeleted: () => notifier.set(filter.copyWith(kinds: {...filter.kinds}..remove(k))),
            ),
          if (account != null)
            InputChip(
              avatar: const Icon(Icons.account_balance_wallet_outlined, size: 18),
              label: Text(account.name),
              onDeleted: () => notifier.set(filter.copyWith(accountId: () => null)),
            ),
          if (category != null)
            InputChip(
              avatar: const Icon(Icons.category_outlined, size: 18),
              label: Text(category.name),
              onDeleted: () => notifier.set(filter.copyWith(categoryId: () => null)),
            ),
          if (filter.payee != null)
            InputChip(
              avatar: const Icon(Icons.storefront_outlined, size: 18),
              label: Text(filter.payee!.isEmpty ? 'Без получателя' : filter.payee!),
              onDeleted: () => notifier.set(filter.copyWith(payee: () => null)),
            ),
          TextButton(
            onPressed: () {
              notifier.reset();
              ref.read(operationsPeriodProvider.notifier).select(Period.all());
            },
            child: const Text('Сбросить'),
          ),
        ],
      ),
    );
  }
}

/// Напоминание о резервной копии: данные живут только в этом браузере.
class _BackupReminder extends ConsumerWidget {
  const _BackupReminder();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ops = ref.watch(operationsProvider).value ?? const [];
    final last = ref.watch(lastBackupProvider);
    final snooze = ref.watch(backupSnoozeUntilProvider);
    if (!last.hasValue || !snooze.hasValue || ops.length < 5) return const SizedBox.shrink();
    final now = DateTime.now();
    final lastBackup = last.value;
    if (lastBackup != null && now.difference(lastBackup).inDays < 7) return const SizedBox.shrink();
    final until = snooze.value;
    if (until != null && now.isBefore(until)) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.cloud_upload_outlined, color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Сохраните резервную копию', style: theme.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(
                        lastBackup == null
                            ? 'Данные хранятся только на этом устройстве.'
                            : 'Последняя копия — ${formatDate(lastBackup)}.',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => ref
                      .read(settingsRepositoryProvider)
                      .setBackupSnoozeUntil(now.add(const Duration(days: 3))),
                  child: const Text('Позже'),
                ),
                FilledButton.tonal(
                  onPressed: () => context.go(Routes.backup),
                  child: const Text('Сохранить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
