import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import 'xlsx_reader.dart';

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
    final book = XlsxReader.decode(bytes);
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

  /// Excel名簿から氏名列だけを読む。
  /// 見出し行（「氏名」「氏　名」など）を探し、その列の値だけを取り出す。
  /// 見出しが見つからない場合は、番号だけのセル・見出し語を除いて1列目を読む。
  static List<String> parseXlsxNames(Uint8List bytes) {
    final book = XlsxReader.decode(bytes);
    final names = <String>[];
    final hasRosterSheet = book.tables.keys.any((k) => k.contains('名簿'));
    final tables = hasRosterSheet
        ? book.tables.entries.where((e) => e.key.contains('名簿'))
        : book.tables.entries;
    for (final entry in tables) {
      final sheet = entry.value;
      final rows = sheet.rows;
      var nameCol = -1;
      var headerRow = -1;
      for (var r = 0; r < rows.length && r < 30 && nameCol < 0; r++) {
        final row = rows[r];
        for (var c = 0; c < row.length; c++) {
          final v = _cellText(row[c]);
          if (_isNameHeader(v)) {
            nameCol = c;
            headerRow = r;
            break;
          }
        }
      }
      if (nameCol < 0) {
        // 見出しが無い場合は1列目を使う（番号・見出し・タイトルは除外）
        for (final row in rows) {
          final v = row.isEmpty ? '' : _cellText(row.first);
          if (_isLikelyName(v)) names.add(v);
        }
        continue;
      }
      for (var r = headerRow + 1; r < rows.length; r++) {
        final row = rows[r];
        if (nameCol >= row.length) continue;
        final v = _cellText(row[nameCol]);
        if (_isLikelyName(v)) names.add(v);
      }
    }
    return names;
  }

  static String _cellText(dynamic cell) {
    final value = cell?.value;
    if (value == null) return '';
    final raw = value is TextCellValue
        ? value.value.toString()
        : value.toString();
    return raw.replaceAll('\u3000', ' ').replaceAll('\n', ' ').trim();
  }

  /// 「氏名」「氏 名」「名前」など、空白を除いて見出し語と一致するか
  static bool _isNameHeader(String v) {
    final compact = v.replaceAll(RegExp(r'\s'), '');
    return compact == '氏名' ||
        compact == '名前' ||
        compact == '参加者' ||
        compact == 'name' ||
        compact == 'Name' ||
        compact == 'NAME';
  }

  /// 氏名として妥当か（空・番号だけ・見出し語・タイトル風の長文は除外）
  static bool _isLikelyName(String v) {
    if (v.isEmpty || v == '-' || v == '○') return false;
    if (_headerWords.contains(v)) return false;
    if (RegExp(r'^[0-9０-９.\-]+$').hasMatch(v)) return false; // 番号・数値
    if (v.contains('名簿') || v.contains('会計') || v.length > 20) return false;
    if (v.startsWith('No') || v.startsWith('Ｎｏ')) return false;
    return true;
  }

  static String _firstColumn(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return '';
    final first = trimmed.split(RegExp(r'[,\t]')).first;
    return first.replaceAll('"', '').trim();
  }
}
