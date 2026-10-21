import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/member.dart';
import '../models/receipt.dart';
import 'member_store.dart';
import 'receipt_store.dart';

/// 会員同期（方式A: Google Apps Script）
///
/// 全員が同じ「送信先URL」と「合言葉」を設定し、同期ボタンで送受信を行います。
/// - 送信: 端末の全データ（削除済みを含む）と、未送信のレシート画像
/// - 受信: 前回同期後に変わったデータ（サーバー側の受信時刻で差分を判定）
/// - 競合: 更新日時が新しい方を優先（最後の更新優先）。削除も全員に反映します。
/// 同期は手動のみです（通信量と処理回数を抑えるため）。
class CloudSyncService {
  static const _urlKey = 'cloud_endpoint_url';
  static const _tokenKey = 'cloud_token';
  static const _lastSyncKey = 'cloud_last_sync';
  static const _cursorKey = 'cloud_sync_cursor';
  static const _pushKey = 'cloud_last_push';

  /// 画像は送信前に縮小して転送量・保存コストを抑える
  static const int maxImageSide = 1200;
  static const int jpegQuality = 80;

  static Future<String> getEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_urlKey) ?? '';
  }

  static Future<String> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey) ?? '';
  }

  static Future<void> saveSettings({
    required String endpoint,
    required String token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_urlKey, endpoint.trim());
    await prefs.setString(_tokenKey, token.trim());
  }

  static Future<DateTime?> lastSyncedAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSyncKey);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// 同期を実行する（送信と受信をまとめて行う）
  static Future<SyncResult> sync() async {
    final endpoint = await getEndpoint();
    final token = await getToken();
    if (endpoint.isEmpty) {
      throw const CloudSyncException('送信先URLが未設定です。設定から登録してください。');
    }
    final uri = _validatedUri(endpoint);
    final prefs = await SharedPreferences.getInstance();
    final since = prefs.getInt(_cursorKey) ?? 0;
    // 前回送信以降に変わったものだけを送る（通信量の節約）
    final pushSince =
        DateTime.tryParse(prefs.getString(_pushKey) ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final startedAt = DateTime.now();

    // --- 送信データの作成 ---
    final dateFmt = DateFormat('yyyy-MM-dd');
    final localReceipts = await ReceiptStore.loadRaw();
    final haveImages = <String, String>{};
    var imagesSent = 0;
    final receiptPayload = <Map<String, dynamic>>[];
    for (final r in localReceipts) {
      // 共有先に画像があることは、変更がなくても伝える
      if (!r.deleted && r.imageUrl.isNotEmpty) {
        haveImages[r.id] = r.imageUrl;
      }
      if (!r.updatedAt.isAfter(pushSince)) continue;
      final item = <String, dynamic>{
        'id': r.id,
        'kind': r.kind.name,
        'date': dateFmt.format(r.date),
        'storeName': r.storeName,
        'amount': r.amount,
        'category': r.category,
        'memo': r.memo,
        'createdAt': isoMillis(r.createdAt),
        'updatedAt': isoMillis(r.updatedAt),
        'deleted': r.deleted,
        'imageUrl': r.imageUrl,
        'imageBase64': null,
        'imageMimeType': null,
      };
      if (!r.deleted &&
          r.imagePath.isNotEmpty &&
          await File(r.imagePath).exists()) {
        // 未送信の画像だけ縮小して送る（送信済みは URL のみで足りる）
        if (r.imageUrl.isEmpty) {
          final encoded = await compressedImageBase64(r.imagePath);
          if (encoded != null) {
            item['imageBase64'] = encoded;
            item['imageMimeType'] = 'image/jpeg';
            imagesSent++;
          }
        }
      }
      receiptPayload.add(item);
    }
    final memberPayload = (await MemberStore.loadRaw())
        .where((m) => m.updatedAt.isAfter(pushSince))
        .map((m) => m.toJson())
        .toList();

    final payload = {
      'schemaVersion': 2,
      'token': token,
      'action': 'sync',
      'since': since,
      // 端末が保持している画像（ID→共有URL）。サーバーは差分の画像だけ返す
      'haveImages': haveImages,
      'receipts': receiptPayload,
      'members': memberPayload,
    };

    // --- 送受信 ---
    final data = await _post(
      uri,
      payload,
      timeout: const Duration(seconds: 180),
    );

    // --- 受信データの反映（更新日時が新しい方を採用） ---
    var received = 0;
    final remoteReceipts = (data['receipts'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    for (final j in remoteReceipts) {
      final remote = Receipt.fromJson(j);
      final b64 = j['imageBase64'] as String?;
      final bytes = (b64 == null || b64.isEmpty)
          ? null
          : Uint8List.fromList(base64Decode(b64));
      if (await ReceiptStore.applyRemote(remote, imageBytes: bytes)) {
        received++;
      }
    }

    final remoteMembers = (data['members'] as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>();
    for (final j in remoteMembers) {
      if (await MemberStore.applyRemote(Member.fromJson(j))) {
        received++;
      }
    }

    // 送信した画像の共有URLを記録
    final urlsRaw = data['imageUrls'] as Map<String, dynamic>? ?? const {};
    await ReceiptStore.setImageUrls(
      urlsRaw.map((k, v) => MapEntry(k, v.toString())),
    );

    final serverTime = (data['serverTime'] as num?)?.toInt();
    if (serverTime != null) {
      await prefs.setInt(_cursorKey, serverTime);
    }
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
    await prefs.setString(_pushKey, startedAt.toIso8601String());

    return SyncResult(
      sentReceipts: receiptPayload.length,
      sentImages: imagesSent,
      receivedChanges: received,
    );
  }

  /// 接続確認（データは送らず、合言葉と疎通のみ確認）
  static Future<void> ping() async {
    final endpoint = await getEndpoint();
    final token = await getToken();
    final uri = _validatedUri(endpoint);
    await _post(uri, {
      'schemaVersion': 2,
      'token': token,
      'ping': true,
    }, timeout: const Duration(seconds: 30));
  }

  static Uri _validatedUri(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.isScheme('https')) {
      throw const CloudSyncException('送信先URLは https:// で始まる必要があります。');
    }
    return uri;
  }

  static Future<Map<String, dynamic>> _post(
    Uri uri,
    Map<String, dynamic> payload, {
    required Duration timeout,
  }) async {
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'text/plain; charset=utf-8'},
          body: utf8.encode(jsonEncode(payload)),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSyncException(
        '通信に失敗しました（HTTP ${response.statusCode}）。送信先の設定を確認してください。',
      );
    }

    final Map<String, dynamic> data;
    try {
      data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw const CloudSyncException(
        '送信先の応答を読み取れませんでした。Apps Script の公開設定を確認してください。',
      );
    }
    if (data['ok'] != true) {
      if (data['error'] == 'unauthorized') {
        throw const CloudSyncException('合言葉（アクセスキー）が一致しません。');
      }
      throw CloudSyncException('同期に失敗しました：${data['error'] ?? '不明なエラー'}');
    }
    return data;
  }

  /// 画像を縮小・再圧縮してBase64化（重い処理はIsolateで実行）
  static Future<String?> compressedImageBase64(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return compute(_compressBytes, bytes);
  }

  /// テスト用：同期的に縮小・Base64化（compute と同じ処理）
  @visibleForTesting
  static String? compressBytesForTest(Uint8List bytes) => _compressBytes(bytes);

  static String? _compressBytes(Uint8List bytes) {
    final img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
    if (decoded == null) return null;
    final resized = decoded.width > decoded.height
        ? (decoded.width > maxImageSide
              ? img.copyResize(decoded, width: maxImageSide)
              : decoded)
        : (decoded.height > maxImageSide
              ? img.copyResize(decoded, height: maxImageSide)
              : decoded);
    final out = img.encodeJpg(resized, quality: jpegQuality);
    return base64Encode(out);
  }
}

/// 同期結果
class SyncResult {
  final int sentReceipts;
  final int sentImages;
  final int receivedChanges;

  const SyncResult({
    required this.sentReceipts,
    required this.sentImages,
    required this.receivedChanges,
  });
}

class CloudSyncException implements Exception {
  final String message;
  const CloudSyncException(this.message);

  @override
  String toString() => message;
}
