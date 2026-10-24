import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/bank_entry.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/bank_reconcile.dart';

void main() {
  final day = DateTime(2025, 7, 10);

  test('合計の残高 = 繰越（現金＋口座等）＋ 口座の入金・出金 ± 現金の増減', () {
    final bal = BankReconcile.balances(
      carryCash: 100000,
      carryBank: 200000,
      bankEntries: [
        BankEntry(
          id: 'd',
          date: day,
          kind: BankEntryKind.deposit,
          label: '入金',
          amount: 50000,
        ),
        BankEntry(
          id: 'w',
          date: day,
          kind: BankEntryKind.withdraw,
          label: '出金',
          amount: 30000,
        ),
        BankEntry(
          id: 'c',
          date: day,
          kind: BankEntryKind.cashOut,
          label: '現金引出',
          amount: 20000,
        ),
      ],
      receipts: [
        Receipt(
          id: 'r1',
          storeName: '現金払い',
          date: day,
          amount: 5000,
          category: '雑費',
          payment: PaymentMethod.cash,
        ),
      ],
    );
    // 口座: 200000 + 50000 - 30000 - 20000 = 200000
    expect(bal.bank, 200000);
    // 現金: 100000 + 20000（引出） - 5000（現金払い） = 115000
    expect(bal.cashOnHand, 115000);
    expect(bal.bank + bal.cashOnHand, 315000);
  });
}
