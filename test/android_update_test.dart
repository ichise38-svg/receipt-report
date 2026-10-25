import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/services/update_checker.dart';

void main() {
  test('版番号が同じでも、ビルド番号が新しければ更新あり', () {
    expect(UpdateChecker.compareFull('1.0.4', 7, '1.0.4', 6), greaterThan(0));
  });

  test('同じ版・同じビルドなら更新なし、古ければ負', () {
    expect(UpdateChecker.compareFull('1.0.4', 6, '1.0.4', 6), 0);
    expect(UpdateChecker.compareFull('1.0.4', 5, '1.0.4', 6), lessThan(0));
  });

  test('版番号が新しければビルド番号に関係なく更新あり', () {
    expect(UpdateChecker.compareFull('1.0.5', 1, '1.0.4', 9), greaterThan(0));
  });

  test('currentFull は「1.0.7 (13)」の形式（+は表示しない）', () {
    expect(
      UpdateChecker.currentFull,
      '${UpdateChecker.currentVersion} (${UpdateChecker.currentBuild})',
    );
    expect(UpdateChecker.currentFull.contains('+'), isFalse);
  });
}
