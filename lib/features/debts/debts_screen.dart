import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../core/widgets/empty_state.dart';
import '../../domain/debts.dart';
import '../../domain/ledger.dart';
import '../../domain/providers.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtViewsProvider);
    final ledger = ref.watch(ledgerProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Долги')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.debtNew),
        icon: const Icon(Icons.add),
        label: const Text('Долг'),
      ),
      body: debts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (all) {
          if (all.isEmpty || ledger == null) {
            return const EmptyState(
              icon: Icons.handshake_outlined,
              title: 'Долгов нет',
              subtitle: 'Записывайте, кому вы дали в долг и у кого взяли. '
                  'Приложение посчитает остаток и напомнит о сроке.',
            );
          }
          final open = all.where((d) => !d.debt.isClosed).toList();
          final theyOwe = open.where((d) => d.theyOwe).toList();
          final iOwe = open.where((d) => !d.theyOwe).toList();
          final closed = all.where((d) => d.debt.isClosed).toList();
          final totals = DebtTotals.of(all);

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              _TotalsCard(totals: totals, ledger: ledger),
              if (theyOwe.isNotEmpty) ...[
                const _Header('Мне должны'),
                for (final d in theyOwe) DebtTile(view: d),
              ],
              if (iOwe.isNotEmpty) ...[
                const _Header('Я должен'),
                for (final d in iOwe) DebtTile(view: d),
              ],
              if (closed.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.task_alt),
                  title: Text('Закрытые (${closed.length})'),
                  children: [for (final d in closed) DebtTile(view: d)],
                ),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals, required this.ledger});

  final DebtTotals totals;
  final Ledger ledger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    String sum(Map<String, int> m) => m.isEmpty
        ? '0'
        : m.entries.map((e) => ledger.currency(e.key).format(e.value)).join('\n');
    Widget cell(String label, Map<String, int> m, Color color) => Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(sum(m), textAlign: TextAlign.center, style: theme.textTheme.titleMedium?.copyWith(color: color)),
        ],
      ),
    );
    return Card.filled(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cell('Мне должны', totals.theyOwe, colors.income),
            cell('Я должен', totals.iOwe, colors.expense),
          ],
        ),
      ),
    );
  }
}

class DebtTile extends StatelessWidget {
  const DebtTile({super.key, required this.view});

  final DebtView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final d = view.debt;
    final overdue = view.isOverdue(DateTime.now());
    final details = [
      if (d.dueDate != null) overdue ? 'просрочен с ${formatDate(d.dueDate!)}' : 'вернуть до ${formatDate(d.dueDate!)}',
      if (d.note.isNotEmpty) d.note,
    ];
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (view.theyOwe ? colors.income : colors.expense).withValues(alpha: 0.15),
        foregroundColor: view.theyOwe ? colors.income : colors.expense,
        child: Icon(view.theyOwe ? Icons.call_made : Icons.call_received),
      ),
      title: Text(d.personName),
      subtitle: details.isEmpty
          ? null
          : Text(
              details.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
            ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            view.currency.format(view.remaining),
            style: theme.textTheme.titleMedium?.copyWith(
              color: d.isClosed ? null : (view.theyOwe ? colors.income : colors.expense),
            ),
          ),
          if (view.repaid > 0 && view.remaining > 0)
            Text('из ${view.currency.format(view.total)}', style: theme.textTheme.bodySmall),
        ],
      ),
      onTap: () => context.push(Routes.debt(d.id)),
    );
  }
}
