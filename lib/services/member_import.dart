import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

/// 名簿ファイル（CSV / TXT / XLSX）から氏名を取り出す
/// 1列目を氏名として扱い、見出し行（氏名・名前・name）は除外する
class MemberImport {
  static const _headerWords = {'氏名', '名前', '参加者', 'name', 'Name', 'NAME'};

  static List<String> parseText(String text) {
    final names = <String>[];
    final cleaned = text.replaceAll('\uFEFF', ''); // BOM除去
    for (final raw in const LineSplitter().convert(cleaned)) {
      final first = _firstColumn(raw);
      if (first.isEmpty || _headerWords.contains(first)) continue;
      names.add(first);
    }
    return names;
  }

  static List<String> parseXlsx(Uint8List bytes) {
    final book = Excel.decodeBytes(bytes);
    if (book.tables.isEmpty) return [];
    final sheet = book.tables.values.first;
    final names = <String>[];
    for (final row in sheet.rows) {
      if (row.isEmpty) continue;
      final value = row.first?.value?.toString().trim() ?? '';
      if (value.isEmpty || _headerWords.contains(value)) continue;
      names.add(value);
    }
    return names;
  }

  static String _firstColumn(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return '';
    final first = trimmed.split(RegExp(r'[,\t]')).first;
    return first.replaceAll('"', '').trim();
  }
}
