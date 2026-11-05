import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/async_utils.dart';
import '../../core/formatters.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/rates/rate_book.dart';
import '../../data/repositories/rates_repository.dart';

class CurrenciesScreen extends ConsumerStatefulWidget {
  const CurrenciesScreen({super.key});

  @override
  ConsumerState<CurrenciesScreen> createState() => _CurrenciesScreenState();
}

class _CurrenciesScreenState extends ConsumerState<CurrenciesScreen> {
  bool _updating = false;

  Future<void> _updateNow() async {
    setState(() => _updating = true);
    try {
      final result = await ref.read(ratesRepositoryProvider).updateFromInternet();
      if (mounted) showSnack(context, _describe(result));
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Не удалось обновить курсы. Проверьте интернет.\n$e');
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  String _describe(RatesUpdateResult r) {
    final parts = <String>[
      if (r.updated.isNotEmpty) 'Курсы обновлены: ${r.updated.join(', ')}',
      if (r.updated.isEmpty) 'Нет валют для обновления',
      if (r.notFound.isNotEmpty)
        'Нет в источнике: ${r.notFound.join(', ')} — задайте курс вручную',
    ];
    return parts.join('. ');
  }

  Future<void> _changeBase(List<Currency> currencies, String current) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Основная валюта'),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('В ней показываются общий капитал и статистика.'),
          ),
          for (final c in currencies)
            ListTile(
              title: Text(c.label),
              trailing: c.code == current ? const Icon(Icons.check) : null,
              onTap: () => Navigator.pop(ctx, c.code),
            ),
        ],
      ),
    );
    if (picked == null || picked == current) return;
    await ref.read(settingsRepositoryProvider).setBaseCurrency(picked);
    if (await ref.read(settingsRepositoryProvider).ratesAutoUpdate()) {
      await _updateNow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencies = ref.watch(currenciesProvider);
    final base = ref.watch(baseCurrencyCodeProvider);
    final book = ref.watch(rateBookProvider);
    final auto = ref.watch(ratesAutoUpdateProvider).value ?? true;
    final lastUpdate = ref.watch(ratesLastUpdateProvider).value;
    final data = combineAsync(
      [currencies, base, book],
      () => (currencies.requireValue, base.requireValue, book.requireValue),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Валюты и курсы'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined),
            tooltip: 'Конвертер',
            onPressed: () => context.push(Routes.converter),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.currencyAdd),
        icon: const Icon(Icons.add),
        label: const Text('Валюта'),
      ),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
        data: (d) {
          final (list, baseCode, rates) = d;
          final baseCurrency = list.firstWhere(
            (c) => c.code == baseCode,
            orElse: () => list.first,
          );
          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('Основная валюта'),
                subtitle: Text(baseCurrency.label),
                trailing: TextButton(
                  onPressed: () => _changeBase(list, baseCode),
                  child: const Text('Изменить'),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.sync),
                title: const Text('Обновлять курсы автоматически'),
                subtitle: Text(
                  lastUpdate == null
                      ? 'Курсы ещё не загружались'
                      : 'Обновлено: ${formatDateTime(lastUpdate)}',
                ),
                value: auto,
                onChanged: (v) =>
                    ref.read(settingsRepositoryProvider).setRatesAutoUpdate(v),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: OutlinedButton.icon(
                  onPressed: _updating ? null : _updateNow,
                  icon: _updating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Обновить курсы сейчас'),
                ),
              ),
              const Divider(height: 24),
              for (final c in list)
                _CurrencyTile(currency: c, base: baseCurrency, rates: rates),
            ],
          );
        },
      ),
    );
  }
}

class _CurrencyTile extends StatelessWidget {
  const _CurrencyTile({
    required this.currency,
    required this.base,
    required this.rates,
  });

  final Currency currency;
  final Currency base;
  final RateBook rates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBase = currency.code == base.code;
    final quote = isBase ? null : rates.quote(currency.code, base.code);

    final Widget subtitle;
    if (isBase) {
      subtitle = const Text('Основная валюта');
    } else if (quote == null) {
      subtitle = Text(
        'Курс не задан',
        style: TextStyle(color: theme.colorScheme.error),
      );
    } else {
      subtitle = Text([
        '1 ${currency.symbol} = ${formatRate(quote.rate)} ${base.symbol}',
        quote.isManual ? 'вручную' : 'авто',
        if (quote.date != null) formatDate(quote.date!),
      ].join(' · '));
    }

    return ListTile(
      leading: CircleAvatar(
        child: Text(
          currency.symbol,
          style: const TextStyle(fontSize: 14),
          maxLines: 1,
          overflow: TextOverflow.clip,
        ),
      ),
      title: Text(currency.label),
      subtitle: subtitle,
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(Routes.currencyEdit(currency.code)),
    );
  }
}
