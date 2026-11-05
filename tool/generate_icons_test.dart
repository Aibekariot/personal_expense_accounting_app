// Генератор иконок приложения (web/icons, web/favicon.png).
// Запуск: flutter test tool/generate_icons_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

const _background = Color(0xFF00897B);
const _bar = Color(0xFFFFFFFF);
const _accent = Color(0xFFFFD54F);

/// Иконка: три растущих столбика на бирюзовом фоне.
/// [scale] < 1 — для «маскируемых» иконок Android (рисунок в безопасной зоне).
void _paint(Canvas c, double s, double scale) {
  c.drawRect(Rect.fromLTWH(0, 0, s, s), Paint()..color = _background);
  c.save();
  c.translate(s / 2, s / 2);
  c.scale(scale);
  c.translate(-s / 2, -s / 2);
  final w = s * 0.14;
  final gap = s * 0.065;
  final base = s * 0.72;
  final x0 = s / 2 - (3 * w + 2 * gap) / 2;
  const heights = [0.22, 0.36, 0.50];
  for (var i = 0; i < 3; i++) {
    final h = s * heights[i];
    c.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(x0 + i * (w + gap), base - h, w, h),
        topLeft: Radius.circular(w * 0.3),
        topRight: Radius.circular(w * 0.3),
      ),
      Paint()..color = i == 2 ? _accent : _bar,
    );
  }
  c.drawRRect(
    RRect.fromRectAndRadius(
      Rect.fromLTWH(x0 - s * 0.05, base + s * 0.035, 3 * w + 2 * gap + s * 0.10, s * 0.04),
      Radius.circular(s * 0.02),
    ),
    Paint()..color = _bar,
  );
  c.restore();
}

Future<void> _render(int size, String path, {double scale = 1}) async {
  final recorder = ui.PictureRecorder();
  _paint(Canvas(recorder), size.toDouble(), scale);
  final image = await recorder.endRecording().toImage(size, size);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  test('иконки', () async {
    await _render(192, 'web/icons/Icon-192.png');
    await _render(512, 'web/icons/Icon-512.png');
    await _render(192, 'web/icons/Icon-maskable-192.png', scale: 0.8);
    await _render(512, 'web/icons/Icon-maskable-512.png', scale: 0.8);
    await _render(180, 'web/icons/apple-touch-icon.png');
    await _render(32, 'web/favicon.png');
  });
}
