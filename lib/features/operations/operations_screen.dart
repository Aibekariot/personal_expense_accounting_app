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
import '../../data/providers.dart';
import '../../domain/ledger.dart';
import '../../domain/operation_filter.dart';
import '../../domain/period.dart';
import '../../domain/providers.dart';
import '../../domain/stats.dart';
import '../accounts/accounts_overview.dart';
import '../plans/upcoming_tile.dart';
import '../../domain/schedule.dart';
import 'filter_sheet.dart';
import 'operation_tile.dart';

/// История операций: по дням, с итогами, поиском и фильтрами.
class OperationsScreen extends ConsumerStatefulWidget {
  const OperationsScreen({super.key});

  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  final _search = TextEditingController();
  bool _searching = false;

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

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Категория, комментарий, сумма…',
                  border: InputBorder.none,
                ),
                onChanged: ref.read(operationFilterProvider.notifier).setQuery,
              )
            : const Text('Операции'),
        actions: [
          if (_searching)
            IconButton(
              tooltip: 'Закрыть поиск',
              icon: const Icon(Icons.close),
              onPressed: _closeSearch,
            )
          else
            IconButton(
              tooltip: 'Поиск',
              icon: const Icon(Icons.search),
              onPressed: () => setState(() => _searching = true),
            ),
          IconButton(
            tooltip: 'Фильтр',
            onPressed: ledger.hasValue ? () => showFilterSheet(context, ref, ledger.requireValue) : null,
            icon: Badge(
              isLabelVisible: filter.hasFilters,
              child: const Icon(Icons.filter_list),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.operationNew()),
        icon: const Icon(Icons.add),
        label: const Text('Добавить'),
      ),
      body: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
        data: (l) => _History(ledger: l, period: period, filter: filter),
      ),
    );
  }
}

class _History extends ConsumerWidget {
  const _History({required this.ledger, required this.period, required this.filter});

  final Ledger ledger;
  final Period period;
  final OperationFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searching = filter.query.trim().isNotEmpty;
    // Поиск — по всем периодам, иначе — за выбранный период.
    final source = searching ? ledger.operations : ledger.inPeriod(period);
    final ops = source.where(filter.matches).toList();

    final header = <Widget>[
      if (!searching) _BalanceHeader(filter: filter),
      if (!searching)
        PeriodBar(
          period: period,
          onChanged: ref.read(operationsPeriodProvider.notifier).select,
        ),
      if (filter.hasFilters) _ActiveFilters(ledger: ledger, filter: filter),
      const _BackupReminder(),
      if (!searching && !filter.hasFilters) _UpcomingBlock(ledger: ledger),
      if (searching)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Найдено во всех периодах: ${ops.length}'),
        )
      else if (ops.isNotEmpty)
        _SummaryCard(totals: PeriodTotals.of(ops), base: ledger.base),
    ];

    if (ops.isEmpty) {
      final noData = ledger.operations.isEmpty;
      return ListView(
        children: [
          ...header,
          const SizedBox(height: 48),
          EmptyState(
            icon: noData ? Icons.receipt_long_outlined : Icons.search_off,
            title: noData
                ? 'Пока нет операций'
                : searching
                    ? 'Ничего не найдено'
                    : 'За этот период операций нет',
            subtitle: noData
                ? 'Нажмите «Добавить», чтобы записать первый расход или доход'
                : filter.hasFilters
                    ? 'Попробуйте сбросить фильтр'
                    : null,
          ),
        ],
      );
    }

    // Список: заголовок дня, затем операции этого дня.
    final byDay = <DateTime, List<OperationView>>{};
    for (final v in ops) {
      byDay.putIfAbsent(dayOf(v.date), () => []).add(v);
    }
    final items = <Object>[
      for (final e in byDay.entries) ...[e.key, ...e.value],
    ];
    final dayTotals = {for (final e in byDay.entries) e.key: PeriodTotals.of(e.value)};

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: header.length + items.length,
      itemBuilder: (context, i) {
        if (i < header.length) return header[i];
        final item = items[i - header.length];
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
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Column(
          children: [
            Row(
              children: [
                cell('Доходы', base.format(totals.income), colors.income),
                cell('Расходы', base.format(totals.expense), colors.expense),
                cell('Итого', base.format(totals.net, signed: true), null),
              ],
            ),
            if (totals.unconverted.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Не учтено операций без курса валюты: ${totals.unconverted.length}',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.totals, required this.base});

  final DateTime day;
  final PeriodTotals totals;
  final Currency base;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary);
    final hasMoney = totals.income != 0 || totals.expense != 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Expanded(child: Text(capitalize(formatDayHeader(day)), style: style)),
          if (hasMoney) Text(base.format(totals.net, signed: true), style: style),
        ],
      ),
    );
  }
}

class _ActiveFilters extends ConsumerWidget {
  const _ActiveFilters({required this.ledger, required this.filter});

  final Ledger ledger;
  final OperationFilter filter;

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
          TextButton(onPressed: notifier.reset, child: const Text('Сбросить')),
        ],
      ),
    );
  }
}

/// Ближайшие и просроченные плановые платежи (на неделю вперёд).
class _UpcomingBlock extends ConsumerWidget {
  const _UpcomingBlock({required this.ledger});

  final Ledger ledger;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plans = ref.watch(plansProvider).value ?? const [];
    final today = dayOf(DateTime.now());
    // По одному (ближайшему) повторению каждого плана.
    final soon = [
      for (final o in upcoming(plans, to: DateTime(today.year, today.month, today.day + 7)))
        if (o.index == o.plan.doneCount) o,
    ];
    if (soon.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    const shown = 4;
    return Card.outlined(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
            child: Row(
              children: [
                Expanded(child: Text('Скоро', style: theme.textTheme.titleSmall)),
                TextButton(
                  onPressed: () => context.push(Routes.plans),
                  child: Text(soon.length > shown ? 'Все (${soon.length})' : 'Все планы'),
                ),
              ],
            ),
          ),
          for (final o in soon.take(shown)) UpcomingTile(occurrence: o, ledger: ledger),
        ],
      ),
    );
  }
}

/// Общий баланс и счета. Нажатие на счёт — показать только его операции.
class _BalanceHeader extends ConsumerWidget {
  const _BalanceHeader({required this.filter});

  final OperationFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(accountsOverviewProvider).value;
    if (overview == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final notifier = ref.read(operationFilterProvider.notifier);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Баланс', style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurfaceVariant)),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    overview.base.format(overview.capital),
                    style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 8,
              children: [
                for (final v in overview.active)
                  FilterChip(
                    avatar: Icon(accountTypeIcon(v.account.type), size: 18, color: Color(v.account.color)),
                    label: Text('${v.account.name}  ${v.currency.format(v.balance)}'),
                    selected: filter.accountId == v.account.id,
                    showCheckmark: false,
                    onSelected: (on) => notifier.set(
                      filter.copyWith(accountId: () => on ? v.account.id : null),
                    ),
                  ),
              ],
            ),
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

    final scheme = Theme.of(context).colorScheme;
    return Card.filled(
      color: scheme.tertiaryContainer,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.backup_outlined, color: scheme.onTertiaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    lastBackup == null
                        ? 'Сохраните резервную копию: данные хранятся только в этом браузере.'
                        : 'Последняя резервная копия — ${formatDate(lastBackup)}. Сохраните свежую.',
                    style: TextStyle(color: scheme.onTertiaryContainer),
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
