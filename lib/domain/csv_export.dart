import '../core/formatters.dart';
import '../core/money.dart';
import '../data/db/app_database.dart';
import 'ledger.dart';

/// Операции в CSV для Excel / Google Таблиц: разделитель «;», запятая
/// в дробных числах, в начале — метка UTF-8 (BOM), чтобы Excel понял кириллицу.
String operationsToCsv(Ledger ledger, Iterable<OperationView> ops) {
  String typeLabel(OperationType t) => switch (t) {
    OperationType.expense => 'Расход',
    OperationType.income => 'Доход',
    OperationType.transfer => 'Перевод',
    OperationType.adjustment => 'Корректировка',
    OperationType.debtOut || OperationType.debtIn => 'Долг',
  };
  String amount(int minor, Currency c) => Money.toEditable(minor, decimals: c.decimals);
  String cell(String s) {
    final v = s.replaceAll('\r', ' ').replaceAll('\n', ' ');
    return v.contains(RegExp('[;"]')) ? '"${v.replaceAll('"', '""')}"' : v;
  }

  final rows = <List<String>>[
    [
      'Дата', 'Тип', 'Счёт', 'Сумма', 'Валюта', 'Категория', 'Подкатегория',
      'Счёт зачисления', 'Сумма зачисления', 'Валюта зачисления', 'Долг',
      'Комментарий', 'Сумма в ${ledger.base.code}',
    ],
    for (final v in ops)
      [
        formatDate(v.date),
        v.isDebt ? v.title : typeLabel(v.type),
        v.account?.name ?? '',
        amount(v.isExpense ? -v.op.amount : v.op.amount, v.currency),
        v.currency.code,
        v.topCategory?.name ?? '',
        v.category?.parentId != null ? v.category!.name : '',
        v.toAccount?.name ?? '',
        v.op.toAmount == null ? '' : amount(v.op.toAmount!, v.toCurrency!),
        v.toCurrency?.code ?? '',
        v.debt?.personName ?? '',
        v.op.note,
        v.baseAmount == null
            ? ''
            : amount(v.isExpense ? -v.baseAmount! : v.baseAmount!, ledger.base),
      ],
  ];
  return '﻿${rows.map((r) => r.map(cell).join(';')).join('\r\n')}\r\n';
}
