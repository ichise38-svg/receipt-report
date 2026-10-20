import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';
import 'receipt_form_screen.dart';
import 'report_screen.dart';
import 'receipt_detail_screen.dart';

/// ホーム：レシート一覧
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Receipt> _receipts = [];
  bool _loading = true;
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await ReceiptStore.loadAll();
    if (!mounted) return;
    setState(() {
      _receipts = list;
      _loading = false;
    });
  }

  Future<void> _openForm() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const ReceiptFormScreen()),
    );
    if (saved == true) _reload();
  }

  Future<void> _openDetail(Receipt r) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReceiptDetailScreen(receipt: r)),
    );
    if (changed == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final total = _receipts.fold<int>(0, (s, r) => s + r.amount);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('レシート管理'),
        actions: [
          IconButton(
            tooltip: '会計報告書を作成',
            icon: const Icon(Icons.summarize),
            onPressed: _receipts.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportScreen(receipts: _receipts),
                      ),
                    ),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('合計（${_receipts.length}件）',
                            style: TextStyle(color: scheme.onPrimaryContainer)),
                        const SizedBox(height: 4),
                        Text(
                          '¥ ${_currency.format(total)}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: scheme.onPrimaryContainer,
                              ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _receipts.isEmpty
                        ? const Center(
                            child: Text('レシートがありません。\n右下のボタンから登録してください。',
                                textAlign: TextAlign.center),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: _receipts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) {
                              final r = _receipts[i];
                              return Card(
                                child: ListTile(
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      width: 56,
                                      height: 56,
                                      child: File(r.imagePath).existsSync()
                                          ? Image.file(File(r.imagePath),
                                              fit: BoxFit.cover)
                                          : const Icon(Icons.receipt),
                                    ),
                                  ),
                                  title: Text(r.storeName),
                                  subtitle: Text(
                                      '${_dateFmt.format(r.date)}  ${r.category}'),
                                  trailing: Text(
                                    '¥${_currency.format(r.amount)}',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold),
                                  ),
                                  onTap: () => _openDetail(r),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openForm,
        icon: const Icon(Icons.camera_alt),
        label: const Text('撮影・登録'),
      ),
    );
  }
}
