import '../models/receipt.dart';

/// 音声・キーボード入力の文章を、収支の操作（追加・修正・削除）に変換する。
///
/// 端末内だけで動き、外部へは送らない（外部 AI は使わない）。解析結果は必ず
/// 確認カードで利用者に示し、承認されてから保存する（この関数は保存しない）。
///
/// 対応する言い方の例:
///   「昨日の交通費 1200円」                    → 追加（支出・交通費・昨日）
///   「昨日電車で300円かかった」                 → 追加（支出・交通費・昨日）
///   「5月3日 スーパーで3500円使った」           → 追加（支出・食費は未指定→雑費・摘要スーパー）
///   「補助金が5万円入った」                     → 追加（収入・補助金）
///   「5月3日の食費を3000円に直す」              → 修正（対象の条件＋新しい金額）
///   「1200円を1500円に変更」                    → 修正（対象は金額 1200 円）
///   「5月3日の食費を削除」                      → 削除（候補を一覧で選ぶ）
class VoiceCommandParser {
  static const _addWords = ['追加', '登録', '入力', '記録', '書き込', '入れて'];
  static const _editWords = [
    '直す',
    '直して',
    '直し',
    '修正',
    '変更',
    '訂正',
    '書き換え',
    '書き直',
  ];
  static const _deleteWords = [
    '削除',
    '消す',
    '消して',
    '取り消',
    '取消',
    '無かったことに',
    'なかったことに',
  ];

  /// 「〜を払った」「〜かかった」などの支出を表す言い回し
  static const _expenseVerbs = [
    '払った',
    '払い',
    '支払',
    'かかった',
    'かかり',
    '使った',
    '使い',
    '買った',
    '買い',
    '出した',
    '出費',
    '負担',
    '飲んだ',
    '食べた',
    '乗った',
    '乗り',
  ];

  /// 「〜が入った」「〜をもらった」などの収入を表す言い回し
  static const _incomeVerbs = [
    '入った',
    '入金',
    'もらった',
    '受け取',
    '受取',
    '振り込まれ',
    '振込',
    '戻った',
    '戻って',
    '返ってき',
    '返金',
  ];

  static const _categoryAliases = {
    '電車': '交通費',
    'バス': '交通費',
    'タクシー': '交通費',
    'ガソリン': '交通費',
    '高速': '交通費',
    '駐車': '交通費',
    '交通': '交通費',
    '食事': '食費',
    '昼食': '食費',
    '夕食': '食費',
    '朝食': '食費',
    'ランチ': '食費',
    '外食': '食費',
    '弁当': '食費',
    '飲み会': '交際費',
    '会費': '交際費',
    '香典': '交際費',
    '電話': '通信費',
    '携帯': '通信費',
    'ネット': '通信費',
    '文具': '消耗品費',
    '文房具': '消耗品費',
    '切手': '通信費',
    '郵便': '通信費',
    '補助': '補助金',
    '売上': '売上',
    '入金': '入金',
  };

  /// 文章を解析する。解釈できない場合は [VoiceCommand.unknown] を返す。
  static VoiceCommand parse(String input, {DateTime? now}) {
    final text = _normalize(input);
    if (text.isEmpty) {
      return const VoiceCommand.unknown('入力が空です。');
    }
    final today = _dateOnly(now ?? DateTime.now());

    final op = _detectOperation(text);
    switch (op) {
      case VoiceAction.delete:
        return _parseDelete(text, today);
      case VoiceAction.edit:
        return _parseEdit(text, today);
      case VoiceAction.add:
      case VoiceAction.unknown:
        return _parseAdd(text, today);
    }
  }

  /// 操作の種類を判定する。操作語が文末寄りにあるものを優先する
  /// （「直接払った」の「直」などの部分一致による誤判定を避ける）
  static VoiceAction _detectOperation(String text) {
    final del = _lastIndexOfAny(text, _deleteWords);
    final edit = _lastIndexOfAny(text, _editWords);
    final add = _lastIndexOfAny(text, _addWords);
    var best = VoiceAction.add;
    var bestIndex = -1;
    if (del >= 0 && del > bestIndex) {
      best = VoiceAction.delete;
      bestIndex = del;
    }
    if (edit >= 0 && edit > bestIndex) {
      best = VoiceAction.edit;
      bestIndex = edit;
    }
    if (add >= 0 && add > bestIndex) {
      best = VoiceAction.add;
      bestIndex = add;
    }
    return best;
  }

  // ---- 追加 ----

  static VoiceCommand _parseAdd(String text, DateTime today) {
    final amountMatch = _findAmount(text);
    if (amountMatch == null) {
      return const VoiceCommand.unknown('金額が読み取れませんでした（例: 1200円、3,000円、2千円）。');
    }
    final kind = _extractKind(text);
    final date = _extractDate(text, today) ?? today;
    final category = _extractCategory(text, kind);
    final store = _extractStore(text, amountMatch);

    final receipt = Receipt(
      kind: kind,
      storeName: store.isEmpty
          ? (kind == EntryKind.income ? '収入' : '（摘要なし）')
          : store,
      date: date,
      amount: amountMatch.value,
      category: category,
      memo: '音声入力: $text',
    );
    return VoiceCommand.add(receipt);
  }

  // ---- 修正・削除（対象の候補を探す。実際の変更は利用者の承認後） ----

  static VoiceCommand _parseEdit(String text, DateTime today) {
    // 「A を B に直す」形式: 「に／へ」の直前の金額が新しい金額、
    // それより前の部分が対象
    final arrow = RegExp(r'(に|へ)\s*(?:変更|修正|直|訂正|書き換え|書き直)');
    final m = arrow.firstMatch(text);
    if (m != null) {
      final before = text.substring(0, m.start);
      // 新しい金額は「に」の直前にある金額（最後に出てくるもの）
      final newAmount =
          _lastAmount(before) ?? _findAmount(text.substring(m.start));
      if (newAmount == null) {
        return const VoiceCommand.unknown('修正後の金額が読み取れませんでした（例: 1500円に直す）。');
      }
      // 対象は新しい金額より前の部分（「1200円を」など）
      final targetPart = before.substring(0, newAmount.start);
      return VoiceCommand.edit(
        newAmount: newAmount.value,
        target: _extractTarget(targetPart, today),
      );
    }

    // 「に」を使わない形式（例: 5月3日の食費 3000円 修正）
    // 新しい金額は最後の金額、対象は手前の部分
    final newAmount = _lastAmount(text);
    if (newAmount == null) {
      return const VoiceCommand.unknown('修正後の金額が読み取れませんでした（例: 1500円に直す）。');
    }
    final targetPart = text.substring(0, newAmount.start);
    return VoiceCommand.edit(
      newAmount: newAmount.value,
      target: _extractTarget(targetPart, today),
    );
  }

  static VoiceCommand _parseDelete(String text, DateTime today) {
    final target = _extractTarget(text, today);
    return VoiceCommand.delete(target: target);
  }

  /// 文中で最後に出てくる金額（「A円をB円に」の B 側に当たる）
  static _AmountMatch? _lastAmount(String text) {
    _AmountMatch? last;
    var rest = text;
    var offset = 0;
    while (true) {
      final found = _findAmount(rest);
      if (found == null) break;
      last = _AmountMatch(
        found.value,
        offset + found.start,
        offset + found.end,
      );
      offset += found.end;
      rest = text.substring(offset);
    }
    return last;
  }

  /// 対象（日付・カテゴリ・金額・収支の区分）を取り出す。すべて任意。
  static VoiceTarget _extractTarget(String text, DateTime today) {
    final date = _extractDate(text, today);
    final category = _categoryWord(text);
    // 対象の金額は「円」付きの数字のみ（修正後の金額は既に除かれている）
    final amount = _findAmount(text)?.value;
    final kind = text.contains('収入') ? EntryKind.income : null;
    return VoiceTarget(
      date: date,
      category: category,
      amount: amount,
      kind: kind,
    );
  }

  // ---- 部品 ----

  /// 全角数字・記号を半角に寄せ、余計な空白を取り除く
  static String _normalize(String s) {
    final sb = StringBuffer();
    for (final ch in s.trim().runes) {
      if (ch >= 0xFF10 && ch <= 0xFF19) {
        sb.writeCharCode(ch - 0xFF10 + 0x30); // 全角数字
      } else if (ch == 0xFF0C) {
        sb.write(','); // 全角カンマ
      } else if (ch == 0x3000) {
        sb.write(' '); // 全角スペース
      } else if (ch == 0xFFE5) {
        sb.write('¥'); // 全角円記号
      } else {
        sb.writeCharCode(ch);
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static int _lastIndexOfAny(String text, List<String> words) {
    var idx = -1;
    for (final w in words) {
      final i = text.lastIndexOf(w);
      if (i > idx) idx = i;
    }
    return idx;
  }

  /// 金額を探す。位置（開始・終了）も返す（店名の除去などに使う）
  static _AmountMatch? _findAmount(String text) {
    // 「○万○千」「○千○百」の表記（例: 1万2千円、2万円、2千円、3千5百円）
    final kanji = RegExp(
      r'(\d+)\s*万\s*(?:(\d+)\s*千)?\s*(?:(\d+)\s*百)?\s*(?:円|¥)?|(\d+)\s*千\s*(?:(\d+)\s*百)?\s*(?:円|¥)?',
    );
    for (final m in kanji.allMatches(text)) {
      if (m.group(1) != null) {
        final man = int.parse(m.group(1)!);
        final sen = int.tryParse(m.group(2) ?? '') ?? 0;
        final hyaku = int.tryParse(m.group(3) ?? '') ?? 0;
        final value = man * 10000 + sen * 1000 + hyaku * 100;
        if (value > 0 && !_isDatePart(text, m.start, m.end)) {
          return _AmountMatch(value, m.start, m.end);
        }
      } else if (m.group(4) != null) {
        final sen = int.parse(m.group(4)!);
        final hyaku = int.tryParse(m.group(5) ?? '') ?? 0;
        final value = sen * 1000 + hyaku * 100;
        if (value > 0 && !_isDatePart(text, m.start, m.end)) {
          return _AmountMatch(value, m.start, m.end);
        }
      }
    }

    // 円・¥ が付いた数字を優先（「1,200円」「¥1200」「1200円也」）
    final yen = RegExp(
      r'[¥]?\s*([\d,]+)\s*(?:円|¥)(?:也)?|¥\s*([\d,]+)',
    ).firstMatch(text);
    if (yen != null) {
      final value = _toInt(yen.group(1) ?? yen.group(2)!);
      if (value > 0) return _AmountMatch(value, yen.start, yen.end);
    }

    // 「円」がなくても、日付の一部でない数字を金額とみなす（最大のもの）
    _AmountMatch? best;
    for (final m in RegExp(r'\d[\d,]*').allMatches(text)) {
      if (_isDatePart(text, m.start, m.end)) continue;
      final v = _toInt(m.group(0)!);
      if (v <= 0) continue;
      if (best == null || v > best.value) {
        best = _AmountMatch(v, m.start, m.end);
      }
    }
    return best;
  }

  /// 「5月3日」「5/3」「2025/5/3」などの日付の一部かどうか
  static bool _isDatePart(String text, int start, int end) {
    final after = text.substring(end);
    final before = text.substring(0, start);
    if (RegExp(r'^\s*[月/／.-]').hasMatch(after)) return true;
    if (RegExp(r'[/／.-]\s*$').hasMatch(before)) return true;
    if (RegExp(r'^\s*日').hasMatch(after) &&
        text.substring(start, end).length <= 2) {
      return true;
    }
    return false;
  }

  static int _toInt(String s) => int.tryParse(s.replaceAll(',', '')) ?? 0;

  static EntryKind _extractKind(String text) {
    if (text.contains('収入') ||
        text.contains('入金') ||
        text.contains('補助') ||
        text.contains('売上') ||
        _containsAny(text, _incomeVerbs)) {
      return EntryKind.income;
    }
    if (_containsAny(text, _expenseVerbs) || text.contains('支出')) {
      return EntryKind.expense;
    }
    return EntryKind.expense;
  }

  /// 「今日」「昨日」「一昨日」「5月3日」「5/3」「2025年5月3日」を日付にする。見つからなければ null
  static DateTime? _extractDate(String text, DateTime today) {
    if (text.contains('一昨日') || text.contains('おととい')) {
      return today.subtract(const Duration(days: 2));
    }
    if (text.contains('昨日') || text.contains('きのう')) {
      return today.subtract(const Duration(days: 1));
    }
    if (text.contains('今日') || text.contains('きょう') || text.contains('本日')) {
      return today;
    }

    final full = RegExp(
      r'(\d{4})[年/.\-](\d{1,2})[月/.\-](\d{1,2})',
    ).firstMatch(text);
    if (full != null) {
      return _safeDate(
        int.parse(full.group(1)!),
        int.parse(full.group(2)!),
        int.parse(full.group(3)!),
      );
    }
    final md =
        RegExp(r'(\d{1,2})\s*月\s*(\d{1,2})\s*日?').firstMatch(text) ??
        RegExp(r'(\d{1,2})/(\d{1,2})').firstMatch(text);
    if (md != null) {
      return _safeDate(
        today.year,
        int.parse(md.group(1)!),
        int.parse(md.group(2)!),
      );
    }
    return null;
  }

  /// 存在しない日付（2月30日など）は null
  static DateTime? _safeDate(int y, int m, int d) {
    if (m < 1 || m > 12 || d < 1 || d > 31) return null;
    final dt = DateTime(y, m, d);
    if (dt.month != m || dt.day != d) return null;
    return dt;
  }

  static bool _containsAny(String text, List<String> words) =>
      words.any(text.contains);

  static String? _categoryWord(String text) {
    for (final c in [...receiptCategories, ...incomeCategories]) {
      if (c != 'その他' && text.contains(c)) return c;
    }
    for (final e in _categoryAliases.entries) {
      if (text.contains(e.key)) return e.value;
    }
    return null;
  }

  static String _extractCategory(String text, EntryKind kind) {
    final found = _categoryWord(text);
    if (found != null) return found;
    return kind == EntryKind.income ? '雑収入' : '雑費';
  }

  /// 摘要（店名・内容）。日付・金額・操作語・収支の語を除いた残りを使う。
  /// 助詞は語の境界にある「の」「で」「を」などだけを除き、店名の中の文字は残す。
  static String _extractStore(String text, _AmountMatch amount) {
    // 金額の位置を取り除いてから、日付・語を消す
    var s = text.replaceRange(amount.start, amount.end, ' ');
    final removeWords = [
      ..._addWords,
      ..._expenseVerbs,
      ..._incomeVerbs,
      ..._deleteWords,
      ..._editWords,
      '収入',
      '支出',
      '今日',
      '昨日',
      '一昨日',
      'きのう',
      'きょう',
      'おととい',
      '本日',
      '円',
      '¥',
    ];
    // 長い語から順に消す（「取り消し」より「取り消」など部分一致の衝突を避ける）
    final sorted = [...removeWords, ...receiptCategories, ...incomeCategories]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final w in sorted) {
      if (w == 'その他') continue;
      s = s.replaceAll(w, ' ');
    }
    s = s.replaceAll(RegExp(r'\d{4}[年/.\-]\d{1,2}[月/.\-]\d{1,2}日?'), ' ');
    s = s.replaceAll(RegExp(r'\d{1,2}\s*月\s*\d{1,2}\s*日?'), ' ');
    s = s.replaceAll(RegExp(r'\d{1,2}/\d{1,2}'), ' ');
    s = s.replaceAll(RegExp(r'\d[\d,]*\s*(万|千|百)?'), ' ');
    // 語の境界にある助詞だけを除く（前後が空白・記号の場合）
    s = s.replaceAll(RegExp(r'(^|\s)[のをでにはがへとも](?=\s|$)'), ' ');
    s = s.replaceAll(RegExp(r'[、。,，！!？?]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

/// 金額の検出結果（値と、入力文中の位置）
class _AmountMatch {
  final int value;
  final int start;
  final int end;
  const _AmountMatch(this.value, this.start, this.end);
}

/// 解析結果
class VoiceCommand {
  final VoiceAction action;
  final Receipt? receipt; // 追加のとき
  final int? newAmount; // 修正のとき
  final VoiceTarget? target; // 修正・削除の対象条件
  final String? message; // 解釈できなかった理由

  const VoiceCommand._(
    this.action, {
    this.receipt,
    this.newAmount,
    this.target,
    this.message,
  });

  const VoiceCommand.unknown(String reason)
    : this._(VoiceAction.unknown, message: reason);

  factory VoiceCommand.add(Receipt r) =>
      VoiceCommand._(VoiceAction.add, receipt: r);

  factory VoiceCommand.edit({
    required int newAmount,
    required VoiceTarget target,
  }) => VoiceCommand._(VoiceAction.edit, newAmount: newAmount, target: target);

  factory VoiceCommand.delete({required VoiceTarget target}) =>
      VoiceCommand._(VoiceAction.delete, target: target);
}

enum VoiceAction { add, edit, delete, unknown }

/// 修正・削除の対象を絞り込む条件（指定がない項目は無視する）
class VoiceTarget {
  final DateTime? date;
  final String? category;
  final int? amount;
  final EntryKind? kind;

  const VoiceTarget({this.date, this.category, this.amount, this.kind});

  bool get isEmpty =>
      date == null && category == null && amount == null && kind == null;

  /// 既存の明細が条件に合うか
  bool matches(Receipt r) {
    if (r.deleted) return false;
    if (date != null &&
        (r.date.year != date!.year ||
            r.date.month != date!.month ||
            r.date.day != date!.day)) {
      return false;
    }
    if (category != null && r.category != category) return false;
    if (amount != null && r.amount != amount) return false;
    if (kind != null && r.kind != kind) return false;
    return true;
  }
}
