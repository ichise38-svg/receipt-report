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

  /// 初期設定の同期先URL（関桜会の Apps Script ウェブアプリURL / 末尾 /exec）。
  /// アプリに組み込むことで、会員は URL を入力しなくても同期できる。
  /// 空の間は同期は無効（設定画面で入力すれば使える）。
  static const builtInSyncEndpoint =
      'https://script.google.com/macros/s/AKfycbxHdxRAf41GBbShw2cAmctX-frRHB6Zivd_8_G3rR3tbIx2CPouU6_ccaDbJNXRgo_ASA/exec';

  /// 共有リンク（ファイルの共有URLなど）は同期先として使えないため除外する
  static bool isUsableEndpoint(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.isScheme('https') || uri.host.isEmpty) {
      return false;
    }
    final host = uri.host.toLowerCase();
    const blockedSuffixes = [
      'onedrive.live.com',
      'live.com',
      '1drv.ms',
      'sharepoint.com',
      'drive.google.com',
      'docs.google.com',
    ];
    for (final s in blockedSuffixes) {
      if (host == s || host.endsWith('.$s')) return false;
    }
    return true;
  }

  /// 同期先URL（利用中の値。保存値が無効・未設定なら初期設定の値）
  static Future<String> getSyncEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_endpointKey) ?? '').trim();
    if (saved.isEmpty || !isUsableEndpoint(saved)) {
      return builtInSyncEndpoint;
    }
    return saved;
  }

  /// 保存されている値が初期設定と違うか（設定画面の表示用）
  static Future<bool> isUsingCustomEndpoint() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getString(_endpointKey) ?? '').trim();
    return saved.isNotEmpty && saved != builtInSyncEndpoint;
  }

  /// 同期先を保存する。URLが変わった場合は同期の基準（受信カーソル・送信済み時刻）を
  /// 消して、次回の同期で全データを新しい同期先へ送り直す。
  /// 戻り値: 同期先が変わったかどうか
  static Future<bool> setSyncEndpoint(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final next = url.trim();
    final changed = (prefs.getString(_endpointKey) ?? '') != next;
    await prefs.setString(_endpointKey, next);
    if (changed) {
      await prefs.remove('cloud_sync_cursor');
      await prefs.remove('cloud_last_push');
      await prefs.remove('cloud_last_sync');
    }
    return changed;
  }

  /// 同期先の候補一覧
  static Future<List<SyncPreset>> getSyncPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_presetsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    return decoded.map(SyncPreset.fromJson).whereType<SyncPreset>().toList();
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

  /// 前年度繰越金（現金・口座等）。報告書・Excelビューワー・口座出納で共有する。
  /// 未保存のときは既定値（前年度の確定額）を返す。
  static const defaultCarryCash = 146353;
  static const defaultCarryBank = 308650;
  static const _carryCashKey = 'carry_cash_v1';
  static const _carryBankKey = 'carry_bank_v1';

  static Future<({int cash, int bank})> getCarry() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      cash: prefs.getInt(_carryCashKey) ?? defaultCarryCash,
      bank: prefs.getInt(_carryBankKey) ?? defaultCarryBank,
    );
  }

  static Future<void> setCarry({required int cash, required int bank}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_carryCashKey, cash);
    await prefs.setInt(_carryBankKey, bank);
  }
}
