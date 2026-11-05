import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/formatters.dart';
import '../../core/widgets/balance_title.dart';
import '../../data/db/app_database.dart';
import '../../domain/debts.dart';
import '../../domain/providers.dart';
import 'accounts_overview.dart';

/// Группы счетов на экране.
enum _Group {
  everyday('Счета и карты'),
  savings('Накопления'),
  credits('Кредиты');

  const _Group(this.title);
  final String title;

  static _Group of(AccountType t) => switch (t) {
    AccountType.deposit => savings,
    AccountType.credit => credits,
    _ => everyday,
  };
}

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final _collapsed = <String>{};

  void _toggle(String key) =>
      setState(() => _collapsed.contains(key) ? _collapsed.remove(key) : _collapsed.add(key));

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(accountsOverviewProvider);
    final debts = ref.watch(debtViewsProvider).value ?? const <DebtView>[];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 64,
        title: const BalanceTitle(),
        actions: [
          IconButton(
            tooltip: 'Новый счёт',
            icon: const Icon(Icons.add),
            onPressed: () => context.push(Routes.accountNew),
          ),
        ],
      ),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
        data: (o) {
          final groups = {for (final g in _Group.values) g: <AccountView>[]};
          for (final v in o.active) {
            groups[_Group.of(v.account.type)]!.add(v);
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              if (o.missingRates.isNotEmpty) _MissingRates(codes: o.missingRates),
              for (final g in _Group.values)
                if (groups[g]!.isNotEmpty || g == _Group.everyday)
                  _GroupCard(
                    title: g.title,
                    total: _sum(groups[g]!, o),
                    base: o.base,
                    collapsed: _collapsed.contains(g.name),
                    onToggle: () => _toggle(g.name),
                    children: [
                      for (final v in groups[g]!) _AccountRow(view: v, overview: o),
                      if (groups[g]!.isEmpty)
                        const ListTile(title: Text('Нет счетов')),
                    ],
                  ),
              _DebtsCard(debts: debts, overview: o),
              if (o.archived.isNotEmpty)
                _GroupCard(
                  title: 'Архив',
                  total: null,
                  base: o.base,
                  collapsed: !_collapsed.contains('archive-open'),
                  onToggle: () => _toggle('archive-open'),
                  children: [for (final v in o.archived) _AccountRow(view: v, overview: o)],
                ),
              const SizedBox(height: 4),
              TextButton.icon(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft),
                onPressed: () => context.push(Routes.accountNew),
                icon: const Icon(Icons.add),
                label: const Text('Добавить счёт, вклад или кредит'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Сумма группы в основной валюте (счета без курса не учитываются).
  int _sum(List<AccountView> views, AccountsOverview o) =>
      views.fold(0, (s, v) => s + (v.balanceInBase ?? 0));
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.title,
    required this.total,
    required this.base,
    required this.collapsed,
    required this.onToggle,
    required this.children,
  });

  final String title;
  final int? total;
  final Currency base;
  final bool collapsed;
  final VoidCallback onToggle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(
                children: [
                  Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Icon(collapsed ? Icons.expand_more : Icons.expand_less, color: theme.colorScheme.onSurfaceVariant),
                  const Spacer(),
                  if (total != null)
                    Text(base.formatRounded(total!), style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
                ],
              ),
            ),
          ),
          if (!collapsed) ...[
            Divider(height: 1, color: theme.colorScheme.outlineVariant),
            ...children,
          ],
        ],
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({required this.view, required this.overview});

  final AccountView view;
  final AccountsOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final a = view.account;
    final color = Color(a.color);
    final isForeign = view.currency.code != overview.base.code;

    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(accountTypeIcon(a.type), color: color, size: 22),
      ),
      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: a.includeInTotal ? null : const Text('не в балансе'),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            view.currency.format(view.balance),
            style: theme.textTheme.titleMedium?.copyWith(color: view.balance < 0 ? colors.expense : null),
          ),
          if (isForeign && view.balanceInBase != null)
            Text(
              '≈ ${overview.base.formatRounded(view.balanceInBase!)}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
        ],
      ),
      onTap: () => context.push(Routes.accountEdit(a.id)),
    );
  }
}

/// Долги: сколько должны мне и сколько должен я (в основной валюте).
class _DebtsCard extends ConsumerWidget {
  const _DebtsCard({required this.debts, required this.overview});

  final List<DebtView> debts;
  final AccountsOverview overview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final ledger = ref.watch(ledgerProvider).value;
    if (ledger == null) return const SizedBox.shrink();
    final totals = DebtTotals.of(debts);
    int sum(Map<String, int> m) => m.entries.fold(
      0,
      (s, e) => s + (ledger.rates.latest.convert(e.value, ledger.currency(e.key), overview.base) ?? 0),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go(Routes.debts),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Text('Долги', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(overview.base.formatRounded(sum(totals.theyOwe)),
                  style: theme.textTheme.titleSmall?.copyWith(color: colors.income)),
              Text('  /  ', style: theme.textTheme.titleSmall),
              Text(overview.base.formatRounded(sum(totals.iOwe)),
                  style: theme.textTheme.titleSmall?.copyWith(color: colors.expense)),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingRates extends StatelessWidget {
  const _MissingRates({required this.codes});

  final List<String> codes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(Icons.warning_amber, color: theme.colorScheme.error),
        title: Text('Нет курса для ${codes.join(', ')}'),
        subtitle: const Text('Эти деньги не вошли в баланс. Укажите курс в «Валюты и курсы».'),
        onTap: () => context.go(Routes.currencies),
      ),
    );
  }
}
