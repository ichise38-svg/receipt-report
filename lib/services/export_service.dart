import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/receipt.dart';

final _currency = NumberFormat('#,##0', 'ja_JP');
final _dateFmt = DateFormat('yyyy/MM/dd');

/// 出力処理（JPEG変換・PDF作成・共有）
class ExportService {
  /// レシート画像をJPEGとして書き出して共有
  static Future<void> shareReceiptAsJpeg(Receipt receipt) async {
    final bytes = await File(receipt.imagePath).readAsBytes();
    final jpeg = bytes;
    final tmp = await _tempFile(
      'receipt_${_dateFmt.format(receipt.date).replaceAll('/', '')}_${receipt.id.substring(0, 6)}.jpg',
    );
    await tmp.writeAsBytes(jpeg);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(tmp.path, mimeType: 'image/jpeg')],
        text: '${receipt.storeName} ${_currency.format(receipt.amount)}円',
      ),
    );
  }

  /// 1枚のレシートをPDFにして共有
  static Future<void> shareReceiptAsPdf(Receipt receipt) async {
    final font = await _loadJapaneseFont();
    final doc = pw.Document();
    final imageBytes = await File(receipt.imagePath).readAsBytes();
    final pdfImage = pw.MemoryImage(imageBytes);

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('レシート', style: pw.TextStyle(fontSize: 18)),
            pw.SizedBox(height: 8),
            _infoRow('店舗名', receipt.storeName),
            _infoRow('日付', _dateFmt.format(receipt.date)),
            _infoRow('金額', '${_currency.format(receipt.amount)} 円'),
            _infoRow('カテゴリ', receipt.category),
            if (receipt.memo.isNotEmpty) _infoRow('メモ', receipt.memo),
            pw.SizedBox(height: 12),
            pw.Expanded(
              child: pw.Center(
                child: pw.Image(pdfImage, fit: pw.BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );

    final file = await _tempFile(
      'receipt_${_dateFmt.format(receipt.date).replaceAll('/', '')}_${receipt.id.substring(0, 6)}.pdf',
    );
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/pdf')]),
    );
  }

  /// 会計報告書（一覧表＋カテゴリ別集計＋レシート画像）をPDFにして共有
  static Future<void> shareReport({
    required String title,
    required List<Receipt> receipts,
  }) async {
    final font = await _loadJapaneseFont();
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final total = receipts.fold<int>(0, (sum, r) => sum + r.amount);

    final byCategory = <String, int>{};
    for (final r in receipts) {
      byCategory[r.category] = (byCategory[r.category] ?? 0) + r.amount;
    }

    final doc = pw.Document();

    // 1ページ目：報告書本体
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: theme,
        margin: const pw.EdgeInsets.all(32),
        build: (ctx) => [
          pw.Text('会計報告書', style: pw.TextStyle(fontSize: 20)),
          pw.SizedBox(height: 4),
          pw.Text(title, style: const pw.TextStyle(fontSize: 12)),
          pw.SizedBox(height: 4),
          pw.Text(
            '作成日: ${_dateFmt.format(DateTime.now())}',
            style: const pw.TextStyle(fontSize: 10),
          ),
          pw.SizedBox(height: 16),
          pw.Text('カテゴリ別集計', style: pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['カテゴリ', '金額（円）'],
            data: byCategory.entries
                .map((e) => [e.key, _currency.format(e.value)])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {1: pw.Alignment.centerRight},
          ),
          pw.SizedBox(height: 16),
          pw.Text('明細', style: pw.TextStyle(fontSize: 14)),
          pw.SizedBox(height: 6),
          pw.TableHelper.fromTextArray(
            headers: ['日付', '店舗名', 'カテゴリ', '金額（円）', 'メモ'],
            data: receipts
                .map((r) => [
                      _dateFmt.format(r.date),
                      r.storeName,
                      r.category,
                      _currency.format(r.amount),
                      r.memo,
                    ])
                .toList(),
            headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 9),
            cellAlignment: pw.Alignment.centerLeft,
            cellAlignments: {3: pw.Alignment.centerRight},
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '合計: ${_currency.format(total)} 円（${receipts.length}件）',
              style: pw.TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );

    // 2ページ目以降：レシート画像
    for (final r in receipts) {
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
              _infoRow('日付', _dateFmt.format(r.date)),
              _infoRow('店舗名', r.storeName),
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
    final file = await _tempFile('会計報告書_$safeTitle.pdf');
    await file.writeAsBytes(await doc.save());
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: '会計報告書 $title',
      ),
    );
  }

  // ---------- 内部ヘルパー ----------

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
