import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/event_excel_service.dart';
import 'package:receipt_report/services/excel_export_service.dart';

void main() {
  test('年間Excelの4行目にファイル名とシート名が出る', () {
    final bytes = ExcelExportService.buildWorkbook(
      mainTitle: '関桜会　収支報告書',
      title: '経費精算',
      entries: [
        Receipt(
          storeName: '駅',
          amount: 1000,
          date: DateTime(2025, 4, 1),
          category: '交通費',
        ),
      ],
      from: DateTime(2025, 4, 1),
      to: DateTime(2025, 4, 30),
      participants: 1,
    );
    final sheet = Excel.decodeBytes(bytes)['収支報告書'];
    final text = sheet.cell(CellIndex.indexByString('A4')).value.toString();
    expect(text, contains('収支報告書_経費精算.xlsx'));
    expect(text, contains('シート: 収支報告書'));
  });

  test('イベントExcelの4行目にファイル名とシート名が出る', () {
    final bytes = EventExcelService.buildWorkbook(
      mainTitle: '関桜会　収支報告書',
      eventName: '25忘年会',
      entries: [
        Receipt(
          storeName: '居酒屋',
          amount: 5000,
          date: DateTime(2025, 12, 1),
          category: '会費',
          event: '25忘年会',
        ),
      ],
      participants: 1,
    );
    final sheet = Excel.decodeBytes(bytes)['会計報告書'];
    final text = sheet.cell(CellIndex.indexByString('A4')).value.toString();
    expect(text, contains('会計報告書_25忘年会.xlsx'));
    expect(text, contains('シート: 会計報告書'));
  });
}
