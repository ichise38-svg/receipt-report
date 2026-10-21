import 'package:shared_preferences/shared_preferences.dart';

/// アプリの設定（同期先URL・報告書のメインタイトル）を端末に保存する
class AppSettings {
  static const defaultMainTitle = '関桜会　収支報告書';
  static const _endpointKey = 'sync_endpoint';
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
