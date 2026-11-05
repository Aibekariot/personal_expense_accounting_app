import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Единственный экземпляр базы данных на всё приложение.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
