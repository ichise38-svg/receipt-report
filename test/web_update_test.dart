import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:receipt_report/services/update_checker.dart';
import 'package:receipt_report/services/web_update_checker.dart';

void main() {
  buildNumberWebTests();

  test('version.json のURLは同じ場所に作られ、毎回違う値が付く', () {
    final base = Uri.parse('https://ichise38-svg.github.io/receipt-report/');
    final a = WebUpdateChecker.versionUri(base, nowMs: 1000);
    final b = WebUpdateChecker.versionUri(base, nowMs: 2000);
    expect(
      a.toString(),
      'https://ichise38-svg.github.io/receipt-report/version.json?t=1000',
    );
    expect(a.queryParameters['t'], isNot(b.queryParameters['t']));
  });

  test('version.json の version を読む', () {
    expect(
      WebUpdateChecker.parseVersion(
        '{"app_name":"receipt_report","version":"1.0.2"}',
      ),
      '1.0.2',
    );
  });

  test('壊れた・版番号のないJSONは null', () {
    expect(WebUpdateChecker.parseVersion('not json'), isNull);
    expect(WebUpdateChecker.parseVersion('{"version":"abc"}'), isNull);
    expect(WebUpdateChecker.parseVersion('{}'), isNull);
    expect(WebUpdateChecker.parseVersion('[1,2]'), isNull);
  });
}

void buildNumberWebTests() {
  test('version.json の build_number を読む（文字列・数値どちらも）', () {
    expect(
      WebUpdateChecker.parseBuild('{"version":"1.0.4","build_number":"7"}'),
      7,
    );
    expect(
      WebUpdateChecker.parseBuild('{"version":"1.0.4","build_number":7}'),
      7,
    );
    expect(WebUpdateChecker.parseBuild('{"version":"1.0.4"}'), isNull);
  });

  test('Web版: 比較用の値（1.0.7+13）なら、公開版 1.0.7 build 13 は更新なし', () async {
    final client = MockClient((_) async => http.Response(
        '{"version":"1.0.7","build_number":"13"}', 200));
    final info = await WebUpdateChecker.check(
      appBase: Uri.parse('https://example.com/receipt-report/'),
      currentVersion: UpdateChecker.currentCompare,
      client: client,
    );
    expect(info, isNull);
  });

  test('Web版: 旧1.0.7 (12) からは build 13 への更新ありと判定される', () async {
    final client = MockClient((_) async => http.Response(
        '{"version":"1.0.7","build_number":"13"}', 200));
    final info = await WebUpdateChecker.check(
      appBase: Uri.parse('https://example.com/receipt-report/'),
      currentVersion: '1.0.7+12',
      client: client,
    );
    expect(info, isNotNull);
    expect(info!.latestVersion, '1.0.7 (13)');
  });
}
