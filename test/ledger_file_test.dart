import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/ledger_file_service.dart';

/// テスト用：年間集計の形式（見出し 月日・摘要・収入・支出・収支・残高・備考）のExcelを作る
Uint8List _annualSample(List<List<Object?>> rows, {String sheet = '2025年集計'}) {
  final excel = Excel.createExcel();
  final s = excel[sheet];
  excel.delete('Sheet1');
  s.cell(CellIndex.indexByString('A1')).value = TextCellValue(
    '2025年　関桜会　収支報告書',
  );
  const headers = ['月日', '摘要', '収入', '支出', '収支', '残高', '備考'];
  for (var c = 0; c < headers.length; c++) {
    s.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2)).value =
        TextCellValue(headers[c]);
  }
  for (var r = 0; r < rows.length; r++) {
    for (var c = 0; c < rows[r].length; c++) {
      final v = rows[r][c];
      if (v == null) continue;
      final cell = s.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 3),
      );
      if (v is int) {
        cell.value = IntCellValue(v);
      } else {
        cell.value = TextCellValue(v as String);
      }
    }
  }
  return Uint8List.fromList(excel.encode()!);
}

void main() {
  test('年間集計の収入・支出を取り込み、繰越行は除外する', () {
    final bytes = _annualSample([
      [null, '前年度繰越金（現金）', 146353, null, null, null, null],
      [45666, '月例集会分', null, 5427, null, null, null],
      [46052, '1月分集金', 114000, null, null, null, null],
      [45689, '新年会', 33000, 114000, null, null, '備考あり'],
    ]);
    final p = LedgerFileService.parseAnnual(bytes, const []);
    expect(p.sheetName, '2025年集計');
    expect(p.carrySkipped, 1);
    // 収入: 1月分集金 / 新年会の収入 ・ 支出: 月例集会分 / 新年会の支出
    expect(p.toAdd.length, 4);
    expect(p.incomeCount, 2);
    expect(p.expenseCount, 2);
    expect(p.incomeTotal, 147000);
    expect(p.expenseTotal, 119427);
    final kai = p.toAdd.firstWhere((r) => r.storeName == '新年会' && r.isIncome);
    expect(kai.memo, '備考あり');
  });

  test('既存データと同じ内容は重複として無視する', () {
    final bytes = _annualSample([
      [45666, '月例集会分', null, 5427],
    ]);
    final existing = [
      Receipt(
        kind: EntryKind.expense,
        storeName: '月例集会分',
        date: DateTime(2025, 1, 9),
        amount: 5427,
        category: '雑費',
      ),
    ];
    final first = LedgerFileService.parseAnnual(bytes, existing);
    expect(first.toAdd, isEmpty);
    expect(first.duplicateCount, 1);
  });

  test('同じ取り込みを2回しても件数が増えない（既存を反映した場合）', () {
    final bytes = _annualSample([
      [46052, '1月分集金', 114000, null],
    ]);
    final first = LedgerFileService.parseAnnual(bytes, const []);
    expect(first.toAdd.length, 1);
    final second = LedgerFileService.parseAnnual(bytes, first.toAdd);
    expect(second.toAdd, isEmpty);
    expect(second.duplicateCount, 1);
  });

  test('日付が「11/8～9」のような文字列は推定とし、備考に元の表記を残す', () {
    final bytes = _annualSample([
      ['11/8～9', '関桜会旅行', 75000, 1067291],
    ]);
    final p = LedgerFileService.parseAnnual(bytes, const []);
    expect(p.needsCheckCount, 2);
    expect(p.toAdd.every((r) => r.memo.contains('日付要確認')), isTrue);
    expect(p.toAdd.every((r) => r.date.year == 2025), isTrue);
  });

  test('小計以降の行は取り込まない', () {
    final bytes = _annualSample([
      [46052, '1月分集金', 114000, null],
      [null, '2025年　小計', 114000, 0],
      [46053, '2月分集金', 114000, null],
    ]);
    final p = LedgerFileService.parseAnnual(bytes, const []);
    expect(p.toAdd.length, 1);
    expect(p.toAdd.single.storeName, '1月分集金');
  });

  test('見出しのないファイルはエラーにする', () {
    final excel = Excel.createExcel();
    excel['Sheet1'].cell(CellIndex.indexByString('A1')).value = TextCellValue(
      '関係ない表',
    );
    final bytes = Uint8List.fromList(excel.encode()!);
    expect(
      () => LedgerFileService.parseAnnual(bytes, const []),
      throwsA(isA<FormatException>()),
    );
  });

  test('テンプレートを作り直して取り込める（往復）', () {
    final template = LedgerFileService.buildTemplateBytes(year: 2026);
    expect(template.isNotEmpty, isTrue);
    final excel = Excel.decodeBytes(Uint8List.fromList(template));
    expect(excel.tables.keys, contains(LedgerFileService.templateSheetName));
    final sheet = excel[LedgerFileService.templateSheetName];
    // 繰越金の入力欄（C4・C5）は0を入れてあり、明細の入力欄（A7以降）は空
    expect(sheet.cell(CellIndex.indexByString('A7')).value, isNull);
    expect(sheet.cell(CellIndex.indexByString('C7')).value, isNull);
  });

  test('年間様式のテンプレートは、見出し・繰越・小計・署名欄を含む', () {
    final template = LedgerFileService.buildTemplateBytes(year: 2026);
    final excel = Excel.decodeBytes(Uint8List.fromList(template));
    final sheet = excel[LedgerFileService.templateSheetName];
    String t(int c, int r) {
      final v = sheet
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
          .value;
      return v is TextCellValue ? v.value.toString() : '';
    }
    expect(t(0, 3), '月日');
    expect(t(1, 3), '摘要');
    expect(t(2, 3), '収入');
    expect(t(3, 3), '支出');
    expect(t(1, 4), '前年度繰越金（現金）');
    expect(t(1, 5), '前年度繰越金（口座等）');
    expect(
      sheet.rows
          .expand((row) => row)
          .any((c) => c != null && c.value.toString().contains('報告者')),
      isTrue,
    );
  });

  test('年間様式のテンプレートに入力すると、既存の取り込みで読み込める', () {
    final template = LedgerFileService.buildTemplateBytes(year: 2026);
    final excel = Excel.decodeBytes(Uint8List.fromList(template));
    final sheet = excel[LedgerFileService.templateSheetName];
    void put(int c, int r, CellValue v) => sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r))
        .value = v;
    put(0, 6, TextCellValue('1/10'));
    put(1, 6, TextCellValue('1月分集金'));
    put(2, 6, IntCellValue(114000));
    put(0, 7, TextCellValue('1/12'));
    put(1, 7, TextCellValue('新年会'));
    put(3, 7, IntCellValue(33000));
    final preview = LedgerFileService.parseAnnual(
      Uint8List.fromList(excel.encode()!),
      const [],
    );
    expect(preview.toAdd.length, 2);
    expect(preview.incomeTotal, 114000);
    expect(preview.expenseTotal, 33000);
  });
}
