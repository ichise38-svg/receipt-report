import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_report/models/receipt.dart';
import 'package:receipt_report/services/voice_command_parser.dart';

void main() {
  final now = DateTime(2026, 5, 10, 12);

  test('昨日の交通費 1200円 を支出の追加にする', () {
    final c = VoiceCommandParser.parse('昨日の交通費 1200円', now: now);
    expect(c.action, VoiceAction.add);
    expect(c.receipt!.kind, EntryKind.expense);
    expect(c.receipt!.category, '交通費');
    expect(c.receipt!.amount, 1200);
    expect(c.receipt!.date, DateTime(2026, 5, 9));
  });

  test('全角の数字とカンマを読む', () {
    final c = VoiceCommandParser.parse('食費 ３，５００円', now: now);
    expect(c.action, VoiceAction.add);
    expect(c.receipt!.amount, 3500);
    expect(c.receipt!.category, '食費');
  });

  test('5月3日の日付を読む', () {
    final c = VoiceCommandParser.parse('5月3日 食費 3500円 スーパー', now: now);
    expect(c.receipt!.date, DateTime(2026, 5, 3));
    expect(c.receipt!.amount, 3500);
    expect(c.receipt!.storeName.contains('スーパー'), isTrue);
  });

  test('収入の補助金を収入として追加する', () {
    final c = VoiceCommandParser.parse('収入 補助金 50000円', now: now);
    expect(c.receipt!.kind, EntryKind.income);
    expect(c.receipt!.category, '補助金');
    expect(c.receipt!.amount, 50000);
  });

  test('1万2千円 を 12000 として読む', () {
    final c = VoiceCommandParser.parse('会費 1万2千円', now: now);
    expect(c.receipt!.amount, 12000);
  });

  test('金額がなければ解釈できない', () {
    final c = VoiceCommandParser.parse('交通費の記録', now: now);
    expect(c.action, VoiceAction.unknown);
    expect(c.message, isNotNull);
  });

  test('存在しない日付（2月30日）は今日として扱い、誤った日付にしない', () {
    final c = VoiceCommandParser.parse('2月30日 交通費 500円', now: now);
    expect(c.receipt!.date, DateTime(2026, 5, 10));
  });

  test('修正：対象の日付・カテゴリと新しい金額を取り出す', () {
    final c = VoiceCommandParser.parse('5月3日の食費を3000円に直す', now: now);
    expect(c.action, VoiceAction.edit);
    expect(c.newAmount, 3000);
    expect(c.target!.date, DateTime(2026, 5, 3));
    expect(c.target!.category, '食費');
  });

  test('削除：対象の条件を取り出す', () {
    final c = VoiceCommandParser.parse('昨日の交通費を削除', now: now);
    expect(c.action, VoiceAction.delete);
    expect(c.target!.date, DateTime(2026, 5, 9));
    expect(c.target!.category, '交通費');
  });

  test('対象の一致判定は削除済みを除外する', () {
    final target = VoiceTarget(date: DateTime(2026, 5, 9), category: '交通費');
    final active = Receipt(
      storeName: 'バス',
      date: DateTime(2026, 5, 9, 8),
      amount: 300,
      category: '交通費',
    );
    expect(target.matches(active), isTrue);
    expect(target.matches(active.copyWith(deleted: true)), isFalse);
    expect(
      target.matches(active.copyWith(date: DateTime(2026, 5, 8))),
      isFalse,
    );
  });

  group('自然な言い回し', () {
    test('「〜かかった」は支出、電車は交通費', () {
      final c = VoiceCommandParser.parse('昨日電車で300円かかった', now: now);
      expect(c.action, VoiceAction.add);
      expect(c.receipt!.kind, EntryKind.expense);
      expect(c.receipt!.category, '交通費');
      expect(c.receipt!.amount, 300);
      expect(c.receipt!.date, DateTime(2026, 5, 9));
    });

    test('「〜入った」は収入、「5万」を金額に読む', () {
      final c = VoiceCommandParser.parse('補助金が5万円入った', now: now);
      expect(c.receipt!.kind, EntryKind.income);
      expect(c.receipt!.category, '補助金');
      expect(c.receipt!.amount, 50000);
    });

    test('「2千円」「3千5百円」を読む', () {
      expect(
        VoiceCommandParser.parse('会費 2千円', now: now).receipt!.amount,
        2000,
      );
      expect(
        VoiceCommandParser.parse('食費 3千5百円', now: now).receipt!.amount,
        3500,
      );
    });

    test('「直接払った」は修正と誤判定しない', () {
      final c = VoiceCommandParser.parse('直接払った 食費 800円', now: now);
      expect(c.action, VoiceAction.add);
      expect(c.receipt!.amount, 800);
    });

    test('店名の中の「は」「の」を壊さない', () {
      final c = VoiceCommandParser.parse('はなまるうどんで食費 700円', now: now);
      expect(c.receipt!.storeName.contains('はなまるうどん'), isTrue);
    });

    test('修正：「1200円を1500円に変更」は新旧の金額を取り違えない', () {
      final c = VoiceCommandParser.parse('1200円を1500円に変更', now: now);
      expect(c.action, VoiceAction.edit);
      expect(c.newAmount, 1500);
      expect(c.target!.amount, 1200);
    });

    test('修正：「昨日の食費を2千円に直して」', () {
      final c = VoiceCommandParser.parse('昨日の食費を2千円に直して', now: now);
      expect(c.action, VoiceAction.edit);
      expect(c.newAmount, 2000);
      expect(c.target!.date, DateTime(2026, 5, 9));
      expect(c.target!.category, '食費');
    });

    test('削除：「昨日の交通費を消して」', () {
      final c = VoiceCommandParser.parse('昨日の交通費を消して', now: now);
      expect(c.action, VoiceAction.delete);
      expect(c.target!.category, '交通費');
    });
  });
}
