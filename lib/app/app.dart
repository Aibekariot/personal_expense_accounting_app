import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/platform/file_io.dart' as io;
import '../data/providers.dart';
import 'bottom_gap.dart';
import 'router.dart';
import 'theme.dart';

/// Системная зона внизу экрана: читается один раз при первом показе.
final _safeBottom = io.safeAreaBottom();

class FinanceApp extends ConsumerWidget {
  const FinanceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Мои финансы',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (ref.watch(themeModeProvider).value ?? 'dark') {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => MediaQuery(
        data: withBottomGap(MediaQuery.of(context), _safeBottom),
        child: child!,
      ),
    );
  }
}
