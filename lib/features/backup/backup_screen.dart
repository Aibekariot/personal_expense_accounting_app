import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/formatters.dart';
import '../../core/platform/file_io.dart' as io;
import '../../core/widgets/dialogs.dart';
import '../../data/backup/backup_service.dart';
import '../../data/providers.dart';
import '../../domain/csv_export.dart';
import '../../domain/providers.dart';

/// Готовый к сохранению файл.
class _PreparedFile {
  _PreparedFile(this.name, this.bytes, this.mime);
  final String name;
  final Uint8List bytes;
  final String mime;
}

final _persistedProvider = FutureProvider<bool?>((ref) => io.isStoragePersisted());

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  String get _stamp => DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on UnsupportedError catch (e) {
      if (mounted) showSnack(context, '${e.message}');
    } on BackupException catch (e) {
      if (mounted) await infoDialog(context, title: 'Не получилось', message: e.message);
    } catch (e) {
      if (mounted) showSnack(context, 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _backup() => _run(() async {
    final json = await ref.read(backupServiceProvider).exportJson();
    final file = _PreparedFile(
      'moi-finansy_$_stamp.json',
      Uint8List.fromList(utf8.encode(json)),
      'application/json',
    );
    if (!mounted) return;
    final saved = await _saveSheet(file, 'Резервная копия готова');
    if (saved) {
      await ref.read(settingsRepositoryProvider).setLastBackup(DateTime.now());
      if (mounted) showSnack(context, 'Копия сохранена. Храните файл в надёжном месте.');
    }
  });

  Future<void> _exportCsv() => _run(() async {
    final ledger = ref.read(ledgerProvider).value;
    if (ledger == null) return;
    if (ledger.operations.isEmpty) {
      showSnack(context, 'Операций пока нет');
      return;
    }
    final csv = operationsToCsv(ledger, ledger.operations.reversed);
    final file = _PreparedFile(
      'operacii_$_stamp.csv',
      Uint8List.fromList(utf8.encode(csv)),
      'text/csv',
    );
    if (!mounted) return;
    await _saveSheet(file, 'Таблица операций готова');
  });

  /// Нижняя панель с кнопками «Скачать» и «Отправить».
  /// Файл уже готов, поэтому кнопки срабатывают сразу — это важно для iPhone.
  Future<bool> _saveSheet(_PreparedFile file, String title) async {
    final canShare = io.canShareFile(file.name, file.mime);
    final result = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('${file.name} · ${(file.bytes.length / 1024).toStringAsFixed(1)} КБ'),
              const SizedBox(height: 16),
              if (canShare) ...[
                FilledButton.icon(
                  onPressed: () async {
                    final ok = await io.shareFile(file.name, file.bytes, file.mime);
                    if (ok && ctx.mounted) Navigator.pop(ctx, true);
                  },
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Отправить или сохранить в «Файлы»'),
                ),
                const SizedBox(height: 8),
              ],
              if (canShare)
                OutlinedButton.icon(
                  onPressed: () => _download(ctx, file),
                  icon: const Icon(Icons.download),
                  label: const Text('Скачать файл'),
                )
              else
                FilledButton.icon(
                  onPressed: () => _download(ctx, file),
                  icon: const Icon(Icons.download),
                  label: const Text('Скачать файл'),
                ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  void _download(BuildContext sheetContext, _PreparedFile file) {
    io.downloadFile(file.name, file.bytes, file.mime);
    Navigator.pop(sheetContext, true);
  }

  Future<void> _restore() => _run(() async {
    final text = await io.pickTextFile();
    if (text == null || !mounted) return;
    final service = ref.read(backupServiceProvider);
    final data = service.parse(text);
    final ok = await confirmDialog(
      context,
      title: 'Восстановить данные из копии?',
      message: [
        if (data.exportedAt != null) 'Копия от ${formatDateTime(data.exportedAt!)}.',
        'В ней: счетов — ${data.accounts.length}, операций — ${data.operations.length}, '
            'долгов — ${data.debts.length}, бюджетов — ${data.budgets.length}.',
        '',
        'ВСЕ текущие данные на этом устройстве будут заменены данными из копии.',
      ].join('\n'),
      confirmLabel: 'Заменить',
    );
    if (!ok) return;
    await service.restore(data);
    if (mounted) showSnack(context, 'Данные восстановлены');
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastBackup = ref.watch(lastBackupProvider).value;
    final persisted = ref.watch(_persistedProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Резервная копия')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            if (_busy) const LinearProgressIndicator(),
            Card.filled(
              margin: const EdgeInsets.all(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline),
                        const SizedBox(width: 8),
                        Text('Где хранятся данные', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Только на этом устройстве, в памяти браузера. На сервер ничего '
                      'не отправляется. Если очистить данные браузера, удалить '
                      'приложение или потерять телефон — данные пропадут.\n\n'
                      'Сохраняйте копию раз в неделю: в «Файлы», в Telegram '
                      '(«Избранное») или на компьютер. На новом телефоне её можно восстановить.',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      lastBackup == null
                          ? 'Копий ещё не было'
                          : 'Последняя копия: ${formatDateTime(lastBackup)}',
                      style: theme.textTheme.titleSmall,
                    ),
                    if (persisted == true) ...[
                      const SizedBox(height: 4),
                      Text('Браузер не удалит данные сам при нехватке места', style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: const Text('Сохранить резервную копию'),
              subtitle: const Text('Все данные в одном файле'),
              onTap: _backup,
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: const Text('Восстановить из копии'),
              subtitle: const Text('Заменит текущие данные данными из файла'),
              onTap: _restore,
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Выгрузить операции в Excel'),
              subtitle: const Text('Файл CSV: открывается в Excel и Google Таблицах'),
              onTap: _exportCsv,
            ),
          ],
        ),
      ),
    );
  }
}
