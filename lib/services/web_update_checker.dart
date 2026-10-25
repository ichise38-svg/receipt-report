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

  /// 公開版のビルド番号（version.json の build_number）。読めなければ null。
  static int? parseBuild(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      final b = decoded['build_number'];
      if (b is int) return b;
      if (b is String) return int.tryParse(b.trim());
      return null;
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
  /// currentVersion は「1.0.4+6」の形式（ビルド番号つき）でも「1.0.4」でもよい。
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
      final latestBuild = parseBuild(res.body);
      final parts = currentVersion.split('+');
      final curVer = parts.first;
      final curBuild = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (UpdateChecker.compareFull(latest, latestBuild, curVer, curBuild) <=
          0) {
        return null;
      }
      return UpdateInfo(
        latestVersion: UpdateChecker.displayVersion(latest, latestBuild),
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
