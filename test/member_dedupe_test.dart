import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/member.dart';
import 'package:receipt_report/services/member_dedupe.dart';

void main() {
  group('正規化', () {
    test('空白・全角空白・改行の違いは同じ名前', () {
      final a = MemberDedupe.normalizeName('山田 太郎');
      expect(MemberDedupe.normalizeName('山田太郎'), a);
      expect(MemberDedupe.normalizeName('山田　太郎'), a);
      expect(MemberDedupe.normalizeName(' 山田\n太郎 '), a);
    });

    test('半角カナと全角カナは同じ名前（濁点・半濁点も）', () {
      expect(MemberDedupe.normalizeName('ﾔﾏﾀﾞ ﾀﾛｳ'),
          MemberDedupe.normalizeName('ヤマダ タロウ'));
      expect(MemberDedupe.normalizeName('ﾊﾟｰﾃｨ'),
          MemberDedupe.normalizeName('パーティ'));
    });

    test('半角英数字と大文字小文字は同じ名前', () {
      expect(MemberDedupe.normalizeName('ABC１２'),
          MemberDedupe.normalizeName('abc12'));
    });

    test('ひらがなとカタカナは統合しない（別人扱い）', () {
      expect(MemberDedupe.normalizeName('やまだ'),
          isNot(MemberDedupe.normalizeName('ヤマダ')));
    });

    test('表示名は変えない（比較用のみ）', () {
      expect(MemberDedupe.normalizeName('ﾔﾏﾀﾞ'), 'ヤマダ');
    });
  });

  group('重複の整理（plan）', () {
    test('同じ人は1件に残し、出席記録は新しい方を採用する', () {
      final older = DateTime(2026, 1, 1);
      final newer = DateTime(2026, 2, 1);
      final a = Member(
        id: 'bbb',
        name: '山田 太郎',
        updatedAt: older,
        eventAttendance: {'新年会': false, '忘年会': true},
      );
      final b = Member(
        id: 'aaa',
        name: '山田太郎',
        updatedAt: newer,
        eventAttendance: {'新年会': true},
      );
      final c = Member(id: 'ccc', name: '佐藤 花子');
      final plan = MemberDedupe.plan([a, b, c]);

      expect(plan.groupCount, 1);
      expect(plan.removeCount, 1);
      expect(plan.droppedIds, ['bbb']);
      final kept = plan.merged.single;
      expect(kept.id, 'aaa');
      // 新年会は新しい方(b)の true、忘年会は a だけが持つので true
      expect(kept.attendsEvent('新年会'), isTrue);
      expect(kept.attendsEvent('忘年会'), isTrue);
    });

    test('重複がなければ何もしない', () {
      final plan = MemberDedupe.plan([
        Member(id: '1', name: '山田'),
        Member(id: '2', name: '佐藤'),
      ]);
      expect(plan.removeCount, 0);
      expect(plan.merged, isEmpty);
    });

    test('削除済みの会員は数えない', () {
      final plan = MemberDedupe.plan([
        Member(id: '1', name: '山田'),
        Member(id: '2', name: '山田', deleted: true),
      ]);
      expect(plan.removeCount, 0);
    });

    test('どの端末で計算しても残る会員は同じ（ID の小さい方）', () {
      final x = Member(id: 'zzz', name: '鈴木');
      final y = Member(id: 'aaa', name: '鈴木 ');
      final p1 = MemberDedupe.plan([x, y]);
      final p2 = MemberDedupe.plan([y, x]);
      expect(p1.merged.single.id, 'aaa');
      expect(p2.merged.single.id, 'aaa');
    });
  });
}
