import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_settings.dart';
import 'update_checker.dart';

/// アプリ内の不具合を端末に記録し、同期先（Apps Script）へ送る。
///
/// 送るのは「版・端末種別・画面・エラーの種類・伏せ字済みメッセージ・
/// スタックの上位数行」のみ。金額・店名・摘要・会員名・画像・URL・
/// トークンは送らない。設定でオフにすると、記録も送信も行わない（初期値はオン）。
class BugReporter {
  BugReporter._();

  static const _enabledKey = 'bug_report_enabled';
  static const _storeKey = 'bug_reports_v2';
  static const maxStored = 100;
  static const _maxMessage = 200;
  static const _maxStackLines = 6;

  static bool _installed = false;
  static bool _enabled = true;

  /// 同期的に読める現在の設定（設定画面の表示用）
  static bool get enabled => _enabled;

  /// 起動時に一度だけ呼ぶ。設定を読み、Flutter と非同期の未処理エラーを捕まえる。
  static Future<void> init() async {
    _enabled = await isEnabled();
    if (_installed) return;
    _installed = true;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      unawaited(
        record(
          details.exception,
          details.stack,
          screen: details.library ?? 'flutter',
        ),
      );
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(record(error, stack, screen: 'async'));
      return true;
    };
  }

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, value);
    _enabled = value;
    if (!value) {
      await prefs.remove(_storeKey);
    }
  }

  /// 例外を1件記録する。記録の失敗で本来の処理は止めない。
  static Future<void> record(
    Object error,
    StackTrace? stack, {
    String screen = '',
  }) async {
    try {
      if (!await isEnabled()) return;
      final kind = error.runtimeType.toString();
      final message = redact(error.toString());
      final frames = _stackLines(stack);
      final sig = '$kind|${frames.isEmpty ? '' : frames.first}|$message';
      final now = DateTime.now().toIso8601String();
      final prefs = await SharedPreferences.getInstance();
      final items = _load(prefs);

      final idx = items.indexWhere((e) => e['sig'] == sig);
      if (idx >= 0) {
        final item = items[idx];
        item['count'] = (item['count'] as int) + 1;
        item['last'] = now;
        item['sent'] = false;
      } else {
        items.add({
          'sig': sig,
          'kind': kind,
          'message': message,
          'stack': frames,
          'screen': screen,
          'count': 1,
          'first': now,
          'last': now,
          'sent': false,
        });
      }
      // 上限を超えたら、最後に発生した日時の古いものから削除
      items.sort(
        (a, b) => (a['last'] as String).compareTo(b['last'] as String),
      );
      while (items.length > maxStored) {
        items.removeAt(0);
      }
      await prefs.setString(_storeKey, jsonEncode(items));
    } catch (_) {
      // 記録の失敗は無視する
    }
  }

  /// 未送信の不具合を同期先へ送る。送れたものは送信済みにする。
  /// オフ・同期先未設定・未送信なしのときは何もしない。
  /// 戻り値は送信できた件数。
  static Future<int> flush() async {
    try {
      if (!await isEnabled()) return 0;
      final prefs = await SharedPreferences.getInstance();
      final items = _load(prefs);
      final pending = items.where((e) => e['sent'] != true).toList();
      if (pending.isEmpty) return 0;

      final uri = Uri.parse(await AppSettings.getSyncEndpoint());
      final payload = {
        'action': 'bug',
        'app': {
          'version': UpdateChecker.currentVersion,
          'build': UpdateChecker.currentBuild,
          'platform': _platformName(),
        },
        'reports': pending
            .map(
              (e) => {
                'sig': e['sig'],
                'kind': e['kind'],
                'message': e['message'],
                'stack': e['stack'],
                'screen': e['screen'],
                'count': e['count'],
                'first': e['first'],
                'last': e['last'],
              },
            )
            .toList(),
      };

      final ok = await _send(uri, payload);
      if (!ok) return 0;
      for (final e in pending) {
        e['sent'] = true;
      }
      await prefs.setString(_storeKey, jsonEncode(items));
      return pending.length;
    } catch (_) {
      return 0;
    }
  }

  /// 設定画面で表示する件数
  static Future<({int total, int pending})> counts() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _load(prefs);
    return (
      total: list.length,
      pending: list.where((e) => e['sent'] != true).length,
    );
  }

  /// 数字・メール・URL・長い英数字（トークンらしいもの）を伏せ字にし、長さを制限する。
  static String redact(String text) {
    var s = text.split('\n').first;
    s = s.replaceAll(RegExp(r'https?://\S+'), '<url>');
    s = s.replaceAll(
      RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}'),
      '<mail>',
    );
    s = s.replaceAll(RegExp(r'[A-Za-z0-9_\-]{20,}'), '<token>');
    s = s.replaceAll(RegExp(r'\d[\d,，]*'), '#');
    s = s.replaceAll(
      RegExp(r'file:///\S+|/(?:home|data|storage)/\S+'),
      '<path>',
    );
    if (s.length > _maxMessage) s = s.substring(0, _maxMessage);
    return s;
  }

  static List<String> _stackLines(StackTrace? stack) {
    if (stack == null) return const [];
    return stack
        .toString()
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .take(_maxStackLines)
        .map(
          (l) => l
              .replaceAll(RegExp(r'https?://\S+'), '<url>')
              .replaceAll(
                RegExp(r'file:///\S+|/(?:home|data|storage)/\S+'),
                '<path>',
              ),
        )
        .toList();
  }

  static List<Map<String, dynamic>> _load(SharedPreferences prefs) {
    final raw = prefs.getString(_storeKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      return (jsonDecode(raw) as List)
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String _platformName() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return defaultTargetPlatform.name;
    }
  }

  /// Apps Script の302は手動で追従する（Androidの自動追従による失敗を避けるため）
  static Future<bool> _send(Uri uri, Map<String, dynamic> payload) async {
    final client = http.Client();
    try {
      final req = http.Request('POST', uri)
        ..followRedirects = false
        ..headers['Content-Type'] = 'text/plain; charset=utf-8'
        ..bodyBytes = utf8.encode(jsonEncode(payload));
      final first = await http.Response.fromStream(
        await client.send(req).timeout(const Duration(seconds: 30)),
      );
      var res = first;
      if (first.statusCode >= 300 && first.statusCode < 400) {
        final loc = first.headers['location'];
        if (loc == null || loc.isEmpty) return false;
        res = await client
            .get(uri.resolve(loc))
            .timeout(const Duration(seconds: 30));
      }
      if (res.statusCode < 200 || res.statusCode >= 300) return false;
      final data =
          jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      return data['ok'] == true;
    } catch (_) {
      return false;
    } finally {
      client.close();
    }
  }
}
