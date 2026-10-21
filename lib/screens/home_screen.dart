import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../models/receipt.dart';
import '../services/ledger_summary.dart';
import '../services/member_store.dart';
import '../services/receipt_store.dart';
import 'receipt_detail_screen.dart';
import 'cloud_sync_screen.dart';
import 'member_screen.dart';
import 'receipt_form_screen.dart';
import 'report_screen.dart';

/// ホーム：収支一覧（残高サマリー付き）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Filter { all, expense, income }

class _HomeScreenState extends State<HomeScreen> {
  List<Receipt> _entries = [];
  List<Member> _members = [];
  bool _loading = true;
  _Filter _filter = _Filter.all;
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final list = await ReceiptStore.loadAll();
    final members = await MemberStore.loadAll();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _members = members;
      _loading = false;
    });
  }

  Future<void> _openSync() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CloudSyncScreen()));
    _reload();
  }

  Future<void> _openMembers() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MemberScreen()));
    _reload();
  }

  Future<void> _openForm({EntryKind kind = EntryKind.expense}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReceiptFormScreen(initialKind: kind)),
    );
    if (saved == true) _reload();
  }

  Future<void> _openDetail(Receipt r) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReceiptDetailScreen(receipt: r)),
    );
    if (changed == true) _reload();
  }

  Future<void> _openReport() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReportScreen(entries: _entries)));
  }

  List<Receipt> get _visible {
    switch (_filter) {
      case _Filter.all:
        return _entries;
      case _Filter.expense:
        return _entries.where((e) => !e.isIncome).toList();
      case _Filter.income:
        return _entries.where((e) => e.isIncome).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = LedgerSummary.from(_entries, participants: _members.length);
    final visible = _visible;

    return Scaffold(
      appBar: AppBar(
        title: const Text('収支管理'),
        actions: [
          IconButton(
            tooltip: '参加者名簿',
            icon: const Icon(Icons.groups),
            onPressed: _openMembers,
          ),
          IconButton(
            tooltip: '会員同期',
            icon: const Icon(Icons.sync),
            onPressed: _openSync,
          ),
          IconButton(
            tooltip: '会計報告書を作成',
            icon: const Icon(Icons.summarize),
            onPressed: _entries.isEmpty ? null : _openReport,
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSummary(summary),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: SegmentedButton<_Filter>(
                      segments: const [
                        ButtonSegment(value: _Filter.all, label: Text('すべて')),
                        ButtonSegment(
                          value: _Filter.expense,
                          label: Text('支出'),
                        ),
                        ButtonSegment(value: _Filter.income, label: Text('収入')),
                      ],
                      selected: {_filter},
                      onSelectionChanged: (s) =>
                          setState(() => _filter = s.first),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: visible.isEmpty
                        ? const Center(
                            child: Text(
                              '登録がありません。\n下のボタンから支出・収入を登録してください。',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: visible.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 8),
                            itemBuilder: (context, i) => _buildTile(visible[i]),
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: _loading
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'income',
                  onPressed: () => _openForm(kind: EntryKind.income),
                  icon: const Icon(Icons.add),
                  label: const Text('収入を登録'),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'expense',
                  onPressed: () => _openForm(kind: EntryKind.expense),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('支出を登録'),
                ),
              ],
            ),
    );
  }

  Widget _buildSummary(LedgerSummary s) {
    final scheme = Theme.of(context).colorScheme;
    final balanceColor = s.balance < 0
        ? Colors.red.shade700
        : scheme.onPrimaryContainer;
    return Container(
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
          Text(
            '差引残高（${s.count}件）',
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 2),
          Text(
            '¥ ${_currency.format(s.balance)}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: balanceColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _amountChip('収入', s.income, Colors.green.shade700),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _amountChip('支出', s.expense, Colors.red.shade700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          InkWell(
            onTap: _openMembers,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                s.participants == 0
                    ? '参加人数：未登録（名簿を登録すると1人あたりを表示）'
                    : '参加人数：${s.participants}名　'
                          '1人あたり支出 ¥ ${_currency.format(s.expensePerPerson)}',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _amountChip(String label, int amount, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(
            '¥ ${_currency.format(amount)}',
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildTile(Receipt r) {
    final isIncome = r.isIncome;
    final hasImage = r.imagePath.isNotEmpty && File(r.imagePath).existsSync();
    final color = isIncome ? Colors.green.shade700 : Colors.red.shade700;
    final sign = isIncome ? '+' : '-';
    return Card(
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: hasImage
                ? Image.file(File(r.imagePath), fit: BoxFit.cover)
                : Container(
                    color: color.withValues(alpha: 0.12),
                    child: Icon(
                      isIncome ? Icons.trending_up : Icons.receipt_long,
                      color: color,
                    ),
                  ),
          ),
        ),
        title: Text(r.storeName),
        subtitle: Text(
          '${_dateFmt.format(r.date)}  ${r.kind.label}・${r.category}',
        ),
        trailing: Text(
          '$sign¥${_currency.format(r.amount)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        onTap: () => _openDetail(r),
      ),
    );
  }
}
