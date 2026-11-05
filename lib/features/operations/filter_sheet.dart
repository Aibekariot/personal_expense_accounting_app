import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/period_bar.dart';
import '../../data/db/app_database.dart';
import '../../domain/ledger.dart';
import '../../domain/operation_filter.dart';
import '../../domain/period.dart';
import '../../domain/providers.dart';

/// Нижняя панель фильтра истории: виды операций, счёт, категория.
Future<void> showFilterSheet(BuildContext context, WidgetRef ref, Ledger ledger) async {
  final current = ref.read(operationFilterProvider);
  final period = ref.read(operationsPeriodProvider);
  final result = await showModalBottomSheet<(OperationFilter, Period)>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _FilterSheet(ledger: ledger, initial: current, period: period),
  );
  if (result == null) return;
  ref.read(operationFilterProvider.notifier).set(result.$1);
  ref.read(operationsPeriodProvider.notifier).select(result.$2);
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.ledger, required this.initial, required this.period});

  final Ledger ledger;
  final OperationFilter initial;
  final Period period;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<OperationKind> _kinds = {...widget.initial.kinds};
  late int? _accountId = widget.initial.accountId;
  late int? _categoryId = widget.initial.categoryId;
  late Period _period = widget.period;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = widget.ledger;
    final accounts = l.accounts.values.toList();

    // Категории: сначала расходы, потом доходы; подкатегории — с отступом.
    final categoryItems = <DropdownMenuItem<int?>>[
      const DropdownMenuItem(value: null, child: Text('Все категории')),
    ];
    for (final type in CategoryType.values) {
      final top = l.categories.values.where((c) => c.type == type && c.parentId == null);
      for (final c in top) {
        categoryItems.add(DropdownMenuItem(
          value: c.id,
          child: Text('${type == CategoryType.income ? 'Доход: ' : ''}${c.name}'),
        ));
        for (final child in l.categories.values.where((x) => x.parentId == c.id)) {
          categoryItems.add(DropdownMenuItem(
            value: child.id,
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(child.name),
            ),
          ));
        }
      }
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Фильтр', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range),
                title: const Text('Период'),
                subtitle: Text(_period.label),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final p = await pickPeriod(context, _period);
                  if (p != null) setState(() => _period = p);
                },
              ),
              const SizedBox(height: 8),
              Text('Вид операции', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final k in OperationKind.values)
                    FilterChip(
                      label: Text(k.label),
                      selected: _kinds.contains(k),
                      onSelected: (on) => setState(() => on ? _kinds.add(k) : _kinds.remove(k)),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<int?>(
                initialValue: _accountId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Счёт'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Все счета')),
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(a.isArchived ? '${a.name} (архив)' : a.name),
                    ),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int?>(
                initialValue: _categoryId,
                isExpanded: true,
                menuMaxHeight: 400,
                decoration: const InputDecoration(
                  labelText: 'Категория',
                  helperText: 'Основная категория включает свои подкатегории',
                ),
                items: categoryItems,
                onChanged: (v) => setState(() => _categoryId = v),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(
                        context,
                        (OperationFilter(query: widget.initial.query), Period.all()),
                      ),
                      child: const Text('Сбросить'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(
                        context,
                        (
                          OperationFilter(
                            kinds: _kinds,
                            accountId: _accountId,
                            categoryId: _categoryId,
                            payee: widget.initial.payee,
                            query: widget.initial.query,
                          ),
                          _period,
                        ),
                      ),
                      child: const Text('Применить'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
