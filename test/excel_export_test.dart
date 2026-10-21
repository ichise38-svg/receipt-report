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
    expect(book.tables.keys, containsAll(['サマリー', '明細']));
    expect(book.tables.keys, isNot(contains('Sheet1')));

    final detail = book.tables['明細']!;
    expect(detail.maxRows, 3); // ヘッダ + 2件
    expect(detail.rows[1][1]?.value.toString(), '支出');
    expect(detail.rows[2][1]?.value.toString(), '収入');

    final summary = book.tables['サマリー']!;
    final formulas = summary.rows
        .expand((r) => r)
        .whereType<Data>()
        .where((c) => c.value is FormulaCellValue)
        .map((c) => (c.value as FormulaCellValue).formula)
        .toList();
    expect(formulas.any((f) => f.contains('SUMIFS')), isTrue);
    expect(formulas.any((f) => f.contains('B7-B6') || f.contains('-')), isTrue);
  });
}
