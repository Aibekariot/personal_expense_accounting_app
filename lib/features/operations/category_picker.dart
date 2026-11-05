import 'package:flutter/material.dart';

import '../../core/app_icons.dart';
import '../../core/widgets/category_avatar.dart';
import '../../data/db/app_database.dart';

/// Выбор категории: сетка основных категорий, под ней — подкатегории
/// выбранной категории.
class CategoryPicker extends StatelessWidget {
  const CategoryPicker({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onSelected,
    this.onSettings,
  });

  /// Категории нужного типа (основные и подкатегории).
  final List<CategoryEntity> categories;
  final int? selectedId;
  final ValueChanged<int> onSelected;

  /// Кнопка «Настроить» в конце сетки.
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final byId = {for (final c in categories) c.id: c};
    final selected = byId[selectedId];
    final selectedTopId = selected?.parentId ?? selected?.id;

    bool visible(CategoryEntity c) => !c.isArchived || c.id == selectedId || c.id == selectedTopId;
    final top = categories.where((c) => c.parentId == null && visible(c)).toList();
    final children = selectedTopId == null
        ? const <CategoryEntity>[]
        : categories.where((c) => c.parentId == selectedTopId && visible(c)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 6 : 4;
            final width = (constraints.maxWidth - 4 * (columns - 1)) / columns;
            return Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final c in top)
                  _Tile(
                    width: width,
                    icon: categoryIcon(c.icon),
                    color: Color(c.color),
                    label: c.name,
                    selected: c.id == selectedTopId,
                    onTap: () => onSelected(c.id),
                  ),
                if (onSettings != null)
                  _Tile(
                    width: width,
                    icon: Icons.tune,
                    color: theme.colorScheme.outline,
                    label: 'Настроить',
                    selected: false,
                    onTap: onSettings!,
                  ),
              ],
            );
          },
        ),
        if (children.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Подкатегория «${byId[selectedTopId]!.name}»',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                label: const Text('Без подкатегории'),
                selected: selectedId == selectedTopId,
                onSelected: (_) => onSelected(selectedTopId!),
              ),
              for (final c in children)
                ChoiceChip(
                  label: Text(c.name),
                  selected: selectedId == c.id,
                  onSelected: (_) => onSelected(c.id),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.width,
    required this.icon,
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            children: [
              CategoryAvatar(icon: icon, color: color, filled: selected, radius: 22),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.bold : null,
                  color: selected ? theme.colorScheme.onSurface : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
