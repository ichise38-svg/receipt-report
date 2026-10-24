import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// xlsx の「計算結果（キャッシュ値）」を読む。
///
/// excel パッケージは数式セルの計算結果を読めないため、Excel が保存している
/// `<v>` の値を直接読む。文字列の表示は excel パッケージの値を使う。
/// 数式の中身は解釈せず、Excel が最後に計算した値だけを使う。
class XlsxCached {
  /// シート名 → (セル参照 → 数値)
  final Map<String, Map<String, num>> _values;

  XlsxCached._(this._values);

  factory XlsxCached.decode(Uint8List bytes) {
    final values = <String, Map<String, num>>{};
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final wbFile = archive.findFile('xl/workbook.xml');
      final relFile = archive.findFile('xl/_rels/workbook.xml.rels');
      if (wbFile == null || relFile == null) {
        return XlsxCached._(values);
      }
      final wb = utf8.decode(wbFile.content as List<int>);
      final rels = utf8.decode(relFile.content as List<int>);

      final relTarget = <String, String>{};
      for (final m in RegExp(r'<Relationship\b([^>]*)/?>').allMatches(rels)) {
        final attrs = m.group(1)!;
        final id = RegExp(r'Id="([^"]+)"').firstMatch(attrs)?.group(1);
        final target = RegExp(r'Target="([^"]+)"').firstMatch(attrs)?.group(1);
        if (id != null && target != null) relTarget[id] = target;
      }

      for (final m in RegExp(r'<sheet\b([^>]*)/?>').allMatches(wb)) {
        final attrs = m.group(1)!;
        final name = _unescape(
          RegExp(r'name="([^"]*)"').firstMatch(attrs)?.group(1) ?? '',
        );
        final rid = RegExp(r'r:id="([^"]+)"').firstMatch(attrs)?.group(1);
        final target = rid == null ? null : relTarget[rid];
        if (target == null) continue;
        final path = target.startsWith('/')
            ? target.substring(1)
            : 'xl/$target';
        final file = archive.findFile(path);
        if (file == null) continue;
        values[name] = _readSheetValues(utf8.decode(file.content as List<int>));
      }
    } catch (_) {
      // 読めない場合は空。呼び出し側は「読めなかった」として扱う。
    }
    return XlsxCached._(values);
  }

  /// セルの計算結果（数値）。数値でなければ null
  num? numberAt(String sheet, String ref) => _values[sheet]?[ref];

  static Map<String, num> _readSheetValues(String xml) {
    final out = <String, num>{};
    final cell = RegExp(
      r'<c r="([A-Z]+[0-9]+)"([^>]*?)(?:/>|>(.*?)</c>)',
      dotAll: true,
    );
    for (final m in cell.allMatches(xml)) {
      final ref = m.group(1)!;
      final attrs = m.group(2) ?? '';
      final body = m.group(3) ?? '';
      // 文字列・エラー・真偽値は数値として扱わない
      if (RegExp(r'\st="(s|str|inlineStr|e|b)"').hasMatch(' $attrs')) continue;
      final v = RegExp(r'<v>([^<]*)</v>').firstMatch(body)?.group(1);
      if (v == null) continue;
      final n = num.tryParse(v.trim());
      if (n != null) out[ref] = n;
    }
    return out;
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
