import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Каркас с нижней навигацией (на телефоне) или боковой (на широком экране).
class HomeShell extends StatelessWidget {
  const HomeShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _destinations = [
    (icon: Icons.receipt_long_outlined, selected: Icons.receipt_long, label: 'Операции'),
    (icon: Icons.account_balance_wallet_outlined, selected: Icons.account_balance_wallet, label: 'Счета'),
    (icon: Icons.pie_chart_outline, selected: Icons.pie_chart, label: 'Статистика'),
    (icon: Icons.menu, selected: Icons.menu, label: 'Ещё'),
  ];

  void _onSelect(int index) {
    // Повторное нажатие на текущую вкладку возвращает в её начало.
    shell.goBranch(index, initialLocation: index == shell.currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: _onSelect,
              labelType: NavigationRailLabelType.all,
              destinations: [
                for (final d in _destinations)
                  NavigationRailDestination(
                    icon: Icon(d.icon),
                    selectedIcon: Icon(d.selected),
                    label: Text(d.label),
                  ),
              ],
            ),
            const VerticalDivider(width: 1),
            Expanded(child: shell),
          ],
        ),
      );
    }

    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: _onSelect,
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selected),
              label: d.label,
            ),
        ],
      ),
    );
  }
}
