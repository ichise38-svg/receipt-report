import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/annual_report.dart';
import 'package:receipt_report/services/excel_layout.dart';

void main() {
  final entries = [
    Receipt(
      storeName: '去年',
      date: DateTime(2025, 12, 31),
      amount: 100,
      category: '交通費',
    ),
    Receipt(
      storeName: '今年初日',
      date: DateTime(2026, 1, 1),
      amount: 300,
      category: '交通費',
    ),
    Receipt(
      kind: EntryKind.income,
      storeName: '今年末日',
      date: DateTime(2026, 12, 31, 18),
      amount: 5000,
      category: '売上',
    ),
    Receipt(
      storeName: '翌年',
      date: DateTime(2027, 1, 1),
      amount: 700,
      category: '交通費',
    ),
  ];

  test('1/1〜12/31 の明細だけが集計される', () {
    final report = AnnualReport.build(
      entries,
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 12, 31),
    );
    expect(report.dataRows.length, 2);
    expect(report.subtotalExpense, 300);
    expect(report.subtotalIncome, 5000);
  });

  test('ビューワーのレイアウトも同じ期間で計算される', () {
    final rows = AnnualLayout.build(
      entries: entries,
      carryCash: 0,
      carryBank: 0,
      participants: 1,
      from: DateTime(2026, 1, 1),
      to: DateTime(2026, 12, 31),
    );
    final entryRows = rows.where((r) => r.kind == 'entry').length;
    expect(entryRows, 2);
  });
}
