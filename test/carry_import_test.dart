import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/services/ledger_file_service.dart';

Uint8List _book(List<List<Object?>> rows, {String year = '2025年'}) {
  final excel = Excel.createExcel();
  final s = excel['2025年集計 (最終版)'];
  excel.delete('Sheet1');
  s.cell(CellIndex.indexByString('A1')).value = TextCellValue(
    '$year　関桜会　収支報告書',
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
  test('繰越金（C列）を読み取り、収入・支出と分けて保持する', () {
    final bytes = _book([
      [null, '前年度繰越金（現金）', 146353, null, null, null, null],
      [null, '前年度繰越金（口座等）', 308650, null, null, null, null],
      [45666, '月例集会分', null, 5427, null, null, null],
      [46052, '1月分集金', 114000, null, null, null, null],
    ]);
    final p = LedgerFileService.parseAnnual(bytes, const []);
    expect(p.hasCarry, isTrue);
    expect(p.carryCash, 146353);
    expect(p.carryBank, 308650);
    expect(p.carryReason, isNull);
    expect(p.toAdd.length, 2);
    expect(p.carrySkipped, 2);
  });

  test('繰越金が空欄なら読めない理由を返し、金額は更新対象にしない', () {
    final bytes = _book([
      [null, '前年度繰越金（現金）', null, null, null, null, null],
      [null, '前年度繰越金（口座等）', 308650, null, null, null, null],
      [45666, '月例集会分', null, 5427, null, null, null],
    ]);
    final p = LedgerFileService.parseAnnual(bytes, const []);
    expect(p.hasCarry, isFalse);
    expect(p.carryReason, contains('現金の繰越'));
    expect(p.carryReason, contains('空欄'));
  });

  test('年が表の年と違う明細は取り込み、年要確認を付ける', () {
    final bytes = _book([
      [null, '前年度繰越金（現金）', 1, null, null, null, null],
      [null, '前年度繰越金（口座等）', 2, null, null, null, null],
      [46052, '1月分集金', 114000, null, null, null, null],
    ]);
    final p = LedgerFileService.parseAnnual(bytes, const []);
    // 46052 = 2026-01-30 → 表の年 2025 と違う
    expect(p.yearMismatchCount, 1);
    expect(p.toAdd.single.memo, contains('年要確認'));
  });

  test('サンプルの2025年集計: 繰越金と明細の合計が一致する', () {
    final file = File('/home/user/uploaded_files/2025関桜会会計報告サンプル.xlsx');
    if (!file.existsSync()) {
      markTestSkipped('サンプルファイルなし');
      return;
    }
    final p = LedgerFileService.parseAnnual(
      Uint8List.fromList(file.readAsBytesSync()),
      const [],
    );
    expect(p.carryCash, 146353);
    expect(p.carryBank, 308650);
    expect(p.incomeTotal, 1744000);
    expect(p.expenseTotal, 1935538);
    expect(p.yearMismatchCount, 6);
  });
}
