import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app/app.dart';
import 'core/platform/file_io.dart' as io;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'ru';
  await initializeDateFormatting('ru');
  // Просим браузер не удалять данные приложения при нехватке места.
  io.requestPersistentStorage();
  runApp(const ProviderScope(child: FinanceApp()));
}
