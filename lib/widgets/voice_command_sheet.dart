import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';
import '../services/voice_command_parser.dart';

/// 音声・キーボードで入力した文章から、追加・修正・削除の確認を行うシート。
///
/// 解析結果は必ずここで表示し、利用者が承認したものだけを保存する。
/// 修正・削除は一致した候補を一覧で示し、利用者が選んだ1件に対して実行する。
Future<bool?> showVoiceCommandSheet(BuildContext context, String text) {
  final command = VoiceCommandParser.parse(text);
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: _VoiceCommandBody(input: text, command: command),
      ),
    ),
  );
}

class _VoiceCommandBody extends StatefulWidget {
  const _VoiceCommandBody({required this.input, required this.command});

  final String input;
  final VoiceCommand command;

  @override
  State<_VoiceCommandBody> createState() => _VoiceCommandBodyState();
}

class _VoiceCommandBodyState extends State<_VoiceCommandBody> {
  final _currency = NumberFormat('#,##0', 'ja_JP');
  final _dateFmt = DateFormat('yyyy/MM/dd');
  bool _busy = false;
  List<Receipt> _candidates = [];
  Receipt? _selected;
  bool _loadingCandidates = false;

  @override
  void initState() {
    super.initState();
    final c = widget.command;
    if (c.action == VoiceAction.edit || c.action == VoiceAction.delete) {
      _findCandidates();
    }
  }

  Future<void> _findCandidates() async {
    setState(() => _loadingCandidates = true);
    final target = widget.command.target;
    final all = await ReceiptStore.loadAll();
    final matched = target == null
        ? <Receipt>[]
        : all.where(target.matches).toList();
    if (!mounted) return;
    setState(() {
      _candidates = matched;
      _selected = matched.length == 1 ? matched.first : null;
      _loadingCandidates = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, String doneMessage) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      Navigator.of(context).pop(true);
      _toast(doneMessage);
    } catch (_) {
      _toast('保存できませんでした。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.command;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('次の内容で処理します', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text('入力: ${widget.input}', style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        switch (c.action) {
          VoiceAction.add => _addView(c.receipt!),
          VoiceAction.edit => _editView(c),
          VoiceAction.delete => _deleteView(c),
          VoiceAction.unknown => _unknownView(c),
        },
      ],
    );
  }

  Widget _unknownView(VoiceCommand c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.message ?? '内容を読み取れませんでした。'),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('閉じる'),
        ),
      ],
    );
  }

  Widget _addView(Receipt r) {
    final isIncome = r.kind == EntryKind.income;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _row('区分', isIncome ? '収入' : '支出'),
        _row('日付', _dateFmt.format(r.date)),
        _row('摘要', r.storeName),
        _row('費目', r.category),
        _row('金額', '¥${_currency.format(r.amount)}'),
        const SizedBox(height: 12),
        _buttons(
          okLabel: '追加する',
          onOk: _busy
              ? null
              : () => _run(() => ReceiptStore.upsert(r), '追加しました。'),
        ),
      ],
    );
  }

  Widget _editView(VoiceCommand c) {
    if (_loadingCandidates) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_candidates.isEmpty) {
      return _notFound();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('修正後の金額: ¥${_currency.format(c.newAmount)}'),
        const SizedBox(height: 8),
        _candidateList(),
        const SizedBox(height: 12),
        _buttons(
          okLabel: '修正する',
          onOk: (_selected == null || _busy)
              ? null
              : () => _run(() async {
                  final s = _selected!;
                  await ReceiptStore.upsert(
                    s.copyWith(
                      amount: c.newAmount,
                      updatedAt: DateTime.now(),
                      memo: _appendMemo(
                        s.memo,
                        '音声で金額を修正（前: ¥${_currency.format(s.amount)}）',
                      ),
                    ),
                  );
                }, '修正しました。'),
        ),
      ],
    );
  }

  Widget _deleteView(VoiceCommand c) {
    if (_loadingCandidates) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_candidates.isEmpty) {
      return _notFound();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('削除する明細を選んでください。'),
        const SizedBox(height: 8),
        _candidateList(),
        const SizedBox(height: 12),
        _buttons(
          okLabel: '削除する',
          danger: true,
          onOk: (_selected == null || _busy)
              ? null
              : () => _run(() => ReceiptStore.delete(_selected!), '削除しました。'),
        ),
      ],
    );
  }

  Widget _notFound() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('一致する明細が見つかりませんでした。日付や費目を変えて、もう一度入力してください。'),
        const SizedBox(height: 12),
        FilledButton.tonal(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('閉じる'),
        ),
      ],
    );
  }

  Widget _candidateList() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: RadioGroup<String>(
        groupValue: _selected?.id,
        onChanged: (v) {
          if (_busy || v == null) return;
          setState(() {
            _selected = _candidates.firstWhere((r) => r.id == v);
          });
        },
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final r in _candidates)
              RadioListTile<String>(
                dense: true,
                value: r.id,
                title: Text(
                  '${_dateFmt.format(r.date)}  ${r.storeName}  ¥${_currency.format(r.amount)}',
                ),
                subtitle: Text('${r.kind.label}・${r.category}'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(label, style: const TextStyle(color: Colors.grey)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buttons({
    required String okLabel,
    required VoidCallback? onOk,
    bool danger = false,
  }) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700)
                : null,
            onPressed: onOk,
            child: Text(okLabel),
          ),
        ),
      ],
    );
  }

  String _appendMemo(String memo, String add) =>
      memo.isEmpty ? add : '$memo／$add';
}
