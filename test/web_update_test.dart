import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/services/web_update_checker.dart';

void main() {
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
