import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../models/bank_entry.dart';
import '../models/receipt.dart';
import '../services/app_settings.dart';
import '../services/bank_reconcile.dart';
import '../services/bank_store.dart';
import '../services/receipt_store.dart';

/// 口座の出納（ATM入出金）と、口座払いの明細との照合
///
/// 手入力で修正した口座の出納を入力し、デビットカードの支出と突き合わせます。
class BankLedgerScreen extends StatefulWidget {
  const BankLedgerScreen({super.key});

  @override
  State<BankLedgerScreen> createState() => _BankLedgerScreenState();
}

class _BankLedgerScreenState extends State<BankLedgerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  List<BankEntry> _bank = [];
  List<Receipt> _receipts = [];
  bool _loading = true;
  int _carryCash = AppSettings.defaultCarryCash;
  int _carryBank = AppSettings.defaultCarryBank;

  final _dateFmt = DateFormat('yyyy/MM/dd');
  final _numFmt = NumberFormat('#,##0', 'ja_JP');

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _reload();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final bank = await BankStore.loadAll();
    final receipts = await ReceiptStore.loadAll();
    final carry = await AppSettings.getCarry();
    if (!mounted) return;
    setState(() {
      _bank = bank;
      _receipts = receipts;
      _carryCash = carry.cash;
      _carryBank = carry.bank;
      _loading = false;
    });
  }

  Future<void> _openEditor({BankEntry? entry}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _BankEntryDialog(entry: entry),
    );
    if (saved == true) _reload();
  }

  Future<void> _delete(BankEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('出納を削除しますか？'),
        content: Text(
          '${_dateFmt.format(entry.date)}  ${entry.label}  ¥${_numFmt.format(entry.amount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('戻る'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await BankStore.delete(entry.id);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('口座の出納・照合'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: '出納（ATM入出金）'),
            Tab(text: '照合・残高'),
          ],
        ),
      ),
      floatingActionButton: _tabs.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add),
              label: const Text('出納を追加'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabs,
              children: [_buildList(), _buildReconcile()],
            ),
    );
  }

  Widget _buildList() {
    if (_bank.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            '口座の出納はまだありません。\n「出納を追加」から入金・出金・現金引出を入力してください。',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: _bank.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final b = _bank[i];
        final isIn = b.kind == BankEntryKind.deposit;
        return ListTile(
          leading: Icon(
            isIn ? Icons.south_west : Icons.north_east,
            color: isIn ? Colors.green.shade700 : Colors.red.shade700,
          ),
          title: Text(b.label.isEmpty ? b.kind.label : b.label),
          subtitle: Text('${_dateFmt.format(b.date)}　${b.kind.label}'),
          trailing: Text(
            '${isIn ? '+' : '-'}¥${_numFmt.format(b.amount)}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          onTap: () => _openEditor(entry: b),
          onLongPress: () => _delete(b),
        );
      },
    );
  }

  Widget _buildReconcile() {
    final bal = BankReconcile.balances(
      carryCash: _carryCash,
      carryBank: _carryBank,
      bankEntries: _bank,
      receipts: _receipts,
    );
    final lines = BankReconcile.reconcile(
      receipts: _receipts,
      bankEntries: _bank,
    );
    final problems = lines
        .where((l) => l.status != ReconcileStatus.matched)
        .toList();
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '残高（全期間）',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                _balanceRow('口座', bal.bank),
                _balanceRow('手持ち現金', bal.cashOnHand),
                const Divider(),
                _balanceRow('口座＋手持ち現金', bal.bank + bal.cashOnHand, bold: true),
                const SizedBox(height: 4),
                Text(
                  '繰越金は報告書・Excelビューワーで入力した値（口座等・現金）を使用しています。',
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '照合結果：口座払いの明細 と 口座の出金（日付・金額）',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (lines.isEmpty)
          const Text('口座払いの明細も口座の出金もありません。')
        else if (problems.isEmpty)
          Text(
            'すべて一致しています（${lines.length}件）。',
            style: TextStyle(color: Colors.green.shade800),
          )
        else
          Text(
            '確認が必要な項目が ${problems.length} 件あります。',
            style: TextStyle(color: Colors.red.shade700),
          ),
        const SizedBox(height: 8),
        for (final l in lines) _reconcileTile(l),
      ],
    );
  }

  Widget _balanceRow(String label, int value, {bool bold = false}) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      color: value < 0 ? Colors.red.shade700 : null,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('¥ ${_numFmt.format(value)}', style: style),
        ],
      ),
    );
  }

  Widget _reconcileTile(ReconcileLine l) {
    final (IconData icon, Color color, String text) = switch (l.status) {
      ReconcileStatus.matched => (
        Icons.check_circle,
        Colors.green.shade700,
        '一致',
      ),
      ReconcileStatus.amountMismatch => (
        Icons.error,
        Colors.orange.shade800,
        '金額が違います（差 ¥${_numFmt.format(l.difference.abs())}）',
      ),
      ReconcileStatus.missingInBank => (
        Icons.warning,
        Colors.red.shade700,
        '口座の出納に出金がありません',
      ),
      ReconcileStatus.missingInLedger => (
        Icons.help_outline,
        Colors.red.shade700,
        '対応する口座払いの明細がありません',
      ),
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: color),
        title: Text(l.label.isEmpty ? '（摘要なし）' : l.label),
        subtitle: Text(
          '${_dateFmt.format(l.date)}　明細 ¥${_numFmt.format(l.ledgerAmount)} / 出納 ¥${_numFmt.format(l.bankAmount)}\n$text',
        ),
        isThreeLine: true,
      ),
    );
  }
}

/// 出納の入力ダイアログ（入金・出金・現金引出）
class _BankEntryDialog extends StatefulWidget {
  final BankEntry? entry;
  const _BankEntryDialog({this.entry});

  @override
  State<_BankEntryDialog> createState() => _BankEntryDialogState();
}

class _BankEntryDialogState extends State<_BankEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _dateFmt = DateFormat('yyyy/MM/dd');
  late BankEntryKind _kind;
  late DateTime _date;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _kind = e?.kind ?? BankEntryKind.withdraw;
    _date = e?.date ?? DateTime.now();
    _labelCtrl.text = e?.label ?? '';
    _amountCtrl.text = e?.amount.toString() ?? '';
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('ja'),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    await BankStore.upsert(
      BankEntry(
        id:
            widget.entry?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        date: _date,
        kind: _kind,
        label: _labelCtrl.text.trim(),
        amount: int.parse(_amountCtrl.text.replaceAll(',', '').trim()),
      ),
    );
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.entry == null ? '出納を追加' : '出納を修正'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<BankEntryKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: BankEntryKind.deposit,
                    label: Text('入金'),
                  ),
                  ButtonSegment(
                    value: BankEntryKind.withdraw,
                    label: Text('出金'),
                  ),
                  ButtonSegment(
                    value: BankEntryKind.cashOut,
                    label: Text('現金引出'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '日付',
                    isDense: true,
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  child: Text(_dateFmt.format(_date)),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _labelCtrl,
                decoration: const InputDecoration(
                  labelText: '摘要（例: 1月、2月集金分・カード出金）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '金額（円）',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').replaceAll(',', '').trim());
                  if (n == null || n <= 0) return '1円以上の金額を入力';
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
