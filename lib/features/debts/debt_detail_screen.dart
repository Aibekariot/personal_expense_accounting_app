import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../domain/debts.dart';
import '../../domain/providers.dart';
import '../operations/operation_tile.dart';

class DebtDetailScreen extends ConsumerWidget {
  const DebtDetailScreen({super.key, required this.debtId});

  final int debtId;

  Future<void> _delete(BuildContext context, WidgetRef ref, DebtView v) async {
    final hasOps = v.operations.isNotEmpty;
    final ok = await confirmDialog(
      context,
      title: 'Удалить долг «${v.debt.personName}»?',
      message: hasOps
          ? 'Вместе с долгом удалятся его операции (${v.operations.length}), '
              'и балансы счетов изменятся. Если долг просто погашен — лучше закройте его.'
          : null,
    );
    if (!ok) return;
    await ref.read(debtRepositoryProvider).delete(v.debt.id);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debts = ref.watch(debtViewsProvider);
    final ledger = ref.watch(ledgerProvider).value;
    final view = debts.value?.where((d) => d.debt.id == debtId).firstOrNull;

    if (view == null || ledger == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: debts.isLoading ? const CircularProgressIndicator() : const Text('Долг не найден'),
        ),
      );
    }
    final d = view.debt;
    final repo = ref.read(debtRepositoryProvider);
    final (repayType, increaseType) = view.theyOwe
        ? (OperationType.debtIn, OperationType.debtOut)
        : (OperationType.debtOut, OperationType.debtIn);

    return Scaffold(
      appBar: AppBar(
        title: Text(d.personName),
        actions: [
          IconButton(
            tooltip: 'Изменить',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => context.push(Routes.debtEdit(d.id)),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'close') {
                await repo.setClosed(d.id, !d.isClosed);
                if (context.mounted) {
                  showSnack(context, d.isClosed ? 'Долг снова открыт' : 'Долг закрыт');
                }
              } else {
                if (context.mounted) await _delete(context, ref, view);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'close', child: Text(d.isClosed ? 'Открыть снова' : 'Закрыть долг')),
              const PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _Header(view: view),
          if (!d.isClosed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.push(Routes.operationNew(type: repayType, debtId: d.id)),
                      icon: const Icon(Icons.payments_outlined),
                      label: Text(view.theyOwe ? 'Мне вернули' : 'Я вернул'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(Routes.operationNew(type: increaseType, debtId: d.id)),
                      icon: const Icon(Icons.add),
                      label: Text(view.theyOwe ? 'Дал ещё' : 'Взял ещё'),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text('История', style: Theme.of(context).textTheme.titleMedium),
          ),
          if (d.initialAmount > 0)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.history)),
              title: const Text('Долг до начала учёта'),
              subtitle: Text('с ${formatDate(d.createdAt)}'),
              trailing: Text(view.currency.format(d.initialAmount)),
            ),
          for (final v in view.operations)
            OperationTile(
              view: v,
              base: ledger.base,
              showDate: true,
              onTap: () => context.push(Routes.operationEdit(v.op.id)),
            ),
          if (view.operations.isEmpty && d.initialAmount == 0)
            const Padding(padding: EdgeInsets.all(16), child: Text('Операций нет')),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.view});

  final DebtView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);
    final d = view.debt;
    final color = view.theyOwe ? colors.income : colors.expense;
    final overdue = view.isOverdue(DateTime.now());
    final progress = view.total <= 0 ? 0.0 : (view.repaid / view.total).clamp(0.0, 1.0);

    return Card.filled(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              d.isClosed ? 'Долг закрыт' : (view.theyOwe ? 'Мне должны' : 'Я должен'),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 4),
            Text(
              view.currency.format(view.remaining),
              style: theme.textTheme.headlineMedium?.copyWith(color: color, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                color: color,
                backgroundColor: color.withValues(alpha: 0.15),
              ),
            ),
            const SizedBox(height: 8),
            Text('Возвращено ${view.currency.format(view.repaid)} из ${view.currency.format(view.total)}'),
            if (d.dueDate != null) ...[
              const SizedBox(height: 4),
              Text(
                overdue ? 'Срок прошёл: ${formatDate(d.dueDate!)}' : 'Вернуть до ${formatDate(d.dueDate!)}',
                style: overdue ? TextStyle(color: theme.colorScheme.error) : null,
              ),
            ],
            if (d.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(d.note, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
