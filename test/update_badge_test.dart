import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receipt_report/services/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  buildNumberTests();

  test('版番号の比較は数字の大小で判定する（1.0.10 > 1.0.9）', () {
    expect(AppSettings.compareVersionStrings('1.0.3', '1.0.2'), greaterThan(0));
    expect(
      AppSettings.compareVersionStrings('1.0.10', '1.0.9'),
      greaterThan(0),
    );
    expect(AppSettings.compareVersionStrings('1.0.2', '1.0.2'), 0);
    expect(AppSettings.compareVersionStrings('1.0.2', '1.0.3'), lessThan(0));
    expect(AppSettings.compareVersionStrings('1.1', '1.0.9'), greaterThan(0));
  });

  test('記録がなければバッジは出ない', () async {
    expect(await AppSettings.hasNewerVersion('1.0.3'), isFalse);
  });

  test('新しい版を記録するとバッジが出る', () async {
    await AppSettings.saveLatestVersion('1.0.4');
    expect(await AppSettings.hasNewerVersion('1.0.3'), isTrue);
  });

  test('今の版と同じ、または古い版ならバッジは出ない（更新後に自動で消える）', () async {
    await AppSettings.saveLatestVersion('1.0.3');
    expect(await AppSettings.hasNewerVersion('1.0.3'), isFalse);
    expect(await AppSettings.hasNewerVersion('1.0.4'), isFalse);
  });
}

void buildNumberTests() {
  test('同じ版番号でもビルド番号が新しければ新しい版（1.0.4+7 > 1.0.4+6）', () {
    expect(
      AppSettings.compareVersionStrings('1.0.4+7', '1.0.4+6'),
      greaterThan(0),
    );
    expect(
      AppSettings.compareVersionStrings('1.0.4+6', '1.0.4+7'),
      lessThan(0),
    );
    expect(AppSettings.compareVersionStrings('1.0.4+6', '1.0.4+6'), 0);
    expect(
      AppSettings.compareVersionStrings('1.0.5+7', '1.0.4+9'),
      greaterThan(0),
    );
  });

  test('アプリ内の版（1.0.4+6）に対して、公開版 1.0.4+7 は通知対象', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.saveLatestVersion('1.0.4+7');
    expect(await AppSettings.hasNewerVersion('1.0.4+6'), isTrue);
  });

  test('アプリ内の版（1.0.4+6）に対して、公開版 1.0.4+6 は通知しない', () async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.saveLatestVersion('1.0.4+6');
    expect(await AppSettings.hasNewerVersion('1.0.4+6'), isFalse);
  });
}
