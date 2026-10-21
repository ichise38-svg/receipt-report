import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt.dart';
import 'xlsx_reader.dart';

/// 取り込みの確認結果（確認ダイアログに表示する内容）
class LedgerImportPreview {
  final String sheetName;

  /// 取り込み対象（重複を除いたもの）
  final List<Receipt> toAdd;

  /// 既存データと同じ内容のため無視した件数
  final int duplicateCount;

  /// 日付の読み取りが推定になった件数（取り込み後に確認・編集してください）
  final int needsCheckCount;

  /// 繰越金行など、対象外にした件数
  final int carrySkipped;

  /// 読み取れなかった行の理由
  final List<String> skippedReasons;

  const LedgerImportPreview({
    required this.sheetName,
    required this.toAdd,
    required this.duplicateCount,
    required this.needsCheckCount,
    required this.carrySkipped,
    required this.skippedReasons,
  });

  int get incomeCount => toAdd.where((r) => r.isIncome).length;
  int get expenseCount => toAdd.length - incomeCount;
  int get incomeTotal =>
      toAdd.where((r) => r.isIncome).fold(0, (s, r) => s + r.amount);
  int get expenseTotal =>
      toAdd.where((r) => !r.isIncome).fold(0, (s, r) => s + r.amount);
}

/// 年間収支の Excel 取り込みと、取り込み用テンプレートの作成
///
/// 対象: 「2025年集計」のような表（見出しに 月日・摘要・収入・支出）。
/// 行事別シートは年間集計と同じ金額を含むため取り込み対象外です（二重計上防止）。
class LedgerFileService {
  static const templateSheetName = '収支入力';

  /// 取り込み（重複は無視する）。既存データは削除済みを除いた一覧を渡す。
  static LedgerImportPreview parseAnnual(
    Uint8List bytes,
    List<Receipt> existing,
  ) {
    final Excel book;
    try {
      book = XlsxReader.decode(bytes);
    } catch (_) {
      throw const FormatException('Excelファイルとして読めませんでした。.xlsx形式か確認してください。');
    }

    final candidates = <_Found>[];
    for (final entry in book.tables.entries) {
      final cols = _findHeader(entry.value.rows);
      if (cols != null) {
        candidates.add(_Found(entry.key, entry.value.rows, cols));
      }
    }
    if (candidates.isEmpty) {
      throw const FormatException(
        '「摘要」「収入」「支出」の見出しが見つかりません。年間集計の表があるファイルを選んでください。',
      );
    }
    // 「集計」を含むシートを優先（行事シートより年間集計を選ぶため）
    final found = candidates.firstWhere(
      (c) => c.name.contains('集計'),
      orElse: () => candidates.first,
    );

    final rows = found.rows;
    final cols = found.cols;
    final yearHint = _yearHint(rows, cols.headerRow);
    final counts = <String, int>{};
    for (final r in existing) {
      if (r.deleted) continue;
      final k = _key(r.kind, r.date, r.storeName, r.amount);
      counts[k] = (counts[k] ?? 0) + 1;
    }

    final toAdd = <Receipt>[];
    var duplicates = 0;
    var needsCheck = 0;
    var carrySkipped = 0;
    final skipped = <String>[];

    for (var i = cols.headerRow + 1; i < rows.length; i++) {
      final row = rows[i];
      final dateText = _text(row, cols.date);
      final summary = _text(row, cols.summary);
      // 日付のない「小計・合計・ATM」行に来たら明細の終わりとみなす
      if (dateText.isEmpty && _isSummaryRow(summary)) break;
      if (row.every((d) => _cellText(d).isEmpty)) continue;
      if (summary.contains('繰越')) {
        carrySkipped++;
        continue;
      }

      final income = _amount(row, cols.income);
      final expense = _amount(row, cols.expense);
      if (income <= 0 && expense <= 0) continue;

      final parsed = _parseDate(row, cols.date, yearHint);
      if (parsed == null) {
        skipped.add('${i + 1}行目「$summary」: 日付を読み取れません');
        continue;
      }
      final name = summary.isEmpty ? '（摘要なし）' : summary;
      final note = _text(row, cols.note);
      final memo = [
        if (!parsed.exact) '日付要確認（元の表記: ${parsed.raw}）',
        if (note.isNotEmpty) note,
      ].join('／');

      // 収入と支出が同じ行にある場合は、それぞれ別の記録にする
      final sides = <(EntryKind, int)>[
        if (income > 0) (EntryKind.income, income),
        if (expense > 0) (EntryKind.expense, expense),
      ];
      for (final (kind, amount) in sides) {
        final key = _key(kind, parsed.date, name, amount);
        final left = counts[key] ?? 0;
        if (left > 0) {
          counts[key] = left - 1;
          duplicates++;
          continue;
        }
        if (!parsed.exact) needsCheck++;
        toAdd.add(
          Receipt(
            kind: kind,
            storeName: name,
            date: parsed.date,
            amount: amount,
            category: _categorize(kind, name),
            memo: memo,
            event: '',
          ),
        );
      }
    }

    return LedgerImportPreview(
      sheetName: found.name,
      toAdd: toAdd,
      duplicateCount: duplicates,
      needsCheckCount: needsCheck,
      carrySkipped: carrySkipped,
      skippedReasons: skipped,
    );
  }

  /// 取り込み用の空のExcel（見出し・計算欄つき）を作る
  static List<int> buildTemplateBytes({int? year}) {
    final excel = Excel.createExcel();
    final sheet = excel[templateSheetName];
    excel.delete('Sheet1');

    final bold = CellStyle(bold: true);
    final small = CellStyle(fontSize: 9);
    final header = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('FFE3F2FD'),
      horizontalAlign: HorizontalAlign.Center,
    );
    final money = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      numberFormat: NumFormat.standard_3,
    );

    void put(int col, int row, CellValue value, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = value;
      if (style != null) cell.cellStyle = style;
    }

    void formula(int col, int row, String f, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = FormulaCellValue(f);
      if (style != null) cell.cellStyle = style;
    }

    const headerRow = 3;
    const firstRow = 4;
    const lastRow = 203; // 200行分の入力欄

    put(
      0,
      0,
      TextCellValue('${year ?? DateTime.now().year}年　収支入力（取り込み用）'),
      style: bold,
    );
    put(
      0,
      1,
      TextCellValue(
        '月日・摘要・収入・支出を入力して保存し、アプリの「ファイルから取り込み」で読み込みます。'
        '収入と支出の両方に金額がある行は、収入と支出を別々に取り込みます。',
      ),
      style: small,
    );
    const headers = ['月日', '摘要', '収入', '支出', '収支', '残高', '備考'];
    for (var c = 0; c < headers.length; c++) {
      put(c, headerRow, TextCellValue(headers[c]), style: header);
    }

    for (var r = firstRow; r <= lastRow; r++) {
      final n = r + 1; // Excel の行番号（1始まり）
      formula(4, r, 'IF(COUNT(C$n:D$n)=0,"",N(C$n)-N(D$n))', style: money);
      formula(
        5,
        r,
        r == firstRow ? 'IF(E$n="","",E$n)' : 'IF(E$n="","",N(F${n - 1})+E$n)',
        style: money,
      );
    }
    final encoded = excel.encode();
    if (encoded == null) {
      throw Exception('テンプレートの作成に失敗しました');
    }
    return encoded;
  }

  /// テンプレートを共有シートで保存・送信する
  static Future<void> shareTemplate() async {
    final bytes = buildTemplateBytes();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: '収支入力テンプレート.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: '収支入力テンプレート',
      ),
    );
  }

  // ---------- 内部処理 ----------

  static _Columns? _findHeader(List<List<Data?>> rows) {
    final limit = rows.length < 30 ? rows.length : 30;
    for (var r = 0; r < limit; r++) {
      final row = rows[r];
      final texts = [for (var c = 0; c < row.length; c++) _cellText(row[c])];
      int idx(String word) => texts.indexWhere((t) => t == word);
      final summary = idx('摘要');
      final income = idx('収入');
      final expense = idx('支出');
      if (summary < 0 || income < 0 || expense < 0) continue;
      var date = idx('月日');
      if (date < 0) date = 0;
      return _Columns(
        headerRow: r,
        date: date,
        summary: summary,
        income: income,
        expense: expense,
        note: idx('備考'),
      );
    }
    return null;
  }

  static bool _isSummaryRow(String text) =>
      text.contains('小計') || text.contains('合計') || text.contains('ATM');

  static int _yearHint(List<List<Data?>> rows, int headerRow) {
    final re = RegExp(r'(20\d{2})年');
    for (var r = 0; r < headerRow && r < rows.length; r++) {
      for (final d in rows[r]) {
        final m = re.firstMatch(_cellText(d));
        if (m != null) return int.parse(m.group(1)!);
      }
    }
    return DateTime.now().year;
  }

  static String _key(EntryKind kind, DateTime date, String name, int amount) {
    final d =
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
    return '${kind.name}|$d|${name.trim()}|$amount';
  }

  static String _cellText(Data? d) {
    final v = d?.value;
    if (v == null) return '';
    if (v is TextCellValue) {
      return v.toString().replaceAll('\u3000', ' ').trim();
    }
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    return '';
  }

  static String _text(List<Data?> row, int col) {
    if (col < 0 || col >= row.length) return '';
    return _cellText(row[col]);
  }

  static int _amount(List<Data?> row, int col) {
    if (col < 0 || col >= row.length) return 0;
    final v = row[col]?.value;
    if (v is IntCellValue) return v.value;
    if (v is DoubleCellValue) return v.value.round();
    if (v is TextCellValue) {
      final cleaned = v.toString().replaceAll(RegExp(r'[,円\s\u3000]'), '');
      return int.tryParse(cleaned) ?? 0;
    }
    return 0;
  }

  /// 日付の読み取り。exact=false は推定（「11/8～9」「1月」など）
  static _ParsedDate? _parseDate(List<Data?> row, int col, int yearHint) {
    if (col < 0 || col >= row.length) return null;
    final v = row[col]?.value;
    if (v is DateCellValue) {
      return _ParsedDate(DateTime(v.year, v.month, v.day), true, '');
    }
    if (v is DateTimeCellValue) {
      return _ParsedDate(DateTime(v.year, v.month, v.day), true, '');
    }
    if (v is IntCellValue || v is DoubleCellValue) {
      final serial = v is IntCellValue
          ? v.value
          : (v as DoubleCellValue).value.floor();
      // Excel のシリアル値（おおむね 1990〜2110 年の範囲のみ採用）
      if (serial < 30000 || serial > 80000) return null;
      final d = DateTime.utc(1899, 12, 30).add(Duration(days: serial));
      return _ParsedDate(DateTime(d.year, d.month, d.day), true, '');
    }
    final raw = _cellText(row[col]);
    if (raw.isEmpty) return null;

    final full = RegExp(
      r'(\d{4})[/年.\-](\d{1,2})[/月.\-](\d{1,2})',
    ).firstMatch(raw);
    if (full != null) {
      return _ParsedDate(
        DateTime(
          int.parse(full.group(1)!),
          int.parse(full.group(2)!),
          int.parse(full.group(3)!),
        ),
        true,
        '',
      );
    }
    final md = RegExp(r'(\d{1,2})[/／](\d{1,2})').firstMatch(raw);
    if (md != null) {
      return _ParsedDate(
        DateTime(yearHint, int.parse(md.group(1)!), int.parse(md.group(2)!)),
        false,
        raw,
      );
    }
    final monthOnly = RegExp(r'^(\d{1,2})月').firstMatch(raw);
    if (monthOnly != null) {
      return _ParsedDate(
        DateTime(yearHint, int.parse(monthOnly.group(1)!), 1),
        false,
        raw,
      );
    }
    return null;
  }

  static String _categorize(EntryKind kind, String text) {
    if (kind == EntryKind.income) {
      if (text.contains('集金')) return '入金';
      if (text.contains('補助')) return '補助金';
      return '雑収入';
    }
    if (_has(text, ['タクシー', '電車', 'バス', 'ガソリン', '駐車', '交通', '切符', '高速'])) {
      return '交通費';
    }
    if (_has(text, [
      '食',
      '飲',
      'ビール',
      '酒',
      '菓子',
      '弁当',
      'BBQ',
      '肉',
      'お茶',
      'ジュース',
      'ケーキ',
    ])) {
      return '食費';
    }
    if (_has(text, ['切手', '郵便', '通信', '電話', 'ネット'])) return '通信費';
    if (_has(text, ['祭礼', '謝礼', '御供', '香典', 'お祝', '見舞'])) return '交際費';
    if (_has(text, ['消耗', '備品', '文具', '用紙', 'インク'])) return '消耗品費';
    return '雑費';
  }

  static bool _has(String text, List<String> words) {
    final upper = text.toUpperCase();
    return words.any((w) => upper.contains(w.toUpperCase()));
  }
}

class _Columns {
  final int headerRow;
  final int date;
  final int summary;
  final int income;
  final int expense;
  final int note;

  const _Columns({
    required this.headerRow,
    required this.date,
    required this.summary,
    required this.income,
    required this.expense,
    required this.note,
  });
}

class _Found {
  final String name;
  final List<List<Data?>> rows;
  final _Columns cols;

  const _Found(this.name, this.rows, this.cols);
}

class _ParsedDate {
  final DateTime date;
  final bool exact;
  final String raw;

  const _ParsedDate(this.date, this.exact, this.raw);
}
