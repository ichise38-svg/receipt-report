import 'package:excel/excel.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import 'event_report.dart';
import 'xlsx_save.dart';

/// イベント別会計報告書を Excel(.xlsx) で書き出す
///
/// 1シート構成。小計・差引は数式で計算します。
class EventExcelService {
  static final _dateFmt = DateFormat('yyyy/MM/dd');

  /// 共有・表示で使うファイル名（例: 会計報告書_25忘年会.xlsx）
  static String fileNameFor(String eventName) {
    final safe = eventName.trim().replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    return '会計報告書_$safe.xlsx';
  }

  static List<int> buildWorkbook({
    required String mainTitle,
    required String eventName,
    required List<Receipt> entries,
    required int participants,
    List<String> participantNames = const [],
  }) {
    final report = EventReport.build(entries, eventName);
    const sheetName = '会計報告書';
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];
    excel.delete('Sheet1');

    final bold = CellStyle(bold: true);
    final title = CellStyle(bold: true, fontSize: 16);
    final small = CellStyle(fontSize: 9);
    final header = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('FFE3F2FD'),
      horizontalAlign: HorizontalAlign.Center,
    );
    final money = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      numberFormat: NumFormat.standard_3,
    );
    final moneyBold = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Right,
      numberFormat: NumFormat.standard_3,
    );

    void text(int col, int row, String v, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = TextCellValue(v);
      if (style != null) cell.cellStyle = style;
    }

    void num(int col, int row, int v, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = IntCellValue(v);
      if (style != null) cell.cellStyle = style;
    }

    void formula(int col, int row, String f, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = FormulaCellValue(f);
      if (style != null) cell.cellStyle = style;
    }

    String ref(int col, int row) => '${'ABCDEFG'[col]}${row + 1}';

    // ---------- 見出し ----------
    // 左上：メインのタイトル、その下にイベント名のタイトル
    text(0, 0, mainTitle, style: title);
    text(0, 1, '${report.eventName}　会計報告書', style: bold);
    if (report.firstDate != null) {
      final period = report.firstDate == report.lastDate
          ? _dateFmt.format(report.firstDate!)
          : '${_dateFmt.format(report.firstDate!)} 〜 ${_dateFmt.format(report.lastDate!)}';
      text(0, 2, '期間: $period');
    }

    // 4行目：いま開いているファイル名とシート名
    text(
      0,
      3,
      'ファイル: ${fileNameFor(eventName)} ／ シート: $sheetName',
      style: small,
    );

    // ---------- 収入の部 ----------
    var row = 4;
    text(0, row, '※収入の部', style: bold);
    row++;
    text(0, row, '項目', style: header);
    text(1, row, '金額（円）', style: header);
    row++;
    final incomeFirst = row;
    for (final l in report.incomeLines) {
      text(0, row, l.label);
      num(1, row, l.amount, style: money);
      row++;
    }
    if (report.incomeLines.isEmpty) {
      text(0, row, '（収入なし）');
      row++;
    }
    final incomeLast = row - 1;
    final incomeSumRow = row;
    text(0, incomeSumRow, '収入合計', style: bold);
    if (report.incomeLines.isEmpty) {
      num(1, incomeSumRow, 0, style: moneyBold);
    } else {
      formula(
        1,
        incomeSumRow,
        'SUM(${ref(1, incomeFirst)}:${ref(1, incomeLast)})',
        style: moneyBold,
      );
    }
    row += 2;

    // ---------- 支出の部 ----------
    text(0, row, '※支出の部', style: bold);
    row++;
    for (var c = 0; c < 4; c++) {
      text(c, row, ['日付', '店舗・摘要', '内容', '金額（円）'][c], style: header);
    }
    row++;
    final expenseFirst = row;
    for (final r in report.entries.where((r) => !r.isIncome)) {
      text(0, row, _dateFmt.format(r.date));
      text(1, row, r.storeName);
      text(2, row, [r.category, if (r.memo.isNotEmpty) r.memo].join('／'));
      num(3, row, r.amount, style: money);
      row++;
    }
    if (report.expenseLines.isEmpty) {
      text(1, row, '（支出なし）');
      row++;
    }
    final expenseLast = row - 1;
    final expenseSumRow = row;
    text(1, expenseSumRow, '支出合計', style: bold);
    if (report.expenseLines.isEmpty) {
      num(3, expenseSumRow, 0, style: moneyBold);
    } else {
      formula(
        3,
        expenseSumRow,
        'SUM(${ref(3, expenseFirst)}:${ref(3, expenseLast)})',
        style: moneyBold,
      );
    }
    row += 2;

    // ---------- 総計 ----------
    text(0, row, '収入総計');
    formula(1, row, ref(1, incomeSumRow), style: money);
    final incomeTotalRow = row;
    row++;
    text(0, row, '支出総計');
    formula(1, row, ref(3, expenseSumRow), style: money);
    final expenseTotalRow = row;
    row++;
    text(0, row, '差引金額（一般会計より支出）', style: bold);
    formula(
      1,
      row,
      '${ref(1, incomeTotalRow)}-${ref(1, expenseTotalRow)}',
      style: moneyBold,
    );
    row += 2;

    text(0, row, '出席者（名）');
    num(1, row, participants, style: money);
    row += 1;
    if (participantNames.isNotEmpty) {
      text(0, row, '参加者名簿');
      row++;
      for (var i = 0; i < participantNames.length; i++) {
        text(0, row, '${i + 1}');
        text(1, row, participantNames[i]);
        row++;
      }
    }
    row += 1;
    text(0, row, '上記の通り報告します');
    row += 2;
    text(2, row, '報告者');

    sheet.setColumnWidth(0, 22);
    sheet.setColumnWidth(1, 26);
    sheet.setColumnWidth(2, 26);
    sheet.setColumnWidth(3, 16);

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Excelの作成に失敗しました');
    }
    return bytes;
  }

  static Future<void> shareWorkbook({
    required String mainTitle,
    required String eventName,
    required List<Receipt> entries,
    required int participants,
    List<String> participantNames = const [],
  }) async {
    final bytes = buildWorkbook(
      mainTitle: mainTitle,
      eventName: eventName,
      entries: entries,
      participants: participants,
      participantNames: participantNames,
    );
    await saveXlsxBytes(
      bytes: bytes,
      fileName: fileNameFor(eventName),
      dialogTitle: '保存先を選んでください（OneDriveなどのクラウドも選べます）',
    );
  }
}
