import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../services/app_settings.dart';
import '../services/bank_reconcile.dart';
import '../services/bank_store.dart';
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
import '../widgets/voice_command_sheet.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../services/web_update_checker.dart';

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
  final _voiceCtrl = TextEditingController();
  final _speech = stt.SpeechToText();
  bool _listening = false;
  DateTime? _lastAutoSync;
  bool _checkingUpdate = false;
  DateTime? _lastUpdateCheck;
  bool _updateBadge = false; // 新しい版がある間、設定アイコンに点を出す
  int? _totalBalance; // 合計の残高（繰越金＋口座の出納。現金・口座等の総額）
  int? _bankOnly; // 口座等の残高
  int? _cashOnly; // 手持ち現金の残高
  List<Member> _members = [];
  bool _loading = true;
  _Filter _filter = _Filter.all;
  bool _showWorkPanel = true;
  int _refreshTick = 0; // 入力・保存のたびにビューワーを再計算する
  Timer? _debounceSync; // 入力が落ち着いてから自動同期する
  Timer? _pollSync; // 前面表示中に他メンバーの変更を定期的に取り込む
  bool _syncAgain = false; // 同期中に変更があったら終了後にもう一度同期する
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
    _autoSync();
    _refreshUpdateBadge();
    _checkUpdate();
    _pollSync = Timer.periodic(const Duration(minutes: 2), (_) => _autoSync());
  }

  /// 起動時に1回、前面に戻ったときは30分以上あいた場合に、新しい版があれば案内する
  Future<void> _checkUpdate({bool force = false}) async {
    if (_checkingUpdate) return;
    final last = _lastUpdateCheck;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < const Duration(minutes: 30)) {
      return;
    }
    _checkingUpdate = true;
    _lastUpdateCheck = DateTime.now();
    try {
      if (kIsWeb) {
        final info = await WebUpdateChecker.check(
          appBase: Uri.base,
          currentVersion: UpdateChecker.currentFull,
        );
        if (info == null) return;
        await AppSettings.saveLatestVersion(info.latestVersion);
        if (!mounted) return;
        await _refreshUpdateBadge();
        if (!mounted) return;
        await _showUpdateDialog(info, web: true);
      } else {
        final info = await UpdateChecker.check();
        if (info == null) return;
        await AppSettings.saveLatestVersion(info.latestVersion);
        if (!mounted) return;
        await _refreshUpdateBadge();
        if (!mounted) return;
        await _showUpdateDialog(info, web: false);
      }
    } finally {
      _checkingUpdate = false;
    }
  }

  /// 設定アイコンに出す「新しい版がある」点の表示を読み直す
  Future<void> _refreshUpdateBadge() async {
    final hasNew = await AppSettings.hasNewerVersion(UpdateChecker.currentFull);
    if (!mounted || hasNew == _updateBadge) return;
    setState(() => _updateBadge = hasNew);
  }

  Future<void> _showUpdateDialog(UpdateInfo info, {required bool web}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新しいバージョンがあります'),
        content: Text(
          '最新版 ${info.latestVersion}（いまのバージョン ${info.currentVersion}）が公開されています。\n'
          '${web ? '「更新する」で再読み込みします。' : 'ダウンロードページを開いて更新してください。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('あとで'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (web) {
                WebUpdateChecker.reloadWithFreshFiles(Uri.base);
              } else {
                UpdateChecker.openDownloadPage();
              }
            },
            child: Text(web ? '更新する' : 'ダウンロードページを開く'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _debounceSync?.cancel();
    _pollSync?.cancel();
    _voiceCtrl.dispose();
    _speech.stop();
    super.dispose();
  }

  /// アプリを前面に戻したときも自動同期（直近の同期から5分以上経っている場合のみ）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoSync();
      _checkUpdate();
    }
  }

  /// 起動時・復帰時・定期の自動同期。失敗しても黙って続行（オフラインでも使えるように）
  Future<void> _autoSync() async {
    if (_syncing) return;
    if (!await CloudSyncService.isConfigured()) return;
    final last = _lastAutoSync;
    if (last != null && DateTime.now().difference(last).inSeconds < 60) return;
    _lastAutoSync = DateTime.now();
    await _runSync(showMessage: false);
  }

  /// 入力・編集・削除のあとに呼ぶ。数秒おいてまとめて自動同期する
  void _scheduleSync() {
    _debounceSync?.cancel();
    _debounceSync = Timer(const Duration(seconds: 3), () async {
      if (!await CloudSyncService.isConfigured()) return;
      _lastAutoSync = DateTime.now();
      await _runSync(showMessage: false);
    });
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
    if (_syncing) {
      _syncAgain = true; // 同期中の変更は終了後に送る
      return;
    }
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
    if (_syncAgain) {
      _syncAgain = false;
      _scheduleSync();
    }
  }

  Future<void> _reload() async {
    final list = await ReceiptStore.loadAll();
    final members = await MemberStore.loadAll();
    final bank = await BankStore.loadAll();
    final carry = await AppSettings.getCarry();
    // 合計の残高は口座出納画面と同じ計算（繰越金＋口座の入出金＋現金の増減）
    final bal = BankReconcile.balances(
      carryCash: carry.cash,
      carryBank: carry.bank,
      bankEntries: bank,
      receipts: list,
    );
    if (!mounted) return;
    setState(() {
      _entries = list;
      _members = members;
      _bankOnly = bal.bank;
      _cashOnly = bal.cashOnHand;
      _totalBalance = bal.bank + bal.cashOnHand;
      _loading = false;
      _refreshTick++;
    });
  }

  Future<void> _openBankLedger() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const BankLedgerScreen()));
    _reload();
    _scheduleSync();
  }

  Future<void> _openMembers() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const MemberScreen()));
    _reload();
    _scheduleSync();
  }

  Future<void> _openForm({EntryKind kind = EntryKind.expense}) async {
    final outcome = await Navigator.of(context).push<SaveOutcome>(
      MaterialPageRoute(builder: (_) => ReceiptFormScreen(initialKind: kind)),
    );
    if (outcome != null) {
      _reload();
      _scheduleSync();
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
    if (changed == true) {
      _reload();
      _scheduleSync();
    }
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
    if (imported == true) {
      _reload();
      _scheduleSync();
    }
  }

  Future<void> _openReport() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReportScreen(entries: _entries)));
    // 報告書画面で繰越金を変えた場合に、合計の残高を読み直す
    _reload();
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
            tooltip: _updateBadge ? '設定（新しい版があります）' : '設定（同期先・報告書タイトル）',
            icon: Badge(
              isLabelVisible: _updateBadge,
              smallSize: 8,
              child: const Icon(Icons.settings),
            ),
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
                  SliverToBoxAdapter(child: _buildVoiceInput()),
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

  /// 文章で追加・修正・削除する入力欄。音声はキーボードのマイク（iPhone）または音声ボタン（Android）で話す
  Widget _buildVoiceInput() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: TextField(
        controller: _voiceCtrl,
        textInputAction: TextInputAction.send,
        decoration: InputDecoration(
          hintText: '例：昨日の交通費 1200円 ／ 5月3日の食費を3000円に直す',
          isDense: true,
          border: const OutlineInputBorder(),
          prefixIcon: const Icon(Icons.edit_note),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!kIsWeb && Platform.isAndroid)
                IconButton(
                  tooltip: '音声で入力',
                  icon: Icon(_listening ? Icons.mic : Icons.mic_none),
                  onPressed: _toggleListening,
                ),
              IconButton(
                tooltip: '送信して確認',
                icon: const Icon(Icons.send),
                onPressed: _submitVoice,
              ),
            ],
          ),
        ),
        onSubmitted: (_) => _submitVoice(),
      ),
    );
  }

  /// Android の音声認識。認識した文字を入力欄に入れ、解析は送信ボタンで行う
  Future<void> _toggleListening() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final ok = await _speech.initialize(
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
    );
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('音声入力を使えませんでした。マイクの許可を確認するか、キーボードのマイクで入力してください。'),
            ),
          );
      }
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(
        localeId: 'ja_JP',
        partialResults: true,
      ),
      onResult: (result) {
        if (!mounted) return;
        _voiceCtrl.value = TextEditingValue(
          text: result.recognizedWords,
          selection: TextSelection.collapsed(
            offset: result.recognizedWords.length,
          ),
        );
        if (result.finalResult) setState(() => _listening = false);
      },
    );
  }

  Future<void> _submitVoice() async {
    final text = _voiceCtrl.text.trim();
    if (text.isEmpty) return;
    final saved = await showVoiceCommandSheet(context, text);
    if (!mounted) return;
    if (saved == true) {
      _voiceCtrl.clear();
      _reload();
      _scheduleSync();
    }
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
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
          if (_totalBalance != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '合計の残高（現金＋口座等・繰越金を含む）',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '¥ ${_currency.format(_totalBalance)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: _totalBalance! < 0
                          ? Colors.red.shade700
                          : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '口座等 ¥${_currency.format(_bankOnly)}　'
                    '現金 ¥${_currency.format(_cashOnly)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
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
