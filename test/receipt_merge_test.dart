import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/receipt_merge.dart';

Receipt _r({
  String id = 'a',
  String store = '駅',
  int amount = 300,
  DateTime? date,
  String photo = '',
  String event = '',
  bool deleted = false,
  EntryKind kind = EntryKind.expense,
}) => Receipt(
  id: id,
  kind: kind,
  storeName: store,
  date: date ?? DateTime(2025, 12, 1),
  amount: amount,
  category: '交通費',
  imagePath: photo,
  event: event,
  deleted: deleted,
);

void main() {
  test('同じ内容は重複扱い（店舗名の前後の空白は無視）', () {
    final all = [_r(store: '駅')];
    final dup = ReceiptMerge.findDuplicate(all, _r(id: 'b', store: ' 駅 '));
    expect(dup?.id, 'a');
  });

  test('金額・日付・区分・店舗名のどれかが違えば別物', () {
    final all = [_r()];
    expect(ReceiptMerge.findDuplicate(all, _r(id: 'b', amount: 301)), isNull);
    expect(
      ReceiptMerge.findDuplicate(all, _r(id: 'b', date: DateTime(2025, 12, 2))),
      isNull,
    );
    expect(ReceiptMerge.findDuplicate(all, _r(id: 'b', store: '店')), isNull);
    expect(
      ReceiptMerge.findDuplicate(all, _r(id: 'b', kind: EntryKind.income)),
      isNull,
    );
  });

  test('削除済みの明細とは重複扱いしない', () {
    final all = [_r(deleted: true)];
    expect(ReceiptMerge.findDuplicate(all, _r(id: 'b')), isNull);
  });

  test('写真がない既存明細に撮影写真だけを付ける（二重作成しない）', () {
    final plan = ReceiptMerge.plan(_r(), _r(id: 'b', photo: '/p/new.jpg'));
    expect(plan.outcome, SaveOutcome.photoAttached);
    expect(plan.updated?.id, 'a');
    expect(plan.updated?.imagePath, '/p/new.jpg');
    expect(plan.discardDraftImage, isFalse);
  });

  test('既に写真がある明細には、同じ内容の写真を重ねない', () {
    final plan = ReceiptMerge.plan(
      _r(photo: '/p/old.jpg'),
      _r(id: 'b', photo: '/p/new.jpg'),
    );
    expect(plan.outcome, SaveOutcome.duplicateSkipped);
    expect(plan.updated, isNull);
    expect(plan.discardDraftImage, isTrue);
  });

  test('イベント名が空の既存明細には、入力のイベント名を補う', () {
    final plan = ReceiptMerge.plan(_r(), _r(id: 'b', event: '25忘年会'));
    expect(plan.outcome, SaveOutcome.eventAttached);
    expect(plan.updated?.event, '25忘年会');
  });

  test('既にイベント名がある明細は、別イベント名で上書きしない', () {
    final plan = ReceiptMerge.plan(
      _r(event: '25旅行'),
      _r(id: 'b', event: '25忘年会'),
    );
    expect(plan.outcome, SaveOutcome.duplicateSkipped);
    expect(plan.updated, isNull);
  });

  test('写真とイベント名の両方を既存明細に反映できる', () {
    final plan = ReceiptMerge.plan(
      _r(),
      _r(id: 'b', photo: '/p/new.jpg', event: '25忘年会'),
    );
    expect(plan.updated?.imagePath, '/p/new.jpg');
    expect(plan.updated?.event, '25忘年会');
    expect(plan.outcome, SaveOutcome.photoAttached);
  });

  test('既存がない場合は新規作成', () {
    final plan = ReceiptMerge.plan(null, _r(id: 'b'));
    expect(plan.outcome, SaveOutcome.created);
  });
}
