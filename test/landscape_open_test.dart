import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/screens/excel_viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('作業パネルで横向きになると全画面のExcel画面が開く', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExcelViewerScreen(embedded: true),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('全画面で見る'), findsOneWidget);

    // 縦から横向きに回転（幅 > 高さ）
    tester.view.physicalSize = const Size(800, 400);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Excelビューワー'), findsOneWidget,
        reason: '全画面（別画面）が開いていない');
  });
}
