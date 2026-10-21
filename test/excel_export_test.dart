import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/excel_export_service.dart';

void main() {
  test('収支Excelに数式・明細・サマリーが含まれる', () {
    final bytes = ExcelExportService.buildWorkbook(
      title: 'テスト',
      entries: [
        Receipt(
          storeName: '駅',
          date: DateTime(2025, 1, 1),
          amount: 300,
          category: '交通費',
        ),
        Receipt(
          kind: EntryKind.income,
          storeName: '売上',
          date: DateTime(2025, 1, 2),
          amount: 5000,
          category: '売上',
        ),
      ],
      from: DateTime(2025, 1, 1),
      to: DateTime(2025, 1, 31),
      participants: 4,
      participantNames: ['山田', '佐藤', '鈴木', '田中'],
    );
    final book = Excel.decodeBytes(bytes);
    expect(book.tables.keys, contains('収支報告書'));
    expect(book.tables.keys, isNot(contains('Sheet1')));

    final sheet = book.tables['収支報告書']!;
    // 見出し行（5行目）
    expect(sheet.rows[4][0]?.value.toString(), '月日');
    // 繰越2行 + 明細2件 の後に小計・合計が続く
    final formulas = sheet.rows
        .expand((r) => r)
        .whereType<Data>()
        .where((c) => c.value is FormulaCellValue)
        .map((c) => (c.value as FormulaCellValue).formula)
        .toList();
    expect(formulas.any((f) => f.startsWith('SUM(')), isTrue);
    expect(formulas.any((f) => f.startsWith('ROUNDDOWN(')), isTrue);
  });
}
