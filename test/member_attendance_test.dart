import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/member.dart';

void main() {
  test('未設定のイベントは参加扱い', () {
    final m = Member(name: '山田');
    expect(m.attendsEvent('25忘年会'), isTrue);
  });

  test('明示的に不参加にしたイベントだけ除外される', () {
    final m = Member(name: '佐藤', eventAttendance: {'25忘年会': false, '旅行': true});
    expect(m.attendsEvent('25忘年会'), isFalse);
    expect(m.attendsEvent('旅行'), isTrue);
    expect(m.attendsEvent('新年会'), isTrue);
  });

  test('JSON往復で参加状況が保持される', () {
    final m = Member(
      name: '鈴木',
      eventAttendance: {'25忘年会': false},
      updatedAt: DateTime.utc(2025, 12, 1),
    );
    final back = Member.fromJson(m.toJson());
    expect(back.eventAttendance, {'25忘年会': false});
    expect(back.attendsEvent('25忘年会'), isFalse);
  });

  test('旧形式（eventAttendance なし）は既定で参加', () {
    final back = Member.fromJson({
      'id': 'x',
      'name': '旧データ',
      'note': '',
      'updatedAt': '2025-01-01T00:00:00.000Z',
      'deleted': false,
    });
    expect(back.eventAttendance, isEmpty);
    expect(back.attendsEvent('25忘年会'), isTrue);
  });

  test('copyWith で参加状況を変えても他の項目は変わらない', () {
    final m = Member(name: '高橋', note: '会員');
    final changed = m.copyWith(eventAttendance: {'旅行': false});
    expect(changed.id, m.id);
    expect(changed.note, '会員');
    expect(changed.attendsEvent('旅行'), isFalse);
  });
}
