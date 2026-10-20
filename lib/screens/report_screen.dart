import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/export_service.dart';

/// 会計報告書作成：期間・対象を指定してPDF出力
class ReportScreen extends StatefulWidget {
  final List<Receipt> receipts;

  const ReportScreen({super.key, required this.receipts});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late DateTime _from;
  late DateTime _to;
  final _titleCtrl = TextEditingController(text: '経費精算');
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');
  final Set<String> _selectedIds = {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final dates = widget.receipts.map((r) => r.date).toList()..sort();
    _from = dates.first;
    _to = dates.last;
    _selectedIds.addAll(widget.receipts.map((r) => r.id));
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  List<Receipt> get _filtered {
    final start = DateTime(_from.year, _from.month, _from.day);
    final end = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    return widget.receipts
        .where((r) =>
            _selectedIds.contains(r.id) &&
            !r.date.isBefore(start) &&
            !r.date.isAfter(end))
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ja'),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _from = picked;
      } else {
        _to = picked;
      }
    });
  }

  Future<void> _export() async {
    final list = _filtered;
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('出力対象のレシートがありません。')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await ExportService.shareReport(
        title: _titleCtrl.text.trim().isEmpty ? '経費精算' : _titleCtrl.text.trim(),
        receipts: list,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('会計報告書の作成に失敗しました。')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final total = list.fold<int>(0, (s, r) => s + r.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('会計報告書を作成')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '報告書のタイトル（用途・案件名）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickDate(true),
                          child: Text('開始 ${_dateFmt.format(_from)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickDate(false),
                          child: Text('終了 ${_dateFmt.format(_to)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text('対象レシート（${list.length}件 / 合計 ¥${_currency.format(total)}）',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...widget.receipts.map((r) {
                    final inRange = !r.date.isBefore(DateTime(
                            _from.year, _from.month, _from.day)) &&
                        !r.date.isAfter(
                            DateTime(_to.year, _to.month, _to.day, 23, 59, 59));
                    return CheckboxListTile(
                      dense: true,
                      enabled: inRange,
                      value: _selectedIds.contains(r.id) && inRange,
                      title: Text('${r.storeName}  ¥${_currency.format(r.amount)}'),
                      subtitle: Text('${_dateFmt.format(r.date)}  ${r.category}'),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedIds.add(r.id);
                        } else {
                          _selectedIds.remove(r.id);
                        }
                      }),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.picture_as_pdf),
                label: Text(_busy ? '作成中...' : '会計報告書（PDF）を作成・共有'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
