import 'package:flutter/material.dart';

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  static const _items = [
    (icon: Icons.currency_exchange, title: 'Валюты и курсы', subtitle: 'Свои валюты, курсы, конвертер'),
    (icon: Icons.category_outlined, title: 'Категории', subtitle: 'Категории доходов и расходов'),
    (icon: Icons.track_changes, title: 'Бюджеты', subtitle: 'Месячные лимиты по категориям'),
    (icon: Icons.handshake_outlined, title: 'Долги', subtitle: 'Кто кому и сколько должен'),
    (icon: Icons.backup_outlined, title: 'Резервная копия', subtitle: 'Сохранить и восстановить данные'),
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
              trailing: const Text('скоро'),
              enabled: false,
            ),
        ],
      ),
    );
  }
}
