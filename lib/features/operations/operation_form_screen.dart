import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/app_icons.dart';
import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/operation_repository.dart';
import '../../domain/budgets.dart';
import '../../domain/debts.dart';
import '../../domain/ledger.dart';
import '../../domain/providers.dart';
import 'category_picker.dart';

/// Добавление, изменение и копирование операции.
///
/// Новая операция: [type] (по умолчанию расход), для долга — [debtId],
/// [accountId] — счёт по умолчанию. Изменение — [operationId].
/// Копия — [copyFromId] (те же поля, дата — сегодня).
class OperationFormScreen extends ConsumerStatefulWidget {
  const OperationFormScreen({
    super.key,
    this.operationId,
    this.type,
    this.debtId,
    this.accountId,
    this.copyFromId,
  });

  final int? operationId;
  final OperationType? type;
  final int? debtId;
  final int? accountId;
  final int? copyFromId;

  @override
  ConsumerState<OperationFormScreen> createState() => _OperationFormScreenState();
}

class _OperationFormScreenState extends ConsumerState<OperationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _toAmount = TextEditingController();
  final _debtAmount = TextEditingController();
  final _note = TextEditingController();

  OperationType _type = OperationType.expense;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  int? _debtId;
  DateTime _date = dayOf(DateTime.now());

  /// Пользователь сам ввёл сумму зачисления / сумму в валюте долга —
  /// больше не подставляем её по курсу.
  bool _toAmountTouched = false;
  bool _debtAmountTouched = false;

  /// Исходная операция (при изменении или копировании).
  Operation? _source;
  bool _amountsFilled = false;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;
  String? _categoryError;

  bool get _isEdit => widget.operationId != null;
  bool get _isTransfer => _type == OperationType.transfer;
  bool get _isAdjustment => _type == OperationType.adjustment;
  bool get _isDebt => _type == OperationType.debtIn || _type == OperationType.debtOut;
  bool get _isCategorized => _type == OperationType.expense || _type == OperationType.income;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amount.dispose();
    _toAmount.dispose();
    _debtAmount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sourceId = widget.operationId ?? widget.copyFromId;
    if (sourceId != null) {
      final op = await ref.read(operationRepositoryProvider).getById(sourceId);
      if (op == null) {
        _notFound = true;
      } else {
        _source = op;
        _type = op.type;
        _accountId = op.accountId;
        _toAccountId = op.toAccountId;
        _categoryId = op.categoryId;
        _debtId = op.debtId;
        _date = _isEdit ? op.date : dayOf(DateTime.now());
        _note.text = op.note;
        _toAmountTouched = true;
        _debtAmountTouched = true;
      }
    } else {
      _type = widget.type ?? OperationType.expense;
      _debtId = widget.debtId;
      _accountId = widget.accountId ??
          await ref.read(settingsRepositoryProvider).lastAccountId();
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Суммы исходной операции — когда известны валюты (нужно число знаков).
  void _fillAmounts(Ledger l) {
    if (_amountsFilled) return;
    _amountsFilled = true;
    final op = _source;
    if (op == null) return;
    _amount.text = Money.toEditable(op.amount, decimals: _currencyOf(l, op.accountId).decimals);
    if (op.toAmount != null && op.toAccountId != null) {
      _toAmount.text = Money.toEditable(op.toAmount!, decimals: _currencyOf(l, op.toAccountId!).decimals);
    }
    final debt = l.debts[op.debtId];
    if (op.debtAmount != null && debt != null) {
      _debtAmount.text = Money.toEditable(op.debtAmount!, decimals: l.currency(debt.currencyCode).decimals);
    }
  }

  Currency _currencyOf(Ledger l, int accountId) =>
      l.currency(l.accounts[accountId]?.currencyCode ?? l.base.code);

  /// Подставляет сумму зачисления и сумму в валюте долга по текущему курсу,
  /// пока пользователь не ввёл их сам.
  void _autofill(Ledger l) {
    final from = _accountId == null ? null : _currencyOf(l, _accountId!);
    if (from == null) return;
    final amount = AmountField.valueOf(_amount, decimals: from.decimals);
    void fill(TextEditingController c, Currency to) {
      final v = amount == null ? null : l.rates.latest.convert(amount, from, to);
      c.text = v == null || v <= 0 ? '' : Money.toEditable(v, decimals: to.decimals);
    }

    if (_isTransfer && !_toAmountTouched && _toAccountId != null) {
      fill(_toAmount, _currencyOf(l, _toAccountId!));
    }
    final debt = l.debts[_debtId];
    if (_isDebt && !_debtAmountTouched && debt != null) {
      fill(_debtAmount, l.currency(debt.currencyCode));
    }
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

  Future<void> _save(Ledger l, List<Budget> budgets) async {
    setState(() => _categoryError = null);
    final formOk = _formKey.currentState!.validate();
    if (_isCategorized && _categoryId == null) {
      setState(() => _categoryError = 'Выберите категорию');
      return;
    }
    if (!formOk) return;

    final accountId = _accountId!;
    final currency = _currencyOf(l, accountId);
    final amount = AmountField.valueOf(_amount, decimals: currency.decimals)!;
    int? toAmount;
    if (_isTransfer) {
      final to = _currencyOf(l, _toAccountId!);
      toAmount = to.code == currency.code
          ? amount
          : AmountField.valueOf(_toAmount, decimals: to.decimals);
    }
    final debt = l.debts[_debtId];
    int? debtAmount;
    if (_isDebt && debt != null && debt.currencyCode != currency.code) {
      debtAmount = AmountField.valueOf(_debtAmount, decimals: l.currency(debt.currencyCode).decimals);
    }

    final input = OperationInput(
      type: _type,
      date: _date,
      accountId: accountId,
      amount: amount,
      categoryId: _categoryId,
      toAccountId: _toAccountId,
      toAmount: toAmount,
      debtId: _debtId,
      debtAmount: debtAmount,
      note: _note.text,
    );
    final error = input.validate();
    if (error != null) {
      showSnack(context, error);
      return;
    }

    // Что станет с бюджетом и долгом после сохранения — считаем заранее.
    final existing = _isEdit ? _source : null;
    final budget = _type == OperationType.expense
        ? budgetAfterExpense(
            l, budgets,
            categoryId: _categoryId!, date: _date, amount: amount,
            currency: currency, replacingOperationId: existing?.id,
          )
        : null;
    final debtRemaining = debt == null
        ? null
        : debtRemainingAfter(
            debtView(l, debt),
            replacing: existing,
            type: _type,
            debtAmount: debtAmount ?? amount,
          );

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(operationRepositoryProvider).save(input, id: existing?.id);
      await ref.read(settingsRepositoryProvider).setLastAccountId(accountId);

      String? message;
      if (debt != null && debtRemaining != null) {
        final closed = debtRemaining <= 0;
        if (closed != debt.isClosed) {
          await ref.read(debtRepositoryProvider).setClosed(debt.id, closed);
          message = closed ? 'Долг погашен полностью и закрыт' : 'Долг снова открыт';
        }
      }
      if (budget != null && budget.ratio >= 0.8) {
        final name = budget.category?.name ?? 'категория';
        message = budget.isOver
            ? 'Бюджет «$name» превышен на ${budget.currency.format(-budget.remaining)}'
            : 'Бюджет «$name»: потрачено ${formatPercent(budget.ratio)} — '
                '${budget.currency.format(budget.spent)} из ${budget.currency.format(budget.limit)}';
      }
      if (!mounted) return;
      context.pop();
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(Ledger l) async {
    final op = _source!;
    final ok = await confirmDialog(context, title: 'Удалить операцию?');
    if (!ok || !mounted) return;
    await ref.read(operationRepositoryProvider).delete(op.id);
    // Если удалили погашение закрытого долга — долг снова открыт.
    final debt = l.debts[op.debtId];
    if (debt != null) {
      final remaining = debtRemainingAfter(debtView(l, debt), replacing: op, type: op.type, debtAmount: 0);
      if (debt.isClosed && remaining > 0) {
        await ref.read(debtRepositoryProvider).setClosed(debt.id, false);
      }
    }
    if (mounted) context.pop();
  }

  String _title(Ledger l) {
    if (_isEdit) return 'Операция';
    final debt = l.debts[_debtId];
    if (_isDebt && debt != null) return debtOperationLabel(debt.direction, _type);
    if (_isAdjustment) return 'Корректировка баланса';
    return 'Новая операция';
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    final l = ledger.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(l == null ? '' : _title(l)),
        actions: [
          if (_isEdit && _source != null && l != null) ...[
            IconButton(
              tooltip: 'Повторить (копия с сегодняшней датой)',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () => context.pushReplacement(Routes.operationCopy(_source!.id)),
            ),
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(l),
            ),
          ],
        ],
      ),
      body: _loading || l == null
          ? Center(
              child: ledger.hasError
                  ? Text('Ошибка: ${ledger.error}')
                  : const CircularProgressIndicator(),
            )
          : _notFound
              ? const Center(child: Text('Операция не найдена'))
              : _buildForm(l, budgets),
    );
  }

  Widget _buildForm(Ledger l, List<Budget> budgets) {
    final theme = Theme.of(context);
    final balances = ref.watch(accountBalancesProvider).value ?? const <int, int>{};
    final active = l.accounts.values.where((a) => !a.isArchived).toList();
    if (active.isEmpty && _accountId == null) {
      return const Center(child: Text('Сначала создайте счёт на вкладке «Счета»'));
    }

    // Счета для выбора: активные + уже выбранные (даже если в архиве).
    List<Account> choices(int? selected) => [
      ...active,
      if (selected != null && l.accounts[selected]?.isArchived == true) l.accounts[selected]!,
    ];
    if (_accountId == null || !l.accounts.containsKey(_accountId)) {
      _accountId = active.first.id;
    }
    if (_isTransfer &&
        (_toAccountId == null || _toAccountId == _accountId || !l.accounts.containsKey(_toAccountId))) {
      _toAccountId = active.where((a) => a.id != _accountId).firstOrNull?.id;
    }
    _fillAmounts(l);

    final currency = _currencyOf(l, _accountId!);
    final debt = l.debts[_debtId];
    if (_isDebt && debt == null) {
      return const Center(child: Text('Долг не найден'));
    }
    final debtCurrency = debt == null ? null : l.currency(debt.currencyCode);
    final toCurrency = _toAccountId == null ? null : _currencyOf(l, _toAccountId!);
    final categoryType = _type == OperationType.income ? CategoryType.income : CategoryType.expense;

    final amountLabel = switch (_type) {
      OperationType.expense => 'Сумма расхода',
      OperationType.income => 'Сумма дохода',
      OperationType.transfer => 'Списать',
      OperationType.adjustment => 'Изменение баланса',
      OperationType.debtIn || OperationType.debtOut =>
        _type == OperationType.debtOut ? 'Сумма (ушло со счёта)' : 'Сумма (пришло на счёт)',
    };
    final accountLabel = switch (_type) {
      OperationType.income || OperationType.debtIn => 'На счёт',
      OperationType.adjustment => 'Счёт',
      _ => 'Со счёта',
    };

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (!_isDebt && !_isAdjustment) ...[
            SegmentedButton<OperationType>(
              segments: const [
                ButtonSegment(value: OperationType.expense, label: Text('Расход')),
                ButtonSegment(value: OperationType.income, label: Text('Доход')),
                ButtonSegment(value: OperationType.transfer, label: Text('Перевод')),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() {
                final next = s.first;
                final nextType = next == OperationType.income ? CategoryType.income : CategoryType.expense;
                if (l.categories[_categoryId]?.type != nextType) _categoryId = null;
                _type = next;
                _categoryError = null;
                _autofill(l);
              }),
            ),
            const SizedBox(height: 16),
          ],
          if (debt != null) ...[
            _DebtCard(view: debtView(l, debt)),
            const SizedBox(height: 16),
          ],
          AmountField(
            controller: _amount,
            decimals: currency.decimals,
            symbol: currency.symbol,
            label: amountLabel,
            allowNegative: _isAdjustment,
            autofocus: !_isEdit,
            helperText: _isAdjustment ? 'Плюс — денег стало больше, минус — меньше' : null,
            textStyle: theme.textTheme.headlineSmall,
            onChanged: (_) => setState(() => _autofill(l)),
          ),
          const SizedBox(height: 16),
          _AccountDropdown(
            label: accountLabel,
            accounts: choices(_accountId),
            balances: balances,
            ledger: l,
            value: _accountId!,
            onChanged: (id) => setState(() {
              _accountId = id;
              _autofill(l);
            }),
          ),
          if (_isTransfer) ...[
            const SizedBox(height: 16),
            if (_toAccountId == null)
              const Text('Для перевода нужен второй счёт — создайте его на вкладке «Счета»')
            else ...[
              _AccountDropdown(
                label: 'На счёт',
                accounts: choices(_toAccountId).where((a) => a.id != _accountId).toList(),
                balances: balances,
                ledger: l,
                value: _toAccountId!,
                onChanged: (id) => setState(() {
                  _toAccountId = id;
                  _autofill(l);
                }),
              ),
              if (toCurrency != null && toCurrency.code != currency.code) ...[
                const SizedBox(height: 16),
                AmountField(
                  controller: _toAmount,
                  decimals: toCurrency.decimals,
                  symbol: toCurrency.symbol,
                  label: 'Зачислить',
                  helperText: _exchangeHint(currency, toCurrency, _amount, _toAmount,
                      'Подставлено по курсу — исправьте на реальную сумму обмена'),
                  onChanged: (_) => setState(() => _toAmountTouched = true),
                ),
              ],
            ],
          ],
          if (debt != null && debtCurrency!.code != currency.code) ...[
            const SizedBox(height: 16),
            AmountField(
              controller: _debtAmount,
              decimals: debtCurrency.decimals,
              symbol: debtCurrency.symbol,
              label: 'Сколько это в валюте долга',
              helperText: _exchangeHint(currency, debtCurrency, _amount, _debtAmount,
                  'Долг в ${debtCurrency.code}, счёт в ${currency.code}: укажите, на сколько уменьшится/вырастет долг'),
              onChanged: (_) => setState(() => _debtAmountTouched = true),
            ),
          ],
          if (_isCategorized) ...[
            const SizedBox(height: 20),
            Text('Категория', style: theme.textTheme.titleSmall),
            if (_categoryError != null)
              Text(_categoryError!, style: TextStyle(color: theme.colorScheme.error)),
            const SizedBox(height: 8),
            CategoryPicker(
              categories: l.categories.values.where((c) => c.type == categoryType).toList(),
              selectedId: _categoryId,
              onSelected: (id) => setState(() {
                _categoryId = id;
                _categoryError = null;
              }),
              onSettings: () => context.push(Routes.categories),
            ),
          ],
          const SizedBox(height: 20),
          _DateChips(date: _date, onChanged: (d) => setState(() => _date = d), onPick: _pickDate),
          const SizedBox(height: 16),
          TextFormField(
            controller: _note,
            maxLength: 200,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Комментарий',
              hintText: 'Необязательно',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : () => _save(l, budgets),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }

  /// Подсказка под второй суммой: курс обмена из введённых сумм.
  String _exchangeHint(
    Currency from,
    Currency to,
    TextEditingController fromCtrl,
    TextEditingController toCtrl,
    String fallback,
  ) {
    final a = AmountField.valueOf(fromCtrl, decimals: from.decimals);
    final b = AmountField.valueOf(toCtrl, decimals: to.decimals);
    if (a == null || b == null || a <= 0 || b <= 0) return fallback;
    final rate = (b / Money.factor(to.decimals)) / (a / Money.factor(from.decimals));
    return rate >= 1
        ? 'Курс обмена: 1 ${from.symbol} = ${formatRate(rate)} ${to.symbol}'
        : 'Курс обмена: 1 ${to.symbol} = ${formatRate(1 / rate)} ${from.symbol}';
  }
}

class _AccountDropdown extends StatelessWidget {
  const _AccountDropdown({
    required this.label,
    required this.accounts,
    required this.balances,
    required this.ledger,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final List<Account> accounts;
  final Map<int, int> balances;
  final Ledger ledger;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      key: ValueKey('$label-$value'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: [
        for (final a in accounts)
          DropdownMenuItem(
            value: a.id,
            child: Row(
              children: [
                Icon(accountTypeIcon(a.type), size: 20, color: Color(a.color)),
                const SizedBox(width: 8),
                Expanded(child: Text(a.name, overflow: TextOverflow.ellipsis)),
                Text(
                  ledger.currency(a.currencyCode).format(balances[a.id] ?? a.initialBalance),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
      ],
      onChanged: (id) {
        if (id != null) onChanged(id);
      },
    );
  }
}

class _DateChips extends StatelessWidget {
  const _DateChips({required this.date, required this.onChanged, required this.onPick});

  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final today = dayOf(DateTime.now());
    final yesterday = DateTime(today.year, today.month, today.day - 1);
    final other = date != today && date != yesterday;
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Сегодня'),
          selected: date == today,
          onSelected: (_) => onChanged(today),
        ),
        ChoiceChip(
          label: const Text('Вчера'),
          selected: date == yesterday,
          onSelected: (_) => onChanged(yesterday),
        ),
        ChoiceChip(
          avatar: const Icon(Icons.calendar_today, size: 18),
          label: Text(other ? formatDate(date) : 'Другая дата'),
          selected: other,
          onSelected: (_) => onPick(),
        ),
      ],
    );
  }
}

class _DebtCard extends StatelessWidget {
  const _DebtCard({required this.view});

  final DebtView view;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.handshake_outlined),
        title: Text(view.debt.personName),
        subtitle: Text(
          '${view.theyOwe ? 'Мне должны' : 'Я должен'}: '
          '${view.currency.format(view.remaining)}',
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
