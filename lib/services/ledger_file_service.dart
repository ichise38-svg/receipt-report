import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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

  /// 年間報告書の様式（サンプル「2025年集計」と同じ構成）の空のExcelを作る
  ///
  /// 上部: タイトル・会計・繰越金（現金／口座等）
  /// 中部: 月日・摘要・収入・支出・収支・残高・備考の明細（行は後から追加できる）
  /// 下部: 小計・合計、ATM入出金、口座と手持ち現金の確認、報告者・監査欄
  static List<int> buildTemplateBytes({int? year}) {
    final y = year ?? DateTime.now().year;
    final excel = Excel.createExcel();
    final sheet = excel[templateSheetName];
    excel.delete('Sheet1');

    final bold = CellStyle(bold: true);
    final title = CellStyle(bold: true, fontSize: 14);
    final small = CellStyle(fontSize: 9, fontColorHex: ExcelColor.grey);
    final header = CellStyle(
      bold: true,
      backgroundColorHex: ExcelColor.fromHexString('FFE3F2FD'),
      horizontalAlign: HorizontalAlign.Center,
    );
    final money = CellStyle(
      horizontalAlign: HorizontalAlign.Right,
      numberFormat: NumFormat.standard_3,
    );
    final date = CellStyle(
      horizontalAlign: HorizontalAlign.Center,
      numberFormat: NumFormat.custom(formatCode: 'm/d'),
    );
    final boldMoney = CellStyle(
      bold: true,
      horizontalAlign: HorizontalAlign.Right,
      numberFormat: NumFormat.standard_3,
    );

    void text(int col, int row, String v, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = TextCellValue(v);
      if (style != null) cell.cellStyle = style;
    }

    void num(int col, int row, int v, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = IntCellValue(v);
      cell.cellStyle = style ?? money;
    }

    void formula(int col, int row, String f, {CellStyle? style}) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = FormulaCellValue(f);
      cell.cellStyle = style ?? money;
    }

    // 列: A月日 B摘要 C収入 D支出 E収支 F残高 G備考（0始まり）
    const headers = ['月日', '摘要', '収入', '支出', '収支', '残高', '備考'];
    text(0, 0, '$y年度\u3000関桜会\u3000収支報告書', style: title);
    text(0, 1, '会計\u3000', style: bold);
    text(
      0,
      2,
      '※ 明細は3行目以降に入力してください。収支と残高は自動計算されます。'
      '収入と支出を同じ行に書くと、別々の記録として取り込まれます。',
      style: small,
    );
    for (var c = 0; c < headers.length; c++) {
      text(c, 3, headers[c], style: header);
    }

    // ここから下は Excel の表示行（1始まり）で指定する。
    // 関数の行引数は 0始まりなので、rowIndex = 表示行 - 1 に変換する。
    void cellAt(int col, int excelRow, String v, {CellStyle? style}) =>
        text(col, excelRow - 1, v, style: style);
    void numAt(int col, int excelRow, int v, {CellStyle? style}) =>
        num(col, excelRow - 1, v, style: style);
    void fx(int col, int excelRow, String f, {CellStyle? style}) =>
        formula(col, excelRow - 1, f, style: style);

    // 繰越金（表示行5・6）
    cellAt(1, 5, '前年度繰越金（現金）');
    numAt(2, 5, 0);
    fx(4, 5, 'C5-D5');
    fx(5, 5, 'E5');
    cellAt(1, 6, '前年度繰越金（口座等）');
    numAt(2, 6, 0);
    fx(4, 6, 'C6-D6');
    fx(5, 6, 'F5+E6');

    // 明細（表示行7〜206）。収支・残高は前の行から自動計算
    const firstData = 7;
    const lastData = 206;
    for (var n = firstData; n <= lastData; n++) {
      fx(4, n, 'IF(COUNT(C$n:D$n)=0,"",N(C$n)-N(D$n))');
      fx(
        5,
        n,
        n == firstData
            ? 'IF(E$n="","",N(F6)+E$n)'
            : 'IF(E$n="","",N(F${n - 1})+E$n)',
      );
      sheet
              .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: n - 1))
              .cellStyle =
          date;
    }

    // 小計（表示行208）・合計（表示行209）
    const subtotal = lastData + 2; // 208
    const total = subtotal + 1; // 209
    cellAt(0, subtotal, '$y年\u3000小計', style: bold);
    fx(2, subtotal, 'SUM(C$firstData:C$lastData)', style: boldMoney);
    fx(3, subtotal, 'SUM(D$firstData:D$lastData)', style: boldMoney);
    fx(4, subtotal, 'C$subtotal-D$subtotal', style: boldMoney);
    cellAt(0, total, '合計（前年繰越金 + $y年小計）', style: bold);
    fx(2, total, 'C$subtotal+C5+C6', style: boldMoney);
    fx(3, total, 'D$subtotal', style: boldMoney);
    fx(4, total, 'C$total-D$total', style: boldMoney);

    // ATM入出金（表示行213: 見出し, 214: 項目名, 215〜254: 入力欄）
    const atmTitle = total + 4; // 213
    const atmFirst = atmTitle + 2; // 215
    const atmLast = atmFirst + 39; // 254
    cellAt(1, atmTitle, 'ATM入出金', style: bold);
    cellAt(2, atmTitle, '入金', style: header);
    cellAt(3, atmTitle, '出金', style: header);
    cellAt(5, atmTitle, '残高', style: header);
    cellAt(0, atmTitle + 1, '月日', style: header);
    cellAt(1, atmTitle + 1, '摘要', style: header);
    cellAt(6, atmTitle + 1, '備考', style: header);
    fx(5, atmFirst, 'C6+C$atmFirst-D$atmFirst');
    for (var n = atmFirst + 1; n <= atmLast; n++) {
      fx(5, n, 'IF(COUNT(C$n:D$n)=0,"",N(F${n - 1})+N(C$n)-N(D$n))');
    }

    // 残高の確認（表示行258〜）
    const check = atmLast + 4; // 258
    cellAt(3, check, '口座', style: bold);
    numAt(5, check, 0, style: boldMoney);
    cellAt(3, check + 1, '手持ち現金', style: bold);
    numAt(5, check + 1, 0, style: boldMoney);
    cellAt(4, check + 2, '合計', style: bold);
    fx(5, check + 2, 'F$check+F${check + 1}', style: boldMoney);
    cellAt(1, check + 4, '口座+手持ち現金の合計', style: bold);
    fx(2, check + 4, 'F${check + 2}', style: boldMoney);
    cellAt(3, check + 4, '（残高計算額との差）', style: small);
    fx(2, check + 5, 'C${check + 4}-E$subtotal', style: boldMoney);

    // 署名欄
    cellAt(5, check + 8, '報告者', style: bold);
    cellAt(5, check + 9, '監査', style: bold);

    final encoded = excel.encode();
    if (encoded == null) {
      throw Exception('テンプレートの作成に失敗しました');
    }
    return encoded;
  }

  /// テンプレートを作成し、保存先を選んで保存する。
  /// 戻り値: 保存先のパス（共有シートを使った場合は null）
  static Future<String?> saveTemplate({int? year}) async {
    final bytes = Uint8List.fromList(buildTemplateBytes(year: year));
    const fileName = '収支報告書_入力用.xlsx';
    if (!kIsWeb) {
      // 端末・クラウドのフォルダを選んで保存（Android/iOSは保存先の選択画面）
      final path = await FilePicker.platform.saveFile(
        dialogTitle: '保存先を選んでください（OneDriveなどのクラウドも選べます）',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        bytes: bytes,
      );
      return path;
    }
    // Web は保存ダイアログが使えないため、共有シートから保存先を選ぶ
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            name: fileName,
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        subject: '収支報告書（入力用）',
      ),
    );
    return null;
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
