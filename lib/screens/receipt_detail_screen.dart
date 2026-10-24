import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/export_service.dart';
import '../services/receipt_merge.dart';
import '../services/receipt_store.dart';
import 'receipt_form_screen.dart';

/// レシート詳細：画像表示、修正、削除、JPEG/PDF出力
class ReceiptDetailScreen extends StatefulWidget {
  final Receipt receipt;

  const ReceiptDetailScreen({super.key, required this.receipt});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  late Receipt _receipt = widget.receipt;
  bool _changed = false;
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  Future<void> _edit() async {
    final saved = await Navigator.of(context).push<SaveOutcome>(
      MaterialPageRoute(builder: (_) => ReceiptFormScreen(receipt: _receipt)),
    );
    if (saved != null) {
      final list = await ReceiptStore.loadAll();
      final updated = list.where((r) => r.id == _receipt.id).firstOrNull;
      if (updated != null && mounted) {
        setState(() => _receipt = updated);
      }
      _changed = true;
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('削除しますか？'),
        content: const Text('このレシートを削除します。元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ReceiptStore.delete(_receipt);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _export(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('書き出しに失敗しました。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _receipt;
    final hasImage = r.imagePath.isNotEmpty && File(r.imagePath).existsSync();
    final color = r.isIncome ? Colors.green.shade700 : Colors.red.shade700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${r.kind.label}の詳細'),
          actions: [
            IconButton(
              tooltip: '修正',
              icon: const Icon(Icons.edit),
              onPressed: _edit,
            ),
            IconButton(
              tooltip: '削除',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (hasImage) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: Colors.grey.shade200,
                    constraints: const BoxConstraints(minHeight: 200),
                    // 長いレシートは2本指で拡大・移動して読める
                    child: InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Image.file(
                        File(r.imagePath),
                        fit: BoxFit.fitWidth,
                        width: double.infinity,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _row('区分', r.kind.label),
              _row(r.isIncome ? '摘要' : '店舗名', r.storeName),
              _row('日付', _dateFmt.format(r.date)),
              _row(
                '金額（税込）',
                '${r.isIncome ? '+' : '-'}¥ ${_currency.format(r.amount)}',
                valueColor: color,
              ),
              _row('カテゴリ', r.category),
              if (r.memo.isNotEmpty) _row('メモ', r.memo),
              const SizedBox(height: 24),
              const Text('書き出し', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Row(
                children: [
                  if (hasImage) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _export(() => ExportService.shareReceiptAsJpeg(r)),
                        icon: const Icon(Icons.image),
                        label: const Text('JPEG'),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _export(() => ExportService.shareReceiptAsPdf(r)),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: const Text('PDF'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 16, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
