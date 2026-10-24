import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/ledger_file_service.dart';

void main() {
  test('全角の日付は半角として読める', () {
    // 全角の日付文字列を含む年間集計を作るのは重いので、正規化だけ確認する
    expect(LedgerFileService.normalizeDigitsForTest('２０２５／３／１'), '2025/3/1');
    expect(LedgerFileService.normalizeDigitsForTest('２０２５．３－１　'), '2025.3-1 ');
  });

  test('サンプルの8行事がすべて取り込み対象になる', () {
    final file = File('/home/user/uploaded_files/2025関桜会会計報告サンプル.xlsx');
    if (!file.existsSync()) {
      markTestSkipped('サンプルがありません');
      return;
    }
    final preview = LedgerFileService.parseAnnual(
      file.readAsBytesSync(),
      const <Receipt>[],
    );
    expect(preview.eventReplaced.length, 8);
    for (final name in const [
      '25忘年会',
      '25旅行',
      '25稽古上げ',
      '25消防BBQ',
      '25草刈りBBQ',
      '25花見会',
      '25レクレーション',
      '25新年会',
    ]) {
      expect(preview.eventReplaced, contains(name));
    }
    expect(preview.skippedReasons, isEmpty);
    final events = preview.toAdd.map((r) => r.event).toSet()..remove('');
    expect(events.length, 8);
  });

  test('年間集計が差引だけを書いている行事も、差引の一致で取り込む', () {
    final file = File(
      Directory('/home/user/uploaded_files')
          .listSync()
          .whereType<File>()
          .firstWhere(
            (e) => e.path.endsWith('sx.xlsx'),
            orElse: () => File('/nonexistent'),
          )
          .path,
    );
    if (!file.existsSync()) {
      markTestSkipped('サンプルがありません');
      return;
    }
    final preview = LedgerFileService.parseAnnual(
      file.readAsBytesSync(),
      const <Receipt>[],
    );
    expect(preview.eventReplaced, containsAll(['新年会', '花見会', '消防BBQ']));
    final events = preview.toAdd.map((r) => r.event).toSet()..remove('');
    expect(events, containsAll(['新年会', '花見会', '消防BBQ']));
  });

  test('行事の日付は全角数字でも読め、1970年にならない', () {
    final file = File(
      Directory('/home/user/uploaded_files')
          .listSync()
          .whereType<File>()
          .firstWhere(
            (e) => e.path.endsWith('sx.xlsx'),
            orElse: () => File('/nonexistent'),
          )
          .path,
    );
    if (!file.existsSync()) {
      markTestSkipped('サンプルがありません');
      return;
    }
    final preview = LedgerFileService.parseAnnual(
      file.readAsBytesSync(),
      const <Receipt>[],
    );
    final ev = preview.toAdd.where(
      (r) => r.event == '新年会' || r.event == '消防BBQ',
    );
    expect(ev, isNotEmpty);
    for (final r in ev) {
      expect(r.date.year, 2026);
    }
  });
}
