import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/ledger_summary.dart';
import '../services/receipt_store.dart';

/// 登録・修正画面（支出・収入ともにレシート画像は任意）
/// 読み取り（OCR/AI）は行わず、手入力で登録する方式（通信・AIコストを抑えるため）
class ReceiptFormScreen extends StatefulWidget {
  final Receipt? receipt;
  final EntryKind initialKind;

  const ReceiptFormScreen({
    super.key,
    this.receipt,
    this.initialKind = EntryKind.expense,
  });

  @override
  State<ReceiptFormScreen> createState() => _ReceiptFormScreenState();
}

class _ReceiptFormScreenState extends State<ReceiptFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  final _dateFmt = DateFormat('yyyy/MM/dd');

  late EntryKind _kind;
  String? _imagePath; // 保存済みまたは新規撮影の画像パス（収入は null 可）
  DateTime _date = DateTime.now();
  String _category = receiptCategories.first;
  bool _saving = false;

  // 本件を除く既存データの集計（入力中の残高見込みに使用）
  int _baseIncome = 0;
  int _baseExpense = 0;
  final _numFmt = NumberFormat('#,##0', 'ja_JP');

  bool get _isEdit => widget.receipt != null;
  List<String> get _categories =>
      _kind == EntryKind.income ? incomeCategories : receiptCategories;

  @override
  void initState() {
    super.initState();
    final r = widget.receipt;
    if (r != null) {
      _kind = r.kind;
      _imagePath = r.imagePath.isEmpty ? null : r.imagePath;
      _storeCtrl.text = r.storeName;
      _amountCtrl.text = r.amount.toString();
      _memoCtrl.text = r.memo;
      _date = r.date;
      _category = r.category;
    } else {
      _kind = widget.initialKind;
      _category = _categories.first;
    }
    // 金額入力のたびに残高見込みを更新
    _amountCtrl.addListener(() => setState(() {}));
    _loadBaseTotals();
  }

  Future<void> _loadBaseTotals() async {
    final all = await ReceiptStore.loadAll();
    final others = all.where((e) => e.id != widget.receipt?.id).toList();
    final summary = LedgerSummary.from(others);
    if (!mounted) return;
    setState(() {
      _baseIncome = summary.income;
      _baseExpense = summary.expense;
    });
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _amountCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (picked == null) return;
      final saved = await ReceiptStore.saveImage(picked.path);
      if (!mounted) return;
      setState(() => _imagePath = saved);
    } catch (e) {
      if (!mounted) return;
      _showMessage('画像の取得に失敗しました。カメラ・写真の許可を確認してください。');
    }
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

  void _changeKind(EntryKind kind) {
    setState(() {
      _kind = kind;
      _category = _categories.first;
      if (kind == EntryKind.income) {
        _imagePath = null;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final receipt = Receipt(
        id: widget.receipt?.id,
        kind: _kind,
        imagePath: _kind == EntryKind.expense ? (_imagePath ?? '') : '',
        storeName: _storeCtrl.text.trim(),
        date: _date,
        amount: int.parse(_amountCtrl.text.replaceAll(',', '')),
        category: _category,
        memo: _memoCtrl.text.trim(),
        createdAt: widget.receipt?.createdAt,
      );
      await ReceiptStore.upsert(receipt);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showMessage('保存に失敗しました。');
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final isExpense = _kind == EntryKind.expense;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit ? '${_kind.label}を修正' : (isExpense ? '支出を登録' : '収入を登録'),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('保存'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<EntryKind>(
                segments: const [
                  ButtonSegment(value: EntryKind.expense, label: Text('支出')),
                  ButtonSegment(value: EntryKind.income, label: Text('収入')),
                ],
                selected: {_kind},
                onSelectionChanged: _isEdit
                    ? null
                    : (s) => _changeKind(s.first),
              ),
              const SizedBox(height: 16),
              _buildLedgerPreview(),
              const SizedBox(height: 16),
              if (isExpense) ...[_buildImageArea(), const SizedBox(height: 16)],
              TextFormField(
                controller: _storeCtrl,
                decoration: InputDecoration(
                  labelText: isExpense ? '店舗名' : '取引先・摘要',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? (isExpense ? '店舗名を入力してください' : '摘要を入力してください')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '金額（税込・円）',
                  border: OutlineInputBorder(),
                  prefixText: '¥ ',
                ),
                validator: (v) {
                  final n = int.tryParse((v ?? '').replaceAll(',', ''));
                  if (n == null || n < 0) return '正しい金額を入力してください';
                  return null;
                },
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(4),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: '日付',
                    border: OutlineInputBorder(),
                    suffixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(_dateFmt.format(_date)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey(_kind),
                initialValue: _categories.contains(_category)
                    ? _category
                    : _categories.first,
                decoration: const InputDecoration(
                  labelText: 'カテゴリ',
                  border: OutlineInputBorder(),
                ),
                items: _categories
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _memoCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'メモ（用途・同行者など）',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save),
                label: Text(_saving ? '保存中...' : '保存する'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 入力中の収支見込み（保存前の残高・保存後の残高）
  Widget _buildLedgerPreview() {
    final scheme = Theme.of(context).colorScheme;
    final amount =
        int.tryParse(_amountCtrl.text.replaceAll(',', '').trim()) ?? 0;
    final before = _baseIncome - _baseExpense;
    final isIncome = _kind == EntryKind.income;
    final after = before + (isIncome ? amount : -amount);
    final afterColor = after < 0 ? Colors.red.shade700 : scheme.onSecondaryContainer;
    final textStyle = TextStyle(color: scheme.onSecondaryContainer);

    return Card(
      color: scheme.secondaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('収支の見込み（保存前）', style: textStyle.copyWith(fontSize: 12)),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('現在の残高', style: textStyle.copyWith(fontSize: 12)),
                      Text(
                        '¥ ${_numFmt.format(before)}',
                        style: textStyle.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward, color: scheme.onSecondaryContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('入力後の残高', style: textStyle.copyWith(fontSize: 12)),
                      Text(
                        '¥ ${_numFmt.format(after)}',
                        style: TextStyle(
                          color: afterColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '今回: ${isIncome ? '+' : '-'}¥ ${_numFmt.format(amount)}（${_kind.label}）',
              style: textStyle.copyWith(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageArea() {
    final hasImage = _imagePath != null && File(_imagePath!).existsSync();
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            height: 240,
            width: double.infinity,
            color: Colors.grey.shade200,
            child: hasImage
                ? Image.file(File(_imagePath!), fit: BoxFit.contain)
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.receipt_long, size: 64),
                        SizedBox(height: 8),
                        Text('レシートなし（任意）'),
                      ],
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('撮影'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('写真から選択'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
