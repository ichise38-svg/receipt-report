import '../models/receipt.dart';

/// 収支の集計（画面・PDF・Excelで共通利用）
class LedgerSummary {
  final int income;
  final int expense;
  final Map<String, int> incomeByCategory;
  final Map<String, int> expenseByCategory;
  final int count;

  /// 参加人数（名簿の人数）。0 の場合は1人あたり計算をしない
  final int participants;

  LedgerSummary._({
    required this.income,
    required this.expense,
    required this.incomeByCategory,
    required this.expenseByCategory,
    required this.count,
    required this.participants,
  });

  /// 差引残高（収入 - 支出）
  int get balance => income - expense;

  /// 1人あたりの支出（小数点以下切り捨て）。参加人数が0なら null
  int? get expensePerPerson =>
      participants > 0 ? expense ~/ participants : null;

  /// 1人あたりの収入（小数点以下切り捨て）。参加人数が0なら null
  int? get incomePerPerson =>
      participants > 0 ? income ~/ participants : null;

  factory LedgerSummary.from(List<Receipt> entries, {int participants = 0}) {
    int income = 0;
    int expense = 0;
    final incomeCat = <String, int>{};
    final expenseCat = <String, int>{};
    for (final e in entries) {
      if (e.isIncome) {
        income += e.amount;
        incomeCat[e.category] = (incomeCat[e.category] ?? 0) + e.amount;
      } else {
        expense += e.amount;
        expenseCat[e.category] = (expenseCat[e.category] ?? 0) + e.amount;
      }
    }
    return LedgerSummary._(
      income: income,
      expense: expense,
      incomeByCategory: incomeCat,
      expenseByCategory: expenseCat,
      count: entries.length,
      participants: participants,
    );
  }
}
