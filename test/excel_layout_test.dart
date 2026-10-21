import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/event_excel_service.dart';
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

  test('イベント別：行番号・金額・数式の位置が実際のExcelと一致する', () {
    final evEntries = [
      Receipt(
        kind: EntryKind.income,
        storeName: '会費',
        date: DateTime(2025, 12, 1),
        amount: 3000,
        category: '会費',
        event: '25忘年会',
      ),
      Receipt(
        storeName: '居酒屋',
        date: DateTime(2025, 12, 5),
        amount: 12000,
        category: '飲食',
        event: '25忘年会',
      ),
      Receipt(
        storeName: '花屋',
        date: DateTime(2025, 12, 6),
        amount: 800,
        category: '備品',
        memo: '飾り',
        event: '25忘年会',
      ),
    ];
    final rows = EventLayout.build(
      entries: evEntries,
      eventName: '25忘年会',
      participants: 4,
      mainTitle: 'T',
    );
    final bytes = EventExcelService.buildWorkbook(
      mainTitle: 'T',
      eventName: '25忘年会',
      entries: evEntries,
      participants: 4,
    );
    final sheet = Excel.decodeBytes(bytes).tables['会計報告書']!;

    LayoutCell cellAt(String kind, int col) => rows
        .firstWhere((r) => r.kind == kind)
        .cells
        .firstWhere((c) => c.col == col);

    // 収入（会費）はB列に金額。見出しの次の行
    final incomeLine = rows.firstWhere((r) => r.label == '収入 会費');
    expect(incomeLine.cells.firstWhere((c) => c.col == 1).address, 'B7');
    expect(sheet.rows[incomeLine.row][1]?.value.toString(), '3000');

    // 支出の明細は日付・摘要・内容・金額（D列）
    final izakaya = rows.firstWhere((r) => r.receipt?.storeName == '居酒屋');
    final amountCell = izakaya.cells.firstWhere((c) => c.col == 3);
    expect(amountCell.address, startsWith('D'));
    expect(sheet.rows[izakaya.row][3]?.value.toString(), '12000');
    expect(sheet.rows[izakaya.row][1]?.value.toString(), '居酒屋');

    // 合計と差引（収入3000 − 支出12800 = −9800）
    expect(cellAt('incomeSum', 1).amount, 3000);
    expect(cellAt('expenseSum', 3).amount, 12800);
    expect(cellAt('total', 1).amount, 3000);
    final balance = rows.where((r) => r.kind == 'total').last;
    expect(balance.cells.firstWhere((c) => c.col == 1).amount, -9800);

    // 数式のセル番地が実際のシートの数式と一致する
    final expenseSum = rows.firstWhere((r) => r.kind == 'expenseSum');
    final formulaText = expenseSum.cells.firstWhere((c) => c.col == 3).formula;
    expect(formulaText, startsWith('=SUM(D'));
    expect(sheet.rows[expenseSum.row][3]?.value.toString(), contains('SUM'));

    // タイトル行（A1・A2）
    expect(rows.firstWhere((r) => r.row == 0).cells.first.text, 'T');
    expect(rows.firstWhere((r) => r.row == 1).cells.first.text, '25忘年会　会計報告書');
  });
}
