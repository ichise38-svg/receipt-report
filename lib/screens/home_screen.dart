import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../services/cloud_sync_service.dart';
import '../models/receipt.dart';
import '../services/ledger_summary.dart';
import '../services/member_store.dart';
import '../services/receipt_store.dart';
import 'chart_screen.dart';
import 'event_report_screen.dart';
import 'excel_viewer_screen.dart';
import 'ledger_file_screen.dart';
import 'receipt_detail_screen.dart';
import 'member_screen.dart';
import 'receipt_form_screen.dart';
import 'report_screen.dart';
import 'settings_screen.dart';
import '../widgets/quick_entry_panel.dart';
import '../services/event_report.dart';
import '../services/receipt_merge.dart';
import 'bank_ledger_screen.dart';
import '../services/update_checker.dart';

/// ホーム：収支一覧（残高サマリー付き）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _Filter { all, expense, income }

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<Receipt> _entries = [];
  bool _syncing = false;
  DateTime? _lastAutoSync;
  bool _updateChecked = false;
  List<Member> _members = [];
  bool _loading = true;
  _Filter _filter = _Filter.all;
  bool _showWorkPanel = true;
  int _refreshTick = 0; // 入力・保存のたびにビューワーを再計算する
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
    _autoSync();
    _checkUpdate();
  }

  /// 起動時に1回だけ、新しいバージョンがあれば案内する
  Future<void> _checkUpdate() async {
    if (_updateChecked) return;
    _updateChecked = true;
    final info = await UpdateChecker.check();
    if (info == null || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新しいバージョンがあります'),
        content: Text(
          '最新版 ${info.latestVersion}（いまのバージョン ${info.currentVersion}）が公開されています。\n'
          'ダウンロードページを開いて更新してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('あとで'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              UpdateChecker.openDownloadPage();
            },
            child: const Text('ダウンロードページを開く'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// アプリを前面に戻したときも自動同期（直近の同期から5分以上経っている場合のみ）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoSync();
  }

  /// 起動時・復帰時の自動同期。失敗しても黙って続行（オフラインでも使えるように）
  Future<void> _autoSync() async {
    if (!await CloudSyncService.isConfigured()) return;
    final last = _lastAutoSync;
    if (last != null && DateTime.now().difference(last).inMinutes < 5) return;
    _lastAutoSync = DateTime.now();
    await _runSync(showMessage: false);
  }

  /// 同期ボタン（手動）。結果を必ず表示する
  Future<void> _manualSync() async {
    if (!await CloudSyncService.isConfigured()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('同期先が未設定です。「設定」から同期先URLを入力してください。')),
        );
      return;
    }
    await _runSync(showMessage: true);
  }

  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
    // 設定画面で同期先を保存すると同期が走るため、表示を読み直す
    await _reload();
    _autoSync();
  }

  Future<void> _runSync({required bool showMessage}) async {
    if (_syncing) return;
    setState(() => _syncing = true);
    String message;
    try {
      final r = await CloudSyncService.sync();
      message = '同期しました（送信 ${r.sentReceipts}件・受信 ${r.receivedChanges}件）';
      await _reload();
    } on CloudSyncException catch (e) {
      message = e.message;
    } catch (_) {
      message = '同期できませんでした。通信状態を確認してください。';
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
    if (showMessage && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _reload() async {
    final list = await ReceiptStore.loadAll();
    final members = await MemberStore.loadAll();
    if (!mounted) return;
    setState(() {
      _entries = list;
      _members = members;
      _loading = false;
      _refreshTick++;
    });
  }

  Future<void> _openBankLedger() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BankLedgerScreen()));
    _reload();
  }

  Future<void> _openMembers() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MemberScreen()));
    _reload();
  }

  Future<void> _openForm({EntryKind kind = EntryKind.expense}) async {
    final outcome = await Navigator.of(context).push<SaveOutcome>(
      MaterialPageRoute(builder: (_) => ReceiptFormScreen(initialKind: kind)),
    );
    if (outcome != null) {
      _reload();
      if (mounted && outcome != SaveOutcome.created) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(saveMessage(outcome))));
      }
    }
  }

  Future<void> _openDetail(Receipt r) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ReceiptDetailScreen(receipt: r)),
    );
    if (changed == true) _reload();
  }

  Future<void> _openEventReport() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => EventReportScreen(entries: _entries)),
    );
  }

  Future<void> _openChart() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChartScreen()));
  }

  Future<void> _openLedgerFile() async {
    final imported = await Navigator.of(
      context,
    ).push<bool>(MaterialPageRoute(builder: (_) => const LedgerFileScreen()));
    if (imported == true) _reload();
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
            tooltip: '設定（同期先・報告書タイトル）',
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
          IconButton(
            tooltip: '同期',
            icon: _syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
            onPressed: _syncing ? null : _manualSync,
          ),
          IconButton(
            tooltip: '収支グラフ',
            icon: const Icon(Icons.bar_chart),
            onPressed: _openChart,
          ),

          PopupMenuButton<String>(
            tooltip: 'ファイル',
            icon: const Icon(Icons.folder_open),
            onSelected: (v) {
              if (v == 'file') _openLedgerFile();
              if (v == 'bank') _openBankLedger();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'file', child: Text('ファイルの新規作成・取り込み')),
              PopupMenuItem(value: 'bank', child: Text('口座の出納・照合（ATM入出金）')),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: '会計報告書',
            icon: const Icon(Icons.summarize),
            onSelected: (v) {
              if (v == 'annual') _openReport();
              if (v == 'event') _openEventReport();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'annual', child: Text('年間の収支報告書')),
              PopupMenuItem(value: 'event', child: Text('イベント別の会計報告書')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _buildSummary(summary)),
                  if (_showWorkPanel)
                    SliverToBoxAdapter(child: _buildWorkPanel()),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SegmentedButton<_Filter>(
                        segments: const [
                          ButtonSegment(value: _Filter.all, label: Text('すべて')),
                          ButtonSegment(
                            value: _Filter.expense,
                            label: Text('支出'),
                          ),
                          ButtonSegment(
                            value: _Filter.income,
                            label: Text('収入'),
                          ),
                        ],
                        selected: {_filter},
                        onSelectionChanged: (s) =>
                            setState(() => _filter = s.first),
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 8)),
                  if (visible.isEmpty)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Text(
                          '登録がありません。\n下のボタンから支出・収入を登録してください。',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                      sliver: SliverList.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
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

  /// 入力とExcelビューワーを並べた作業パネル（入力すると下のシートにすぐ反映）
  Widget _buildWorkPanel() {
    final scheme = Theme.of(context).colorScheme;
    final events = EventReport.namesOf(_entries);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      constraints: const BoxConstraints(maxHeight: 620),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '入力 → すぐ下のExcelに反映',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            QuickEntryPanel(knownEvents: events, onSaved: _reload),
            const Divider(height: 24),
            ExcelViewerScreen(embedded: true, refreshKey: _refreshTick),
          ],
        ),
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => setState(() => _showWorkPanel = !_showWorkPanel),
              icon: Icon(
                _showWorkPanel ? Icons.expand_less : Icons.table_chart,
                size: 18,
              ),
              label: Text(
                _showWorkPanel ? '入力とExcelビューワーを閉じる' : '入力しながらExcelで確認',
              ),
            ),
          ),
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
