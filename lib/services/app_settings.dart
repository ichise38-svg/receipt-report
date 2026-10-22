import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 同期先の候補（名前とURLの組）
class SyncPreset {
  const SyncPreset({required this.name, required this.url});

  final String name;
  final String url;

  Map<String, dynamic> toJson() => {'name': name, 'url': url};

  static SyncPreset? fromJson(Object? json) {
    if (json is! Map) return null;
    final name = (json['name'] as String?)?.trim() ?? '';
    final url = (json['url'] as String?)?.trim() ?? '';
    if (name.isEmpty || url.isEmpty) return null;
    return SyncPreset(name: name, url: url);
  }
}

/// アプリの設定（同期先URL・同期先の候補・報告書のメインタイトル）を端末に保存する
class AppSettings {
  static const defaultMainTitle = '関桜会　収支報告書';
  static const _endpointKey = 'sync_endpoint';
  static const _presetsKey = 'sync_endpoint_presets';
  static const _mainTitleKey = 'report_main_title';

  /// 同期先URL（未設定なら空文字）
  static Future<String> getSyncEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString(_endpointKey) ?? '').trim();
  }

  static Future<void> setSyncEndpoint(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_endpointKey, url.trim());
  }

  /// 同期先の候補一覧
  static Future<List<SyncPreset>> getSyncPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_presetsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded
        .map(SyncPreset.fromJson)
        .whereType<SyncPreset>()
        .toList();
  }

  static Future<void> setSyncPresets(List<SyncPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _presetsKey,
      jsonEncode(presets.map((p) => p.toJson()).toList()),
    );
  }

  /// 報告書の主タイトル（左上に表示される。年間・イベント別の両方）
  static Future<String> getMainTitle() async {
    final prefs = await SharedPreferences.getInstance();
    final v = (prefs.getString(_mainTitleKey) ?? '').trim();
    return v.isEmpty ? defaultMainTitle : v;
  }

  static Future<void> setMainTitle(String title) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mainTitleKey, title.trim());
  }
}
