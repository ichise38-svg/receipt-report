import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt.dart';
import 'ledger_summary.dart';

final _currency = NumberFormat('#,##0', 'ja_JP');
final _dateFmt = DateFormat('yyyy/MM/dd');

/// 出力処理（JPEG・PDF・報告書）
class ExportService {
  /// レシート画像をJPEGとして書き出して共有
  static Future<void> shareReceiptAsJpeg(Receipt receipt) async {
    final tmp = await _tempFile(_receiptFileBase(receipt, 'jpg'));
    await tmp.writeAsBytes(await File(receipt.imagePath).readAsBytes());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(tmp.path, mimeType: 'image/jpeg')],
        text: '${receipt.storeName} ${_currency.format(receipt.amount)}円',
      ),
    );
  }

  /// 1件分の収支をPDFにして共有
  static Future<void> shareReceiptAsPdf(Receipt receipt) async {
    final font = await _loadJapaneseFont();
    final doc = pw.Document();
    final hasImage =
        receipt.imagePath.isNotEmpty && File(receipt.imagePath).existsSync();
    final pdfImage = hasImage
        ? pw.MemoryImage(await File(receipt.imagePath).readAsBytes())
        : null;

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

    final file = await _tempFile(_receiptFileBase(receipt, 'pdf'));
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]),
    );
  }

  /// 会計報告書（収支サマリー・カテゴリ別集計・明細・レシート画像）をPDFで共有
  static Future<void> shareReport({
    required String title,
    required List<Receipt> receipts,
    required DateTime from,
    required DateTime to,
    required int participants,
    List<String> participantNames = const [],
  }) async {
    final font = await _loadJapaneseFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final summary = LedgerSummary.from(receipts, participants: participants);
    final sorted = [...receipts]..sort((a, b) => a.date.compareTo(b.date));

    final doc = pw.Document();

    // 1ページ目以降：報告書本体（明細が多い場合は自動で改ページ）
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text('会計報告書（収支）', style: const pw.TextStyle(fontSize: 20)),
          pw.SizedBox(height: 4),
          pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 2),
          pw.Text(
            '対象期間: ${_dateFmt.format(from)} 〜 ${_dateFmt.format(to)}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.Text(
            '作成日: ${_dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 14),
          pw.Text('収支サマリー', style: const pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 6),
          _table(
            headers: ['項目', '金額（円）'],
            rows: [
              ['収入合計', _currency.format(summary.income)],
              ['支出合計', _currency.format(summary.expense)],
              ['差引残高（収入－支出）', _currency.format(summary.balance)],
              ['参加人数', '${summary.participants}名'],
              if (summary.expensePerPerson != null)
                ['1人あたり支出', _currency.format(summary.expensePerPerson)],
              if (summary.incomePerPerson != null)
                ['1人あたり収入', _currency.format(summary.incomePerPerson)],
            ],
            rightAlignCols: const {1},
          ),
          pw.SizedBox(height: 14),
          pw.Text('支出（カテゴリ別）', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 4),
          _categoryTable(
            receiptCategories,
            summary.expenseByCategory,
            summary.expense,
          ),
          pw.SizedBox(height: 12),
          pw.Text('収入（カテゴリ別）', style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 4),
          _categoryTable(
            incomeCategories,
            summary.incomeByCategory,
            summary.income,
          ),
          pw.SizedBox(height: 14),
          pw.Text(
            '明細（${sorted.length}件）',
            style: const pw.TextStyle(fontSize: 14),
          ),
          pw.SizedBox(height: 6),
          _table(
            headers: ['日付', '区分', '店舗・摘要', 'カテゴリ', '金額（円）', 'メモ'],
            rows: sorted
                .map(
                  (r) => [
                    _dateFmt.format(r.date),
                    r.kind.label,
                    r.storeName,
                    r.category,
                    _currency.format(r.amount),
                    r.memo,
                  ],
                )
                .toList(),
            rightAlignCols: const {4},
            fontSize: 9,
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

    // 画像のあるレシートは1件1ページで添付
    for (final r in sorted) {
      if (r.imagePath.isEmpty) continue;
      final file = File(r.imagePath);
      if (!await file.exists()) continue;
      final image = pw.MemoryImage(await file.readAsBytes());
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
    final file = await _tempFile('収支報告書_$safeTitle.pdf');
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: '収支報告書 $title',
      ),
    );
  }

  // ---------- 内部ヘルパー ----------

  static String _receiptFileBase(Receipt r, String ext) {
    final shortId = r.id.length >= 6 ? r.id.substring(0, 6) : r.id;
    return 'receipt_${_dateFmt.format(r.date).replaceAll('/', '')}_$shortId.$ext';
  }

  static pw.Widget _categoryTable(
    List<String> categories,
    Map<String, int> byCategory,
    int total,
  ) {
    final rows = categories
        .where((c) => (byCategory[c] ?? 0) != 0)
        .map((c) => [c, _currency.format(byCategory[c] ?? 0)])
        .toList();
    rows.add(['合計', _currency.format(total)]);
    return _table(
      headers: ['カテゴリ', '金額（円）'],
      rows: rows,
      rightAlignCols: const {1},
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

  static Future<File> _tempFile(String name) async {
    final dir = await getTemporaryDirectory();
    return File(p.join(dir.path, name));
  }
}
