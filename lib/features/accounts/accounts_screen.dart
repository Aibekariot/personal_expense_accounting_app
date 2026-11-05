import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/formatters.dart';
import 'accounts_overview.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(accountsOverviewProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Счета')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.accountNew),
        icon: const Icon(Icons.add),
        label: const Text('Счёт'),
      ),
      body: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
        data: (o) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            _CapitalCard(overview: o),
            if (o.active.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Нет счетов. Добавьте первый кнопкой «Счёт».'),
              ),
            for (final v in o.active) _AccountTile(view: v, overview: o),
            if (o.archived.isNotEmpty)
              ExpansionTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text('Архив (${o.archived.length})'),
                children: [
                  for (final v in o.archived) _AccountTile(view: v, overview: o),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CapitalCard extends StatelessWidget {
  const _CapitalCard({required this.overview});

  final AccountsOverview overview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = overview;

    return Card.filled(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Общий капитал',
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              o.base.format(o.capital),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: scheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (o.byCurrency.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  for (final t in o.byCurrency)
                    Text(
                      t.currency.format(t.amount),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                ],
              ),
            ],
            if (o.missingRates.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.warning_amber, size: 18, color: scheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Нет курса для ${o.missingRates.join(', ')} — эти деньги не '
                      'вошли в итог. Укажите курс: «Ещё» → «Валюты и курсы».',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({required this.view, required this.overview});

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
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        foregroundColor: color,
        child: Icon(accountTypeIcon(a.type)),
      ),
      title: Text(a.name),
      subtitle: Text([
        accountTypeLabel(a.type),
        if (!a.includeInTotal) 'не в капитале',
      ].join(' · ')),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            view.currency.format(view.balance),
            style: theme.textTheme.titleMedium?.copyWith(
              color: view.balance < 0 ? colors.expense : null,
            ),
          ),
          if (isForeign && view.balanceInBase != null)
            Text(
              '≈ ${overview.base.format(view.balanceInBase!)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      onTap: () => context.push(Routes.accountEdit(a.id)),
    );
  }
}
