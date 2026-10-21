import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/bank_entry.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/bank_reconcile.dart';

Receipt _bankExp(String id, DateTime d, int amount, {String name = '店'}) =>
    Receipt(
      id: id,
      storeName: name,
      date: d,
      amount: amount,
      category: '雑費',
      payment: PaymentMethod.bank,
    );

BankEntry _out(String id, DateTime d, int amount, {String label = 'カード出金'}) =>
    BankEntry(
      id: id,
      date: d,
      kind: BankEntryKind.withdraw,
      label: label,
      amount: amount,
    );

void main() {
  final day = DateTime(2025, 7, 10);

  test('同じ日付・金額は一致になる', () {
    final lines = BankReconcile.reconcile(
      receipts: [_bankExp('a', day, 5000)],
      bankEntries: [_out('b', day, 5000)],
    );
    expect(lines.single.status, ReconcileStatus.matched);
  });

  test('同じ日付で金額が違う場合は金額違い', () {
    final lines = BankReconcile.reconcile(
      receipts: [_bankExp('a', day, 5000)],
      bankEntries: [_out('b', day, 4800)],
    );
    expect(lines.single.status, ReconcileStatus.amountMismatch);
    expect(lines.single.difference, 200);
  });

  test('口座の出納がない明細は出納の入力漏れとして表示', () {
    final lines = BankReconcile.reconcile(
      receipts: [_bankExp('a', day, 5000)],
      bankEntries: const [],
    );
    expect(lines.single.status, ReconcileStatus.missingInBank);
  });

  test('対応する明細がない出金は表示', () {
    final lines = BankReconcile.reconcile(
      receipts: const [],
      bankEntries: [_out('b', day, 3000, label: '1月集金分')],
    );
    expect(lines.single.status, ReconcileStatus.missingInLedger);
  });

  test('現金払い・収入・削除済みは照合の対象外', () {
    final lines = BankReconcile.reconcile(
      receipts: [
        Receipt(
          id: 'cash',
          storeName: '現金',
          date: day,
          amount: 1000,
          category: '雑費',
        ),
        Receipt(
          id: 'inc',
          kind: EntryKind.income,
          storeName: '集金',
          date: day,
          amount: 2000,
          category: '売上',
          payment: PaymentMethod.bank,
        ),
        Receipt(
          id: 'del',
          storeName: '削除',
          date: day,
          amount: 3000,
          category: '雑費',
          payment: PaymentMethod.bank,
          deleted: true,
        ),
      ],
      bankEntries: const [],
    );
    expect(lines, isEmpty);
  });

  test('現金引出は照合の対象外（口座残高と現金にだけ影響）', () {
    final lines = BankReconcile.reconcile(
      receipts: const [],
      bankEntries: [
        BankEntry(
          id: 'c',
          date: day,
          kind: BankEntryKind.cashOut,
          label: 'カード出金',
          amount: 50000,
        ),
      ],
    );
    expect(lines, isEmpty);
  });

  test('同じ日・同じ金額が2件ずつあっても両方一致になる', () {
    final lines = BankReconcile.reconcile(
      receipts: [_bankExp('a', day, 1000), _bankExp('b', day, 1000)],
      bankEntries: [_out('x', day, 1000), _out('y', day, 1000)],
    );
    expect(lines.where((l) => l.status == ReconcileStatus.matched).length, 2);
  });

  test('期間外の明細は除外される', () {
    final lines = BankReconcile.reconcile(
      receipts: [_bankExp('a', DateTime(2024, 12, 31), 5000)],
      bankEntries: const [],
      from: DateTime(2025, 1, 1),
      to: DateTime(2025, 12, 31),
    );
    expect(lines, isEmpty);
  });

  test('残高: 口座は入金・出金・現金引出で増減、現金は現金引出と現金払いで増減', () {
    final bal = BankReconcile.balances(
      carryCash: 100000,
      carryBank: 300000,
      bankEntries: [
        BankEntry(
          id: '1',
          date: day,
          kind: BankEntryKind.deposit,
          label: '集金',
          amount: 114000,
        ),
        BankEntry(
          id: '2',
          date: day,
          kind: BankEntryKind.cashOut,
          label: 'カード出金',
          amount: 50000,
        ),
        _out('3', day, 20000),
      ],
      receipts: [
        Receipt(
          id: 'c1',
          storeName: '現金払い',
          date: day,
          amount: 3000,
          category: '雑費',
        ),
        _bankExp('b1', day, 7000),
      ],
    );
    // 口座: 300000 + 114000 - 50000 - 20000 = 344000（口座払いの明細は出納側で反映）
    expect(bal.bank, 344000);
    // 現金: 100000 + 50000 - 3000 = 147000
    expect(bal.cashOnHand, 147000);
  });

  test('支払方法の既定は現金・既存JSONは現金扱い', () {
    final r = Receipt.fromJson({
      'id': 'old',
      'storeName': '旧データ',
      'date': DateTime(2025, 1, 1).toIso8601String(),
      'amount': 100,
      'category': '雑費',
    });
    expect(r.payment, PaymentMethod.cash);
    final round = Receipt.fromJson(
      _bankExp('new', day, 1).copyWith(payment: PaymentMethod.bank).toJson(),
    );
    expect(round.payment, PaymentMethod.bank);
  });
}
