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
}
