import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../models/receipt.dart';
import '../services/member_store.dart';
import '../services/excel_export_service.dart';
import '../services/export_service.dart';
import '../services/ledger_summary.dart';

/// 会計報告書作成：期間・対象を指定して PDF / Excel で出力
class ReportScreen extends StatefulWidget {
  final List<Receipt> entries;

  const ReportScreen({super.key, required this.entries});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  late DateTime _from;
  late DateTime _to;
  final _titleCtrl = TextEditingController(text: '経費精算');
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');
  final Set<String> _excludedIds = {};
  bool _busy = false;
  List<Member> _members = [];
  bool _includeRoster = true; // 名簿を報告書に含めるか

  @override
  void initState() {
    super.initState();
    MemberStore.loadAll().then((m) {
      if (mounted) setState(() => _members = m);
    });
    final now = DateTime.now();
    final dates = widget.entries.map((r) => r.date).toList()..sort();
    _from = dates.isEmpty ? DateTime(now.year, now.month, 1) : dates.first;
    _to = dates.isEmpty ? now : dates.last;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  bool _inRange(Receipt r) {
    final start = DateTime(_from.year, _from.month, _from.day);
    final end = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    return !r.date.isBefore(start) && !r.date.isAfter(end);
  }

  bool _isIncluded(Receipt r) => _inRange(r) && !_excludedIds.contains(r.id);

  List<Receipt> get _filtered =>
      widget.entries.where(_isIncluded).toList()
        ..sort((a, b) => a.date.compareTo(b.date));

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

  int get _participantCount => _members.length;

  List<String> get _rosterNames =>
      _includeRoster ? _members.map((m) => m.name).toList() : const [];

  String get _title =>
      _titleCtrl.text.trim().isEmpty ? '経費精算' : _titleCtrl.text.trim();

  Future<void> _export({required bool excel}) async {
    final list = _filtered;
    if (list.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('出力対象の登録がありません。')));
      return;
    }
    setState(() => _busy = true);
    try {
      if (excel) {
        await ExcelExportService.shareLedger(
          title: _title,
          entries: list,
          from: _from,
          to: _to,
          participants: _participantCount,
          participantNames: _rosterNames,
        );
      } else {
        await ExportService.shareReport(
          title: _title,
          receipts: list,
          from: _from,
          to: _to,
          participants: _participantCount,
          participantNames: _rosterNames,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(excel ? 'Excelの作成に失敗しました。' : 'PDFの作成に失敗しました。')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    final summary = LedgerSummary.from(list, participants: _participantCount);
    final inRangeEntries = widget.entries.where(_inRange).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

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
                    onChanged: (_) => setState(() {}),
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
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '対象 ${list.length}件のプレビュー',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          _previewRow('収入合計', summary.income),
                          _previewRow('支出合計', summary.expense),
                          const Divider(),
                          _previewRow('差引残高', summary.balance, bold: true),
                          const Divider(),
                          Text('参加人数：${_members.length}名'),
                          if (summary.expensePerPerson != null)
                            _previewRow('1人あたり支出', summary.expensePerPerson!),
                          if (_members.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: Text(
                                '※名簿が未登録のため人数は0名です。ホーム右上の名簿から登録できます。',
                                style: TextStyle(fontSize: 12, color: Colors.orange),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('参加者名簿を報告書に含める'),
                    subtitle: Text('${_members.length}名'),
                    value: _includeRoster,
                    onChanged: (v) => setState(() => _includeRoster = v),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '対象の登録（チェックを外すと除外）',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  if (inRangeEntries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('期間内に登録がありません。'),
                    ),
                  ...inRangeEntries.map((r) {
                    final checked = !_excludedIds.contains(r.id);
                    return CheckboxListTile(
                      dense: true,
                      value: checked,
                      title: Text(
                        '${r.storeName}  ${r.isIncome ? '+' : '-'}¥${_currency.format(r.amount)}',
                      ),
                      subtitle: Text(
                        '${_dateFmt.format(r.date)}  ${r.kind.label}・${r.category}',
                      ),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _excludedIds.remove(r.id);
                        } else {
                          _excludedIds.add(r.id);
                        }
                      }),
                    );
                  }),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _export(excel: true),
                      icon: const Icon(Icons.table_chart),
                      label: const Text('Excel'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _export(excel: false),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(_busy ? '作成中...' : 'PDF'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _previewRow(String label, int amount, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text('¥ ${_currency.format(amount)}', style: style),
      ],
    );
  }
}
