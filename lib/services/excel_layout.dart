import '../models/receipt.dart';
import 'annual_report.dart';

/// 「A〜G」の列名（0始まりの列番号から）
String excelColumnName(int col) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[col];

/// Excelの1セル分（ExcelExportService.buildWorkbook と同じ位置）
class LayoutCell {
  final int col; // 0始まり
  final int row; // 0始まり
  final String text; // 文字・日付の場合の表示値
  final int? amount; // 金額（数式の結果を含む）
  final String? formula; // 数式（例: =C6-D6）。表示用
  const LayoutCell({
    required this.col,
    required this.row,
    this.text = '',
    this.amount,
    this.formula,
  });

  /// 「C6」のようなセル番地（1始まりの行番号）
  String get address => '${excelColumnName(col)}${row + 1}';

  bool get isFormula => formula != null;
}

/// 画面の1行（Excelの1行に対応）
class LayoutRow {
  final int row; // 0始まり
  final String kind; // carry / entry / subtotal / total / participants
  final String label; // 行の説明
  final Receipt? receipt; // 明細行のみ
  final List<LayoutCell> cells;
  const LayoutRow({
    required this.row,
    required this.kind,
    required this.label,
    this.receipt,
    required this.cells,
  });
}

/// 年間収支報告書の行・セル割り当て（ExcelExportService.buildWorkbook と一致させる）
///
/// 見出しは4行目（index 4）、明細は5行目（index 5）から始まります。
class AnnualLayout {
  static const headerRow = 4;
  static const headers = ['月日', '摘要', '収入', '支出', '収支', '残高', '備考'];

  static List<LayoutRow> build({
    required List<Receipt> entries,
    required int carryCash,
    required int carryBank,
    required int participants,
  }) {
    final report = AnnualReport.build(
      entries,
      carryCash: carryCash,
      carryBank: carryBank,
    );
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final result = <LayoutRow>[];
    final firstRow = headerRow + 1;
    final dataFirst = firstRow + report.carryRows.length;
    var row = firstRow;
    var balance = 0;
    var entryNo = 0;

    // ---- 繰越行 ＋ 明細行 ----
    for (final r in report.rows) {
      final isCarry = r.isCarry;
      final receipt = isCarry ? null : sorted[entryNo++];
      balance += r.income - r.expense;
      final cells = <LayoutCell>[
        if (r.date != null)
          LayoutCell(col: 0, row: row, text: _fmtDate(r.date!)),
        LayoutCell(col: 1, row: row, text: r.summary),
        if (r.isCarry || r.income > 0)
          LayoutCell(col: 2, row: row, amount: r.income),
        if (r.expense > 0) LayoutCell(col: 3, row: row, amount: r.expense),
        LayoutCell(
          col: 4,
          row: row,
          amount: r.income - r.expense,
          formula: '=C${row + 1}-D${row + 1}',
        ),
        LayoutCell(
          col: 5,
          row: row,
          amount: balance,
          formula: row == firstRow
              ? '=E${row + 1}'
              : '=F$row+E${row + 1}',
        ),
        if (r.note.isNotEmpty) LayoutCell(col: 6, row: row, text: r.note),
      ];
      result.add(LayoutRow(
        row: row,
        kind: isCarry ? 'carry' : 'entry',
        label: isCarry ? '前年度繰越金' : '明細 $entryNo件目',
        receipt: receipt,
        cells: cells,
      ));
      row++;
    }

    // ---- 小計（明細のみ） ----
    final subRow = row;
    final lastData = subRow - 1; // 0始まり
    final subIncome = report.subtotalIncome;
    final subExpense = report.subtotalExpense;
    final hasData = report.dataRows.isNotEmpty;
    result.add(LayoutRow(
      row: subRow,
      kind: 'subtotal',
      label: '小計（明細のみ）',
      cells: [
        LayoutCell(col: 1, row: subRow, text: '小計'),
        LayoutCell(
          col: 2,
          row: subRow,
          amount: subIncome,
          formula: hasData
              ? '=SUM(C${dataFirst + 1}:C${lastData + 1})'
              : null,
        ),
        LayoutCell(
          col: 3,
          row: subRow,
          amount: subExpense,
          formula: hasData
              ? '=SUM(D${dataFirst + 1}:D${lastData + 1})'
              : null,
        ),
        LayoutCell(
          col: 4,
          row: subRow,
          amount: subIncome - subExpense,
          formula: '=C${subRow + 1}-D${subRow + 1}',
        ),
      ],
    ));

    // ---- 合計（繰越金＋小計） ----
    final totalRow = subRow + 1;
    final totalIncome = report.totalIncome;
    final totalExpense = report.totalExpense;
    result.add(LayoutRow(
      row: totalRow,
      kind: 'total',
      label: '合計（繰越金＋小計）',
      cells: [
        LayoutCell(col: 1, row: totalRow, text: '合計（前年繰越金＋小計）'),
        LayoutCell(
          col: 2,
          row: totalRow,
          amount: totalIncome,
          formula: '=C${firstRow + 1}+C${firstRow + 2}+C${subRow + 1}',
        ),
        LayoutCell(
          col: 3,
          row: totalRow,
          amount: totalExpense,
          formula: '=D${subRow + 1}',
        ),
        LayoutCell(
          col: 4,
          row: totalRow,
          amount: report.balance,
          formula: '=C${totalRow + 1}-D${totalRow + 1}',
        ),
        LayoutCell(
          col: 5,
          row: totalRow,
          amount: balance,
          formula: '=F$subRow',
        ),
      ],
    ));

    // ---- 参加人数・1人あたり ----
    final partRow = totalRow + 2;
    final perPerson = participants > 0 ? totalExpense ~/ participants : null;
    result.add(LayoutRow(
      row: partRow,
      kind: 'participants',
      label: '参加人数・1人あたり',
      cells: [
        LayoutCell(col: 1, row: partRow, text: '参加人数（名）'),
        LayoutCell(col: 2, row: partRow, amount: participants),
        LayoutCell(col: 1, row: partRow + 1, text: '1人あたり支出（円）'),
        if (perPerson != null)
          LayoutCell(
            col: 2,
            row: partRow + 1,
            amount: perPerson,
            formula: '=ROUNDDOWN(D${totalRow + 1}/C${partRow + 1},0)',
          ),
      ],
    ));
    return result;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
