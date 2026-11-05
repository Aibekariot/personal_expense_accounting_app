import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/app_icons.dart';
import '../../core/widgets/category_avatar.dart';
import '../../data/db/app_database.dart';
import '../../data/providers.dart';

class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  CategoryType _type = CategoryType.expense;

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Категории')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.categoryNew(_type)),
        icon: const Icon(Icons.add),
        label: const Text('Категория'),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (all) {
          final ofType = all.where((c) => c.type == _type).toList();
          final top = ofType.where((c) => c.parentId == null).toList();
          final active = top.where((c) => !c.isArchived).toList();
          final archived = top.where((c) => c.isArchived).toList();
          List<CategoryEntity> childrenOf(CategoryEntity c) =>
              ofType.where((x) => x.parentId == c.id).toList();

          return ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: SegmentedButton<CategoryType>(
                  segments: const [
                    ButtonSegment(value: CategoryType.expense, label: Text('Расходы')),
                    ButtonSegment(value: CategoryType.income, label: Text('Доходы')),
                  ],
                  selected: {_type},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _type = s.first),
                ),
              ),
              for (final c in active) ...[
                _CategoryTile(category: c),
                for (final child in childrenOf(c)) _CategoryTile(category: child, indent: true),
              ],
              if (archived.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text('Архив (${archived.length})'),
                  subtitle: const Text('Не показываются при вводе, но остаются в истории'),
                  children: [
                    for (final c in archived) ...[
                      _CategoryTile(category: c),
                      for (final child in childrenOf(c)) _CategoryTile(category: child, indent: true),
                    ],
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, this.indent = false});

  final CategoryEntity category;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final c = category;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      contentPadding: EdgeInsets.only(left: indent ? 56 : 16, right: 8),
      leading: CategoryAvatar(
        icon: categoryIcon(c.icon),
        color: Color(c.color),
        radius: indent ? 14 : 20,
      ),
      title: Text(c.name, style: c.isArchived ? TextStyle(color: muted) : null),
      subtitle: c.isArchived ? const Text('в архиве') : null,
      trailing: indent
          ? null
          : IconButton(
              tooltip: 'Добавить подкатегорию',
              icon: const Icon(Icons.add),
              onPressed: () => context.push(Routes.categoryNew(c.type, parentId: c.id)),
            ),
      onTap: () => context.push(Routes.categoryEdit(c.id)),
    );
  }
}
