import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/platform/file_io.dart' as io;
import '../../data/providers.dart';

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final themeMode = ref.watch(themeModeProvider).value ?? 'dark';
    final hideBalance = ref.watch(hideBalanceProvider).value ?? false;

    Widget item(IconData icon, String title, {String? subtitle, String? route, VoidCallback? onTap}) =>
        ListTile(
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap ?? (route == null ? null : () => context.push(route)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Card(
            color: theme.colorScheme.primaryContainer,
            margin: const EdgeInsets.only(bottom: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.bar_chart_rounded, color: theme.colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Мои финансы', style: theme.textTheme.titleMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.w600,
                        )),
                        Text(
                          'Все функции бесплатно. Данные — только на этом устройстве.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          _Group(children: [
            item(Icons.track_changes, 'Бюджет', subtitle: 'План и факт на месяц', route: Routes.budgets),
            item(Icons.handshake_outlined, 'Долги', subtitle: 'Кто кому и сколько должен', route: Routes.debts),
            item(Icons.storefront_outlined, 'Получатели и плательщики', route: Routes.payees),
            item(Icons.category_outlined, 'Категории', route: Routes.categories),
          ]),
          _Group(children: [
            item(Icons.currency_exchange, 'Валюты и курсы', route: Routes.currencies),
            item(Icons.calculate_outlined, 'Конвертер валют', route: Routes.converter),
          ]),
          _Group(children: [
            item(Icons.cloud_upload_outlined, 'Резервная копия', subtitle: 'Сохранить, восстановить, Excel', route: Routes.backup),
            item(
              Icons.palette_outlined,
              'Оформление',
              subtitle: switch (themeMode) {
                'light' => 'Светлая тема',
                'system' => 'Как в системе',
                _ => 'Тёмная тема',
              },
              onTap: () => _pickTheme(context, ref, themeMode),
            ),
            SwitchListTile(
              secondary: Icon(Icons.visibility_off_outlined, color: theme.colorScheme.primary),
              title: const Text('Скрывать баланс'),
              subtitle: const Text('Вместо суммы — «•••». Также можно нажать на баланс'),
              value: hideBalance,
              onChanged: (v) => ref.read(settingsRepositoryProvider).setHideBalance(v),
            ),
            if (!io.isInstalledApp())
              item(Icons.install_mobile, 'Установить на телефон', onTap: () => _showInstallHelp(context)),
          ]),
          const SizedBox(height: 8),
          Center(
            child: Text('Версия 1.1', style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            )),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTheme(BuildContext context, WidgetRef ref, String current) async {
    final mode = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: RadioGroup<String>(
          groupValue: current,
          onChanged: (v) => Navigator.pop(ctx, v),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              RadioListTile(value: 'dark', title: Text('Тёмная')),
              RadioListTile(value: 'light', title: Text('Светлая')),
              RadioListTile(value: 'system', title: Text('Как в системе')),
            ],
          ),
        ),
      ),
    );
    if (mode != null) await ref.read(settingsRepositoryProvider).setThemeMode(mode);
  }

  void _showInstallHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Установка на телефон'),
        content: const SingleChildScrollView(
          child: Text(
            'iPhone (Safari):\n'
            '1. Нажмите кнопку «Поделиться» (квадрат со стрелкой).\n'
            '2. Выберите «На экран „Домой“».\n'
            '3. Нажмите «Добавить».\n\n'
            'Android (Chrome):\n'
            '1. Нажмите ⋮ в правом верхнем углу.\n'
            '2. Выберите «Установить приложение» или «Добавить на гл. экран».\n\n'
            'Важно для iPhone: у установленного приложения своё хранилище, '
            'отдельное от Safari. Если вы уже вносили данные в Safari — '
            'сохраните резервную копию и восстановите её в установленном приложении.',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
        ],
      ),
    );
  }
}

/// Группа пунктов меню в карточке.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final divider = Divider(height: 1, indent: 56, color: Theme.of(context).colorScheme.outlineVariant);
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) divider,
            children[i],
          ],
        ],
      ),
    );
  }
}
