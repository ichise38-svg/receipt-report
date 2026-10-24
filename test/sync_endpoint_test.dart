import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:receipt_report/services/app_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('初期設定のURLを保存しても同期先は変わらない（カーソルを消さない）', () async {
    final changed = await AppSettings.setSyncEndpoint(
      AppSettings.builtInSyncEndpoint,
    );
    expect(changed, isFalse);
    expect(
      await AppSettings.getSyncEndpoint(),
      AppSettings.builtInSyncEndpoint,
    );
    expect(await AppSettings.isUsingCustomEndpoint(), isFalse);
  });

  test('別のURLを保存すると変更扱いになり、初期設定に戻すと再び変更扱い', () async {
    expect(
      await AppSettings.setSyncEndpoint('https://example.com/exec'),
      isTrue,
    );
    expect(await AppSettings.isUsingCustomEndpoint(), isTrue);
    expect(
      await AppSettings.setSyncEndpoint(AppSettings.builtInSyncEndpoint),
      isTrue,
    );
    expect(await AppSettings.isUsingCustomEndpoint(), isFalse);
  });
}
