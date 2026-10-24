import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt.dart';
import 'receipt_merge.dart';

/// レシートの保存・読み込み（SharedPreferences + アプリ内の画像ファイル）
///
/// 削除済み（tombstone）も含めた全件は loadRaw()。画面表示は loadAll()（削除済みを除外）。
class ReceiptStore {
  static const _key = 'receipts_v1';

  /// 同期用：削除済みを含む全件
  static Future<List<Receipt>> loadRaw() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => Receipt.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// 表示用：削除済みを除き、日付の新しい順
  static Future<List<Receipt>> loadAll() async {
    final receipts = (await loadRaw()).where((r) => !r.deleted).toList();
    receipts.sort((a, b) => b.date.compareTo(a.date));
    return receipts;
  }

  static Future<void> _saveRaw(List<Receipt> receipts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(receipts.map((r) => r.toJson()).toList()),
    );
  }

  /// 新規追加（既存IDなら更新）
  /// 画像を差し替えた場合は共有先のURLを無効化し、古い画像ファイルを削除する
  static Future<void> upsert(Receipt receipt) async {
    final all = await loadRaw();
    final index = all.indexWhere((r) => r.id == receipt.id);
    var toSave = receipt;
    if (index >= 0) {
      final existing = all[index];
      final sameImage = existing.imagePath == receipt.imagePath;
      toSave = receipt.copyWith(imageUrl: sameImage ? existing.imageUrl : '');
      if (!sameImage) await _deleteImageFile(existing.imagePath);
      all[index] = toSave;
    } else {
      all.add(toSave);
    }
    await _saveRaw(all);
  }

  /// 撮影・入力の保存。同じ内容（区分・日付・店舗名・金額）が既にあれば二重に作らず、
  /// 写真やイベント名だけを既存明細に反映する。編集中（同じID）はそのまま更新する。
  static Future<SaveOutcome> saveMerged(Receipt draft) async {
    final all = await loadRaw();
    final sameId = all.indexWhere((r) => r.id == draft.id);
    if (sameId >= 0) {
      // 修正（同じID）はそのまま上書き
      await upsert(draft);
      return SaveOutcome.updated;
    }
    final existing = ReceiptMerge.findDuplicate(all, draft);
    final plan = ReceiptMerge.plan(existing, draft);
    if (plan.outcome == SaveOutcome.created) {
      await upsert(draft);
      return SaveOutcome.created;
    }
    if (plan.discardDraftImage) {
      await _deleteImageFile(draft.imagePath);
    }
    if (plan.updated != null) {
      final index = all.indexWhere((r) => r.id == existing!.id);
      all[index] = plan.updated!;
      await _saveRaw(all);
    }
    return plan.outcome;
  }

  /// ファイル取り込み用：まとめて追加（画像なし）
  static Future<void> addAll(List<Receipt> receipts) async {
    if (receipts.isEmpty) return;
    final all = await loadRaw();
    all.addAll(receipts);
    await _saveRaw(all);
  }

  /// 過去の不具合で作られた日付不明（1970年）の明細を削除（tombstone）にする。
  /// 件数を返す。すでに削除済みのものは対象外。
  static Future<int> purgeEpochDated() async {
    final all = await loadRaw();
    var count = 0;
    final now = DateTime.now();
    for (var i = 0; i < all.length; i++) {
      final r = all[i];
      if (r.deleted || r.date.year != 1970) continue;
      all[i] = r.copyWith(
        deleted: true,
        updatedAt: now,
        imagePath: '',
        imageUrl: '',
      );
      count++;
    }
    if (count > 0) await _saveRaw(all);
    return count;
  }

  /// 削除（tombstone として残し、同期で全員に反映させる）
  static Future<void> delete(Receipt receipt) async {
    final all = await loadRaw();
    final tomb = receipt.copyWith(
      deleted: true,
      updatedAt: DateTime.now(),
      imagePath: '',
      imageUrl: '',
    );
    final index = all.indexWhere((r) => r.id == receipt.id);
    if (index >= 0) {
      all[index] = tomb;
    } else {
      all.add(tomb);
    }
    await _saveRaw(all);
    await _deleteImageFile(receipt.imagePath);
  }

  /// 同期で受け取った内容を反映する。ローカルの方が新しければ何もしない。
  /// 戻り値: 反映したら true
  static Future<bool> applyRemote(
    Receipt remote, {
    Uint8List? imageBytes,
  }) async {
    final all = await loadRaw();
    final index = all.indexWhere((r) => r.id == remote.id);
    final local = index >= 0 ? all[index] : null;
    if (local != null && !local.updatedAt.isBefore(remote.updatedAt)) {
      return false;
    }

    var imagePath = '';
    var imageUrl = '';
    if (!remote.deleted) {
      imageUrl = remote.imageUrl;
      if (imageBytes != null) {
        imagePath = await saveBytes(imageBytes);
      } else if (remote.imageUrl.isNotEmpty &&
          local != null &&
          local.imageUrl == remote.imageUrl &&
          local.imagePath.isNotEmpty &&
          await File(local.imagePath).exists()) {
        // 画像が変わっていなければ端末内の画像をそのまま使う
        imagePath = local.imagePath;
      }
    }
    if (local != null &&
        local.imagePath.isNotEmpty &&
        local.imagePath != imagePath) {
      await _deleteImageFile(local.imagePath);
    }

    final merged = remote.copyWith(imagePath: imagePath, imageUrl: imageUrl);
    if (index >= 0) {
      all[index] = merged;
    } else {
      all.add(merged);
    }
    await _saveRaw(all);
    return true;
  }

  /// 共有先へアップロード済みの画像URLを記録する（更新日時は変えない）
  static Future<void> setImageUrls(Map<String, String> urls) async {
    if (urls.isEmpty) return;
    final all = await loadRaw();
    var changed = false;
    for (var i = 0; i < all.length; i++) {
      final url = urls[all[i].id];
      if (url != null && url.isNotEmpty && all[i].imageUrl != url) {
        all[i] = all[i].copyWith(imageUrl: url);
        changed = true;
      }
    }
    if (changed) await _saveRaw(all);
  }

  /// 同期先を変えたとき、旧同期先の画像URLを消して新しい同期先へ画像を送り直す
  static Future<void> clearImageUrls() async {
    final all = await loadRaw();
    var changed = false;
    for (var i = 0; i < all.length; i++) {
      if (all[i].imageUrl.isNotEmpty) {
        all[i] = all[i].copyWith(imageUrl: '');
        changed = true;
      }
    }
    if (changed) await _saveRaw(all);
  }

  static Future<void> _deleteImageFile(String path) async {
    if (path.isEmpty) return;
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 画像をアプリ専用フォルダへコピーして保存パスを返す
  static Future<String> saveImage(String sourcePath) async {
    final dest = await _newImagePath();
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// バイト列を画像ファイルとして保存（同期で受け取った画像用）
  static Future<String> saveBytes(Uint8List bytes) async {
    final dest = await _newImagePath();
    await File(dest).writeAsBytes(bytes, flush: true);
    return dest;
  }

  static Future<String> _newImagePath() async {
    final dir = await getApplicationDocumentsDirectory();
    final receiptDir = Directory(p.join(dir.path, 'receipts'));
    if (!await receiptDir.exists()) {
      await receiptDir.create(recursive: true);
    }
    final fileName = 'receipt_${DateTime.now().microsecondsSinceEpoch}.jpg';
    return p.join(receiptDir.path, fileName);
  }
}
