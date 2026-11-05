import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/db/app_database.dart';

/// Кнопка «+»: раскрывает меню — расход, доход, перевод, долг, план.
class QuickAddFab extends StatelessWidget {
  const QuickAddFab({super.key});

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (fabContext) => FloatingActionButton(
        tooltip: 'Добавить',
        shape: const CircleBorder(),
        onPressed: () => _open(fabContext),
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }

  Future<void> _open(BuildContext fabContext) async {
    final box = fabContext.findRenderObject()! as RenderBox;
    final fab = box.localToGlobal(Offset.zero) & box.size;
    final screen = MediaQuery.sizeOf(fabContext);
    final colors = MoneyColors.of(fabContext);
    final scheme = Theme.of(fabContext).colorScheme;

    final items = <(String, IconData, Color, String)>[
      ('Расход', Icons.remove, colors.expense, Routes.operationNew(type: OperationType.expense)),
      ('Доход', Icons.add, colors.income, Routes.operationNew(type: OperationType.income)),
      ('Перевод', Icons.swap_horiz, scheme.primary, Routes.operationNew(type: OperationType.transfer)),
      ('Долг', Icons.handshake_outlined, scheme.tertiary, Routes.debtNew),
      ('Регулярный платёж', Icons.event_repeat, scheme.primary, Routes.planNew()),
    ];

    final route = await showGeneralDialog<String>(
      context: fabContext,
      barrierDismissible: true,
      barrierLabel: 'Закрыть',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (ctx, _, _) => Stack(
        children: [
          Positioned(
            right: screen.width - fab.right,
            bottom: screen.height - fab.top + 12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 10,
              children: [
                for (final (label, icon, color, target) in items.reversed)
                  _Pill(label: label, icon: icon, color: color, onTap: () => Navigator.pop(ctx, target)),
              ],
            ),
          ),
          Positioned.fromRect(
            rect: fab,
            child: FloatingActionButton(
              heroTag: null,
              tooltip: 'Закрыть',
              shape: const CircleBorder(),
              onPressed: () => Navigator.pop(ctx),
              child: const Icon(Icons.close, size: 28),
            ),
          ),
        ],
      ),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(anim),
          child: child,
        ),
      ),
    );
    if (route == null || !fabContext.mounted) return;
    // Долги живут во вкладке «Ещё»: переходим к списку долгов и открываем
    // форму поверх — после сохранения новый долг сразу виден в списке.
    if (route == Routes.debtNew) fabContext.go(Routes.debts);
    fabContext.push(route);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon, required this.color, required this.onTap});

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      shape: const StadiumBorder(),
      elevation: 2,
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 12,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleSmall),
              CircleAvatar(
                radius: 16,
                backgroundColor: color.withValues(alpha: 0.18),
                foregroundColor: color,
                child: Icon(icon, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
