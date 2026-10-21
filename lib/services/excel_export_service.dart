import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt.dart';
import 'annual_report.dart';

/// 年間収支報告書を Excel(.xlsx) で書き出す
///
/// シート構成:
/// - 「収支報告書」: 月日・摘要・収入・支出・収支・残高・備考（添付サンプルと同じ並び）
/// - 「参加者名簿」: 名簿がある場合のみ
/// 小計・合計・残高・1人あたりは数式で計算するため、Excel 側で修正しても再計算されます。
class ExcelExportService {
  static final _dateFmt = DateFormat('yyyy/MM/dd');

  static const _headerRow = 4; // 0始まり: 見出し行
  static const _headers = ['月日', '摘要', '収入', '支出', '収支', '残高', '備考'];

  /// 収支報告書のExcelバイト列を生成（共有は行わない）
  static List<int> buildWorkbook({
    required String title,
    required List<Receipt> entries,
    required DateTime from,
    required DateTime to,
    required int participants,
    List<String> participantNames = const [],
    int carryCash = 0,
    int carryBank = 0,
  }) {
    final report = AnnualReport.build(
      entries,
      carryCash: carryCash,
      carryBank: carryBank,
    );
    final excel = Excel.createExcel();
    final sheet = excel['収支報告書'];
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

    void put(int col, int row, CellValue value, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = value;
      if (style != null) cell.cellStyle = style;
    }

    void formula(int col, int row, String f, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = FormulaCellValue(f);
      if (style != null) cell.cellStyle = style;
    }

    // 0始まりの行・列を「C7」のような表記に変換
    String ref(int col, int row) => '${'ABCDEFG'[col]}${row + 1}';

    // ---------- 見出し ----------
    put(0, 0, TextCellValue(title), style: titleStyle);
    put(
      0,
      1,
      TextCellValue(
        '対象期間: ${_dateFmt.format(from)} 〜 ${_dateFmt.format(to)}',
      ),
    );
    put(0, 2, TextCellValue('作成日: ${_dateFmt.format(DateTime.now())}'));

    for (var c = 0; c < _headers.length; c++) {
      put(c, _headerRow, TextCellValue(_headers[c]), style: header);
    }

    // ---------- 繰越金・明細 ----------
    final firstRow = _headerRow + 1;
    final dataFirst = firstRow + report.carryRows.length;
    var row = firstRow;
    for (final r in report.rows) {
      if (r.date != null) {
        put(0, row, TextCellValue(_dateFmt.format(r.date!)));
      }
      put(1, row, TextCellValue(r.summary));
      if (r.isCarry || r.income > 0) {
        put(2, row, IntCellValue(r.income), style: money);
      }
      if (r.expense > 0) {
        put(3, row, IntCellValue(r.expense), style: money);
      }
      formula(4, row, '${ref(2, row)}-${ref(3, row)}', style: money);
      formula(
        5,
        row,
        row == firstRow
            ? ref(4, row)
            : '${ref(5, row - 1)}+${ref(4, row)}',
        style: money,
      );
      if (r.note.isNotEmpty) put(6, row, TextCellValue(r.note));
      row++;
    }

    // ---------- 小計 ----------
    final subRow = row;
    put(1, subRow, TextCellValue('小計'), style: bold);
    if (report.dataRows.isEmpty) {
      put(2, subRow, IntCellValue(0), style: money);
      put(3, subRow, IntCellValue(0), style: money);
    } else {
      final last = subRow; // 小計直前の行 = 明細の最終行（1始まりの表記はref側で補正）
      formula(
        2,
        subRow,
        'SUM(${ref(2, dataFirst)}:${ref(2, last - 1)})',
        style: moneyBold,
      );
      formula(
        3,
        subRow,
        'SUM(${ref(3, dataFirst)}:${ref(3, last - 1)})',
        style: moneyBold,
      );
    }
    formula(4, subRow, '${ref(2, subRow)}-${ref(3, subRow)}', style: moneyBold);

    // ---------- 合計 ----------
    final totalRow = subRow + 1;
    put(1, totalRow, TextCellValue('合計（前年繰越金＋小計）'), style: bold);
    formula(
      2,
      totalRow,
      '${ref(2, firstRow)}+${ref(2, firstRow + 1)}+${ref(2, subRow)}',
      style: moneyBold,
    );
    formula(3, totalRow, ref(3, subRow), style: moneyBold);
    formula(
      4,
      totalRow,
      '${ref(2, totalRow)}-${ref(3, totalRow)}',
      style: moneyBold,
    );
    formula(5, totalRow, ref(5, subRow - 1), style: moneyBold);

    // ---------- 参加人数・1人あたり ----------
    final partRow = totalRow + 2;
    put(1, partRow, TextCellValue('参加人数（名）'));
    put(2, partRow, IntCellValue(participants), style: money);
    if (participants > 0) {
      put(1, partRow + 1, TextCellValue('1人あたり支出（円）'));
      formula(
        2,
        partRow + 1,
        'ROUNDDOWN(${ref(3, totalRow)}/${ref(2, partRow)},0)',
        style: money,
      );
    }

    // ---------- 報告者・監査 ----------
    final signRow = partRow + 3;
    put(5, signRow, TextCellValue('報告者'));
    put(5, signRow + 2, TextCellValue('監査'));

    sheet.setColumnWidth(0, 12);
    sheet.setColumnWidth(1, 26);
    for (var c = 2; c <= 5; c++) {
      sheet.setColumnWidth(c, 14);
    }
    sheet.setColumnWidth(6, 30);

    // ---------- 参加者名簿（名簿がある場合のみ） ----------
    if (participantNames.isNotEmpty) {
      final rosterSheet = excel['参加者名簿'];
      rosterSheet.appendRow(['No.', '氏名'].map(TextCellValue.new).toList());
      for (var c = 0; c < 2; c++) {
        rosterSheet
                .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
                .cellStyle =
            header;
      }
      for (var i = 0; i < participantNames.length; i++) {
        rosterSheet.appendRow([
          IntCellValue(i + 1),
          TextCellValue(participantNames[i]),
        ]);
      }
      rosterSheet.setColumnWidth(0, 8);
      rosterSheet.setColumnWidth(1, 24);
    }

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
    required int participants,
    List<String> participantNames = const [],
    int carryCash = 0,
    int carryBank = 0,
  }) async {
    final bytes = buildWorkbook(
      title: title,
      entries: entries,
      from: from,
      to: to,
      participants: participants,
      participantNames: participantNames,
      carryCash: carryCash,
      carryBank: carryBank,
    );
    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: '収支報告書_$safeTitle.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: '収支報告書 $title',
      ),
    );
  }
}
