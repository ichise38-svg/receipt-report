import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/bank_entry.dart';
import '../models/receipt.dart';
import 'ledger_file_service.dart';

/// 口座の出納（ATM入出金）の保存
///
/// - loadRaw(): 削除済み（tombstone）を含む全件（同期用）
/// - loadAll(): 画面・照合用（削除済みを除き、日付順）
/// 同期は receipts と同じく「更新日時が新しい方を採用」。
class BankStore {
  static const _key = 'bank_entries_v1';

  /// 同期用：削除済みを含む全件。
  /// updatedAt を持たない旧データには今の時刻を付け、1回だけ保存し直す
  /// （次の同期で必ず送信されるようにするため）。
  static Future<List<BankEntry>> loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    final stamp = isoMillis(DateTime.now());
    var migrated = false;
    final entries = <BankEntry>[];
    for (final e in list) {
      final map = Map<String, dynamic>.from(e as Map);
      if (map['updatedAt'] == null) {
        map['updatedAt'] = stamp;
        migrated = true;
      }
      entries.add(BankEntry.fromJson(map));
    }
    if (migrated) await _saveAll(entries);
    return entries;
  }

  /// 表示・照合用：削除済みを除き、日付順
  static Future<List<BankEntry>> loadAll() async {
    final entries = (await loadRaw()).where((e) => !e.deleted).toList();
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

  /// 追加・修正（更新日時は保存時刻にする）
  static Future<void> upsert(BankEntry entry) async {
    final all = await loadRaw();
    final stamped = entry.copyWith(updatedAt: DateTime.now(), deleted: false);
    final index = all.indexWhere((e) => e.id == entry.id);
    if (index >= 0) {
      all[index] = stamped;
    } else {
      all.add(stamped);
    }
    await _saveAll(all);
  }

  /// 既存の口座入金に「集金」判定を一度だけ適用する（既存データの移行）
  /// 判定は取り込みと同じ（摘要の月と同じ月の現金収入の合計が一致）。
  /// 戻り値: 集金に変わった件数
  static Future<int> backfillCollections(List<Receipt> receipts) async {
    final all = await loadRaw();
    final marked = LedgerFileService.markCollections(
      all.where((e) => !e.deleted).toList(),
      receipts,
    );
    final byId = {for (final m in marked) m.id: m};
    var changed = 0;
    for (var i = 0; i < all.length; i++) {
      final m = byId[all[i].id];
      if (m == null || m.collection == all[i].collection) continue;
      all[i] = all[i].copyWith(
        collection: m.collection,
        updatedAt: DateTime.now(),
      );
      if (m.collection) changed++;
    }
    if (changed > 0) await _saveAll(all);
    return changed;
  }

  /// 削除（tombstone として残し、同期で全員に反映させる）
  static Future<void> delete(String id) async {
    final all = await loadRaw();
    final index = all.indexWhere((e) => e.id == id);
    if (index < 0) return;
    all[index] = all[index].copyWith(deleted: true, updatedAt: DateTime.now());
    await _saveAll(all);
  }

  /// 同期で受け取った内容を反映する。ローカルの方が新しければ何もしない。
  /// 戻り値: 反映したら true
  static Future<bool> applyRemote(BankEntry remote) async {
    final all = await loadRaw();
    final index = all.indexWhere((e) => e.id == remote.id);
    if (index >= 0 && !all[index].updatedAt.isBefore(remote.updatedAt)) {
      return false;
    }
    if (index >= 0) {
      all[index] = remote;
    } else {
      all.add(remote);
    }
    await _saveAll(all);
    return true;
  }
}
