import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/member.dart';
import 'member_dedupe.dart';
import 'receipt_store.dart';

/// 参加者名簿の保存（SharedPreferences）と名簿の写真（端末内のみ・同期しない）
///
/// 削除済み（tombstone）も含めた全件は loadRaw()。画面表示は loadAll()。
class MemberStore {
  static const _key = 'members_v1';
  static const _photoKey = 'roster_photos_v1';

  /// 同期用：削除済みを含む全件
  static Future<List<Member>> loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list.map((e) => Member.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 表示用：削除済みを除く
  static Future<List<Member>> loadAll() async {
    return (await loadRaw()).where((m) => !m.deleted).toList();
  }

  static Future<void> _saveRaw(List<Member> members) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(members.map((m) => m.toJson()).toList()),
    );
  }

  /// 同じ正規化名の別会員がいれば、その会員（ID）を返す（新規追加の前に確認する）
  static Future<Member?> findSameName(String name, {String? exceptId}) async {
    final key = MemberDedupe.normalizeName(name);
    if (key.isEmpty) return null;
    for (final m in await loadAll()) {
      if (m.id == exceptId) continue;
      if (MemberDedupe.normalizeName(m.name) == key) return m;
    }
    return null;
  }

  static Future<void> upsert(Member member) async {
    final all = await loadRaw();
    final index = all.indexWhere((m) => m.id == member.id);
    if (index >= 0) {
      all[index] = member.copyWith(updatedAt: DateTime.now());
    } else {
      all.add(member);
    }
    await _saveRaw(all);
  }

  /// 同じ人（正規化名が同じ）の重複を1件にまとめる。
  /// 残す会員は ID の小さい方。出席記録はイベントごとに新しい方を採用。
  /// 戻り値は削除扱いにした件数。
  static Future<int> mergeDuplicates() async {
    final all = await loadRaw();
    final plan = MemberDedupe.plan(all);
    if (plan.removeCount == 0) return 0;
    final mergedById = {for (final m in plan.merged) m.id: m};
    final dropped = plan.droppedIds.toSet();
    final now = DateTime.now();
    final result = <Member>[];
    for (final m in all) {
      if (dropped.contains(m.id)) {
        result.add(m.deleted ? m : m.copyWith(deleted: true, updatedAt: now));
      } else if (mergedById.containsKey(m.id)) {
        result.add(mergedById[m.id]!);
      } else {
        result.add(m);
      }
    }
    await _saveRaw(result);
    return plan.removeCount;
  }

  static Future<void> delete(String id) async {
    final all = await loadRaw();
    final index = all.indexWhere((m) => m.id == id);
    if (index < 0) return;
    all[index] = all[index].copyWith(deleted: true, updatedAt: DateTime.now());
    await _saveRaw(all);
  }

  /// ファイル読込用：同名は追加しない。追加件数を返す
  static Future<int> addNames(List<String> names) async {
    final all = await loadRaw();
    final existing = all
        .where((m) => !m.deleted)
        .map((m) => MemberDedupe.normalizeName(m.name))
        .toSet();
    var added = 0;
    for (final raw in names) {
      final name = raw.trim();
      final key = MemberDedupe.normalizeName(name);
      if (key.isEmpty || existing.contains(key)) continue;
      all.add(Member(name: name));
      existing.add(key);
      added++;
    }
    await _saveRaw(all);
    return added;
  }

  /// イベントごとの参加状況をまとめて保存する（変更があった人だけ updatedAt を更新）
  /// [attendance] は 会員ID → 参加したか。含まれない会員は変更しない。
  static Future<void> setEventAttendance({
    required String eventName,
    required Map<String, bool> attendance,
  }) async {
    final all = await loadRaw();
    final now = DateTime.now();
    final updated = all.map((m) {
      if (m.deleted || !attendance.containsKey(m.id)) return m;
      final value = attendance[m.id]!;
      if (m.attendsEvent(eventName) == value &&
          m.eventAttendance.containsKey(eventName)) {
        return m;
      }
      final map = Map<String, bool>.of(m.eventAttendance)..[eventName] = value;
      return m.copyWith(eventAttendance: map, updatedAt: now);
    }).toList();
    await _saveRaw(updated);
  }

  /// 全員分を削除（tombstone にして同期で反映）
  static Future<void> clearAll() async {
    final all = await loadRaw();
    final now = DateTime.now();
    final cleared = all
        .map((m) => m.deleted ? m : m.copyWith(deleted: true, updatedAt: now))
        .toList();
    await _saveRaw(cleared);
  }

  /// 同期で受け取った内容を反映する。ローカルの方が新しければ何もしない。
  static Future<bool> applyRemote(Member remote) async {
    final all = await loadRaw();
    final index = all.indexWhere((m) => m.id == remote.id);
    if (index >= 0 && !all[index].updatedAt.isBefore(remote.updatedAt)) {
      return false;
    }
    if (index >= 0) {
      all[index] = remote;
    } else {
      all.add(remote);
    }
    await _saveRaw(all);
    // 別IDで同じ人が届いた場合は1件にまとめる
    if (!remote.deleted) await mergeDuplicates();
    return true;
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
