import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt.dart';
import 'annual_report.dart';
import 'event_report.dart';

final _currency = NumberFormat('#,##0', 'ja_JP');
final _dateFmt = DateFormat('yyyy/MM/dd');

/// 出力処理（JPEG・PDF・報告書）
class ExportService {
  /// レシート画像をJPEGとして書き出して共有
  static Future<void> shareReceiptAsJpeg(Receipt receipt) async {
    final bytes = await _readBytes(receipt.imagePath);
    if (bytes == null) {
      throw Exception('レシート画像が見つかりません');
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            bytes,
            mimeType: 'image/jpeg',
            name: _receiptFileBase(receipt, 'jpg'),
          ),
        ],
        text: '${receipt.storeName} ${_currency.format(receipt.amount)}円',
      ),
    );
  }

  /// 1件分の収支をPDFにして共有
  static Future<void> shareReceiptAsPdf(Receipt receipt) async {
    final font = await _loadJapaneseFont();
    final doc = pw.Document();
    final imageBytes = await _readBytes(receipt.imagePath);
    final pdfImage = imageBytes != null ? pw.MemoryImage(imageBytes) : null;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              receipt.isIncome ? '収入明細' : 'レシート',
              style: const pw.TextStyle(fontSize: 18),
            ),
            pw.SizedBox(height: 8),
            _infoRow('区分', receipt.kind.label),
            _infoRow(receipt.isIncome ? '摘要' : '店舗名', receipt.storeName),
            _infoRow('日付', _dateFmt.format(receipt.date)),
            _infoRow('金額', '${_currency.format(receipt.amount)} 円'),
            _infoRow('カテゴリ', receipt.category),
            if (receipt.memo.isNotEmpty) _infoRow('メモ', receipt.memo),
            if (pdfImage != null) ...[
              pw.SizedBox(height: 12),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final pdfBytes = await doc.save();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            pdfBytes,
            mimeType: 'application/pdf',
            name: _receiptFileBase(receipt, 'pdf'),
          ),
        ],
      ),
    );
  }

  /// 年間収支報告書（添付サンプルと同じ並び）をPDFで共有
  static Future<void> shareReport({
    required String mainTitle,
    required String title,
    required List<Receipt> receipts,
    required DateTime from,
    required DateTime to,
    required int participants,
    List<String> participantNames = const [],
    int carryCash = 0,
    int carryBank = 0,
  }) async {
    final font = await _loadJapaneseFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final report = AnnualReport.build(
      receipts,
      carryCash: carryCash,
      carryBank: carryBank,
      from: from,
      to: to,
    );
    final balances = report.runningBalances;
    final rows = report.rows;

    String money(int v) => v == 0 ? '' : _currency.format(v);

    final doc = pw.Document();

    // 1ページ目以降：年間収支報告書本体（明細が多い場合は自動で改ページ）
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Text(mainTitle, style: const pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 2),
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            '対象期間: ${_dateFmt.format(from)} 〜 ${_dateFmt.format(to)}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.Text(
            '作成日: ${_dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 10),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: const {
              0: pw.FixedColumnWidth(58),
              1: pw.FlexColumnWidth(3),
              2: pw.FixedColumnWidth(62),
              3: pw.FixedColumnWidth(62),
              4: pw.FixedColumnWidth(62),
              5: pw.FixedColumnWidth(68),
              6: pw.FlexColumnWidth(2),
            },
            children: [
              _tableRow(const [
                '月日',
                '摘要',
                '収入',
                '支出',
                '収支',
                '残高',
                '備考',
              ], header: true),
              for (var i = 0; i < rows.length; i++)
                _tableRow([
                  rows[i].date == null ? '' : _dateFmt.format(rows[i].date!),
                  rows[i].summary,
                  money(rows[i].income),
                  money(rows[i].expense),
                  _currency.format(rows[i].income - rows[i].expense),
                  _currency.format(balances[i]),
                  rows[i].note,
                ]),
              _tableRow([
                '',
                '小計（明細のみ）',
                _currency.format(report.subtotalIncome),
                _currency.format(report.subtotalExpense),
                _currency.format(
                  report.subtotalIncome - report.subtotalExpense,
                ),
                '',
                '',
              ], bold: true),
              _tableRow([
                '',
                '合計（前年繰越金＋小計）',
                _currency.format(report.totalIncome),
                _currency.format(report.totalExpense),
                _currency.format(report.balance),
                _currency.format(report.balance),
                '',
              ], bold: true),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Text('次年度へ繰り越す額', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 4),
          _table(
            headers: ['項目', '金額（円）'],
            rows: [
              ['参加人数', '$participants名'],
              ['差引残高（次年度繰越）', _currency.format(report.balance)],
              if (participants > 0)
                [
                  '1人あたり支出',
                  _currency.format(report.totalExpense ~/ participants),
                ],
            ],
            rightAlignCols: const {1},
          ),
          pw.SizedBox(height: 24),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Text('報告者　　　　　　　　', style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(width: 40),
              pw.Text('監査　　　　　　　　', style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ],
      ),
    );

    if (participantNames.isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => [
            pw.Text(
              '参加者名簿（${participantNames.length}名）',
              style: const pw.TextStyle(fontSize: 14),
            ),
            pw.SizedBox(height: 6),
            _table(
              headers: ['No.', '氏名'],
              rows: [
                for (var i = 0; i < participantNames.length; i++)
                  ['${i + 1}', participantNames[i]],
              ],
            ),
          ],
        ),
      );
    }

    // 画像のあるレシートは1件1ページで添付（日付順）
    final sorted = [...receipts]..sort((a, b) => a.date.compareTo(b.date));
    for (final r in sorted) {
      final bytes = await _readBytes(r.imagePath);
      if (bytes == null) continue;
      final image = pw.MemoryImage(bytes);
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          margin: const pw.EdgeInsets.all(32),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _infoRow('区分', r.kind.label),
              _infoRow('日付', _dateFmt.format(r.date)),
              _infoRow(r.isIncome ? '摘要' : '店舗名', r.storeName),
              _infoRow('金額', '${_currency.format(r.amount)} 円'),
              _infoRow('カテゴリ', r.category),
              if (r.memo.isNotEmpty) _infoRow('メモ', r.memo),
              pw.SizedBox(height: 12),
              pw.Expanded(
                child: pw.Center(
                  child: pw.Image(image, fit: pw.BoxFit.contain),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
    final pdfBytes = await doc.save();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            pdfBytes,
            mimeType: 'application/pdf',
            name: '収支報告書_$safeTitle.pdf',
          ),
        ],
        subject: '収支報告書 $title',
      ),
    );
  }

  /// イベント別会計報告書（25忘年会・旅行と同じ並び）をPDFで共有
  static Future<void> shareEventReport({
    required String mainTitle,
    required String eventName,
    required List<Receipt> receipts,
    required int participants,
  }) async {
    final report = EventReport.build(receipts, eventName);
    final font = await _loadJapaneseFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final doc = pw.Document();

    final period = report.firstDate == null
        ? ''
        : report.firstDate == report.lastDate
        ? _dateFmt.format(report.firstDate!)
        : '${_dateFmt.format(report.firstDate!)} 〜 ${_dateFmt.format(report.lastDate!)}';

    String money(int v) => '¥ ${_currency.format(v)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          // 左上：メインのタイトル＋その下にイベント名のタイトル
          pw.Text(mainTitle, style: const pw.TextStyle(fontSize: 16)),
          pw.SizedBox(height: 2),
          pw.Text(
            '${report.eventName}　会計報告書',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 2),
          pw.Text(period, style: const pw.TextStyle(fontSize: 10)),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('収入総計', style: const pw.TextStyle(fontSize: 11)),
              pw.Text(
                money(report.incomeTotal),
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('支出総計', style: const pw.TextStyle(fontSize: 11)),
              pw.Text(
                money(report.expenseTotal),
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
          pw.Divider(color: PdfColors.grey500),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                '差引金額（一般会計より支出）',
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                money(report.balance),
                style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            '※収入の部',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          _table(
            headers: ['項目', '金額（円）'],
            rows: [
              for (final l in report.incomeLines)
                [l.label, _currency.format(l.amount)],
              if (report.incomeLines.isEmpty) ['（収入なし）', ''],
              ['合計', _currency.format(report.incomeTotal)],
            ],
            rightAlignCols: const {1},
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            '※支出の部',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          _table(
            headers: ['日付', '店舗・摘要', '内容', '金額（円）'],
            rows: [
              for (final r in report.entries.where((r) => !r.isIncome))
                [
                  _dateFmt.format(r.date),
                  r.storeName,
                  [r.category, if (r.memo.isNotEmpty) r.memo].join('／'),
                  _currency.format(r.amount),
                ],
              if (report.expenseLines.isEmpty) ['', '（支出なし）', '', ''],
              ['', '合計', '', _currency.format(report.expenseTotal)],
            ],
            rightAlignCols: const {3},
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            '参加者：$participants名',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 24),
          pw.Text('上記の通り報告します', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 16),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '報告者　　　　　　　　',
              style: const pw.TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );

    final safeName = report.eventName.replaceAll(
      RegExp(r'[\\/:*?"<>|\s]'),
      '_',
    );
    final pdfBytes = await doc.save();
    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            pdfBytes,
            mimeType: 'application/pdf',
            name: '会計報告書_$safeName.pdf',
          ),
        ],
        subject: '会計報告書 ${report.eventName}',
      ),
    );
  }

  // ---------- 内部ヘルパー ----------

  static String _receiptFileBase(Receipt r, String ext) {
    final shortId = r.id.length >= 6 ? r.id.substring(0, 6) : r.id;
    return 'receipt_${_dateFmt.format(r.date).replaceAll('/', '')}_$shortId.$ext';
  }

  static pw.TableRow _tableRow(
    List<String> cells, {
    bool header = false,
    bool bold = false,
  }) {
    final style = pw.TextStyle(
      fontSize: 8,
      fontWeight: (header || bold) ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.TableRow(
      decoration: header
          ? const pw.BoxDecoration(color: PdfColors.blue50)
          : null,
      children: [
        for (var i = 0; i < cells.length; i++)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 3),
            child: pw.Text(
              cells[i],
              style: style,
              textAlign: (i >= 2 && i <= 5 && !header)
                  ? pw.TextAlign.right
                  : pw.TextAlign.left,
            ),
          ),
      ],
    );
  }

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    Set<int> rightAlignCols = const {},
    double fontSize = 10,
  }) {
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        fontSize: fontSize,
      ),
      cellStyle: pw.TextStyle(fontSize: fontSize),
      cellAlignment: pw.Alignment.centerLeft,
      cellAlignments: {
        for (final c in rightAlignCols) c: pw.Alignment.centerRight,
      },
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    );
  }

  static pw.Widget _infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 70,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 11)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  /// 日本語フォントを読み込む（取得失敗時は英数字のみ表示可能なフォント）
  static Future<pw.Font> _loadJapaneseFont() async {
    try {
      return await PdfGoogleFonts.notoSansJPRegular();
    } catch (_) {
      return pw.Font.helvetica();
    }
  }

  /// 画像ファイルを読み込む（Web や読めない場合は null）
  static Future<Uint8List?> _readBytes(String path) async {
    if (path.isEmpty || kIsWeb) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
