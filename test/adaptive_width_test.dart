import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/widgets/adaptive_width_frame.dart';

void main() {
  Future<double> widthOf(WidgetTester tester, double screenWidth) async {
    tester.view.physicalSize = Size(screenWidth, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveWidthFrame(
          child: Container(key: const Key('body'), color: Colors.red),
        ),
      ),
    );
    return tester.getSize(find.byKey(const Key('body'))).width;
  }

  testWidgets('タブレット幅では本文を720pxに制限する', (tester) async {
    expect(await widthOf(tester, 1280), 720);
  });

  testWidgets('スマホ幅では全幅のまま', (tester) async {
    expect(await widthOf(tester, 390), 390);
  });
}
