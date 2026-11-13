import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/bank_entry.dart';
import 'package:receipt_report/services/excel_layout.dart';

void main() {
  test('口座出納は前年繰越から入金＋・出金−で残高を計算する', () {
    final rows = BankLayout.build(
      startRow: 10,
      carryBank: 100000,
      entries: [
        BankEntry(
          date: DateTime(2025, 2, 1),
          kind: BankEntryKind.withdraw,
          label: '振込',
          amount: 30000,
        ),
        BankEntry(
          date: DateTime(2025, 1, 5),
          kind: BankEntryKind.deposit,
          label: '1月集金',
          amount: 50000,
        ),
        BankEntry(
          date: DateTime(2025, 3, 1),
          kind: BankEntryKind.cashOut,
          label: 'カード出金',
          amount: 20000,
        ),
      ],
    );
    // 日付順に並ぶ（1/5 入金, 2/1 出金, 3/1 現金引出）
    final entries = rows.where((r) => r.kind == 'bankEntry').toList();
    expect(entries.length, 3);
    final first = entries[0];
    final last = entries[2];
    expect(first.cells.firstWhere((c) => c.col == 2).amount, 50000);
    expect(first.cells.firstWhere((c) => c.col == 5).amount, 150000);
    expect(entries[1].cells.firstWhere((c) => c.col == 5).amount, 120000);
    expect(last.cells.firstWhere((c) => c.col == 5).amount, 100000);
    // 残高の最終値は口座残高の行と一致
    final balance = rows.firstWhere((r) => r.kind == 'bankBalance');
    expect(balance.cells.firstWhere((c) => c.col == 5).amount, 100000);
    // 入金・出金・現金引出の欄
    expect(
      entries[1].cells.any((c) => c.col == 3 && c.amount == 30000),
      isTrue,
    );
    expect(last.cells.any((c) => c.col == 6 && c.text == '現金引出'), isTrue);
  });

  test('出納がなくても繰越と残高の行は出る', () {
    final rows = BankLayout.build(
      startRow: 0,
      carryBank: 5000,
      entries: const [],
    );
    expect(rows.any((r) => r.kind == 'bankEntry'), isFalse);
    final balance = rows.firstWhere((r) => r.kind == 'bankBalance');
    expect(balance.cells.firstWhere((c) => c.col == 5).amount, 5000);
  });
}
