import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/ledger_summary.dart';

void main() {
  test('収入・支出・残高を正しく集計する', () {
    final entries = [
      Receipt(
        storeName: 'A',
        date: DateTime(2025, 1, 1),
        amount: 1000,
        category: '食費',
      ),
      Receipt(
        storeName: 'B',
        date: DateTime(2025, 1, 2),
        amount: 500,
        category: '交通費',
      ),
      Receipt(
        kind: EntryKind.income,
        storeName: '売上',
        date: DateTime(2025, 1, 3),
        amount: 3000,
        category: '売上',
      ),
    ];
    final s = LedgerSummary.from(entries);
    expect(s.income, 3000);
    expect(s.expense, 1500);
    expect(s.balance, 1500);
    expect(s.count, 3);
    expect(s.expenseByCategory['食費'], 1000);
    expect(s.incomeByCategory['売上'], 3000);
  });

  test('旧データ（kind未設定）は支出として読み込む', () {
    final r = Receipt.fromJson({
      'id': 'x',
      'imagePath': '/tmp/a.jpg',
      'storeName': 'old',
      'date': '2024-05-01T00:00:00.000',
      'amount': 800,
      'category': '食費',
      'memo': '',
      'createdAt': '2024-05-01T00:00:00.000',
    });
    expect(r.kind, EntryKind.expense);
    expect(r.isIncome, false);
    expect(r.amount, 800);
  });
}
