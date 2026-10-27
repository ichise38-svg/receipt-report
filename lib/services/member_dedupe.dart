import '../models/member.dart';

/// 会員の同一人物判定と重複整理。
///
/// 判定は「空白を除き、半角カナ→全角カナ、半角英数字→全角英数字、大文字→小文字」
/// の正規化名で行う。ひらがなとカタカナは別人として扱う（統合しない）。
class MemberDedupe {
  MemberDedupe._();

  static const _halfKanaMap = <String, String>{
    'ｦ': 'ヲ',
    'ｧ': 'ァ',
    'ｨ': 'ィ',
    'ｩ': 'ゥ',
    'ｪ': 'ェ',
    'ｫ': 'ォ',
    'ｬ': 'ャ',
    'ｭ': 'ュ',
    'ｮ': 'ョ',
    'ｯ': 'ッ',
    'ｰ': 'ー',
    'ｱ': 'ア',
    'ｲ': 'イ',
    'ｳ': 'ウ',
    'ｴ': 'エ',
    'ｵ': 'オ',
    'ｶ': 'カ',
    'ｷ': 'キ',
    'ｸ': 'ク',
    'ｹ': 'ケ',
    'ｺ': 'コ',
    'ｻ': 'サ',
    'ｼ': 'シ',
    'ｽ': 'ス',
    'ｾ': 'セ',
    'ｿ': 'ソ',
    'ﾀ': 'タ',
    'ﾁ': 'チ',
    'ﾂ': 'ツ',
    'ﾃ': 'テ',
    'ﾄ': 'ト',
    'ﾅ': 'ナ',
    'ﾆ': 'ニ',
    'ﾇ': 'ヌ',
    'ﾈ': 'ネ',
    'ﾉ': 'ノ',
    'ﾊ': 'ハ',
    'ﾋ': 'ヒ',
    'ﾌ': 'フ',
    'ﾍ': 'ヘ',
    'ﾎ': 'ホ',
    'ﾏ': 'マ',
    'ﾐ': 'ミ',
    'ﾑ': 'ム',
    'ﾒ': 'メ',
    'ﾓ': 'モ',
    'ﾔ': 'ヤ',
    'ﾕ': 'ユ',
    'ﾖ': 'ヨ',
    'ﾗ': 'ラ',
    'ﾘ': 'リ',
    'ﾙ': 'ル',
    'ﾚ': 'レ',
    'ﾛ': 'ロ',
    'ﾜ': 'ワ',
    'ﾝ': 'ン',
  };

  /// 濁点（全角カナ）
  static const _dakuten = <String, String>{
    'カ': 'ガ',
    'キ': 'ギ',
    'ク': 'グ',
    'ケ': 'ゲ',
    'コ': 'ゴ',
    'サ': 'ザ',
    'シ': 'ジ',
    'ス': 'ズ',
    'セ': 'ゼ',
    'ソ': 'ゾ',
    'タ': 'ダ',
    'チ': 'ヂ',
    'ツ': 'ヅ',
    'テ': 'デ',
    'ト': 'ド',
    'ハ': 'バ',
    'ヒ': 'ビ',
    'フ': 'ブ',
    'ヘ': 'ベ',
    'ホ': 'ボ',
    'ウ': 'ヴ',
  };

  /// 半濁点（全角カナ）
  static const _handakuten = <String, String>{
    'ハ': 'パ',
    'ヒ': 'ピ',
    'フ': 'プ',
    'ヘ': 'ペ',
    'ホ': 'ポ',
  };

  /// 比較用の正規化名。表示名は変えない。
  static String normalizeName(String raw) {
    final out = StringBuffer();
    final chars = raw.split('');
    for (var i = 0; i < chars.length; i++) {
      final ch = chars[i];
      if (ch == 'ﾞ' || ch == 'ﾟ') {
        // 濁点・半濁点（単独で来た場合は無視）
        continue;
      }
      var base = _halfKanaMap[ch] ?? ch;
      // 直後の濁点・半濁点を合成（半角カナ、または全角カナ＋結合記号）
      if (i + 1 < chars.length &&
          (chars[i + 1] == 'ﾞ' || chars[i + 1] == 'ﾟ')) {
        final mark = chars[i + 1];
        final combined = mark == 'ﾞ' ? _dakuten[base] : _handakuten[base];
        if (combined != null) {
          base = combined;
          i++;
        }
      }
      out.write(base);
    }
    // 半角英数字→全角、大文字→小文字、空白（半角・全角・改行・タブ）を除去
    final res = StringBuffer();
    for (final rune in out.toString().runes) {
      if (rune == 0x20 ||
          rune == 0x3000 ||
          rune == 0x09 ||
          rune == 0x0A ||
          rune == 0x0D) {
        continue;
      }
      var code = rune;
      if (code >= 0x21 && code <= 0x7E) code += 0xFEE0;
      res.write(String.fromCharCode(code).toLowerCase());
    }
    return res.toString();
  }

  /// 同じ正規化名の会員をまとめた結果。
  /// [keep] は残す会員（ID の文字列順で最小）、[drop] は削除扱いにする会員。
  /// 出席記録はイベントごとに更新日時が新しい方を採用し、keep に反映する。
  static DedupeResult plan(List<Member> members) {
    final groups = <String, List<Member>>{};
    for (final m in members) {
      if (m.deleted) continue;
      final key = normalizeName(m.name);
      if (key.isEmpty) continue;
      groups.putIfAbsent(key, () => []).add(m);
    }
    final merged = <Member>[];
    final dropped = <String>[];
    for (final group in groups.values) {
      if (group.length < 2) continue;
      group.sort((a, b) => a.id.compareTo(b.id));
      final keep = group.first;
      final attendance = <String, bool>{};
      final stamps = <String, DateTime>{};
      for (final m in group) {
        m.eventAttendance.forEach((event, value) {
          final prev = stamps[event];
          if (prev == null || m.updatedAt.isAfter(prev)) {
            stamps[event] = m.updatedAt;
            attendance[event] = value;
          }
        });
      }
      final newest = group
          .map((m) => m.updatedAt)
          .reduce((a, b) => a.isAfter(b) ? a : b);
      merged.add(
        keep.copyWith(
          eventAttendance: attendance,
          updatedAt: DateTime.now().isAfter(newest) ? DateTime.now() : newest,
        ),
      );
      for (final m in group.skip(1)) {
        dropped.add(m.id);
      }
    }
    return DedupeResult(merged: merged, droppedIds: dropped);
  }
}

class DedupeResult {
  /// 残す会員（出席記録を統合済み・更新日時を更新）
  final List<Member> merged;

  /// 削除扱いにする会員ID
  final List<String> droppedIds;

  const DedupeResult({required this.merged, required this.droppedIds});

  int get groupCount => merged.length;
  int get removeCount => droppedIds.length;
}
