import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_icons.dart';
import '../../core/widgets/category_avatar.dart';
import '../../core/widgets/color_picker.dart';
import '../../core/widgets/dialogs.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';

/// Создание (categoryId == null) или изменение категории.
class CategoryFormScreen extends ConsumerStatefulWidget {
  const CategoryFormScreen({
    super.key,
    this.categoryId,
    this.type = CategoryType.expense,
    this.parentId,
  });

  final int? categoryId;
  final CategoryType type;
  final int? parentId;

  @override
  ConsumerState<CategoryFormScreen> createState() => _CategoryFormScreenState();
}

class _CategoryFormScreenState extends ConsumerState<CategoryFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();

  late CategoryType _type = widget.type;
  int? _parentId;
  String _icon = 'more';
  int _color = pickerColors.first;

  CategoryEntity? _existing;
  bool _hasChildren = false;
  bool _loading = true;
  bool _notFound = false;
  bool _saving = false;

  bool get _isEdit => widget.categoryId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(categoryRepositoryProvider);
    if (_isEdit) {
      final c = await repo.getById(widget.categoryId!);
      if (c == null) {
        _notFound = true;
      } else {
        _existing = c;
        _name.text = c.name;
        _type = c.type;
        _parentId = c.parentId;
        _icon = c.icon;
        _color = c.color;
        _hasChildren = (await repo.children(c.id)).isNotEmpty;
      }
    } else if (widget.parentId != null) {
      // Подкатегория по умолчанию — с иконкой и цветом родителя.
      final parent = await repo.getById(widget.parentId!);
      if (parent != null) {
        _parentId = parent.id;
        _type = parent.type;
        _icon = parent.icon;
        _color = parent.color;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repo = ref.read(categoryRepositoryProvider);
    setState(() => _saving = true);
    try {
      final existing = _existing;
      if (existing == null) {
        await repo.create(
          name: _name.text.trim(),
          type: _type,
          parentId: _parentId,
          icon: _icon,
          color: _color,
        );
      } else {
        await repo.update(existing.copyWith(
          name: _name.text.trim(),
          parentId: Value(_parentId),
          icon: _icon,
          color: _color,
        ));
      }
      if (mounted) context.pop();
    } on ArgumentError catch (e) {
      if (mounted) showSnack(context, '${e.message}');
    } catch (e) {
      if (mounted) showSnack(context, 'Не удалось сохранить: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleArchive() async {
    final c = _existing!;
    await ref.read(categoryRepositoryProvider).setArchived(c.id, !c.isArchived);
    if (!mounted) return;
    showSnack(context, c.isArchived ? 'Категория возвращена из архива' : 'Категория в архиве');
    context.pop();
  }

  Future<void> _delete() async {
    final c = _existing!;
    final repo = ref.read(categoryRepositoryProvider);
    if (await repo.isUsed(c.id)) {
      if (!mounted) return;
      await infoDialog(
        context,
        title: 'Нельзя удалить категорию',
        message: 'Категория (или её подкатегория) используется в операциях или '
            'бюджетах. Отправьте её в архив: при вводе она больше не будет '
            'показываться, а история и статистика сохранятся.',
      );
      return;
    }
    if (!mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Удалить «${c.name}»?',
      message: _hasChildren ? 'Подкатегории тоже будут удалены.' : null,
    );
    if (!ok) return;
    await repo.delete(c.id);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final existing = _existing;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Категория' : (_parentId != null ? 'Новая подкатегория' : 'Новая категория')),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notFound
              ? const Center(child: Text('Категория не найдена'))
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final theme = Theme.of(context);
    final all = ref.watch(categoriesProvider).value ?? const <CategoryEntity>[];
    final parents = all
        .where((c) => c.type == _type && c.parentId == null && c.id != _existing?.id)
        .toList();

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              CategoryAvatar(icon: categoryIcon(_icon), color: Color(_color), filled: true, radius: 28),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: _name,
                  autofocus: !_isEdit,
                  maxLength: 50,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Название',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Введите название' : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_isEdit && _parentId == null) ...[
            SegmentedButton<CategoryType>(
              segments: const [
                ButtonSegment(value: CategoryType.expense, label: Text('Расход')),
                ButtonSegment(value: CategoryType.income, label: Text('Доход')),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<int?>(
            key: ValueKey('parent-$_type'),
            initialValue: _parentId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Входит в категорию',
              border: const OutlineInputBorder(),
              helperText: _hasChildren
                  ? 'У категории есть подкатегории — она может быть только основной'
                  : null,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('Нет — это основная категория')),
              for (final p in parents) DropdownMenuItem(value: p.id, child: Text(p.name)),
            ],
            onChanged: _hasChildren ? null : (v) => setState(() => _parentId = v),
          ),
          const SizedBox(height: 20),
          Text('Иконка', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in categoryIcons.entries)
                InkWell(
                  onTap: () => setState(() => _icon = e.key),
                  customBorder: const CircleBorder(),
                  child: CategoryAvatar(
                    icon: e.value,
                    color: Color(_color),
                    filled: e.key == _icon,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text('Цвет', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          ColorPicker(selected: _color, onChanged: (c) => setState(() => _color = c)),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
  }
}
