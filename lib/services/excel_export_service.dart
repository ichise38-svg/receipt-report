import 'dart:io';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt.dart';

/// 収支報告書を Excel(.xlsx) で書き出す
/// シート構成: 「サマリー」（カテゴリ別集計・収支残高）/「明細」（全件一覧）
/// 合計は数式で計算するため、Excel 側で明細を修正しても再計算される。
class ExcelExportService {
  static final _dateFmt = DateFormat('yyyy/MM/dd');

  /// 収支報告書のExcelバイト列を生成（共有は行わない）
  static List<int> buildWorkbook({
    required String title,
    required List<Receipt> entries,
    required DateTime from,
    required DateTime to,
  }) {
    final sorted = [...entries]..sort((a, b) => a.date.compareTo(b.date));
    final excel = Excel.createExcel();
    final summarySheet = excel['サマリー'];
    final detailSheet = excel['明細'];
    excel.delete('Sheet1');

    final bold = CellStyle(bold: true);
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
    final titleStyle = CellStyle(bold: true, fontSize: 16);

    // ---------- 明細シート ----------
    final detailHeaders = ['日付', '区分', '取引先・店舗', 'カテゴリ', '金額（円）', 'メモ'];
    detailSheet.appendRow(detailHeaders.map(TextCellValue.new).toList());
    for (var c = 0; c < detailHeaders.length; c++) {
      detailSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
              .cellStyle =
          header;
    }
    for (final e in sorted) {
      detailSheet.appendRow([
        TextCellValue(_dateFmt.format(e.date)),
        TextCellValue(e.kind.label),
        TextCellValue(e.storeName),
        TextCellValue(e.category),
        IntCellValue(e.amount),
        TextCellValue(e.memo),
      ]);
    }
    final lastDetailRow = sorted.length; // 0始まりのヘッダ行を除いた末尾行(1始まり)
    for (var r = 1; r <= lastDetailRow; r++) {
      detailSheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: r))
              .cellStyle =
          money;
    }
    detailSheet.setColumnWidth(0, 12);
    detailSheet.setColumnWidth(1, 8);
    detailSheet.setColumnWidth(2, 24);
    detailSheet.setColumnWidth(3, 12);
    detailSheet.setColumnWidth(4, 14);
    detailSheet.setColumnWidth(5, 30);

    // 明細の金額範囲（数式用）
    final amountRange = sorted.isEmpty ? null : 'E2:E${lastDetailRow + 1}';
    final kindRange = sorted.isEmpty ? null : 'B2:B${lastDetailRow + 1}';
    final catRange = sorted.isEmpty ? null : 'D2:D${lastDetailRow + 1}';

    // ---------- サマリーシート ----------
    void put(int col, int row, CellValue value, {CellStyle? style}) {
      summarySheet
              .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
              .value =
          value;
      if (style != null) {
        summarySheet
                .cell(
                  CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
                )
                .cellStyle =
            style;
      }
    }

    void putFormula(int col, int row, String formula, {CellStyle? style}) {
      summarySheet
          .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
          .value = FormulaCellValue(
        formula,
      );
      if (style != null) {
        summarySheet
                .cell(
                  CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
                )
                .cellStyle =
            style;
      }
    }

    put(0, 0, TextCellValue('会計報告書（収支）'), style: titleStyle);
    put(0, 1, TextCellValue(title));
    put(
      0,
      2,
      TextCellValue('対象期間: ${_dateFmt.format(from)} 〜 ${_dateFmt.format(to)}'),
    );
    put(0, 3, TextCellValue('作成日: ${_dateFmt.format(DateTime.now())}'));

    // 収支サマリー
    int row = 5;
    put(0, row, TextCellValue('項目'), style: header);
    put(1, row, TextCellValue('金額（円）'), style: header);
    row++;
    final incomeRow = row + 1;
    put(0, row, TextCellValue('収入合計'));
    putFormula(
      1,
      row,
      amountRange == null ? '0' : 'SUMIFS($amountRange,$kindRange,"収入")',
      style: money,
    );
    row++;
    final expenseRow = row + 1;
    put(0, row, TextCellValue('支出合計'));
    putFormula(
      1,
      row,
      amountRange == null ? '0' : 'SUMIFS($amountRange,$kindRange,"支出")',
      style: money,
    );
    row++;
    put(0, row, TextCellValue('差引残高（収入－支出）'), style: bold);
    putFormula(1, row, 'B$incomeRow-B$expenseRow', style: moneyBold);
    row += 2;

    // 支出カテゴリ別
    row = _writeCategoryTable(
      summarySheet: summarySheet,
      put: put,
      putFormula: putFormula,
      startRow: row,
      title: '支出（カテゴリ別）',
      categories: receiptCategories,
      kindLabel: '支出',
      catRange: catRange,
      kindRange: kindRange,
      amountRange: amountRange,
      header: header,
      money: money,
      moneyBold: moneyBold,
      hasData: sorted.isNotEmpty,
    );
    row += 1;

    // 収入カテゴリ別
    row = _writeCategoryTable(
      summarySheet: summarySheet,
      put: put,
      putFormula: putFormula,
      startRow: row,
      title: '収入（カテゴリ別）',
      categories: incomeCategories,
      kindLabel: '収入',
      catRange: catRange,
      kindRange: kindRange,
      amountRange: amountRange,
      header: header,
      money: money,
      moneyBold: moneyBold,
      hasData: sorted.isNotEmpty,
    );

    summarySheet.setColumnWidth(0, 26);
    summarySheet.setColumnWidth(1, 16);

    final bytes = excel.encode();
    if (bytes == null) {
      throw Exception('Excelの作成に失敗しました');
    }
    return bytes;
  }

  static Future<void> shareLedger({
    required String title,
    required List<Receipt> entries,
    required DateTime from,
    required DateTime to,
  }) async {
    final bytes = buildWorkbook(
      title: title,
      entries: entries,
      from: from,
      to: to,
    );
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, '収支報告書_$safeTitle.xlsx'));
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile(
            file.path,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: '収支報告書 $title',
      ),
    );
  }

  static int _writeCategoryTable({
    required Sheet summarySheet,
    required void Function(int, int, CellValue, {CellStyle? style}) put,
    required void Function(int, int, String, {CellStyle? style}) putFormula,
    required int startRow,
    required String title,
    required List<String> categories,
    required String kindLabel,
    required String? catRange,
    required String? kindRange,
    required String? amountRange,
    required CellStyle header,
    required CellStyle money,
    required CellStyle moneyBold,
    required bool hasData,
  }) {
    var row = startRow;
    put(0, row, TextCellValue(title), style: header);
    put(1, row, TextCellValue('金額（円）'), style: header);
    row++;
    final firstRow = row + 1;
    for (final cat in categories) {
      put(0, row, TextCellValue(cat));
      if (hasData && amountRange != null) {
        putFormula(
          1,
          row,
          'SUMIFS($amountRange,$kindRange,"$kindLabel",$catRange,"$cat")',
          style: money,
        );
      } else {
        put(1, row, const IntCellValue(0), style: money);
      }
      row++;
    }
    final lastRow = row - 1;
    put(0, row, TextCellValue('合計'), style: header);
    putFormula(1, row, 'SUM(B$firstRow:B$lastRow)', style: moneyBold);
    return row + 1;
  }
}
