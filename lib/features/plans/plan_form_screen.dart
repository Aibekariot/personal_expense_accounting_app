import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/plan_repository.dart';
import '../../domain/ledger.dart';
import '../../domain/payees.dart';
import '../../domain/providers.dart';
import '../../domain/schedule.dart';
import '../operations/category_picker.dart';
import '../operations/payee_field.dart';

/// Новый план ([planId] == null) или изменение. [fromOperationId] — сделать
/// регулярной существующую операцию (поля берутся из неё).
class PlanFormScreen extends ConsumerStatefulWidget {
  const PlanFormScreen({super.key, this.planId, this.fromOperationId});

  final int? planId;
  final int? fromOperationId;

  @override
  ConsumerState<PlanFormScreen> createState() => _PlanFormScreenState();
}

class _PlanFormScreenState extends ConsumerState<PlanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _toAmount = TextEditingController();
  final _payee = TextEditingController();
  final _payeeFocus = FocusNode();
  final _note = TextEditingController();
  final _every = TextEditingController(text: '1');

  OperationType _type = OperationType.expense;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  DateTime _start = dayOf(DateTime.now());
  RepeatUnit _unit = RepeatUnit.month;
  DateTime? _end;
  bool _auto = false;
  bool _categoryTouched = false;

  /// Суммы источника (плана или операции) — заполняются, когда известны валюты.
  (int, int?)? _sourceAmounts;
  PlannedOperation? _existing;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;
  String? _categoryError;

  bool get _isEdit => widget.planId != null;
  bool get _isCategorized => _type != OperationType.transfer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_amount, _toAmount, _payee, _note, _every]) {
      c.dispose();
    }
    _payeeFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isEdit) {
      final p = await ref.read(planRepositoryProvider).getById(widget.planId!);
      if (p == null) {
        _notFound = true;
      } else {
        _existing = p;
        _type = p.type;
        _accountId = p.accountId;
        _toAccountId = p.toAccountId;
        _categoryId = p.categoryId;
        _payee.text = p.payee;
        _note.text = p.note;
        _start = p.startDate;
        _unit = p.repeatUnit;
        _every.text = '${p.repeatEvery}';
        _end = p.endDate;
        _auto = p.autoConfirm;
        _categoryTouched = true;
        _sourceAmounts = (p.amount, p.toAmount);
      }
    } else if (widget.fromOperationId != null) {
      final op = await ref.read(operationRepositoryProvider).getById(widget.fromOperationId!);
      if (op != null) {
        _type = op.type;
        _accountId = op.accountId;
        _toAccountId = op.toAccountId;
        _categoryId = op.categoryId;
        _payee.text = op.payee;
        _note.text = op.note;
        // Следующий раз — через месяц после этой операции.
        _start = DateTime(op.date.year, op.date.month + 1, op.date.day);
        _categoryTouched = true;
        _sourceAmounts = (op.amount, op.toAmount);
      }
    } else {
      final settings = ref.read(settingsRepositoryProvider);
      _accountId = await settings.defaultAccountId() ?? await settings.lastAccountId();
    }
    if (mounted) setState(() => _loading = false);
  }

  Currency _currencyOf(Ledger l, int id) => l.currency(l.accounts[id]?.currencyCode ?? l.base.code);

  Future<void> _pickDate({required bool end}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: end ? (_end ?? _start) : _start,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 30),
      helpText: end ? 'Последний платёж не позже' : 'Первый платёж',
    );
    if (picked != null) setState(() => end ? _end = dayOf(picked) : _start = dayOf(picked));
  }

  Future<void> _save(Ledger l) async {
    setState(() => _categoryError = null);
    final ok = _formKey.currentState!.validate();
    if (_isCategorized && _categoryId == null) {
      setState(() => _categoryError = 'Выберите категорию');
      return;
    }
    if (!ok) return;
    final currency = _currencyOf(l, _accountId!);
    final amount = AmountField.valueOf(_amount, decimals: currency.decimals)!;
    int? toAmount;
    if (_type == OperationType.transfer && _toAccountId != null) {
      final to = _currencyOf(l, _toAccountId!);
      toAmount = to.code == currency.code ? amount : AmountField.valueOf(_toAmount, decimals: to.decimals);
    }
    final input = PlanInput(
      type: _type,
      accountId: _accountId!,
      amount: amount,
      startDate: _start,
      repeatUnit: _unit,
      repeatEvery: int.tryParse(_every.text) ?? 1,
      endDate: _unit == RepeatUnit.none ? null : _end,
      categoryId: _categoryId,
      toAccountId: _toAccountId,
      toAmount: toAmount,
      payee: _payee.text,
      note: _note.text,
      autoConfirm: _auto,
    );
    final error = input.validate();
    if (error != null) {
      showSnack(context, error);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(planRepositoryProvider).save(input, id: _existing?.id);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(
      context,
      title: 'Удалить план?',
      message: 'Уже проведённые операции останутся в истории.',
    );
    if (!ok) return;
    await ref.read(planRepositoryProvider).delete(_existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(ledgerProvider).value;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Плановая операция' : 'Новый план'),
        actions: [
          if (_existing != null)
            IconButton(tooltip: 'Удалить', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _loading || l == null
          ? const Center(child: CircularProgressIndicator())
          : _notFound
              ? const Center(child: Text('План не найден'))
              : _buildForm(l),
    );
  }

  Widget _buildForm(Ledger l) {
    final theme = Theme.of(context);
    final active = l.accounts.values.where((a) => !a.isArchived).toList();
    if (active.isEmpty) return const Center(child: Text('Сначала создайте счёт'));
    if (_accountId == null || !l.accounts.containsKey(_accountId)) _accountId = active.first.id;
    if (_type == OperationType.transfer && (_toAccountId == null || _toAccountId == _accountId)) {
      _toAccountId = active.where((a) => a.id != _accountId).firstOrNull?.id;
    }
    final currency = _currencyOf(l, _accountId!);
    final toCurrency = _toAccountId == null ? null : _currencyOf(l, _toAccountId!);
    final src = _sourceAmounts;
    if (src != null) {
      _sourceAmounts = null;
      _amount.text = Money.toEditable(src.$1, decimals: currency.decimals);
      if (src.$2 != null && toCurrency != null) {
        _toAmount.text = Money.toEditable(src.$2!, decimals: toCurrency.decimals);
      }
    }
    final categoryType = _type == OperationType.income ? CategoryType.income : CategoryType.expense;

    Widget accountDropdown(String label, int value, List<Account> list, ValueChanged<int> onChanged) =>
        DropdownButtonFormField<int>(
          key: ValueKey('$label-$value'),
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final a in list) DropdownMenuItem(value: a.id, child: Text(a.name))],
          onChanged: (v) => v == null ? null : setState(() => onChanged(v)),
        );

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SegmentedButton<OperationType>(
            segments: const [
              ButtonSegment(value: OperationType.expense, label: Text('Расход')),
              ButtonSegment(value: OperationType.income, label: Text('Доход')),
              ButtonSegment(value: OperationType.transfer, label: Text('Перевод')),
            ],
            selected: {_type},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              final nextType = s.first == OperationType.income ? CategoryType.income : CategoryType.expense;
              if (l.categories[_categoryId]?.type != nextType) {
                _categoryId = null;
                _categoryTouched = false;
              }
              _type = s.first;
            }),
          ),
          const SizedBox(height: 16),
          AmountField(
            controller: _amount,
            decimals: currency.decimals,
            symbol: currency.symbol,
            label: 'Сумма',
            autofocus: !_isEdit && widget.fromOperationId == null,
          ),
          const SizedBox(height: 16),
          accountDropdown(
            _type == OperationType.income ? 'На счёт' : 'Со счёта',
            _accountId!,
            active,
            (v) => _accountId = v,
          ),
          if (_type == OperationType.transfer && _toAccountId != null) ...[
            const SizedBox(height: 16),
            accountDropdown(
              'На счёт',
              _toAccountId!,
              active.where((a) => a.id != _accountId).toList(),
              (v) => _toAccountId = v,
            ),
            if (toCurrency != null && toCurrency.code != currency.code) ...[
              const SizedBox(height: 16),
              AmountField(
                controller: _toAmount,
                decimals: toCurrency.decimals,
                symbol: toCurrency.symbol,
                label: 'Зачислить',
              ),
            ],
          ],
          if (_isCategorized) ...[
            const SizedBox(height: 16),
            PayeeField(
              controller: _payee,
              focusNode: _payeeFocus,
              label: _type == OperationType.income ? 'Плательщик' : 'Получатель',
              hint: _type == OperationType.income ? 'Например: работа' : 'Например: хозяйка квартиры',
              suggestions: payeeSuggestions(l, _type, _payee.text),
              onChanged: (v) => setState(() {
                if (!_categoryTouched) _categoryId = suggestCategory(l, v, _type) ?? _categoryId;
              }),
              onSelected: (v) => setState(() {
                _payee.text = v;
                if (!_categoryTouched) _categoryId = suggestCategory(l, v, _type) ?? _categoryId;
              }),
            ),
            const SizedBox(height: 16),
            Text('Категория', style: theme.textTheme.titleSmall),
            if (_categoryError != null)
              Text(_categoryError!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            CategoryPicker(
              categories: l.categories.values.where((c) => c.type == categoryType).toList(),
              selectedId: _categoryId,
              onSelected: (id) => setState(() {
                _categoryId = id;
                _categoryTouched = true;
                _categoryError = null;
              }),
            ),
          ],
          const SizedBox(height: 20),
          Text('Расписание', style: theme.textTheme.titleSmall),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(_unit == RepeatUnit.none ? 'Дата' : 'Первый платёж'),
            subtitle: Text(formatDate(_start)),
            onTap: () => _pickDate(end: false),
          ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<RepeatUnit>(
                  initialValue: _unit,
                  decoration: const InputDecoration(labelText: 'Повторять'),
                  items: const [
                    DropdownMenuItem(value: RepeatUnit.none, child: Text('Не повторять')),
                    DropdownMenuItem(value: RepeatUnit.day, child: Text('Каждый день')),
                    DropdownMenuItem(value: RepeatUnit.week, child: Text('Каждую неделю')),
                    DropdownMenuItem(value: RepeatUnit.month, child: Text('Каждый месяц')),
                    DropdownMenuItem(value: RepeatUnit.year, child: Text('Каждый год')),
                  ],
                  onChanged: (v) => setState(() => _unit = v ?? _unit),
                ),
              ),
              if (_unit != RepeatUnit.none) ...[
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _every,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Интервал',
                      helperText: '1 — каждый раз',
                    ),
                    validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? 'Не меньше 1' : null,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ],
          ),
          if (_unit != RepeatUnit.none) ...[
            const SizedBox(height: 4),
            Text(
              repeatLabel(_unit, int.tryParse(_every.text) ?? 1),
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_busy),
              title: const Text('Окончание'),
              subtitle: Text(_end == null ? 'Без окончания' : 'Не позже ${formatDate(_end!)}'),
              onTap: () => _pickDate(end: true),
              trailing: _end == null
                  ? null
                  : IconButton(
                      tooltip: 'Без окончания',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _end = null),
                    ),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Проводить автоматически'),
            subtitle: const Text(
              'В день платежа операция запишется сама (при открытии приложения). '
              'Удобно для подписок и автоплатежей. Если выключено — платёж появится '
              'в блоке «Скоро» в ленте, и вы проведёте его сами.',
            ),
            value: _auto,
            onChanged: (v) => setState(() => _auto = v),
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
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving ? null : () => _save(l),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Сохранить'),
          ),
          if (_existing != null && _existing!.doneCount > 0) ...[
            const SizedBox(height: 12),
            Text(
              'Если изменить дату первого платежа или повтор, отсчёт начнётся заново с новой даты.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (!_isEdit) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.push(Routes.categories),
              child: const Text('Настроить категории'),
            ),
          ],
        ],
      ),
    );
  }
}
