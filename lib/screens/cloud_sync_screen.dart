import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/member.dart';
import '../models/receipt.dart';
import '../services/cloud_sync_service.dart';
import '../services/member_store.dart';

/// クラウド連携：送信先の設定と、期間を指定した手動送信
class CloudSyncScreen extends StatefulWidget {
  final List<Receipt> entries;

  const CloudSyncScreen({super.key, required this.entries});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _endpointCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  final _titleCtrl = TextEditingController(text: '経費精算');
  final _dateFmt = DateFormat('yyyy/MM/dd');
  final _currency = NumberFormat('#,##0', 'ja_JP');

  late DateTime _from;
  late DateTime _to;
  bool _loading = true;
  bool _busy = false;
  DateTime? _lastSynced;
  List<Member> _members = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final dates = widget.entries.map((e) => e.date).toList()..sort();
    _from = dates.isEmpty ? DateTime(now.year, now.month, 1) : dates.first;
    _to = dates.isEmpty ? now : dates.last;
    _load();
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _tokenCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _endpointCtrl.text = await CloudSyncService.getEndpoint();
    _tokenCtrl.text = await CloudSyncService.getToken();
    _lastSynced = await CloudSyncService.lastSyncedAt();
    _members = await MemberStore.loadAll();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  List<Receipt> get _target {
    final start = DateTime(_from.year, _from.month, _from.day);
    final end = DateTime(_to.year, _to.month, _to.day, 23, 59, 59);
    return widget.entries
        .where((e) => !e.date.isBefore(start) && !e.date.isAfter(end))
        .toList();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _saveSettings() async {
    await CloudSyncService.saveSettings(
      endpoint: _endpointCtrl.text,
      token: _tokenCtrl.text,
    );
    _toast('送信先を保存しました。');
  }

  Future<void> _ping() async {
    await _saveSettings();
    setState(() => _busy = true);
    try {
      await CloudSyncService.ping();
      _toast('接続できました。');
    } on CloudSyncException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('接続できませんでした。URLとネットワークを確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload() async {
    final list = _target;
    if (list.isEmpty) {
      _toast('送信対象の登録がありません。');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('クラウドへ送信しますか？'),
        content: Text('${list.length}件（画像は縮小して送信）を送信します。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('送信'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await _saveSettings();
    setState(() => _busy = true);
    try {
      final count = await CloudSyncService.upload(
        entries: list,
        title: _titleCtrl.text.trim().isEmpty ? '経費精算' : _titleCtrl.text.trim(),
        from: _from,
        to: _to,
        participants: _members.length,
        participantNames: _members.map((m) => m.name).toList(),
      );
      _lastSynced = await CloudSyncService.lastSyncedAt();
      _toast('$count件を送信しました。');
    } on CloudSyncException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('送信に失敗しました。通信状態を確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final total = target.fold<int>(0, (s, e) => e.isIncome ? s : s + e.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('クラウド連携')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '送信先（Google Apps Script / Cloudflare Worker など）',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _endpointCtrl,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: '送信先URL（https://...）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _tokenCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'アクセスキー（任意）',
                      border: OutlineInputBorder(),
                      helperText: '送信データに含めて照合します',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _saveSettings,
                          child: const Text('設定を保存'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _busy ? null : _ping,
                          child: const Text('接続確認'),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  const Text(
                    '送信内容',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: '報告書のタイトル',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: context,
                              initialDate: _from,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              locale: const Locale('ja'),
                            );
                            if (p != null) setState(() => _from = p);
                          },
                          child: Text('開始 ${_dateFmt.format(_from)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final p = await showDatePicker(
                              context: context,
                              initialDate: _to,
                              firstDate: DateTime(2000),
                              lastDate: DateTime(2100),
                              locale: const Locale('ja'),
                            );
                            if (p != null) setState(() => _to = p);
                          },
                          child: Text('終了 ${_dateFmt.format(_to)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      title: Text('送信対象 ${target.length}件'),
                      subtitle: Text('支出合計 ¥${_currency.format(total)}'),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _lastSynced == null
                        ? '最終送信: まだありません'
                        : '最終送信: ${DateFormat('yyyy/MM/dd HH:mm').format(_lastSynced!)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _upload,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(_busy ? '送信中...' : 'クラウドへ送信'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '※ 送信は手動のみです。自動同期は行いません（通信量の節約のため）。',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }
}
