import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/app_settings.dart';
import '../services/cloud_sync_service.dart';
import '../services/receipt_store.dart';
import '../services/update_checker.dart';
import '../services/web_update_checker.dart';

/// 設定：同期先URL（任意のクラウドのHTTPSエンドポイント）と報告書の主タイトル
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _endpointCtrl = TextEditingController();
  final _titleCtrl = TextEditingController();
  List<SyncPreset> _presets = [];
  bool _loading = true;
  bool _busy = false;
  bool _checkingUpdate = false;

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
    final presets = await AppSettings.getSyncPresets();
    if (!mounted) return;
    setState(() {
      _endpointCtrl.text = url;
      _titleCtrl.text = title;
      _presets = presets;
      _loading = false;
    });
  }

  Future<void> _addPreset() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    final result = await showDialog<SyncPreset>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('同期先の候補を追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '名前（例: OneDrive、Google Apps Script）',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: urlCtrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'URL（https://）',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final url = urlCtrl.text.trim();
              if (name.isEmpty ||
                  !(Uri.tryParse(url)?.isScheme('https') ?? false)) {
                return;
              }
              Navigator.pop(ctx, SyncPreset(name: name, url: url));
            },
            child: const Text('追加'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    urlCtrl.dispose();
    if (result == null) return;
    final updated = [..._presets, result];
    await AppSettings.setSyncPresets(updated);
    if (!mounted) return;
    setState(() => _presets = updated);
    _snack('候補に追加しました。');
  }

  Future<void> _deletePreset(SyncPreset preset) async {
    final updated = _presets.where((p) => p != preset).toList();
    await AppSettings.setSyncPresets(updated);
    if (!mounted) return;
    setState(() => _presets = updated);
  }

  void _usePreset(SyncPreset preset) {
    setState(() => _endpointCtrl.text = preset.url);
    _snack('「${preset.name}」のURLを入力しました。保存を押すと反映されます。');
  }

  /// 設定画面の「更新を確認」: 結果をその場で伝える（Android・Web 共通）
  Future<void> _manualUpdateCheck() async {
    setState(() => _checkingUpdate = true);
    try {
      final info = kIsWeb
          ? await WebUpdateChecker.check(
              appBase: Uri.base,
              currentVersion: UpdateChecker.currentFull,
            )
          : await UpdateChecker.check();
      if (!mounted) return;
      if (info == null) {
        await AppSettings.saveLatestVersion(UpdateChecker.currentFull);
        _snack('最新版です（いまのバージョン ${UpdateChecker.currentFull}）。');
        return;
      }
      await AppSettings.saveLatestVersion(info.latestVersion);
      _snack('新しい版 ${info.latestVersion} があります。');
      if (kIsWeb) {
        WebUpdateChecker.reloadWithFreshFiles(Uri.base);
      } else {
        UpdateChecker.openDownloadPage();
      }
    } catch (_) {
      if (mounted) _snack('確認できませんでした。通信状態を確認してください。');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
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
    if (url.isNotEmpty && !AppSettings.isUsableEndpoint(url)) {
      _snack(
        'このURLは同期先に使えません。Google Apps Script のウェブアプリURL（/exec で終わるURL）を入力してください。',
      );
      return;
    }
    final changed = await AppSettings.setSyncEndpoint(url);
    if (changed) {
      // 旧同期先の画像URLは新しい同期先では無効なので消し、画像を送り直す
      await ReceiptStore.clearImageUrls();
    }
    await AppSettings.setMainTitle(_titleCtrl.text);
    if (!await CloudSyncService.isConfigured()) {
      _snack('保存しました。');
      return;
    }
    // 同期先を設定したら、その場で同期してデータを反映する
    await _syncNow();
  }

  /// 同期を実行し、結果を表示する（設定画面から）
  Future<void> _syncNow() async {
    setState(() => _busy = true);
    try {
      final r = await CloudSyncService.sync();
      _snack('保存して同期しました（送信 ${r.sentReceipts}件・受信 ${r.receivedChanges}件）');
    } on CloudSyncException catch (e) {
      _snack('保存しました。同期は失敗しました：${e.message}');
    } catch (_) {
      _snack('保存しました。同期できませんでした。通信状態を確認してください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                    '関桜会のアプリには同期先が最初から設定されています。入力は不要です。別の同期先を使う場合のみ、ここに Google Apps Script のウェブアプリURL（/exec で終わるURL）を入力してください。空欄のままなら、初期設定の同期先を使います。',
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
                  Text('同期先の候補', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  if (_presets.isEmpty)
                    const Text(
                      '候補はまだありません。下の「候補を追加」から登録できます。',
                      style: TextStyle(fontSize: 12),
                    ),
                  for (final preset in _presets)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.cloud_outlined),
                        title: Text(preset.name),
                        subtitle: Text(
                          preset.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _usePreset(preset),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: '候補から削除',
                          onPressed: () => _deletePreset(preset),
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addPreset,
                    icon: const Icon(Icons.add),
                    label: const Text('候補を追加'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _checkingUpdate ? null : _manualUpdateCheck,
                    icon: const Icon(Icons.system_update_alt),
                    label: Text(_checkingUpdate ? '確認中…' : '更新を確認'),
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
