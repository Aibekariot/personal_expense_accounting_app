import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialogs.dart';
import '../../core/widgets/empty_state.dart';
import '../../core/widgets/period_bar.dart';
import '../../data/providers.dart';
import '../../domain/operation_filter.dart';
import '../../domain/payees.dart';
import '../../domain/period.dart';
import '../../domain/providers.dart';

class _AllTimeNotifier extends PeriodNotifier {
  @override
  Period build() => Period.all();
}

final _payeesPeriodProvider = NotifierProvider<PeriodNotifier, Period>(_AllTimeNotifier.new);

/// Получатели (кому платим) и плательщики (кто платит нам) с итогами.
class PayeesScreen extends ConsumerStatefulWidget {
  const PayeesScreen({super.key});

  @override
  ConsumerState<PayeesScreen> createState() => _PayeesScreenState();
}

class _PayeesScreenState extends ConsumerState<PayeesScreen> {
  bool _income = false;
  String _query = '';

  void _open(Period period, String name) {
    ref.read(operationsPeriodProvider.notifier).select(period);
    ref.read(operationFilterProvider.notifier).set(OperationFilter(
      kinds: {_income ? OperationKind.income : OperationKind.expense},
      payee: name,
    ));
    context.go(Routes.operations);
  }

  Future<void> _rename(String name) async {
    final controller = TextEditingController(text: name);
    final next = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Переименовать'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(),
            ),
            const SizedBox(height: 8),
            const Text(
              'Имя изменится во всех операциях. Если такое имя уже есть — '
              'получатели объединятся (удобно для «Глобус» и «глобус цум»).',
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Сохранить')),
        ],
      ),
    );
    if (next == null || next.trim().isEmpty || next.trim() == name) return;
    final count = await ref.read(operationRepositoryProvider).renamePayee(name, next);
    if (mounted) showSnack(context, 'Изменено операций: $count');
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final period = ref.watch(_payeesPeriodProvider);
    final theme = Theme.of(context);
    final colors = MoneyColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Получатели и плательщики')),
      body: ledger.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (l) {
          final q = _query.trim().toLowerCase();
          final stats = payeeStats(l, period: period)
              .where((s) => _income ? s.income > 0 : s.expense > 0)
              .where((s) => q.isEmpty || s.name.toLowerCase().contains(q))
              .toList()
            ..sort((a, b) => (_income ? b.income : b.expense).compareTo(_income ? a.income : a.expense));
          final total = stats.fold(0, (s, e) => s + (_income ? e.income : e.expense));

          return ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              PeriodBar(period: period, onChanged: ref.read(_payeesPeriodProvider.notifier).select),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Получатели')),
                    ButtonSegment(value: true, label: Text('Плательщики')),
                  ],
                  selected: {_income},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _income = s.first),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Поиск',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              if (stats.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 48),
                  child: EmptyState(
                    icon: Icons.storefront_outlined,
                    title: _income ? 'Плательщиков пока нет' : 'Получателей пока нет',
                    subtitle: 'Указывайте получателя при вводе операции — например, «Глобус». '
                        'В следующий раз категория подставится сама, а здесь будет видно, '
                        'сколько вы тратите в каждом месте.',
                  ),
                )
              else
                for (final s in stats)
                  ListTile(
                    leading: CircleAvatar(child: Text(s.name.characters.first.toUpperCase())),
                    title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      '${s.count} опер. · последняя ${formatShortDate(s.lastUsed!)}'
                      '${total > 0 ? ' · ${formatPercent((_income ? s.income : s.expense) / total)}' : ''}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l.base.format(_income ? s.income : s.expense),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: _income ? colors.income : colors.expense,
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (_) => _rename(s.name),
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('Переименовать или объединить')),
                          ],
                        ),
                      ],
                    ),
                    onTap: () => _open(period, s.name),
                  ),
            ],
          );
        },
      ),
    );
  }
}
