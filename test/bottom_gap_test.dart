import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_expense_accounting/app/bottom_gap.dart';

void main() {
  test('без системной зоны — только наш отступ', () {
    final d = withBottomGap(const MediaQueryData(), 0);
    expect(d.padding.bottom, bottomGap);
    expect(d.viewPadding.bottom, bottomGap);
  });

  test('отступ прибавляется к системной зоне', () {
    expect(withBottomGap(const MediaQueryData(), 34).padding.bottom, 34 + bottomGap);
    const native = MediaQueryData(padding: EdgeInsets.only(bottom: 48));
    expect(withBottomGap(native, 0).padding.bottom, 48 + bottomGap);
  });

  test('при открытой клавиатуре отступ не добавляется', () {
    const open = MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300));
    expect(withBottomGap(open, 34).padding.bottom, 0);
  });

  test('остальные отступы не меняются', () {
    const top = MediaQueryData(padding: EdgeInsets.only(top: 24));
    expect(withBottomGap(top, 0).padding.top, 24);
  });
}
