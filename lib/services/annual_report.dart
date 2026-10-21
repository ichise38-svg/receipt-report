import '../models/receipt.dart';

/// 年間収支報告書の1行（繰越金の行、または明細の行）
class AnnualReportRow {
  final DateTime? date; // 繰越行は null
  final String summary; // 摘要
  final int income; // 収入
  final int expense; // 支出
  final String note; // 備考
  final bool isCarry; // 前年度繰越金の行か

  const AnnualReportRow({
    this.date,
    required this.summary,
    this.income = 0,
    this.expense = 0,
    this.note = '',
    this.isCarry = false,
  });
}

/// 年間収支報告書の集計（PDF・Excel で共通利用）
///
/// 並び: 前年度繰越金（現金）→ 前年度繰越金（口座等）→ 明細（日付順）
/// 小計は明細のみ、合計は「繰越金＋小計」で求めます。
class AnnualReport {
  final int carryCash;
  final int carryBank;
  final List<AnnualReportRow> carryRows;
  final List<AnnualReportRow> dataRows;

  AnnualReport._({
    required this.carryCash,
    required this.carryBank,
    required this.carryRows,
    required this.dataRows,
  });

  factory AnnualReport.build(
    List<Receipt> entries, {
    int carryCash = 0,
    int carryBank = 0,
  }) {
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final data = sorted
        .map(
          (r) => AnnualReportRow(
            date: r.date,
            summary: r.storeName,
            income: r.isIncome ? r.amount : 0,
            expense: r.isIncome ? 0 : r.amount,
            note: r.memo.isEmpty ? r.category : '${r.category}／${r.memo}',
          ),
        )
        .toList();
    return AnnualReport._(
      carryCash: carryCash,
      carryBank: carryBank,
      carryRows: [
        AnnualReportRow(
          summary: '前年度繰越金（現金）',
          income: carryCash,
          isCarry: true,
        ),
        AnnualReportRow(
          summary: '前年度繰越金（口座等）',
          income: carryBank,
          isCarry: true,
        ),
      ],
      dataRows: data,
    );
  }

  /// 表示順の全行（繰越 ＋ 明細）
  List<AnnualReportRow> get rows => [...carryRows, ...dataRows];

  int get subtotalIncome => dataRows.fold(0, (s, r) => s + r.income);
  int get subtotalExpense => dataRows.fold(0, (s, r) => s + r.expense);

  int get totalIncome => carryCash + carryBank + subtotalIncome;
  int get totalExpense => subtotalExpense;

  /// 差引残高（次年度へ繰り越す額）
  int get balance => totalIncome - totalExpense;

  /// 各行の残高（先頭行から順に加算）
  List<int> get runningBalances {
    var bal = 0;
    return rows.map((r) {
      bal += r.income - r.expense;
      return bal;
    }).toList();
  }
}
