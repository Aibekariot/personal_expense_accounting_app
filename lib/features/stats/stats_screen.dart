import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: const EmptyState(
        icon: Icons.pie_chart_outline,
        title: 'Пока нечего показать',
        subtitle: 'Статистика появится после добавления операций',
      ),
    );
  }
}
