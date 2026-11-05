import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/async_utils.dart';
import '../../core/formatters.dart';
import '../../core/widgets/amount_field.dart';
import '../../data/providers.dart';

/// Конвертер: вводишь сумму — видишь её во всех своих валютах.
class ConverterScreen extends ConsumerStatefulWidget {
  const ConverterScreen({super.key});

  @override
  ConsumerState<ConverterScreen> createState() => _ConverterScreenState();
}

class _ConverterScreenState extends ConsumerState<ConverterScreen> {
  final _amount = TextEditingController(text: '100');
  String? _from;

  @override
  void initState() {
    super.initState();
    _amount.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencies = ref.watch(currenciesProvider);
    final base = ref.watch(baseCurrencyCodeProvider);
    final book = ref.watch(rateBookProvider);
    final data = combineAsync(
      [currencies, base, book],
      () => (currencies.requireValue, base.requireValue, book.requireValue),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Конвертер валют')),
      body: data.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка загрузки: $e')),
        data: (d) {
          final (list, baseCode, rates) = d;
          final from = list.firstWhere(
            (c) => c.code == (_from ?? baseCode),
            orElse: () => list.first,
          );
          final amount = AmountField.valueOf(_amount, decimals: from.decimals);
          final theme = Theme.of(context);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: AmountField(
                      controller: _amount,
                      decimals: from.decimals,
                      autofocus: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<String>(
                      initialValue: from.code,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Валюта',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in list)
                          DropdownMenuItem(value: c.code, child: Text(c.code)),
                      ],
                      onChanged: (v) => setState(() => _from = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Card.outlined(
                child: Column(
                  children: [
                    for (final c in list)
                      if (c.code != from.code)
                        Builder(builder: (context) {
                          final quote = rates.quote(from.code, c.code);
                          final converted =
                              amount == null ? null : rates.convert(amount, from, c);
                          return ListTile(
                            title: Text(
                              quote == null
                                  ? 'нет курса'
                                  : converted == null
                                      ? '—'
                                      : c.format(converted),
                              style: theme.textTheme.titleMedium,
                            ),
                            subtitle: Text(c.name),
                            trailing: quote == null
                                ? null
                                : Text(
                                    '1 ${from.symbol} = ${formatRate(quote.rate)} ${c.symbol}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                          );
                        }),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
