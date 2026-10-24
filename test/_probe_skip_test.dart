import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/services/ledger_file_service.dart';

void main() {
  test('probe', () {
    for (final f in [
      '/home/user/uploaded_files/2025関桜会会計報告サンプル.xlsx',
      '/home/user/samples/収支報告書_サンプル_2025年4月.xlsx',
      '/home/user/samples/収支報告書_名簿付きサンプル.xlsx',
      '/home/user/samples/収支報告書_添付形式サンプル.xlsx',
      '/home/user/samples/イベント別報告_25忘年会サンプル.xlsx',
    ]) {
      final bytes = Uint8List.fromList(File(f).readAsBytesSync());
      try {
        final p = LedgerFileService.parseAnnual(bytes, const []);
        // ignore: avoid_print
        print('FILE ${f.split('/').last}: sheet=${p.sheetName} add=${p.toAdd.length} skipped=${p.skippedReasons.length} needsCheck=${p.needsCheckCount} year=${p.yearMismatchCount}');
        for (final s in p.skippedReasons.take(20)) {
          // ignore: avoid_print
          print('  SKIP $s');
        }
      } catch (e) {
        // ignore: avoid_print
        print('FILE ${f.split('/').last}: ERROR $e');
      }
    }
  });
}
