import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bank_entry.dart';

/// 口座の出納（ATM入出金）の保存
///
/// 現時点では端末内のみに保存する（クラウド同期の対象外）。
class BankStore {
  static const _key = 'bank_entries_v1';

  static Future<List<BankEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final entries = list
        .map((e) => BankEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    entries.sort((a, b) => a.date.compareTo(b.date));
    return entries;
  }

  static Future<void> _saveAll(List<BankEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }

  /// 追加（同じIDなら修正）
  static Future<void> upsert(BankEntry entry) async {
    final all = await loadAll();
    final index = all.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      all[index] = entry;
    } else {
      all.add(entry);
    }
    await _saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((e) => e.id == id);
    await _saveAll(all);
  }
}
