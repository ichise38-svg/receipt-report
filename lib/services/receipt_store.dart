import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt.dart';

/// レシートの保存・読み込み（SharedPreferences + アプリ内の画像ファイル）
class ReceiptStore {
  static const _key = 'receipts_v1';

  static Future<List<Receipt>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final receipts = list
        .map((e) => Receipt.fromJson(e as Map<String, dynamic>))
        .toList();
    receipts.sort((a, b) => b.date.compareTo(a.date));
    return receipts;
  }

  static Future<void> _saveAll(List<Receipt> receipts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(receipts.map((r) => r.toJson()).toList()),
    );
  }

  /// 新規追加（既存IDなら更新）
  static Future<void> upsert(Receipt receipt) async {
    final all = await loadAll();
    final index = all.indexWhere((r) => r.id == receipt.id);
    if (index >= 0) {
      all[index] = receipt;
    } else {
      all.add(receipt);
    }
    await _saveAll(all);
  }

  static Future<void> delete(Receipt receipt) async {
    final all = await loadAll();
    all.removeWhere((r) => r.id == receipt.id);
    await _saveAll(all);
    if (receipt.imagePath.isEmpty) return;
    final file = File(receipt.imagePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 画像をアプリ専用フォルダへコピーして保存パスを返す
  static Future<String> saveImage(String sourcePath) async {
    final dir = await getApplicationDocumentsDirectory();
    final receiptDir = Directory(p.join(dir.path, 'receipts'));
    if (!await receiptDir.exists()) {
      await receiptDir.create(recursive: true);
    }
    final fileName = 'receipt_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final dest = p.join(receiptDir.path, fileName);
    await File(sourcePath).copy(dest);
    return dest;
  }
}
