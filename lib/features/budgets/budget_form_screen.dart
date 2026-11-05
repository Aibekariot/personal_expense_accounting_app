import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatters.dart';
import '../../core/money.dart';
import '../../core/widgets/amount_field.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';

/// Создание (budgetId == null) или изменение бюджета.
class BudgetFormScreen extends ConsumerStatefulWidget {
  const BudgetFormScreen({super.key, this.budgetId});

  final int? budgetId;

  @override
  ConsumerState<BudgetFormScreen> createState() => _BudgetFormScreenState();
}

class _BudgetFormScreenState extends ConsumerState<BudgetFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _limit = TextEditingController();

  int? _categoryId;
  String? _currencyCode;
  Budget? _existing;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  bool get _isEdit => widget.budgetId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _limit.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_isEdit) {
      final b = await ref.read(budgetRepositoryProvider).getById(widget.budgetId!);
      if (b == null) {
        _notFound = true;
      } else {
        final currency = await ref.read(currencyRepositoryProvider).getByCode(b.currencyCode);
        _existing = b;
        _categoryId = b.categoryId;
        _currencyCode = b.currencyCode;
        _limit.text = Money.toEditable(b.monthlyLimit, decimals: currency?.decimals ?? 2);
      }
    } else {
      _currencyCode = await ref.read(settingsRepositoryProvider).baseCurrency();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save(Currency currency) async {
    if (!_formKey.currentState!.validate()) return;
    final limit = AmountField.valueOf(_limit, decimals: currency.decimals)!;
    setState(() => _saving = true);
    try {
      await ref.read(budgetRepositoryProvider).save(
        id: _existing?.id,
        categoryId: _categoryId!,
        monthlyLimit: limit,
        currencyCode: currency.code,
      );
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final ok = await confirmDialog(context, title: 'Удалить статью бюджета?');
    if (!ok) return;
    await ref.read(budgetRepositoryProvider).delete(_existing!.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Статья бюджета' : 'Новая статья бюджета'),
        actions: [
          if (_existing != null)
            IconButton(tooltip: 'Удалить', icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notFound
              ? const Center(child: Text('Бюджет не найден'))
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final categories = ref.watch(categoriesProvider).value ?? const <CategoryEntity>[];
    final currencies = ref.watch(currenciesProvider).value ?? const <Currency>[];
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    if (currencies.isEmpty) return const Center(child: CircularProgressIndicator());

    final withBudget = {for (final b in budgets) if (b.id != _existing?.id) b.categoryId};
    final items = <DropdownMenuItem<int>>[];
    for (final type in CategoryType.values) {
      final ofType = categories.where((c) => c.type == type && (!c.isArchived || c.id == _categoryId));
      final prefix = type == CategoryType.income ? 'Доход: ' : '';
      for (final top in ofType.where((c) => c.parentId == null)) {
        items.add(DropdownMenuItem(
          value: top.id,
          enabled: !withBudget.contains(top.id),
          child: Text('$prefix${top.name}${withBudget.contains(top.id) ? ' (уже есть)' : ''}'),
        ));
        for (final child in ofType.where((c) => c.parentId == top.id)) {
          items.add(DropdownMenuItem(
            value: child.id,
            enabled: !withBudget.contains(child.id),
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text('${child.name}${withBudget.contains(child.id) ? ' (уже есть)' : ''}'),
            ),
          ));
        }
      }
    }
    final isIncome = categories.where((c) => c.id == _categoryId).firstOrNull?.type == CategoryType.income;
    final currency = currencies.firstWhere((c) => c.code == _currencyCode, orElse: () => currencies.first);

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _categoryId,
            isExpanded: true,
            menuMaxHeight: 420,
            decoration: const InputDecoration(
              labelText: 'Категория',
              helperText: 'Расход — лимит на месяц, доход — план дохода. '
                  'Для основной категории учитываются и подкатегории',
              helperMaxLines: 2,
            ),
            items: items,
            onChanged: (v) => setState(() => _categoryId = v),
            validator: (v) => v == null ? 'Выберите категорию' : null,
          ),
          const SizedBox(height: 20),
          AmountField(
            controller: _limit,
            decimals: currency.decimals,
            symbol: currency.symbol,
            label: isIncome ? 'План дохода на месяц' : 'Лимит на месяц',
            autofocus: !_isEdit,
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: currency.code,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Валюта бюджета',
              helperText: 'Расходы в других валютах пересчитываются по курсу на дату расхода',
              helperMaxLines: 2,
            ),
            items: [
              for (final c in currencies) DropdownMenuItem(value: c.code, child: Text(c.label)),
            ],
            onChanged: (v) => setState(() => _currencyCode = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : () => _save(currency),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
