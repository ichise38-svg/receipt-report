import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/services/bug_reporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('金額・URL・長い英数字（トークン）・パスを伏せ字にする', () {
    final out = BugReporter.redact(
      'FormatException: 金額 123,456 円 https://example.com/x?t=abc '
      'token=ABCDEFGHIJKLMNOPQRSTUVWXYZ012345 /home/user/a.xlsx',
    );
    expect(out.contains('123'), isFalse);
    expect(out.contains('example.com'), isFalse);
    expect(out.contains('ABCDEFGHIJKLMNOPQRSTUVWXYZ012345'), isFalse);
    expect(out.contains('/home/user'), isFalse);
    expect(out.contains('<url>'), isTrue);
    expect(out.contains('<token>'), isTrue);
    expect(out.contains('<path>'), isTrue);
  });

  test('メールアドレスを伏せ字にする', () {
    final out = BugReporter.redact('mail someone@example.jp failed');
    expect(out.contains('someone@example.jp'), isFalse);
    expect(out.contains('<mail>'), isTrue);
  });

  test('メッセージは200文字以内に切り詰める', () {
    final out = BugReporter.redact('x' * 500);
    expect(out.length <= 200, isTrue);
  });

  test('同じ不具合は1件にまとめ、件数だけ増やす', () async {
    final err = StateError('失敗');
    for (var i = 0; i < 3; i++) {
      await BugReporter.record(err, null, screen: 'home');
    }
    final c = await BugReporter.counts();
    expect(c.total, 1);
    expect(c.pending, 1);
  });

  test('保存は最大100件に抑える', () async {
    // 数字は伏せ字になるため、文字で区別できる別々のメッセージを使う
    const letters = 'abcdefghijklmnopqrstuvwxyz';
    for (var i = 0; i < BugReporter.maxStored + 5; i++) {
      final tag =
          '${letters[i % 26]}${letters[(i ~/ 26) % 26]}${letters[(i ~/ 676) % 26]}';
      await BugReporter.record(
        StateError('err $tag'),
        null,
        screen: 'screen$tag',
      );
    }
    final c = await BugReporter.counts();
    expect(c.total, BugReporter.maxStored);
  });

  test('機能をオフにすると記録しない', () async {
    await BugReporter.setEnabled(false);
    await BugReporter.record(StateError('x'), null, screen: 'home');
    final c = await BugReporter.counts();
    expect(c.total, 0);
    await BugReporter.setEnabled(true);
  });
}
