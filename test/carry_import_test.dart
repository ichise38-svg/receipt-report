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
  eventTests();
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

void _addSheet(Excel excel, String name, List<List<Object?>> cells) {
  final s = excel[name];
  for (var r = 0; r < cells.length; r++) {
    for (var c = 0; c < cells[r].length; c++) {
      final v = cells[r][c];
      if (v == null) continue;
      final cell = s.cell(
        CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r),
      );
      if (v is int) {
        cell.value = IntCellValue(v);
      } else {
        cell.value = TextCellValue(v as String);
      }
    }
  }
}

/// 行事別シート（I10 収入総計・I11 支出総計、J列に明細）を作る。行は 1 始まり。
List<List<Object?>> _eventSheet({
  required String date,
  required int income,
  required int expense,
  required List<(String, int)> incomeItems,
  required List<(String, int)> expenseItems,
}) {
  final rows = List.generate(50, (_) => List<Object?>.filled(10, null));
  void put(int excelRow, int col0, Object? v) => rows[excelRow - 1][col0] = v;
  put(6, 9, date);
  put(10, 8, income); // 収入総計（テストでは値を直接書く）
  put(11, 8, expense);
  put(15, 1, '※収入の部');
  var r = 16;
  for (final (label, amt) in incomeItems) {
    put(r, 2, '・$label');
    put(r, 9, amt);
    r++;
  }
  put(20, 2, '合計');
  put(34, 1, '※支出の部');
  r = 36;
  for (final (label, amt) in expenseItems) {
    put(r, 2, '・$label');
    put(r, 9, amt);
    r++;
  }
  put(41, 2, '合計');
  return rows;
}

/// 年間集計の明細行を書く。ヘッダー（3行目＝index 2）の下、index 3 から始める。
void _addAnnual(Excel excel, List<List<Object?>> rows) {
  final s = excel['2025年集計 (最終版)'];
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
}

void eventTests() {
  test('行事別シートを優先し、年間集計の同じ行は取り込まない（二重計上しない）', () {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final annual = excel['2025年集計 (最終版)'];
    annual.cell(CellIndex.indexByString('A1')).value = TextCellValue(
      '2025年　関桜会　収支報告書',
    );
    const headers = ['月日', '摘要', '収入', '支出', '収支', '残高', '備考'];
    for (var c = 0; c < headers.length; c++) {
      annual
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2))
          .value = TextCellValue(
        headers[c],
      );
    }
    _addAnnual(excel, [
      [null, '前年度繰越金（現金）', 1000],
      [null, '前年度繰越金（口座等）', 2000],
      [46036, '忘年会', 48000, 6000], // 行事と一致 → 行事側を使う
      [46037, '別の支払', null, 3000], // 行事と一致しない → 年間側を使う
    ]);
    _addSheet(
      excel,
      '25忘年会',
      _eventSheet(
        date: '2025年12月21日(日)',
        income: 48000,
        expense: 6000,
        incomeItems: const [('会費', 48000)],
        expenseItems: const [('会場費', 6000)],
      ),
    );
    final bytes = Uint8List.fromList(excel.encode()!);
    final p = LedgerFileService.parseAnnual(bytes, const []);

    expect(p.eventReplaced, ['25忘年会']);
    final event = p.toAdd.where((r) => r.event == '25忘年会').toList();
    expect(event.length, 2);
    expect(event.every((r) => r.date == DateTime(2025, 12, 21)), isTrue);
    // 年間の「忘年会」行は残っていない（二重計上なし）
    expect(p.toAdd.where((r) => r.storeName == '忘年会'), isEmpty);
    // 一致しない年間の行は通常どおり取り込む
    expect(p.toAdd.where((r) => r.storeName == '別の支払').length, 1);
  });

  test('合計が一致しない行事シートは使わず、年間集計をそのまま取り込む', () {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final annual = excel['2025年集計 (最終版)'];
    const headers = ['月日', '摘要', '収入', '支出', '収支', '残高', '備考'];
    for (var c = 0; c < headers.length; c++) {
      annual
          .cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 2))
          .value = TextCellValue(
        headers[c],
      );
    }
    _addAnnual(excel, [
      [null, '前年度繰越金（現金）', 1000],
      [null, '前年度繰越金（口座等）', 2000],
      [46036, '忘年会', 48000, 6000],
    ]);
    // 明細の合計（3000）が I11（6000）と違う → 不一致
    _addSheet(
      excel,
      '25忘年会',
      _eventSheet(
        date: '2025年12月21日(日)',
        income: 48000,
        expense: 6000,
        incomeItems: const [('会費', 48000)],
        expenseItems: const [('会場費', 3000)],
      ),
    );
    final p = LedgerFileService.parseAnnual(
      Uint8List.fromList(excel.encode()!),
      const [],
    );
    expect(p.eventReplaced, isEmpty);
    expect(p.toAdd.where((r) => r.storeName == '忘年会').length, 2);
  });
}
