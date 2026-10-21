import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/bank_entry.dart';
import 'package:receipt_report/services/bank_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('追加・修正・削除（tombstone）が同期用の全件に残る', () async {
    await BankStore.upsert(
      BankEntry(
        id: 'a',
        date: DateTime(2025, 1, 5),
        kind: BankEntryKind.deposit,
        label: '1月、2月集金分',
        amount: 228000,
      ),
    );
    expect((await BankStore.loadAll()).length, 1);

    await BankStore.delete('a');
    expect(await BankStore.loadAll(), isEmpty);
    final raw = await BankStore.loadRaw();
    expect(raw.single.deleted, isTrue);
  });

  test('同期で新しい更新は反映、古い更新は無視する', () async {
    final base = DateTime.utc(2025, 3, 1, 10);
    final seed = BankEntry(
      id: 'b',
      date: DateTime(2025, 3, 1),
      kind: BankEntryKind.cashOut,
      label: 'カード出金',
      amount: 50000,
      updatedAt: base,
    );
    expect(await BankStore.applyRemote(seed), isTrue);

    final older = seed.copyWith(
      label: '古い',
      amount: 1,
      updatedAt: base.subtract(const Duration(hours: 1)),
    );
    expect(await BankStore.applyRemote(older), isFalse);

    final newer = seed.copyWith(
      label: '新しい',
      amount: 60000,
      updatedAt: base.add(const Duration(hours: 1)),
    );
    expect(await BankStore.applyRemote(newer), isTrue);
    final list = await BankStore.loadAll();
    expect(list.single.amount, 60000);
    expect(list.single.label, '新しい');
  });

  test('JSONの往復で区分・削除・更新日時が保たれる', () {
    final e = BankEntry(
      id: 'c',
      date: DateTime(2025, 4, 2),
      kind: BankEntryKind.withdraw,
      label: 'カード出金',
      amount: 450000,
      updatedAt: DateTime.utc(2025, 4, 2, 1, 2, 3, 4),
      deleted: true,
    );
    final back = BankEntry.fromJson(e.toJson());
    expect(back.kind, BankEntryKind.withdraw);
    expect(back.deleted, isTrue);
    expect(back.updatedAt.toUtc(), e.updatedAt.toUtc());
  });

  test('updatedAt を持たない旧データは読み込み時に補われる', () async {
    SharedPreferences.setMockInitialValues({
      'bank_entries_v1':
          '[{"id":"old","date":"2025-01-05T00:00:00.000","kind":"deposit","label":"旧","amount":100}]',
    });
    final raw = await BankStore.loadRaw();
    expect(raw.single.id, 'old');
    expect(raw.single.amount, 100);
    // 補った値が保存されているので、次回も同じ更新日時になる
    final again = await BankStore.loadRaw();
    expect(again.single.updatedAt, raw.single.updatedAt);
  });
}
