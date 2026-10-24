import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/services/event_report.dart';
import 'package:receipt_report/services/ledger_file_service.dart';
import 'package:receipt_report/services/receipt_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('サンプル取り込み→保存→読み戻し→行事一覧まで8行事が残る', () async {
    final file = File('/home/user/uploaded_files/2025関桜会会計報告サンプル.xlsx');
    if (!file.existsSync()) {
      markTestSkipped('サンプルがありません');
      return;
    }
    final preview = LedgerFileService.parseAnnual(
      file.readAsBytesSync(),
      await ReceiptStore.loadRaw(),
    );
    await ReceiptStore.addAll(preview.toAdd);
    final saved = await ReceiptStore.loadRaw();
    final names = EventReport.namesOf(saved);
    // ignore: avoid_print
    print('count=${saved.length} events=$names');
    for (final n in names) {
      final rep = EventReport.build(saved, n);
      // ignore: avoid_print
      print(
        '$n: ${rep.entries.length}件 inc=${rep.incomeLines.length} exp=${rep.expenseLines.length}',
      );
    }
    expect(names.length, 8);
    expect(saved.where((r) => r.event.isNotEmpty).length, 34);
    // 二回目の取り込みは全て重複
    final again = LedgerFileService.parseAnnual(file.readAsBytesSync(), saved);
    expect(again.toAdd, isEmpty);
    expect(again.duplicateCount, 56);
  });
}
