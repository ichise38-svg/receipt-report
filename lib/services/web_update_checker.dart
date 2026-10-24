import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'update_checker.dart';

/// iPhone などの Web 版（ホーム画面に追加したアプリ）用の更新確認。
///
/// 公開先の `version.json`（ビルド時に作られる）を取りに行き、
/// アプリに入っている版と比べる。取得に失敗しても黙って null を返す。
class WebUpdateChecker {
  WebUpdateChecker._();

  /// 版の確認は、同じ公開先の version.json を毎回取り直す（キャッシュを避ける）
  static Uri versionUri(Uri base, {int? nowMs}) {
    final stamp = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return base
        .resolve('version.json')
        .replace(queryParameters: {'t': '$stamp'});
  }

  /// 公開版の版番号（例: "1.0.2"）を取り出す。読めなければ null。
  static String? parseVersion(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final v = decoded['version'];
      if (v is! String) return null;
      final trimmed = v.trim();
      return RegExp(r'^[0-9]+(\.[0-9]+)*$').hasMatch(trimmed) ? trimmed : null;
    } catch (_) {
      return null;
    }
  }

  /// 「更新する」を押したとき: 版番号付きのURLで読み直す。
  /// Flutter の service worker は古いキャッシュを使うため、
  /// 別URLで開くと新しいファイルを取りに行く。
  static void reloadWithFreshFiles(Uri current) {
    final target = current.replace(
      queryParameters: {
        ...current.queryParameters,
        'v': '${DateTime.now().millisecondsSinceEpoch}',
      },
    );
    launchUrl(target, webOnlyWindowName: '_self');
  }

  /// 新しい版があれば UpdateInfo を返す。なければ・失敗時は null。
  static Future<UpdateInfo?> check({
    required Uri appBase,
    required String currentVersion,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final res = await c
          .get(versionUri(appBase), headers: {'Cache-Control': 'no-cache'})
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final latest = parseVersion(res.body);
      if (latest == null) return null;
      if (UpdateChecker.compareVersions(latest, currentVersion) <= 0) {
        return null;
      }
      return UpdateInfo(
        latestVersion: latest,
        currentVersion: currentVersion,
        downloadUrl: appBase.toString(),
      );
    } catch (_) {
      return null;
    } finally {
      if (client == null) c.close();
    }
  }
}
