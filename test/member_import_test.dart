import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/services/member_import.dart';

void main() {
  test('CSVの1列目を氏名として読み、見出し行と空行を除外する', () {
    const csv = '氏名,所属\n山田 太郎,A班\n\n"佐藤 花子",B班\n鈴木一郎\n';
    expect(MemberImport.parseText(csv), ['山田 太郎', '佐藤 花子', '鈴木一郎']);
  });

  test('BOM付きテキストとタブ区切りに対応する', () {
    const txt = '\uFEFF名前\n田中\t会計\n高橋\n';
    expect(MemberImport.parseText(txt), ['田中', '高橋']);
  });

  test('Excelは「氏　名」列だけを読み、番号・タイトル・他シートを除外する', () {
    final excel = Excel.createExcel();
    final sheet = excel['2026年 会員名簿'];
    sheet.appendRow([TextCellValue('2026年度 関桜会 会員名簿')]);
    sheet.appendRow([null]);
    sheet.appendRow([
      TextCellValue('Ｎｏ．'),
      TextCellValue('氏\u3000名'),
      TextCellValue('会費'),
    ]);
    sheet.appendRow([
      IntCellValue(1),
      TextCellValue('山田 太郎'),
      TextCellValue('○'),
    ]);
    sheet.appendRow([
      IntCellValue(2),
      TextCellValue('佐藤 花子'),
      TextCellValue('-'),
    ]);
    final other = excel['集計'];
    other.appendRow([TextCellValue('月日'), TextCellValue('小計')]);
    final bytes = Uint8List.fromList(excel.encode()!);

    expect(MemberImport.parseXlsxNames(bytes), ['山田 太郎', '佐藤 花子']);
  });
}
