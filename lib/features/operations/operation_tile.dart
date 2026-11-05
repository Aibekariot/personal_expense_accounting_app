import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/formatters.dart';
import '../../core/widgets/category_avatar.dart';
import '../../data/db/app_database.dart';
import '../../domain/ledger.dart';

/// Иконка операции: категория, перевод, корректировка или долг.
IconData operationIcon(OperationView v) => switch (v.type) {
  OperationType.expense || OperationType.income =>
    categoryIcon(v.category?.icon ?? v.topCategory?.icon ?? 'more'),
  OperationType.transfer =>
    v.currency.code == v.toCurrency?.code ? Icons.swap_horiz : Icons.currency_exchange,
  OperationType.adjustment => Icons.tune,
  OperationType.debtIn || OperationType.debtOut => Icons.handshake_outlined,
};

Color operationColor(BuildContext context, OperationView v) => switch (v.type) {
  OperationType.expense || OperationType.income =>
    Color(v.category?.color ?? v.topCategory?.color ?? 0xFF757575),
  _ => MoneyColors.of(context).neutral,
};

/// Сумма операции так, как её видит пользователь: «−1 500 сом»,
/// «+50 000 сом», «100 $ → 8 745 сом».
String operationAmountText(OperationView v) {
  final op = v.op;
  return switch (op.type) {
    OperationType.expense || OperationType.debtOut => v.currency.format(-op.amount),
    OperationType.income || OperationType.debtIn => v.currency.format(op.amount, signed: true),
    OperationType.adjustment => v.currency.format(op.amount, signed: true),
    OperationType.transfer => v.currency.code == v.toCurrency?.code
        ? v.currency.format(op.amount)
        : '${v.currency.format(op.amount)} → ${v.toCurrency?.format(op.toAmount ?? 0) ?? '?'}',
  };
}

Color? operationAmountColor(BuildContext context, OperationView v) {
  final colors = MoneyColors.of(context);
  return switch (v.type) {
    OperationType.expense => colors.expense,
    OperationType.income => colors.income,
    _ => null,
  };
}

class OperationTile extends StatelessWidget {
  const OperationTile({
    super.key,
    required this.view,
    required this.base,
    this.onTap,
    this.showDate = false,
  });

  final OperationView view;
  final Currency base;
  final VoidCallback? onTap;

  /// Показывать дату (в списках без группировки по дням).
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = view;
    final note = v.op.note;
    final showBase = v.baseAmount != null && v.currency.code != base.code;
    final secondary = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ListTile(
      onTap: onTap,
      leading: CategoryAvatar(icon: operationIcon(v), color: operationColor(context, v)),
      title: Text(v.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          if (showDate) formatShortDate(v.date),
          v.details,
          if (note.isNotEmpty) note,
        ].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.45),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              operationAmountText(v),
              textAlign: TextAlign.end,
              style: theme.textTheme.titleSmall?.copyWith(
                color: operationAmountColor(context, v),
              ),
            ),
            if (showBase) Text('≈ ${base.format(v.baseAmount!)}', style: secondary),
          ],
        ),
      ),
    );
  }
}
