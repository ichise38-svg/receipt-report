import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/excel_export_service.dart';
import 'package:receipt_report/services/excel_layout.dart';

void main() {
  final entries = [
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
  ];

  test('ビューワーの行番号・金額が実際のExcelと一致する', () {
    final rows = AnnualLayout.build(
      entries: entries,
      carryCash: 1000,
      carryBank: 2000,
      participants: 2,
    );
    final bytes = ExcelExportService.buildWorkbook(
      mainTitle: 'T',
      title: 'テスト',
      entries: entries,
      from: DateTime(2025, 1, 1),
      to: DateTime(2025, 1, 31),
      participants: 2,
      carryCash: 1000,
      carryBank: 2000,
    );
    final sheet = Excel.decodeBytes(bytes).tables['収支報告書']!;

    // 明細1件目（支出300）は行 index 7（繰越2行の後）
    final firstEntry = rows.firstWhere((r) => r.receipt?.storeName == '駅');
    expect(firstEntry.row, 7);
    final expenseCell = firstEntry.cells.firstWhere((c) => c.col == 3);
    expect(expenseCell.address, 'D8');
    expect(sheet.rows[7][3]?.value.toString(), '300');
    expect(sheet.rows[7][1]?.value.toString(), '駅');

    // 繰越金（現金）は C6
    final carry = rows.firstWhere((r) => r.kind == 'carry');
    expect(carry.cells.firstWhere((c) => c.col == 2).address, 'C6');
    expect(sheet.rows[5][2]?.value.toString(), '1000');

    // 小計・合計の金額
    final subtotal = rows.firstWhere((r) => r.kind == 'subtotal');
    expect(subtotal.cells.firstWhere((c) => c.col == 2).amount, 5000);
    final total = rows.firstWhere((r) => r.kind == 'total');
    expect(total.cells.firstWhere((c) => c.col == 2).amount, 8000);
    expect(total.cells.firstWhere((c) => c.col == 3).amount, 300);

    // 1人あたり = 300 ÷ 2 = 150
    final per = rows.firstWhere((r) => r.kind == 'participants');
    expect(per.cells.last.amount, 150);
  });

  test('列名はA〜G', () {
    expect(excelColumnName(0), 'A');
    expect(excelColumnName(6), 'G');
  });
}
