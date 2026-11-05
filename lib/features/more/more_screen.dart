import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/platform/file_io.dart' as io;

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _items = [
    (icon: Icons.handshake_outlined, title: 'Долги', subtitle: 'Кто кому и сколько должен', route: Routes.debts),
    (icon: Icons.track_changes, title: 'Бюджеты', subtitle: 'Месячные лимиты по категориям', route: Routes.budgets),
    (icon: Icons.storefront_outlined, title: 'Получатели и плательщики', subtitle: 'Где и сколько тратите, переименование', route: Routes.payees),
    (icon: Icons.category_outlined, title: 'Категории', subtitle: 'Категории доходов и расходов', route: Routes.categories),
    (icon: Icons.currency_exchange, title: 'Валюты и курсы', subtitle: 'Свои валюты, основная валюта, курсы', route: Routes.currencies),
    (icon: Icons.calculate_outlined, title: 'Конвертер валют', subtitle: 'Пересчитать сумму во все валюты', route: Routes.converter),
    (icon: Icons.backup_outlined, title: 'Резервная копия', subtitle: 'Сохранить, восстановить, выгрузить в Excel', route: Routes.backup),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ещё')),
      body: ListView(
        children: [
          for (final item in _items)
            ListTile(
              leading: Icon(item.icon),
              title: Text(item.title),
              subtitle: Text(item.subtitle),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(item.route),
            ),
          if (!io.isInstalledApp())
            ListTile(
              leading: const Icon(Icons.install_mobile),
              title: const Text('Установить на телефон'),
              subtitle: const Text('Иконка на главном экране, как у обычного приложения'),
              onTap: () => _showInstallHelp(context),
            ),
        ],
      ),
    );
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
