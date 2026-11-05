import 'package:flutter/material.dart';

/// Круглая иконка категории или счёта.
class CategoryAvatar extends StatelessWidget {
  const CategoryAvatar({
    super.key,
    required this.icon,
    required this.color,
    this.filled = false,
    this.radius = 20,
  });

  final IconData icon;
  final Color color;

  /// Залитый круг с белой иконкой (выбранная категория).
  final bool filled;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: filled ? color : color.withValues(alpha: 0.15),
      foregroundColor: filled ? Colors.white : color,
      child: Icon(icon, size: radius * 1.1),
    );
  }
}
