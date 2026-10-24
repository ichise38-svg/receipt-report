import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// 新しいバージョンの情報
class UpdateInfo {
  const UpdateInfo({
    required this.latestVersion,
    required this.currentVersion,
    required this.downloadUrl,
  });

  final String latestVersion;
  final String currentVersion;
  final String downloadUrl;
}

/// GitHub Releases の最新版と、いま動いているアプリのバージョンを比べる。
///
/// リリース本文に次の1行を書いておくと、その番号を新版として使う:
///   version: 1.0.5+7
/// 版番号（1.0.5）だけでなくビルド番号（+7）も比べる。
/// 失敗（オフライン・未設定など）は黙って null を返し、アプリの動作は止めない。
class UpdateChecker {
  /// このアプリのバージョン（pubspec.yaml の version と必ず合わせる）
  static const currentVersion = '1.0.7';

  /// このアプリのビルド番号（pubspec.yaml の +の後ろと必ず合わせる）
  static const currentBuild = 12;

  /// 版番号とビルド番号を並べた表示用の値（例: 1.0.4+6）
  static String get currentFull => '$currentVersion+$currentBuild';

  static const _releaseApi =
      'https://api.github.com/repos/ichise38-svg/receipt-report/releases/tags/android-latest';
  static const downloadPageUrl =
      'https://ichise38-svg.github.io/receipt-report/android.html';

  static Future<UpdateInfo?> check() async {
    try {
      const current = currentVersion;
      final res = await http
          .get(
            Uri.parse(_releaseApi),
            headers: {'Accept': 'application/vnd.github+json'},
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final body = jsonDecode(res.body);
      if (body is! Map) return null;
      final notes = (body['body'] as String?) ?? '';
      final m = RegExp(r'version:\s*([0-9]+(?:\.[0-9]+)*)').firstMatch(notes);
      if (m == null) return null;
      final latest = m.group(1)!;
      final latestBuild = _buildFromNotes(notes);
      if (compareFull(latest, latestBuild, current, currentBuild) <= 0) {
        return null;
      }
      return UpdateInfo(
        latestVersion: latestBuild == null ? latest : '$latest+$latestBuild',
        currentVersion: '$current+$currentBuild',
        downloadUrl: downloadPageUrl,
      );
    } catch (_) {
      return null;
    }
  }

  /// ダウンロードページをブラウザで開く（Androidは Chrome を優先）
  static Future<bool> openDownloadPage() async {
    final uri = Uri.parse(downloadPageUrl);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  /// リリース本文の「build: 7」または「version: 1.0.5+7」からビルド番号を読む
  static int? _buildFromNotes(String notes) {
    final plus = RegExp(
      r'version:\s*[0-9]+(?:\.[0-9]+)*\+([0-9]+)',
    ).firstMatch(notes);
    if (plus != null) return int.tryParse(plus.group(1)!);
    final b = RegExp(r'build:\s*([0-9]+)').firstMatch(notes);
    return b == null ? null : int.tryParse(b.group(1)!);
  }

  /// 版番号を先に比べ、同じなら ビルド番号で比べる（負: a が古い / 0: 同じ / 正: a が新しい）
  static int compareFull(String a, int? aBuild, String b, int? bBuild) {
    final v = compareVersions(a, b);
    if (v != 0) return v;
    return (aBuild ?? 0).compareTo(bBuild ?? 0);
  }

  /// "1.2.3" 形式の比較（負なら a が古い、0 は同じ、正なら a が新しい）
  static int compareVersions(String a, String b) {
    List<int> parts(String v) =>
        v.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final pa = parts(a);
    final pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x - y;
    }
    return 0;
  }
}
