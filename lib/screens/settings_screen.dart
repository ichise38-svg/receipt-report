import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/cloud_sync_service.dart';

/// 設定：同期先URL（任意のクラウドのHTTPSエンドポイント）と報告書の主タイトル
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _endpointCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final url = await AppSettings.getSyncEndpoint();
    final title = await AppSettings.getMainTitle();
    if (!mounted) return;
    setState(() {
      _endpointCtrl.text = url;
      _titleCtrl.text = title;
      _loading = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final url = _endpointCtrl.text.trim();
    if (url.isNotEmpty && !(Uri.tryParse(url)?.isScheme('https') ?? false)) {
      _snack('同期先URLは https:// で始まる必要があります。');
      return;
    }
    await AppSettings.setSyncEndpoint(url);
    await AppSettings.setMainTitle(_titleCtrl.text);
    _snack('保存しました。');
  }

  Future<void> _testConnection() async {
    await _save();
    setState(() => _busy = true);
    try {
      await CloudSyncService.ping();
      _snack('接続に成功しました。');
    } on CloudSyncException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('接続できませんでした。URLと通信状態を確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '報告書のタイトル',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'メインのタイトル（報告書の左上に表示）',
                      helperText: 'イベント別の報告書では、この下にイベント名のタイトルを表示します。',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '同期先（クラウド）',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '共有するデータの保存先URLを入力します。Google Apps Script のウェブアプリURL（https://…/exec）など、任意のHTTPSエンドポイントに設定できます。全員が同じURLを入力すると同じデータを共有します。',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _endpointCtrl,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '同期先URL（https://）',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _testConnection,
                          icon: _busy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.wifi_tethering),
                          label: const Text('接続テスト'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: const Icon(Icons.save),
                          label: const Text('保存'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}
