import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';

/// Добавление (code == null) или редактирование валюты и её курса.
class CurrencyFormScreen extends ConsumerStatefulWidget {
  const CurrencyFormScreen({super.key, this.code});

  final String? code;

  @override
  ConsumerState<CurrencyFormScreen> createState() => _CurrencyFormScreenState();
}

class _CurrencyFormScreenState extends ConsumerState<CurrencyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _symbol = TextEditingController();
  final _rate = TextEditingController();
  int _decimals = 2;
  DateTime _rateDate = DateTime.now();

  Currency? _existing;
  bool _isUsed = false;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  bool get _isEdit => widget.code != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _symbol.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isEdit) {
      final repo = ref.read(currencyRepositoryProvider);
      final c = await repo.getByCode(widget.code!);
      if (c == null) {
        _notFound = true;
      } else {
        _existing = c;
        _code.text = c.code;
        _name.text = c.name;
        _symbol.text = c.symbol;
        _decimals = c.decimals;
        _isUsed = await repo.isUsed(c.code);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _rateDate,
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked != null) setState(() => _rateDate = picked);
  }

  Future<void> _save(String baseCode) async {
    if (!_formKey.currentState!.validate()) return;
    final currencies = ref.read(currencyRepositoryProvider);
    final rates = ref.read(ratesRepositoryProvider);
    final code = _existing?.code ?? _code.text.trim();
    final name = _name.text.trim();
    final symbol = _symbol.text.trim().isEmpty ? code : _symbol.text.trim();
    final rate = parseRate(_rate.text);

    setState(() => _saving = true);
    try {
      final existing = _existing;
      if (existing == null) {
        if (await currencies.getByCode(code) != null) {
          if (mounted) showSnack(context, 'Валюта с кодом $code уже есть');
          return;
        }
        await currencies.add(code: code, name: name, symbol: symbol, decimals: _decimals);
      } else {
        await currencies.update(
          existing.copyWith(name: name, symbol: symbol, decimals: _decimals),
        );
      }

      if (rate != null && code != baseCode) {
        await rates.setManual(from: code, to: baseCode, rate: rate, date: _rateDate);
      } else if (existing == null &&
          await ref.read(settingsRepositoryProvider).ratesAutoUpdate()) {
        // Новая валюта без ручного курса — пробуем сразу подтянуть из интернета.
        unawaited(rates.updateFromInternet().then((_) {}, onError: (_) {}));
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String baseCode) async {
    final c = _existing!;
    final repo = ref.read(currencyRepositoryProvider);
    if (c.code == baseCode || await repo.isUsed(c.code)) {
      if (!mounted) return;
      await infoDialog(
        context,
        title: 'Нельзя удалить валюту',
        message: c.code == baseCode
            ? 'Это основная валюта. Сначала выберите другую основную валюту.'
            : 'Валюта используется в счетах, долгах или бюджетах.',
      );
      return;
    }
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Удалить валюту ${c.code}?',
      message: 'Все её курсы тоже будут удалены.',
    );
    if (!ok) return;
    await repo.delete(c.code);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final baseCode = ref.watch(baseCurrencyCodeProvider).value;
    final existing = _existing;

    return Scaffold(
      appBar: AppBar(
        title: Text(existing != null ? existing.label : 'Новая валюта'),
        actions: [
          if (existing != null && baseCode != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Удалить',
              onPressed: () => _delete(baseCode),
            ),
        ],
      ),
      body: _loading || baseCode == null
          ? const Center(child: CircularProgressIndicator())
          : _notFound
              ? const Center(child: Text('Валюта не найдена'))
              : _buildForm(baseCode),
    );
  }

  Widget _buildForm(String baseCode) {
    final theme = Theme.of(context);
    final isBase = _existing?.code == baseCode;
    final currencies = ref.watch(currenciesProvider).value ?? const <Currency>[];
    final base = currencies.where((c) => c.code == baseCode).firstOrNull;
    final baseSymbol = base?.symbol ?? baseCode;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            controller: _code,
            enabled: !_isEdit,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              _UpperCaseFormatter(),
              FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: const InputDecoration(
              labelText: 'Код',
              helperText: 'Например CNY, TRY или свой: GOLD',
            ),
            validator: (v) => RegExp(r'^[A-Z0-9]{1,10}$').hasMatch(v?.trim() ?? '')
                ? null
                : 'Латинские буквы и цифры, до 10 символов',
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Например: Китайский юань',
            ),
            validator: (v) {
              final t = v?.trim() ?? '';
              if (t.isEmpty) return 'Введите название';
              if (t.length > 50) return 'Не длиннее 50 символов';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _symbol,
            decoration: const InputDecoration(
              labelText: 'Символ',
              helperText: 'Как показывать суммы: 100 ¥. Пусто — будет код',
            ),
            validator: (v) =>
                (v?.trim().length ?? 0) > 10 ? 'Не длиннее 10 символов' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _decimals,
            decoration: InputDecoration(
              labelText: 'Знаков после запятой',
              helperText: _isUsed
                  ? 'Нельзя изменить: валюта уже используется'
                  : null,
            ),
            items: const [
              DropdownMenuItem(value: 0, child: Text('0 — только целые')),
              DropdownMenuItem(value: 1, child: Text('1')),
              DropdownMenuItem(value: 2, child: Text('2 — обычно (копейки, центы)')),
              DropdownMenuItem(value: 3, child: Text('3')),
              DropdownMenuItem(value: 4, child: Text('4')),
            ],
            onChanged: _isUsed ? null : (v) => setState(() => _decimals = v ?? 2),
          ),
          if (!isBase) ...[
            const SizedBox(height: 24),
            Text('Курс к основной валюте ($baseCode)', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Заполните, если курса нет в интернете или хотите свой '
              '(например, курс вашего обменника). Ручной курс важнее загруженного '
              'в тот же день.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rate,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                    ],
                    decoration: InputDecoration(
                      labelText: '1 ед. = ? $baseSymbol',
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? null
                        : parseRate(v) == null
                            ? 'Неверный курс'
                            : null,
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text(formatDate(_rateDate)),
                  ),
                ),
              ],
            ),
            if (_existing != null)
              _RateHistory(code: _existing!.code, baseCode: baseCode, baseSymbol: baseSymbol),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _save(baseCode),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}

/// Последние курсы валюты к основной (и загруженные, и ручные).
class _RateHistory extends ConsumerWidget {
  const _RateHistory({
    required this.code,
    required this.baseCode,
    required this.baseSymbol,
  });

  final String code;
  final String baseCode;
  final String baseSymbol;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final all = ref.watch(ratesProvider).value ?? const <ExchangeRate>[];
    final rows = [
      for (final r in all)
        if (r.fromCode == code && r.toCode == baseCode)
          (rate: r, value: r.rate)
        else if (r.fromCode == baseCode && r.toCode == code)
          (rate: r, value: 1 / r.rate),
    ]..sort((a, b) {
        final c = b.rate.date.compareTo(a.rate.date);
        return c != 0 ? c : b.rate.id.compareTo(a.rate.id);
      });
    if (rows.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('История курсов', style: theme.textTheme.titleSmall),
          for (final row in rows.take(10))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${formatRate(row.value)} $baseSymbol'),
              subtitle: Text(
                '${formatDate(row.rate.date)} · '
                '${row.rate.isManual ? 'вручную' : 'из интернета'}',
              ),
              trailing: row.rate.isManual
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Удалить этот курс',
                      onPressed: () =>
                          ref.read(ratesRepositoryProvider).deleteRate(row.rate.id),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
