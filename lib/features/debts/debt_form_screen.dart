import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';

/// Новый долг (debtId == null) или изменение существующего.
class DebtFormScreen extends ConsumerStatefulWidget {
  const DebtFormScreen({super.key, this.debtId});

  final int? debtId;

  @override
  ConsumerState<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends ConsumerState<DebtFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  DebtDirection _direction = DebtDirection.theyOwe;

  /// Деньги прошли через счёт в приложении (иначе — долг до начала учёта).
  bool _viaAccount = true;
  int? _accountId;
  String? _currencyCode;
  DateTime _date = dayOf(DateTime.now());
  DateTime? _dueDate;

  Debt? _existing;
  bool _hasOperations = false;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  bool get _isEdit => widget.debtId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isEdit) {
      final repo = ref.read(debtRepositoryProvider);
      final d = await repo.getById(widget.debtId!);
      if (d == null) {
        _notFound = true;
      } else {
        final currency = await ref.read(currencyRepositoryProvider).getByCode(d.currencyCode);
        _existing = d;
        _person.text = d.personName;
        _note.text = d.note;
        _direction = d.direction;
        _currencyCode = d.currencyCode;
        _dueDate = d.dueDate;
        _viaAccount = false;
        _amount.text = d.initialAmount == 0
            ? ''
            : Money.toEditable(d.initialAmount, decimals: currency?.decimals ?? 2);
        _hasOperations = await repo.hasOperations(d.id);
      }
    } else {
      final settings = ref.read(settingsRepositoryProvider);
      _accountId = await settings.defaultAccountId() ?? await settings.lastAccountId();
      _currencyCode = await ref.read(settingsRepositoryProvider).baseCurrency();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickDue() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime(now.year, now.month + 1, now.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 20),
      helpText: 'Вернуть до',
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5),
    );
    if (picked != null) setState(() => _date = dayOf(picked));
  }

  Future<void> _save(Currency currency) async {
    if (!_formKey.currentState!.validate()) return;
    final amount = AmountField.valueOf(_amount, decimals: currency.decimals, emptyIsZero: _isEdit) ?? 0;
    final repo = ref.read(debtRepositoryProvider);
    setState(() => _saving = true);
    try {
      final existing = _existing;
      if (existing == null) {
        await repo.create(
          personName: _person.text.trim(),
          direction: _direction,
          currencyCode: currency.code,
          amount: amount,
          accountId: _viaAccount ? _accountId : null,
          date: _date,
          dueDate: _dueDate,
          note: _note.text.trim(),
        );
        if (_viaAccount && _accountId != null) {
          await ref.read(settingsRepositoryProvider).setLastAccountId(_accountId!);
        }
      } else {
        await repo.update(existing.copyWith(
          personName: _person.text.trim(),
          direction: _direction,
          currencyCode: currency.code,
          initialAmount: amount,
          dueDate: Value(_dueDate),
          note: _note.text.trim(),
        ));
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Изменить долг' : 'Новый долг')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notFound
              ? const Center(child: Text('Долг не найден'))
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    final accounts = (ref.watch(accountsProvider).value ?? const <Account>[])
        .where((a) => !a.isArchived)
        .toList();
    final currencies = ref.watch(currenciesProvider).value ?? const <Currency>[];
    if (currencies.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_viaAccount && accounts.isEmpty) _viaAccount = false;
    if (_viaAccount && !accounts.any((a) => a.id == _accountId)) _accountId = accounts.first.id;

    final account = accounts.where((a) => a.id == _accountId).firstOrNull;
    final code = _viaAccount && account != null ? account.currencyCode : _currencyCode;
    final currency = currencies.firstWhere((c) => c.code == code, orElse: () => currencies.first);
    final canChangeKind = !_hasOperations;

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<DebtDirection>(
            segments: const [
              ButtonSegment(value: DebtDirection.theyOwe, label: Text('Я дал в долг')),
              ButtonSegment(value: DebtDirection.iOwe, label: Text('Я взял в долг')),
            ],
            selected: {_direction},
            showSelectedIcon: false,
            onSelectionChanged: canChangeKind ? (s) => setState(() => _direction = s.first) : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _person,
            autofocus: !_isEdit,
            maxLength: 50,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: _direction == DebtDirection.theyOwe ? 'Кому дал' : 'У кого взял',
              hintText: 'Имя человека или банк',
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите имя' : null,
          ),
          if (!_isEdit && accounts.isNotEmpty)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(_direction == DebtDirection.theyOwe
                  ? 'Деньги ушли с моего счёта'
                  : 'Деньги пришли на мой счёт'),
              subtitle: const Text('Выключите для долга, который был до начала учёта'),
              value: _viaAccount,
              onChanged: (v) => setState(() => _viaAccount = v),
            ),
          const SizedBox(height: 8),
          if (_viaAccount && account != null) ...[
            DropdownButtonFormField<int>(
              initialValue: account.id,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Счёт'),
              items: [for (final a in accounts) DropdownMenuItem(value: a.id, child: Text(a.name))],
              onChanged: (v) => setState(() => _accountId = v),
            ),
            const SizedBox(height: 16),
          ] else ...[
            DropdownButtonFormField<String>(
              initialValue: currency.code,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Валюта долга',
                helperText: canChangeKind ? null : 'Нельзя сменить: по долгу уже есть операции',
              ),
              items: [for (final c in currencies) DropdownMenuItem(value: c.code, child: Text(c.label))],
              onChanged: canChangeKind ? (v) => setState(() => _currencyCode = v) : null,
            ),
            const SizedBox(height: 16),
          ],
          AmountField(
            controller: _amount,
            decimals: currency.decimals,
            symbol: currency.symbol,
            label: _isEdit ? 'Долг до начала учёта' : 'Сумма долга',
            emptyIsZero: _isEdit,
            helperText: _isEdit
                ? 'Сумма, которая была до начала учёта в приложении. '
                    'Новые суммы и возвраты добавляйте кнопками на странице долга.'
                : null,
          ),
          if (!_isEdit && _viaAccount) ...[
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Дата'),
              subtitle: Text(formatDate(_date)),
              onTap: _pickDate,
            ),
          ],
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available),
            title: const Text('Вернуть до'),
            subtitle: Text(_dueDate == null ? 'Без срока' : formatDate(_dueDate!)),
            onTap: _pickDue,
            trailing: _dueDate == null
                ? null
                : IconButton(
                    tooltip: 'Убрать срок',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _dueDate = null),
                  ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _note,
            maxLength: 200,
            decoration: const InputDecoration(
              labelText: 'Комментарий',
              hintText: 'Необязательно',
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : () => _save(currency),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Сохранить'),
          ),
          if (_isEdit) ...[
            const SizedBox(height: 8),
            Text(
              'Чтобы записать возврат или новую сумму, используйте кнопки на странице долга.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
