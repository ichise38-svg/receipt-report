import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/receipt.dart';

/// クラウド連携（手動送信のみ）
///
/// アプリは「送信先URL」へ収支データと縮小したレシート画像をJSONで送るだけです。
/// 送信先（Google Apps Script / Cloudflare Worker / 自社サーバーなど）で
/// スプレッドシート追記やExcel・PDF保存を行います。
/// 秘密鍵はアプリに埋め込まないため、APIキーの流出リスクはありません。
class CloudSyncService {
  static const _urlKey = 'cloud_endpoint_url';
  static const _tokenKey = 'cloud_token';
  static const _lastSyncKey = 'cloud_last_sync';

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

  /// 指定した収支をクラウドへ送信する（画像は縮小して添付）
  /// 戻り値は送信件数
  static Future<int> upload({
    required List<Receipt> entries,
    required String title,
    required DateTime from,
    required DateTime to,
    required int participants,
    List<String> participantNames = const [],
  }) async {
    final endpoint = await getEndpoint();
    final token = await getToken();
    if (endpoint.isEmpty) {
      throw const CloudSyncException('送信先URLが未設定です。設定から登録してください。');
    }
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.isScheme('https')) {
      throw const CloudSyncException('送信先URLは https:// で始まる必要があります。');
    }

    final payload = {
      'schemaVersion': 1,
      'token': token,
      'title': title,
      'period': {'from': from.toIso8601String(), 'to': to.toIso8601String()},
      'participants': {
        'count': participants,
        'names': participantNames,
      },
      'sentAt': DateTime.now().toIso8601String(),
      'entries': await Future.wait(entries.map(_toPayload)),
    };

    final body = jsonEncode(payload);
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'text/plain; charset=utf-8'},
          body: utf8.encode(body),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSyncException(
        '送信に失敗しました（HTTP ${response.statusCode}）。送信先の設定を確認してください。',
      );
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, DateTime.now().toIso8601String());
    return entries.length;
  }

  /// 接続確認（データは送らず、疎通のみ確認）
  static Future<void> ping() async {
    final endpoint = await getEndpoint();
    final token = await getToken();
    final uri = Uri.tryParse(endpoint);
    if (uri == null || !uri.isScheme('https')) {
      throw const CloudSyncException('送信先URLは https:// で始まる必要があります。');
    }
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'text/plain; charset=utf-8'},
          body: utf8.encode(
            jsonEncode({'schemaVersion': 1, 'token': token, 'ping': true}),
          ),
        )
        .timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudSyncException('接続確認に失敗しました（HTTP ${response.statusCode}）。');
    }
  }

  static Future<Map<String, dynamic>> _toPayload(Receipt r) async {
    final map = <String, dynamic>{
      'id': r.id,
      'kind': r.kind.name,
      'date': r.date.toIso8601String(),
      'storeName': r.storeName,
      'amount': r.amount,
      'category': r.category,
      'memo': r.memo,
      'imageBase64': null,
      'imageMimeType': null,
    };
    if (r.imagePath.isNotEmpty) {
      final encoded = await compressedImageBase64(r.imagePath);
      if (encoded != null) {
        map['imageBase64'] = encoded;
        map['imageMimeType'] = 'image/jpeg';
      }
    }
    return map;
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

class CloudSyncException implements Exception {
  final String message;
  const CloudSyncException(this.message);

  @override
  String toString() => message;
}
