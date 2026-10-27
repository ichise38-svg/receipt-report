import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/member.dart';

void main() {
  test('イベント出席はイベントごとに判定され、登録人数とは別に数えられる', () {
    final members = [
      Member(name: 'A', eventAttendance: {'新年会': true}),
      Member(name: 'B', eventAttendance: {'新年会': false}),
      Member(name: 'C'),
    ];
    final registered = members.length;
    final attendees = members
        .where((m) => m.attendsEvent('新年会'))
        .length;
    expect(registered, 3);
    expect(attendees, 2);
  });
}
