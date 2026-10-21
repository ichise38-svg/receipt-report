import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/receipt_merge.dart';
import '../services/receipt_store.dart';

/// ホーム画面に置く簡易入力パネル（画像なし・手入力）
///
/// 入力内容はビューワーに即反映されるよう、保存のたびに [onSaved] を呼びます。
/// レシート画像を付けたい場合は従来の登録画面を使ってください。
class QuickEntryPanel extends StatefulWidget {
  final VoidCallback onSaved;
  final List<String> knownEvents;

  const QuickEntryPanel({
    super.key,
    required this.onSaved,
    required this.knownEvents,
  });

  @override
  State<QuickEntryPanel> createState() => _QuickEntryPanelState();
}

class _QuickEntryPanelState extends State<QuickEntryPanel> {
  final _formKey = GlobalKey<FormState>();
  final _storeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  final _eventCtrl = TextEditingController();
  final _dateFmt = DateFormat('yyyy/MM/dd');

  EntryKind _kind = EntryKind.expense;
  DateTime _date = DateTime.now();
  String _category = receiptCategories.first;
  bool _saving = false;

  List<String> get _categories =>
      _kind == EntryKind.income ? incomeCategories : receiptCategories;

  @override
  void dispose() {
    _storeCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    _eventCtrl.dispose();
    super.dispose();
  }

  void _changeKind(EntryKind kind) {
    setState(() {
      _kind = kind;
      _category = _categories.first;
    });
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

  void _clear() {
    _storeCtrl.clear();
    _amountCtrl.clear();
    _memoCtrl.clear();
    setState(() => _date = DateTime.now());
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final receipt = Receipt(
        kind: _kind,
        imagePath: '',
        storeName: _storeCtrl.text.trim(),
        date: _date,
        amount: int.parse(_amountCtrl.text.replaceAll(',', '').trim()),
        category: _category,
        memo: _memoCtrl.text.trim(),
        event: _eventCtrl.text.trim(),
      );
      final outcome = await ReceiptStore.saveMerged(receipt);
      if (!mounted) return;
      _clear();
      setState(() => _saving = false);
      widget.onSaved();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(saveMessage(outcome))));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('保存に失敗しました。')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = _kind == EntryKind.expense;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<EntryKind>(
            segments: const [
              ButtonSegment(value: EntryKind.expense, label: Text('支出')),
              ButtonSegment(value: EntryKind.income, label: Text('収入')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => _changeKind(s.first),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: InkWell(
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
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextFormField(
                  controller: _amountCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '金額（円）',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    final n = int.tryParse(
                      (v ?? '').replaceAll(',', '').trim(),
                    );
                    if (n == null || n < 0) return '金額を入力';
                    return null;
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _storeCtrl,
            decoration: InputDecoration(
              labelText: isExpense ? '店舗名・摘要' : '取引先・摘要',
              isDense: true,
              border: const OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? '摘要を入力' : null,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_kind),
                  initialValue: _categories.contains(_category)
                      ? _category
                      : _categories.first,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'カテゴリ',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final c in _categories)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Autocomplete<String>(
                  initialValue: TextEditingValue(text: _eventCtrl.text),
                  optionsBuilder: (value) {
                    final q = value.text.trim();
                    return widget.knownEvents.where(
                      (e) => q.isEmpty || e.contains(q),
                    );
                  },
                  onSelected: (v) => _eventCtrl.text = v,
                  fieldViewBuilder: (context, controller, focusNode, _) {
                    return TextFormField(
                      controller: controller,
                      focusNode: focusNode,
                      onChanged: (v) => _eventCtrl.text = v,
                      decoration: const InputDecoration(
                        labelText: 'イベント名（任意）',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: _memoCtrl,
            decoration: const InputDecoration(
              labelText: 'メモ（任意）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save, size: 18),
                  label: Text(_saving ? '保存中...' : '保存して反映'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _saving ? null : _clear,
                child: const Text('クリア'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'レシート画像を付ける場合は「支出を登録」から入力してください。',
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }
}
