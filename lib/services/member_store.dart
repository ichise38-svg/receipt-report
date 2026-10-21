import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/member.dart';
import 'receipt_store.dart';

/// 参加者名簿の保存（SharedPreferences）と名簿の写真（アプリ内ファイル）
class MemberStore {
  static const _key = 'members_v1';
  static const _photoKey = 'roster_photos_v1';

  static Future<List<Member>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Member.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  static Future<void> _saveAll(List<Member> members) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(members.map((m) => m.toJson()).toList()),
    );
  }

  static Future<void> upsert(Member member) async {
    final all = await loadAll();
    final index = all.indexWhere((m) => m.id == member.id);
    if (index >= 0) {
      all[index] = member;
    } else {
      all.add(member);
    }
    await _saveAll(all);
  }

  static Future<void> delete(String id) async {
    final all = await loadAll();
    all.removeWhere((m) => m.id == id);
    await _saveAll(all);
  }

  /// ファイル読込用：同名は追加しない。追加件数を返す
  static Future<int> addNames(List<String> names) async {
    final all = await loadAll();
    final existing = all.map((m) => m.name).toSet();
    var added = 0;
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty || existing.contains(name)) continue;
      all.add(Member(name: name));
      existing.add(name);
      added++;
    }
    await _saveAll(all);
    return added;
  }

  static Future<void> clearAll() async {
    await _saveAll([]);
  }

  static Future<List<String>> loadRosterPhotos() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_photoKey) ?? [];
    return list.where((p) => File(p).existsSync()).toList();
  }

  /// 名簿の写真（撮影した名簿の控え）を保存
  static Future<void> addRosterPhoto(String sourcePath) async {
    final saved = await ReceiptStore.saveImage(sourcePath);
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_photoKey) ?? [];
    list.add(saved);
    await prefs.setStringList(_photoKey, list);
  }

  static Future<void> removeRosterPhoto(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_photoKey) ?? [];
    list.remove(path);
    await prefs.setStringList(_photoKey, list);
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
