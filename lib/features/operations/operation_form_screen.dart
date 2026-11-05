import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/app_icons.dart';
import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/amount_keypad.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';
import '../../data/repositories/operation_repository.dart';
import '../../domain/budgets.dart';
import '../../domain/calculator.dart';
import '../../domain/debts.dart';
import '../../domain/ledger.dart';
import '../../domain/payees.dart';
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
  final _toAmount = TextEditingController();
  final _debtAmount = TextEditingController();
  final _note = TextEditingController();
  final _payee = TextEditingController();
  final _payeeFocus = FocusNode();

  /// Выражение суммы с калькулятора: «350+120».
  String _expr = '';
  bool _keypadVisible = true;

  OperationType _type = OperationType.expense;
  int? _accountId;
  int? _toAccountId;
  int? _categoryId;
  int? _debtId;
  DateTime _date = dayOf(DateTime.now());

  /// Пользователь сам выбрал категорию — больше не подставляем её по получателю.
  bool _categoryTouched = false;

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
  String? _amountError;

  bool get _isEdit => widget.operationId != null;
  bool get _isTransfer => _type == OperationType.transfer;
  bool get _isAdjustment => _type == OperationType.adjustment;
  bool get _isDebt => _type == OperationType.debtIn || _type == OperationType.debtOut;
  bool get _isCategorized => _type == OperationType.expense || _type == OperationType.income;

  @override
  void initState() {
    super.initState();
    _payeeFocus.addListener(() {
      if (_payeeFocus.hasFocus) setState(() => _keypadVisible = false);
    });
    _load();
  }

  @override
  void dispose() {
    _toAmount.dispose();
    _debtAmount.dispose();
    _note.dispose();
    _payee.dispose();
    _payeeFocus.dispose();
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
        _payee.text = op.payee;
        _categoryTouched = true;
        _toAmountTouched = true;
        _debtAmountTouched = true;
        // Сумма уже есть — клавиатура откроется по нажатию на сумму.
        _keypadVisible = !_isEdit;
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
    _expr = Money.toEditable(op.amount, decimals: _currencyOf(l, op.accountId).decimals)
        .replaceAll('-', '−');
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

  int? _amountValue(Ledger l) =>
      _accountId == null ? null : evaluateAmount(_expr, decimals: _currencyOf(l, _accountId!).decimals);

  /// Подставляет сумму зачисления и сумму в валюте долга по текущему курсу,
  /// пока пользователь не ввёл их сам.
  void _autofill(Ledger l) {
    if (_accountId == null) return;
    final from = _currencyOf(l, _accountId!);
    final amount = _amountValue(l);
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

  void _onKey(Ledger l, String key) {
    final decimals = _currencyOf(l, _accountId!).decimals;
    setState(() {
      _expr = pressKey(_expr, key, decimals: decimals, allowNegative: _isAdjustment);
      _amountError = null;
      _autofill(l);
    });
  }

  void _showKeypad() {
    FocusScope.of(context).unfocus();
    setState(() => _keypadVisible = true);
  }

  /// Получатель изменён: подставляем категорию, которую обычно выбирают для него.
  void _onPayeeChanged(Ledger l, String value) {
    setState(() {
      if (!_categoryTouched && _isCategorized) {
        final suggested = suggestCategory(l, value, _type);
        if (suggested != null && l.categories.containsKey(suggested)) {
          _categoryId = suggested;
          _categoryError = null;
        }
      }
    });
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
    // Незаконченное выражение («350+») — сначала посчитать.
    if (_expr.isNotEmpty && hasOperator(_expr) && _amountValue(l) == null) {
      setState(() => _amountError = 'Выражение не закончено');
      return;
    }
    final accountId = _accountId!;
    final currency = _currencyOf(l, accountId);
    final amount = _amountValue(l);
    setState(() {
      _categoryError = null;
      _amountError = amount == null ? 'Введите сумму' : null;
    });
    final formOk = _formKey.currentState!.validate();
    if (_isCategorized && _categoryId == null) {
      setState(() => _categoryError = 'Выберите категорию');
    }
    if (amount == null || !formOk || (_isCategorized && _categoryId == null)) return;

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
      payee: _payee.text,
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
    final ready = !_loading && l != null && !_notFound;

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
      body: !ready
          ? Center(
              child: _notFound
                  ? const Text('Операция не найдена')
                  : ledger.hasError
                      ? Text('Ошибка: ${ledger.error}')
                      : const CircularProgressIndicator(),
            )
          : _buildBody(l, budgets),
    );
  }

  Widget _buildBody(Ledger l, List<Budget> budgets) {
    final active = l.accounts.values.where((a) => !a.isArchived).toList();
    if (active.isEmpty && _accountId == null) {
      return const Center(child: Text('Сначала создайте счёт на вкладке «Счета»'));
    }
    if (_accountId == null || !l.accounts.containsKey(_accountId)) {
      _accountId = active.first.id;
    }
    if (_isTransfer &&
        (_toAccountId == null || _toAccountId == _accountId || !l.accounts.containsKey(_toAccountId))) {
      _toAccountId = active.where((a) => a.id != _accountId).firstOrNull?.id;
    }
    _fillAmounts(l);
    if (_isDebt && l.debts[_debtId] == null) {
      return const Center(child: Text('Долг не найден'));
    }
    final currency = _currencyOf(l, _accountId!);

    return Column(
      children: [
        Expanded(child: _buildForm(l, active)),
        if (_keypadVisible)
          AmountKeypad(
            onKey: (k) => _onKey(l, k),
            onAction: _saving ? () {} : () => _save(l, budgets),
            onHide: () => setState(() => _keypadVisible = false),
            showEquals: hasOperator(_expr),
            allowComma: currency.decimals > 0,
          )
        else
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton(
                onPressed: _saving ? null : () => _save(l, budgets),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Сохранить'),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildForm(Ledger l, List<Account> active) {
    final theme = Theme.of(context);
    final balances = ref.watch(accountBalancesProvider).value ?? const <int, int>{};

    // Счета для выбора: активные + уже выбранные (даже если в архиве).
    List<Account> choices(int? selected) => [
      ...active,
      if (selected != null && l.accounts[selected]?.isArchived == true) l.accounts[selected]!,
    ];

    final currency = _currencyOf(l, _accountId!);
    final debt = l.debts[_debtId];
    final debtCurrency = debt == null ? null : l.currency(debt.currencyCode);
    final toCurrency = _toAccountId == null ? null : _currencyOf(l, _toAccountId!);
    final categoryType = _type == OperationType.income ? CategoryType.income : CategoryType.expense;
    final amount = _amountValue(l);

    final accountLabel = switch (_type) {
      OperationType.income || OperationType.debtIn => 'На счёт',
      OperationType.adjustment => 'Счёт',
      _ => 'Со счёта',
    };

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
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
                if (l.categories[_categoryId]?.type != nextType) {
                  _categoryId = null;
                  _categoryTouched = false;
                }
                _type = next;
                _categoryError = null;
                _autofill(l);
                if (!_categoryTouched) _onPayeeChanged(l, _payee.text);
              }),
            ),
            const SizedBox(height: 12),
          ],
          if (debt != null) ...[
            _DebtCard(view: debtView(l, debt)),
            const SizedBox(height: 12),
          ],
          _AmountDisplay(
            expr: _expr,
            value: amount,
            currency: currency,
            type: _type,
            active: _keypadVisible,
            error: _amountError,
            onTap: _showKeypad,
          ),
          const SizedBox(height: 12),
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
            const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                _SecondaryAmount(
                  controller: _toAmount,
                  currency: toCurrency,
                  label: 'Зачислить',
                  helper: _exchangeHint(currency, toCurrency, amount,
                      AmountField.valueOf(_toAmount, decimals: toCurrency.decimals),
                      'Подставлено по курсу — исправьте на реальную сумму обмена'),
                  onFocus: () => setState(() => _keypadVisible = false),
                  onChanged: () => setState(() => _toAmountTouched = true),
                ),
              ],
            ],
          ],
          if (debt != null && debtCurrency!.code != currency.code) ...[
            const SizedBox(height: 12),
            _SecondaryAmount(
              controller: _debtAmount,
              currency: debtCurrency,
              label: 'Сколько это в валюте долга',
              helper: _exchangeHint(currency, debtCurrency, amount,
                  AmountField.valueOf(_debtAmount, decimals: debtCurrency.decimals),
                  'Долг в ${debtCurrency.code}, счёт в ${currency.code}: укажите, на сколько изменится долг'),
              onFocus: () => setState(() => _keypadVisible = false),
              onChanged: () => setState(() => _debtAmountTouched = true),
            ),
          ],
          if (_isCategorized) ...[
            const SizedBox(height: 12),
            _PayeeField(
              controller: _payee,
              focusNode: _payeeFocus,
              label: _type == OperationType.income ? 'Плательщик' : 'Получатель',
              hint: _type == OperationType.income ? 'Например: работа' : 'Магазин, кафе, человек',
              suggestions: payeeSuggestions(l, _type, _payee.text),
              onChanged: (v) => _onPayeeChanged(l, v),
              onSelected: (v) {
                _payee.text = v;
                _payee.selection = TextSelection.collapsed(offset: v.length);
                _onPayeeChanged(l, v);
                FocusScope.of(context).unfocus();
              },
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
              onSettings: () => context.push(Routes.categories),
            ),
          ],
          const SizedBox(height: 16),
          _DateChips(date: _date, onChanged: (d) => setState(() => _date = d), onPick: _pickDate),
          const SizedBox(height: 16),
          Focus(
            onFocusChange: (f) {
              if (f) setState(() => _keypadVisible = false);
            },
            child: TextFormField(
              controller: _note,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Комментарий',
                hintText: 'Необязательно',
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Подсказка под второй суммой: курс обмена из введённых сумм.
  String _exchangeHint(Currency from, Currency to, int? a, int? b, String fallback) {
    if (a == null || b == null || a <= 0 || b <= 0) return fallback;
    final rate = (b / Money.factor(to.decimals)) / (a / Money.factor(from.decimals));
    return rate >= 1
        ? 'Курс обмена: 1 ${from.symbol} = ${formatRate(rate)} ${to.symbol}'
        : 'Курс обмена: 1 ${to.symbol} = ${formatRate(1 / rate)} ${from.symbol}';
  }
}

/// Крупная сумма вверху формы; нажатие открывает клавиатуру-калькулятор.
class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({
    required this.expr,
    required this.value,
    required this.currency,
    required this.type,
    required this.active,
    required this.error,
    required this.onTap,
  });

  final String expr;
  final int? value;
  final Currency currency;
  final OperationType type;
  final bool active;
  final String? error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = MoneyColors.of(context);
    final accent = switch (type) {
      OperationType.expense => colors.expense,
      OperationType.income => colors.income,
      _ => scheme.onSurface,
    };
    final withOps = hasOperator(expr);
    final shown = expr.isEmpty ? '0' : formatExpression(expr);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: error != null ? scheme.error : (active ? scheme.primary : Colors.transparent),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  type == OperationType.adjustment ? 'Изменение' : 'Сумма',
                  style: theme.textTheme.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$shown ${currency.symbol}',
                      style: (withOps ? theme.textTheme.titleLarge : theme.textTheme.displaySmall)
                          ?.copyWith(
                        color: expr.isEmpty ? scheme.onSurfaceVariant : (withOps ? null : accent),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (withOps)
              Text(
                value == null ? '= …' : '= ${currency.format(value!)}',
                style: theme.textTheme.headlineMedium?.copyWith(color: accent, fontWeight: FontWeight.w500),
              ),
            if (error != null)
              Text(error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
          ],
        ),
      ),
    );
  }
}

/// Вторая сумма (зачисление при обмене, сумма в валюте долга) — с обычной клавиатурой.
class _SecondaryAmount extends StatelessWidget {
  const _SecondaryAmount({
    required this.controller,
    required this.currency,
    required this.label,
    required this.helper,
    required this.onFocus,
    required this.onChanged,
  });

  final TextEditingController controller;
  final Currency currency;
  final String label;
  final String helper;
  final VoidCallback onFocus;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) {
        if (f) onFocus();
      },
      child: AmountField(
        controller: controller,
        decimals: currency.decimals,
        symbol: currency.symbol,
        label: label,
        helperText: helper,
        onChanged: (_) => onChanged(),
      ),
    );
  }
}

/// Получатель с подсказками из истории (частые — первыми).
class _PayeeField extends StatelessWidget {
  const _PayeeField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.suggestions,
    required this.onChanged,
    required this.onSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String hint;
  final List<String> suggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          focusNode: focusNode,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            counterText: '',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.storefront_outlined),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
          ),
          onChanged: onChanged,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              spacing: 6,
              children: [
                for (final s in suggestions)
                  ActionChip(
                    label: Text(s),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onSelected(s),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
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
