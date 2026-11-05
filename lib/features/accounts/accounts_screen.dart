import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_icons.dart';
import '../../data/db/app_database.dart';
import '../../data/db/database_provider.dart';

final accountsProvider = StreamProvider<List<Account>>((ref) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.accounts)
    ..where((a) => a.isArchived.equals(false))
    ..orderBy([(a) => OrderingTerm(expression: a.sortOrder)]);
  return query.watch();
});

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Счета')),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
        data: (list) => ListView(
          children: [
            for (final a in list)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: Color(a.color).withValues(alpha: 0.15),
                  foregroundColor: Color(a.color),
                  child: Icon(accountTypeIcon(a.type)),
                ),
                title: Text(a.name),
                subtitle: Text('${accountTypeLabel(a.type)} · ${a.currencyCode}'),
              ),
          ],
        ),
      ),
    );
  }
}
