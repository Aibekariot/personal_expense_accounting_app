import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../features/accounts/accounts_overview.dart';
import '../formatters.dart';

/// Общий баланс в заголовке экрана. Нажатие — скрыть или показать суммы
/// (удобно, когда телефон смотрят через плечо).
class BalanceTitle extends ConsumerWidget {
  const BalanceTitle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overview = ref.watch(accountsOverviewProvider).value;
    final hidden = ref.watch(hideBalanceProvider).value ?? false;
    final theme = Theme.of(context);
    if (overview == null) return const SizedBox.shrink();

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => ref.read(settingsRepositoryProvider).setHideBalance(!hidden),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                hidden ? '••• ${overview.base.symbol}' : overview.base.formatRounded(overview.capital),
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 4,
              children: [
                Text(
                  'Баланс',
                  style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                Icon(
                  hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Скрыта ли сумма: вместо цифр показывать «•••».
String maskedAmount(WidgetRef ref, String formatted) =>
    (ref.watch(hideBalanceProvider).value ?? false) ? '•••' : formatted;
