import 'package:flutter/material.dart';

import '../../core/widgets/empty_state.dart';

class OperationsScreen extends StatelessWidget {
  const OperationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Операции')),
      body: const EmptyState(
        icon: Icons.receipt_long_outlined,
        title: 'Операций пока нет',
        subtitle: 'Здесь будет история доходов, расходов и переводов',
      ),
    );
  }
}
