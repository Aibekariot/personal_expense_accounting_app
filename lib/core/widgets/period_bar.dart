import 'package:flutter/material.dart';

import '../../domain/period.dart';

/// Переключатель периода: ‹ Ноябрь 2026 ›. Нажатие на название — выбор периода.
class PeriodBar extends StatelessWidget {
  const PeriodBar({
    super.key,
    required this.period,
    required this.onChanged,
    this.monthsOnly = false,
  });

  final Period period;
  final ValueChanged<Period> onChanged;

  /// Только месяцы (для бюджетов).
  final bool monthsOnly;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final options = <(String, Period Function())>[
      ('Этот месяц', () => Period.month(now)),
      ('Прошлый месяц', () => Period.month(DateTime(now.year, now.month - 1))),
      if (!monthsOnly) ...[
        ('Этот год', () => Period.year(now)),
        ('Прошлый год', () => Period.year(DateTime(now.year - 1))),
        ('Всё время', Period.all),
      ],
    ];
    final result = await showModalBottomSheet<Object>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, make) in options)
              ListTile(
                title: Text(label),
                trailing: make() == period ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, make()),
              ),
            if (!monthsOnly)
              ListTile(
                leading: const Icon(Icons.date_range),
                title: const Text('Выбрать даты…'),
                onTap: () => Navigator.pop(ctx, 'custom'),
              ),
          ],
        ),
      ),
    );
    if (!context.mounted || result == null) return;
    if (result is Period) {
      onChanged(result);
      return;
    }
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 5),
      initialDateRange: period.kind == PeriodKind.all
          ? null
          : DateTimeRange(start: period.start, end: period.lastDay),
      helpText: 'Период',
      saveText: 'Готово',
    );
    if (range != null) onChanged(Period.custom(range.start, range.end));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Предыдущий период',
            onPressed: period.canStep ? () => onChanged(period.previous!) : null,
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: TextButton(
              onPressed: () => _pick(context),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      period.label,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'Следующий период',
            onPressed: period.canStep ? () => onChanged(period.next!) : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}
