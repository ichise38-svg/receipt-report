import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/cloud_sync_service.dart';

/// 会員同期：接続先と合言葉の設定、ボタン1つで送受信
class CloudSyncScreen extends StatefulWidget {
  const CloudSyncScreen({super.key});

  @override
  State<CloudSyncScreen> createState() => _CloudSyncScreenState();
}

class _CloudSyncScreenState extends State<CloudSyncScreen> {
  final _dateFmt = DateFormat('yyyy/MM/dd HH:mm');

  bool _loading = true;
  bool _busy = false;
  DateTime? _lastSynced;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _lastSynced = await CloudSyncService.lastSyncedAt();
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _ping() async {
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

  Future<void> _sync() async {
    setState(() => _busy = true);
    try {
      final r = await CloudSyncService.sync();
      _lastSynced = await CloudSyncService.lastSyncedAt();
      _toast(
        '同期しました。送信 ${r.sentReceipts}件（画像${r.sentImages}件）'
        '／受信 ${r.receivedChanges}件の変更',
      );
    } on CloudSyncException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('同期に失敗しました。通信状態を確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会員同期')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    '接続先は自動で設定されています。全員が同じアプリを使えばそのまま同期できます。',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _ping,
                    child: const Text('接続確認'),
                  ),
                  const Divider(height: 32),
                  Text(
                    _lastSynced == null
                        ? '最終同期: まだありません'
                        : '最終同期: ${_dateFmt.format(_lastSynced!)}',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _sync,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync),
                    label: Text(_busy ? '同期中...' : '今すぐ同期'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '・同期は手動のみです（通信量と費用の節約のため）。\n'
                    '・送信と受信を同時に行います。変更の多い方は、同期前に入力内容を確認してください。\n'
                    '・同じ項目を複数人が編集した場合は、最後に保存した内容が残ります。\n'
                    '・削除は全員の端末に反映されます。\n'
                    '・参加者名簿の写真は同期されず、各端末に残ります。',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }
}
