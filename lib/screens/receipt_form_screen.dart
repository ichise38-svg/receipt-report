import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../models/receipt.dart';
import '../services/receipt_store.dart';

/// 撮影・新規登録／編集画面
/// 読み取りは行わず、入力内容を手で修正・登録する方式（通信・AIコストを抑えるため）
class ReceiptFormScreen extends StatefulWidget {
  final Receipt? receipt;

  const ReceiptFormScreen({super.key, this.receipt});

  @override
  State<ReceiptFormScreen> createState() => _ReceiptFormScreenState();
}

class _ReceiptFormScreenState extends State<ReceiptFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _storeCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();
  final _dateFmt = DateFormat('yyyy/MM/dd');

  String? _imagePath; // 保存済みまたは新規撮影の画像パス
  DateTime _date = DateTime.now();
  String _category = receiptCategories.first;
  bool _saving = false;

  bool get _isEdit => widget.receipt != null;

  @override
  void initState() {
    super.initState();
    final r = widget.receipt;
    if (r != null) {
      _imagePath = r.imagePath;
      _storeCtrl.text = r.storeName;
      _amountCtrl.text = r.amount.toString();
      _memoCtrl.text = r.memo;
      _date = r.date;
      _category = r.category;
    } else {
      _pickImage(ImageSource.camera);
    }
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_imagePath == null) {
      _showMessage('レシート画像を撮影または選択してください。');
      return;
    }
    setState(() => _saving = true);
    try {
      final receipt = Receipt(
        id: widget.receipt?.id,
        imagePath: _imagePath!,
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
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'レシートを修正' : 'レシートを登録'),
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
              _buildImageArea(),
              const SizedBox(height: 16),
              TextFormField(
                controller: _storeCtrl,
                decoration: const InputDecoration(
                  labelText: '店舗名',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? '店舗名を入力してください' : null,
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
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'カテゴリ',
                  border: OutlineInputBorder(),
                ),
                items: receiptCategories
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
                : const Center(child: Icon(Icons.receipt_long, size: 64)),
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
