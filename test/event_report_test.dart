import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/event_report.dart';

void main() {
  final entries = [
    Receipt(
      kind: EntryKind.income,
      storeName: '会費',
      date: DateTime(2025, 12, 21),
      amount: 48000,
      category: '入金',
      event: '25忘年会',
    ),
    Receipt(
      kind: EntryKind.income,
      storeName: '補助',
      date: DateTime(2025, 12, 1),
      amount: 5000,
      category: '入金',
      event: ' 25忘年会 ',
    ),
    Receipt(
      storeName: '居酒屋',
      date: DateTime(2025, 12, 21),
      amount: 40000,
      category: '食費',
      event: '25忘年会',
    ),
    Receipt(
      storeName: '別イベント',
      date: DateTime(2025, 11, 1),
      amount: 9999,
      category: '交際費',
      event: '25旅行',
    ),
    Receipt(
      storeName: '削除済み',
      date: DateTime(2025, 12, 21),
      amount: 1000,
      category: '食費',
      event: '25忘年会',
      deleted: true,
    ),
  ];

  test('イベント名で絞り込み、収入は項目ごとに合算する', () {
    final r = EventReport.build(entries, '25忘年会');
    expect(r.entries.length, 3);
    expect(r.incomeLines.length, 1);
    expect(r.incomeLines.first.label, '入金');
    expect(r.incomeLines.first.amount, 53000);
  });

  test('支出は1件1行、収入合計・支出合計・差引を計算する', () {
    final r = EventReport.build(entries, '25忘年会');
    expect(r.expenseLines.length, 1);
    expect(r.expenseTotal, 40000);
    expect(r.incomeTotal, 53000);
    expect(r.balance, 13000);
  });

  test('削除済み・別イベントは含まない', () {
    final r = EventReport.build(entries, '25旅行');
    expect(r.entries.length, 1);
    expect(r.expenseTotal, 9999);
    expect(EventReport.build(entries, '存在しない').isEmpty, isTrue);
  });
}
