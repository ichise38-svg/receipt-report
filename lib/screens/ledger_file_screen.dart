import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/app_settings.dart';
import '../services/ledger_file_service.dart';
import '../services/receipt_store.dart';

/// ファイルの新規作成（入力用テンプレート）と、Excelからの取り込み
class LedgerFileScreen extends StatefulWidget {
  const LedgerFileScreen({super.key});

  @override
  State<LedgerFileScreen> createState() => _LedgerFileScreenState();
}

class _LedgerFileScreenState extends State<LedgerFileScreen> {
  bool _busy = false;
  bool _updateCarry = true;
  final _currency = NumberFormat('#,##0', 'ja_JP');
  List<String> _skipped = [];

  @override
  void initState() {
    super.initState();
    _loadSkipped();
  }

  Future<void> _loadSkipped() async {
    final list = await AppSettings.getImportSkipped();
    if (!mounted) return;
    setState(() => _skipped = list);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _createTemplate() async {
    setState(() => _busy = true);
    try {
      final path = await LedgerFileService.saveTemplate();
      if (path != null) {
        _toast('保存しました。');
      } else if (!kIsWeb) {
        _toast('保存をキャンセルしました。');
      }
    } catch (_) {
      _toast('テンプレートを作成できませんでした。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      _toast('ファイルを読み込めませんでした。');
      return;
    }

    setState(() => _busy = true);
    LedgerImportPreview preview;
    try {
      final existing = await ReceiptStore.loadRaw();
      preview = LedgerFileService.parseAnnual(bytes, existing);
    } on FormatException catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
      return;
    } catch (_) {
      _toast('取り込みに失敗しました。ファイル形式を確認してください。');
      if (mounted) setState(() => _busy = false);
      return;
    }
    if (mounted) setState(() => _busy = false);
    if (!mounted) return;

    _updateCarry = preview.hasCarry;
    final ok = await _confirm(preview);
    if (ok != true) return;

    setState(() => _busy = true);
    try {
      await ReceiptStore.addAll(preview.toAdd);
      await AppSettings.setImportSkipped(preview.skippedReasons);
      await _loadSkipped();
      var carryMsg = '';
      if (preview.hasCarry && _updateCarry) {
        await AppSettings.setCarry(
          cash: preview.carryCash!,
          bank: preview.carryBank!,
        );
        carryMsg = '（繰越金も更新しました）';
      }
      _toast('${preview.toAdd.length}件を取り込みました。$carryMsg');
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      _toast('保存できませんでした。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(LedgerImportPreview p) {
    final nothing = p.toAdd.isEmpty && !p.hasCarry;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('取り込み内容の確認'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p.hasCarry) ...[
                  Text(
                    '前年度繰越金（Excelから読み取り）',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text('　現金: ¥${_currency.format(p.carryCash)}'),
                  Text('　口座等: ¥${_currency.format(p.carryBank)}'),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('この繰越金で端末の繰越金を更新する'),
                    value: _updateCarry,
                    onChanged: (v) =>
                        setDialog(() => _updateCarry = v ?? false),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  Text(
                    '繰越金は更新しません（${p.carryReason ?? '読み取れませんでした'}）。'
                    '報告書画面で手入力してください。',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                  const SizedBox(height: 8),
                ],
                if (p.yearMismatchCount > 0)
                  Text(
                    '年がExcelの表の年と違う明細: ${p.yearMismatchCount}件（備考に「年要確認」を付けて取り込みます）',
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                Text('読み取り元のシート: ${p.sheetName}'),
                const SizedBox(height: 8),
                Text('取り込む件数: ${p.toAdd.length}件'),
                Text(
                  '　収入 ${p.incomeCount}件（¥${_currency.format(p.incomeTotal)}）',
                ),
                Text(
                  '　支出 ${p.expenseCount}件（¥${_currency.format(p.expenseTotal)}）',
                ),
                const SizedBox(height: 8),
                Text('重複のため無視: ${p.duplicateCount}件'),
                Text('繰越金行（報告書画面で入力）: ${p.carrySkipped}件'),
                if (p.needsCheckCount > 0)
                  Text(
                    '日付を推定: ${p.needsCheckCount}件（備考に元の表記を残します。後で確認してください）',
                    style: TextStyle(color: Colors.orange.shade800),
                  ),
                if (p.skippedReasons.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '読み取れなかった行: ${p.skippedReasons.length}件（取り込み後も画面に残ります）',
                    style: TextStyle(color: Colors.red.shade700),
                  ),
                  for (final s in p.skippedReasons.take(5)) Text('・$s'),
                  if (p.skippedReasons.length > 5)
                    Text('ほか ${p.skippedReasons.length - 5}件'),
                ],
                if (p.eventReplaced.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '行事別シートを優先（${p.eventReplaced.length}件）:',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    '　${p.eventReplaced.join('、')}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  const Text(
                    '　年間集計の同じ行は、行事別の明細に置き換えて取り込みます（二重計上はしません）。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                if (p.excelBalanceEnd != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Excelの最終残高: ¥${_currency.format(p.excelBalanceEnd)}'
                    '（取り込み後の残高と比べて確認してください）',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: nothing ? null : () => Navigator.pop(ctx, true),
              child: const Text('取り込む'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ファイルの新規作成・取り込み')),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _busy,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _card(
                icon: Icons.note_add,
                title: '新規作成：収支入力テンプレート',
                body:
                    'サンプルと同じ様式（繰越金・月日・摘要・収入・支出・残高・小計・ATM入出金・署名欄）の空のExcelを作成します。'
                    '保存先（端末・OneDriveなどのクラウドフォルダ）を選べます。'
                    '記入後、下の「取り込み」で読み込めます。'
                    '共有画面でOneDriveなどのアプリを選ぶと、そのまま保存できる場合があります。',
                buttonLabel: '報告書の様式を作成・保存先を選ぶ',
                onPressed: _createTemplate,
              ),
              const SizedBox(height: 12),
              _card(
                icon: Icons.file_open,
                title: '取り込み：Excelから収支を追加',
                body:
                    '「2025年集計」のような年間集計の表（月日・摘要・収入・支出の見出し）を読み込みます。'
                    '同じ日付・摘要・金額の既存データは重複として無視します。'
                    '取り込み前に件数を確認できます。'
                    'ファイル選択画面で「OneDrive」（端末にアプリがある場合）を選ぶと、'
                    'OneDrive上のExcelをそのまま読み込めます。',
                buttonLabel: 'Excelを選んで取り込む',
                onPressed: _import,
              ),
              if (_skipped.isNotEmpty) ...[
                const SizedBox(height: 12),
                _skippedCard(),
              ],
              const SizedBox(height: 16),
              const Text(
                '注意：取り込んだ内容は同期の対象になります（同期ボタンで共有されます）。'
                '取り込み後、内容を確認してください。',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 直近の取り込みで読めなかった行・項目の一覧（確認して手入力してください）
  Widget _skippedCard() {
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber, color: Colors.red.shade700),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '読み取れなかった行: ${_skipped.length}件',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Colors.red.shade700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'これらの行は取り込まれていません。Excelを確認して、必要なら報告書や記録画面で手入力してください。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            for (final s in _skipped)
              Text('・$s', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await AppSettings.setImportSkipped([]);
                  if (!mounted) return;
                  setState(() => _skipped = []);
                },
                child: const Text('一覧を消す'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card({
    required IconData icon,
    required String title,
    required String body,
    required String buttonLabel,
    required VoidCallback onPressed,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onPressed, child: Text(buttonLabel)),
          ],
        ),
      ),
    );
  }
}
