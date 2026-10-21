import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// 既存の Excel（.xlsx）を読み込む共通処理
///
/// excel パッケージは「カスタム書式IDは164以上」を要求するが、
/// 円表示などの書式に組み込みID（5・6・42 など）を使ったファイルは読めない。
/// そこで読み込み時だけメモリ上で styles.xml の該当IDを振り直す（元ファイルは変更しない）。
class XlsxReader {
  static Excel decode(Uint8List bytes) {
    try {
      return Excel.decodeBytes(bytes);
    } catch (_) {
      final fixed = _fixBuiltinNumFormats(bytes);
      if (fixed == null) rethrow;
      return Excel.decodeBytes(fixed);
    }
  }

  /// numFmt の組み込みID（164未満）を 164 以上の未使用IDへ振り直した xlsx を返す。
  /// 直す必要がなければ null。
  static Uint8List? _fixBuiltinNumFormats(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return null;
    }
    final stylesFile = archive.findFile('xl/styles.xml');
    if (stylesFile == null) return null;
    final content = stylesFile.content;
    final xml = utf8.decode(content as List<int>);

    final numFmts = RegExp(
      r'<numFmts[^>]*>.*?</numFmts>',
      dotAll: true,
    ).firstMatch(xml);
    if (numFmts == null) return null;
    final block = numFmts.group(0)!;

    // ファイル内で使われている書式ID（セルの参照）
    final used = RegExp(
      r'numFmtId="(\d+)"',
    ).allMatches(xml).map((m) => int.parse(m.group(1)!)).toSet();
    // styles.xml に定義済みの書式ID（numFmt 要素）
    final defined = RegExp(
      r'<numFmt numFmtId="(\d+)"',
    ).allMatches(block).map((m) => int.parse(m.group(1)!)).toSet();
    // excel パッケージが最初から知っている組み込み書式
    const knownBuiltins = {
      0,
      1,
      2,
      3,
      4,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      37,
      38,
      39,
      40,
      45,
      46,
      47,
      48,
      49,
    };
    // 164未満で、定義が必要なID（定義済みの組み込み含む）
    final needRemap =
        used
            .where((id) => id > 0 && id < 164 && !knownBuiltins.contains(id))
            .toList()
          ..sort();
    if (needRemap.isEmpty) return null;

    var next = 164;
    final taken = {...used, ...defined};
    final remap = <int, int>{};
    for (final id in needRemap) {
      while (taken.contains(next)) {
        next++;
      }
      remap[id] = next;
      taken.add(next);
      next++;
    }

    // 1) 既存の numFmt 要素のIDを振り直す
    final rewritten = block.replaceAllMapped(
      RegExp(r'<numFmt numFmtId="(\d+)"'),
      (m) {
        final id = int.parse(m.group(1)!);
        return '<numFmt numFmtId="${remap[id] ?? id}"';
      },
    );
    // 2) 未定義の組み込みIDは「General」で新規定義する
    final added = StringBuffer();
    for (final id in needRemap) {
      if (!defined.contains(id)) {
        added.write('<numFmt numFmtId="${remap[id]}" formatCode="General"/>');
      }
    }
    final newBlock = rewritten.replaceFirst('</numFmts>', '$added</numFmts>');
    var newXml = xml.replaceFirst(block, newBlock);
    // 3) セルの書式参照（cellXfs など）を同じ対応で振り直す
    newXml = newXml.replaceAllMapped(
      RegExp(r'(<xf\b[^>]*?\bnumFmtId=")(\d+)(")'),
      (m) {
        final id = int.parse(m.group(2)!);
        final mapped = remap[id];
        if (mapped == null) return m.group(0)!;
        return '${m.group(1)}$mapped${m.group(3)}';
      },
    );

    final out = Archive();
    for (final file in archive) {
      if (file.name == 'xl/styles.xml') {
        final data = Uint8List.fromList(utf8.encode(newXml));
        out.addFile(ArchiveFile(file.name, data.length, data));
      } else {
        out.addFile(file);
      }
    }
    final encoded = ZipEncoder().encode(out);
    return encoded == null ? null : Uint8List.fromList(encoded);
  }
}
