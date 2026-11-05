import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/color_picker.dart';
import '../../core/widgets/dialogs.dart';
import '../../app/router.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../domain/operation_filter.dart';
import '../../domain/period.dart';
import '../../domain/providers.dart';

/// Создание (accountId == null) или редактирование счёта.
class AccountFormScreen extends ConsumerStatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final int? accountId;

  @override
  ConsumerState<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends ConsumerState<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _initialBalance = TextEditingController();

  AccountType _type = AccountType.cash;
  String? _currencyCode;
  int _color = pickerColors.first;
  bool _includeInTotal = true;

  Account? _existing;
  bool _hasOperations = false;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  bool get _isEdit => widget.accountId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _initialBalance.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = ref.read(accountRepositoryProvider);
    if (_isEdit) {
      final a = await accounts.getById(widget.accountId!);
      if (a == null) {
        _notFound = true;
      } else {
        final currency = await ref.read(currencyRepositoryProvider).getByCode(a.currencyCode);
        _existing = a;
        _name.text = a.name;
        _type = a.type;
        _currencyCode = a.currencyCode;
        _color = a.color;
        _includeInTotal = a.includeInTotal;
        _initialBalance.text = a.initialBalance == 0
            ? ''
            : Money.toEditable(a.initialBalance, decimals: currency?.decimals ?? 2);
        _hasOperations = await accounts.hasOperations(a.id);
      }
    } else {
      _currencyCode = await ref.read(settingsRepositoryProvider).baseCurrency();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(List<Currency> currencies) async {
    if (!_formKey.currentState!.validate()) return;
    final currency = currencies.firstWhere((c) => c.code == _currencyCode);
    final initial = AmountField.valueOf(
      _initialBalance,
      decimals: currency.decimals,
      emptyIsZero: true,
    )!;
    final repo = ref.read(accountRepositoryProvider);

    setState(() => _saving = true);
    try {
      final existing = _existing;
      if (existing == null) {
        await repo.create(
          name: _name.text.trim(),
          type: _type,
          currencyCode: currency.code,
          initialBalance: initial,
          color: _color,
          includeInTotal: _includeInTotal,
        );
      } else {
        await repo.update(existing.copyWith(
          name: _name.text.trim(),
          type: _type,
          currencyCode: currency.code,
          initialBalance: initial,
          color: _color,
          includeInTotal: _includeInTotal,
        ));
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleArchive() async {
    final a = _existing!;
    await ref.read(accountRepositoryProvider).setArchived(a.id, !a.isArchived);
    if (!mounted) return;
    showSnack(context, a.isArchived ? 'Счёт возвращён из архива' : 'Счёт перенесён в архив');
    context.pop();
  }

  /// Корректировка: пользователь вводит, сколько денег на самом деле.
  Future<void> _adjust(Account a, Currency currency, int balance) async {
    final controller = TextEditingController(
      text: Money.toEditable(balance, decimals: currency.decimals),
    );
    final formKey = GlobalKey<FormState>();
    final actual = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Корректировка баланса'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('В приложении: ${currency.format(balance)}.\n'
                  'Сколько денег на счёте на самом деле?'),
              const SizedBox(height: 16),
              AmountField(
                controller: controller,
                decimals: currency.decimals,
                symbol: currency.symbol,
                label: 'Фактический остаток',
                allowNegative: true,
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          FilledButton(
            onPressed: () {
              if (!formKey.currentState!.validate()) return;
              Navigator.pop(ctx, AmountField.valueOf(controller, decimals: currency.decimals));
            },
            child: const Text('Исправить'),
          ),
        ],
      ),
    );
    if (actual == null) return;
    final diff = await ref.read(operationRepositoryProvider).adjustBalance(
      accountId: a.id,
      currentBalance: balance,
      actualBalance: actual,
      date: DateTime.now(),
    );
    if (!mounted) return;
    showSnack(
      context,
      diff == 0
          ? 'Баланс и так совпадает'
          : 'Записана корректировка ${currency.format(diff, signed: true)}',
    );
  }

  void _openOperations(Account a) {
    ref.read(operationFilterProvider.notifier).set(OperationFilter(accountId: a.id));
    ref.read(operationsPeriodProvider.notifier).select(Period.all());
    context.go(Routes.operations);
  }

  Future<void> _delete() async {
    final a = _existing!;
    final repo = ref.read(accountRepositoryProvider);
    if (await repo.hasOperations(a.id)) {
      if (!mounted) return;
      await infoDialog(
        context,
        title: 'Нельзя удалить счёт',
        message: 'По счёту есть операции. Отправьте счёт в архив: он пропадёт '
            'из списка, а история операций сохранится.',
      );
      return;
    }
    if (!mounted) return;
    final ok = await confirmDialog(context, title: 'Удалить счёт «${a.name}»?');
    if (!ok) return;
    await repo.delete(a.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final currencies = ref.watch(currenciesProvider).value ?? const <Currency>[];
    final existing = _existing;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Счёт' : 'Новый счёт'),
        actions: [
          if (existing != null)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'archive' ? _toggleArchive() : _delete(),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'archive',
                  child: Text(existing.isArchived ? 'Вернуть из архива' : 'В архив'),
                ),
                const PopupMenuItem(value: 'delete', child: Text('Удалить')),
              ],
            ),
        ],
      ),
      body: _loading || currencies.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _notFound
              ? const Center(child: Text('Счёт не найден'))
              : _buildForm(currencies),
    );
  }

  Widget _buildForm(List<Currency> currencies) {
    final theme = Theme.of(context);
    final currency = currencies.firstWhere(
      (c) => c.code == _currencyCode,
      orElse: () => currencies.first,
    );
    _currencyCode = currency.code;

    final existing = _existing;
    final balance = existing == null
        ? null
        : ref.watch(accountBalancesProvider).value?[existing.id];

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (existing != null && balance != null) ...[
            Card.filled(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Текущий баланс', style: theme.textTheme.labelLarge),
                    Text(currency.format(balance), style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.tonalIcon(
                          onPressed: () => _adjust(existing, currency, balance),
                          icon: const Icon(Icons.tune),
                          label: const Text('Корректировка'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _openOperations(existing),
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Операции'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => context.push(
                            Routes.operationNew(type: OperationType.transfer, accountId: existing.id),
                          ),
                          icon: const Icon(Icons.swap_horiz),
                          label: const Text('Перевод'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
          TextFormField(
            controller: _name,
            autofocus: !_isEdit,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Название',
              hintText: 'Например: Наличные \$, Карта Мбанк',
              border: OutlineInputBorder(),
            ),
            maxLength: 50,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Введите название' : null,
          ),
          const SizedBox(height: 8),
          Text('Тип', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final t in AccountType.values)
                ChoiceChip(
                  avatar: Icon(accountTypeIcon(t), size: 18),
                  label: Text(accountTypeLabel(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: currency.code,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Валюта',
              border: const OutlineInputBorder(),
              helperText: _hasOperations
                  ? 'Нельзя сменить: по счёту уже есть операции'
                  : null,
            ),
            items: [
              for (final c in currencies)
                DropdownMenuItem(
                  value: c.code,
                  child: Text(c.label, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: _hasOperations
                ? null
                : (v) => setState(() => _currencyCode = v),
          ),
          const SizedBox(height: 20),
          AmountField(
            controller: _initialBalance,
            decimals: currency.decimals,
            symbol: currency.symbol,
            label: 'Начальный остаток',
            helperText: 'Сколько денег на счёте на момент начала учёта.\n'
                'Если на кредитке долг — нажмите ± и введите с минусом.',
            allowNegative: true,
            emptyIsZero: true,
          ),
          const SizedBox(height: 20),
          Text('Цвет', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ColorPicker(
            selected: _color,
            onChanged: (c) => setState(() => _color = c),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Учитывать в общем капитале'),
            subtitle: const Text(
              'Выключите, например, для чужих денег на вашей карте',
            ),
            value: _includeInTotal,
            onChanged: (v) => setState(() => _includeInTotal = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _save(currencies),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
