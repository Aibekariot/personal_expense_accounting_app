import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// ВЫСОТА НИЖНЕЙ ПАНЕЛИ НАД КРАЕМ ЭКРАНА — меняйте это число.
///
/// Больше число — выше нижняя панель. Вместе с ней поднимаются клавиатура
/// калькулятора, кнопка «Сохранить» и нижние меню. Единица — логические
/// пиксели (те же, что во всех размерах Flutter). 0 — вплотную к краю.
const bottomGap = 28.0;

/// Добавляет отступ снизу. В браузере Flutter считает отступы экрана нулевыми
/// и не знает про системную зону (полоску жестов iPhone), поэтому её размер
/// [safeInset] передаётся отдельно. SafeArea и нижняя панель учтут его сами.
MediaQueryData withBottomGap(MediaQueryData data, double safeInset) {
  // Открыта экранная клавиатура — край экрана закрыт, отступ не нужен.
  if (data.viewInsets.bottom > 0) return data;
  final bottom = math.max(data.padding.bottom, safeInset) + bottomGap;
  return data.copyWith(
    padding: data.padding.copyWith(bottom: bottom),
    viewPadding: data.viewPadding.copyWith(bottom: bottom),
  );
}
