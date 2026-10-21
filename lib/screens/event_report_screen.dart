import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/app_settings.dart';
import '../services/event_excel_service.dart';
import '../services/event_report.dart';
import '../services/export_service.dart';
import '../services/member_store.dart';

/// イベント別会計報告書：イベントを選んで PDF / Excel で出力
class EventReportScreen extends StatefulWidget {
  final List<Receipt> entries;

  const EventReportScreen({super.key, required this.entries});

  @override
  State<EventReportScreen> createState() => _EventReportScreenState();
}

class _EventReportScreenState extends State<EventReportScreen> {
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');
  String? _selected;
  int _participants = 0;
  String _mainTitle = AppSettings.defaultMainTitle;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final events = _eventNames;
    if (events.isNotEmpty) _selected = events.first;
    MemberStore.loadAll().then((m) {
      if (mounted) setState(() => _participants = m.length);
    });
    AppSettings.getMainTitle().then((t) {
      if (mounted) setState(() => _mainTitle = t);
    });
  }

  /// イベント名の一覧（新しい登録があるものを上に）
  List<String> get _eventNames {
    final latest = <String, DateTime>{};
    for (final r in widget.entries) {
      if (r.deleted || r.event.trim().isEmpty) continue;
      final name = r.event.trim();
      final cur = latest[name];
      if (cur == null || r.date.isAfter(cur)) latest[name] = r.date;
    }
    final names = latest.keys.toList()
      ..sort((a, b) => latest[b]!.compareTo(latest[a]!));
    return names;
  }

  Future<void> _export({required bool excel}) async {
    final name = _selected;
    if (name == null) return;
    setState(() => _busy = true);
    try {
      if (excel) {
        await EventExcelService.shareWorkbook(
          mainTitle: _mainTitle,
          eventName: name,
          entries: widget.entries,
          participants: _participants,
        );
      } else {
        await ExportService.shareEventReport(
          mainTitle: _mainTitle,
          eventName: name,
          receipts: widget.entries,
          participants: _participants,
        );
      }
    } catch (_) {
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
    final events = _eventNames;
    final report = _selected == null
        ? null
        : EventReport.build(widget.entries, _selected!);

    return Scaffold(
      appBar: AppBar(title: const Text('イベント別の会計報告書')),
      body: SafeArea(
        child: events.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    'イベント名が設定された登録がありません。\n'
                    '支出・収入の登録時に「イベント名」を入力すると、ここで報告書を作成できます。',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: _selected,
                    decoration: const InputDecoration(
                      labelText: 'イベント',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final e in events)
                        DropdownMenuItem(value: e, child: Text(e)),
                    ],
                    onChanged: (v) => setState(() => _selected = v),
                  ),
                  const SizedBox(height: 12),
                  if (report != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${report.entries.length}件'
                              '${report.firstDate == null ? '' : '　${_dateFmt.format(report.firstDate!)}'
                                        '${report.lastDate == report.firstDate ? '' : ' 〜 ${_dateFmt.format(report.lastDate!)}'}'}',
                            ),
                            const SizedBox(height: 8),
                            _row('収入総計', report.incomeTotal),
                            _row('支出総計', report.expenseTotal),
                            const Divider(),
                            _row('差引金額', report.balance, bold: true),
                            const SizedBox(height: 4),
                            Text(
                              '参加者：$_participants名',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
      bottomNavigationBar: events.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy || _selected == null
                            ? null
                            : () => _export(excel: true),
                        icon: const Icon(Icons.table_chart),
                        label: const Text('Excel'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy || _selected == null
                            ? null
                            : () => _export(excel: false),
                        icon: const Icon(Icons.picture_as_pdf),
                        label: Text(_busy ? '作成中...' : 'PDF'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _row(String label, int amount, {bool bold = false}) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text('¥ ${_currency.format(amount)}', style: style),
        ],
      ),
    );
  }
}
