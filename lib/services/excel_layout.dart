import '../models/receipt.dart';
import 'annual_report.dart';
import 'event_excel_service.dart';
import 'event_report.dart';

/// 「A〜G」の列名（0始まりの列番号から）
String excelColumnName(int col) => 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[col];

/// Excelの1セル分（ExcelExportService.buildWorkbook と同じ位置）
class LayoutCell {
  final int col; // 0始まり
  final int row; // 0始まり
  final String text; // 文字・日付の場合の表示値
  final int? amount; // 金額（数式の結果を含む）
  final String? formula; // 数式（例: =C6-D6）。表示用
  final bool header; // 見出しセル（ビューワーで強調表示）
  final String? role; // この列・この行の意味（説明パネル用）
  const LayoutCell({
    required this.col,
    required this.row,
    this.text = '',
    this.amount,
    this.formula,
    this.header = false,
    this.role,
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
    final result = <LayoutRow>[
      LayoutRow(
        row: headerRow,
        kind: 'header',
        label: '見出し',
        cells: [
          for (var c = 0; c < headers.length; c++)
            LayoutCell(col: c, row: headerRow, text: headers[c], header: true),
        ],
      ),
    ];
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
          formula: row == firstRow ? '=E${row + 1}' : '=F$row+E${row + 1}',
        ),
        if (r.note.isNotEmpty) LayoutCell(col: 6, row: row, text: r.note),
      ];
      result.add(
        LayoutRow(
          row: row,
          kind: isCarry ? 'carry' : 'entry',
          label: isCarry ? '前年度繰越金' : '明細 $entryNo件目',
          receipt: receipt,
          cells: cells,
        ),
      );
      row++;
    }

    // ---- 小計（明細のみ） ----
    final subRow = row;
    final lastData = subRow - 1; // 0始まり
    final subIncome = report.subtotalIncome;
    final subExpense = report.subtotalExpense;
    final hasData = report.dataRows.isNotEmpty;
    result.add(
      LayoutRow(
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
      ),
    );

    // ---- 合計（繰越金＋小計） ----
    final totalRow = subRow + 1;
    final totalIncome = report.totalIncome;
    final totalExpense = report.totalExpense;
    result.add(
      LayoutRow(
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
      ),
    );

    // ---- 参加人数・1人あたり ----
    final partRow = totalRow + 2;
    final perPerson = participants > 0 ? totalExpense ~/ participants : null;
    result.add(
      LayoutRow(
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
      ),
    );
    return result;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}

/// イベント別会計報告書の行・セル割り当て（EventExcelService.buildWorkbook と一致させる）
///
/// 行は明細数で変わるため、0始まりの行番号を都度計算します。
class EventLayout {
  static const _startRow = 4; // 5行目から「※収入の部」

  static List<LayoutRow> build({
    required List<Receipt> entries,
    required String eventName,
    required int participants,
    required String mainTitle,
  }) {
    final report = EventReport.build(entries, eventName);
    final rows = <LayoutRow>[];
    var row = 0;

    // ---- 見出し（1〜4行目）：ExcelExportService と同じ位置 ----
    rows.add(
      LayoutRow(
        row: 0,
        kind: 'title',
        label: 'メインタイトル',
        cells: [
          LayoutCell(
            col: 0,
            row: 0,
            text: mainTitle,
            header: true,
            role: 'A1：メインタイトル（左上）',
          ),
        ],
      ),
    );
    rows.add(
      LayoutRow(
        row: 1,
        kind: 'title',
        label: 'イベント名のタイトル',
        cells: [
          LayoutCell(
            col: 0,
            row: 1,
            text: '${report.eventName}　会計報告書',
            role: 'A2：イベント名のタイトル',
          ),
        ],
      ),
    );
    if (report.firstDate != null) {
      final period = report.firstDate == report.lastDate
          ? _fmtDate(report.firstDate!)
          : '${_fmtDate(report.firstDate!)} 〜 ${_fmtDate(report.lastDate!)}';
      rows.add(
        LayoutRow(
          row: 2,
          kind: 'title',
          label: '期間',
          cells: [
            LayoutCell(
              col: 0,
              row: 2,
              text: '期間: $period',
              role: 'A3：対象期間（明細の日付から自動）',
            ),
          ],
        ),
      );
    }
    rows.add(
      LayoutRow(
        row: 3,
        kind: 'title',
        label: 'ファイル情報',
        cells: [
          LayoutCell(
            col: 0,
            row: 3,
            text:
                'ファイル: ${EventExcelService.fileNameFor(eventName)} ／ シート: 会計報告書',
            role: 'A4：ファイル名とシート名',
          ),
        ],
      ),
    );
    row = _startRow;

    void add(
      String kind,
      String label,
      List<LayoutCell> cells, {
      Receipt? receipt,
    }) {
      rows.add(
        LayoutRow(
          row: row,
          kind: kind,
          label: label,
          receipt: receipt,
          cells: cells,
        ),
      );
    }

    LayoutCell t(int col, String text, {bool header = false, String? role}) =>
        LayoutCell(col: col, row: row, text: text, header: header, role: role);
    LayoutCell n(int col, int amount, {String? formula, String? role}) =>
        LayoutCell(
          col: col,
          row: row,
          amount: amount,
          formula: formula,
          role: role,
        );

    // ---- 収入の部 ----
    add('section', '収入の部', [t(0, '※収入の部', header: true)]);
    row++;
    add('header', '見出し', [
      t(0, '項目', header: true),
      t(1, '金額（円）', header: true),
    ]);
    row++;
    final incomeFirst = row;
    for (final l in report.incomeLines) {
      add('income', '収入 ${l.label}', [
        t(0, l.label, role: 'A列「項目」（収入の種類）'),
        n(1, l.amount, role: 'B列「金額（円）」'),
      ]);
      row++;
    }
    if (report.incomeLines.isEmpty) {
      add('income', '収入なし', [t(0, '（収入なし）')]);
      row++;
    }
    final incomeLast = row - 1;
    final incomeSumRow = row;
    add('incomeSum', '収入合計', [
      t(0, '収入合計'),
      n(
        1,
        report.incomeTotal,
        formula: report.incomeLines.isEmpty
            ? null
            : '=SUM(B${incomeFirst + 1}:B${incomeLast + 1})',
        role: 'B列「金額」＝収入の項目を合計',
      ),
    ]);
    row += 2;

    // ---- 支出の部 ----
    add('section', '支出の部', [t(0, '※支出の部', header: true)]);
    row++;
    add('header', '見出し', [
      for (var c = 0; c < 4; c++)
        t(c, const ['日付', '店舗・摘要', '内容', '金額（円）'][c], header: true),
    ]);
    row++;
    final expenseFirst = row;
    final expenseEntries = report.entries.where((r) => !r.isIncome).toList();
    for (var i = 0; i < expenseEntries.length; i++) {
      final r = expenseEntries[i];
      add('entry', '支出 ${i + 1}件目', [
        t(0, _fmtDate(r.date), role: 'A列「日付」'),
        t(1, r.storeName, role: 'B列「店舗・摘要」'),
        t(
          2,
          [r.category, if (r.memo.isNotEmpty) r.memo].join('／'),
          role: 'C列「内容」（カテゴリ／メモ）',
        ),
        n(3, r.amount, role: 'D列「金額（円）」'),
      ], receipt: r);
      row++;
    }
    if (expenseEntries.isEmpty) {
      add('entry', '支出なし', [t(1, '（支出なし）')]);
      row++;
    }
    final expenseLast = row - 1;
    final expenseSumRow = row;
    add('expenseSum', '支出合計', [
      t(1, '支出合計'),
      n(
        3,
        report.expenseTotal,
        formula: expenseEntries.isEmpty
            ? null
            : '=SUM(D${expenseFirst + 1}:D${expenseLast + 1})',
        role: 'D列「金額」＝支出の明細を合計',
      ),
    ]);
    row += 2;

    // ---- 総計 ----
    final incomeTotalRow = row;
    add('total', '収入総計', [
      t(0, '収入総計'),
      n(
        1,
        report.incomeTotal,
        formula: '=B${incomeSumRow + 1}',
        role: 'B列＝収入合計を転記',
      ),
    ]);
    row++;
    final expenseTotalRow = row;
    add('total', '支出総計', [
      t(0, '支出総計'),
      n(
        1,
        report.expenseTotal,
        formula: '=D${expenseSumRow + 1}',
        role: 'B列＝支出合計を転記',
      ),
    ]);
    row++;
    add('total', '差引金額', [
      t(0, '差引金額（一般会計より支出）'),
      n(
        1,
        report.balance,
        formula: '=B${incomeTotalRow + 1}-B${expenseTotalRow + 1}',
        role: 'B列＝収入総計−支出総計',
      ),
    ]);
    row += 2;

    // ---- 参加者 ----
    add('participants', '参加者（名）', [
      t(0, '参加者（名）'),
      n(1, participants, role: 'B列＝登録されている参加者数'),
    ]);

    return rows;
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
}
