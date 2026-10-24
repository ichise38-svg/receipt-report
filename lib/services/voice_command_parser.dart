import '../models/receipt.dart';

/// 音声・キーボード入力の文章を、収支の操作（追加・修正・削除）に変換する。
///
/// 端末内だけで動き、外部へは送らない。解析結果は必ず確認カードで利用者に示し、
/// 承認されてから保存する（この関数は保存しない）。
///
/// 対応する言い方の例:
///   「昨日の交通費 1200円」                 → 追加（支出・交通費・昨日）
///   「5月3日 食費 3,500円 スーパー」         → 追加（支出・食費・5/3）
///   「収入 補助金 50000円」                  → 追加（収入・補助金）
///   「さっきの交通費を1500円に直す」          → 修正（直近の該当明細の金額）
///   「5月3日の食費を削除」                   → 削除（候補を一覧で選ぶ）
class VoiceCommandParser {
  static const _addWords = ['追加', '登録', '入力', '記録'];
  static const _editWords = ['直す', '修正', '変更', '訂正', '書き換え'];
  static const _deleteWords = ['削除', '消す', '消して', '取り消し', '取消'];

  /// 文章を解析する。解釈できない場合は [VoiceCommand.unknown] を返す。
  static VoiceCommand parse(String input, {DateTime? now}) {
    final text = _normalize(input);
    if (text.isEmpty) {
      return const VoiceCommand.unknown('入力が空です。');
    }
    final today = _dateOnly(now ?? DateTime.now());

    if (_containsAny(text, _deleteWords)) {
      return _parseDelete(text, today);
    }
    if (_containsAny(text, _editWords)) {
      return _parseEdit(text, today);
    }
    return _parseAdd(text, today);
  }

  // ---- 追加 ----

  static VoiceCommand _parseAdd(String text, DateTime today) {
    final amount = _extractAmount(text);
    if (amount == null) {
      return const VoiceCommand.unknown('金額が読み取れませんでした（例: 1200円）。');
    }
    final kind = _extractKind(text);
    final date = _extractDate(text, today) ?? today;
    final category = _extractCategory(text, kind);
    final store = _extractStore(text, kind, category);

    final receipt = Receipt(
      kind: kind,
      storeName: store.isEmpty
          ? (kind == EntryKind.income ? '収入' : '（摘要なし）')
          : store,
      date: date,
      amount: amount,
      category: category,
      memo: '音声入力: $text',
    );
    return VoiceCommand.add(receipt);
  }

  // ---- 修正・削除（対象の候補を探す。実際の変更は利用者の承認後） ----

  static VoiceCommand _parseEdit(String text, DateTime today) {
    final amount = _extractAmount(text);
    if (amount == null) {
      return const VoiceCommand.unknown('修正後の金額が読み取れませんでした（例: 1500円に直す）。');
    }
    final target = _extractTarget(text, today);
    return VoiceCommand.edit(newAmount: amount, target: target);
  }

  static VoiceCommand _parseDelete(String text, DateTime today) {
    final target = _extractTarget(text, today);
    return VoiceCommand.delete(target: target);
  }

  /// 対象（日付・カテゴリ・店名・金額）を取り出す。すべて任意。
  static VoiceTarget _extractTarget(String text, DateTime today) {
    final date = _extractDate(text, today);
    final category = _categoryWord(text);
    final amount = _extractAmount(text);
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
      } else {
        sb.writeCharCode(ch);
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static bool _containsAny(String text, List<String> words) =>
      words.any(text.contains);

  /// 「1,200円」「1200円」「¥1200」「1200」（日付の数字を除く）から金額を取り出す
  static int? _extractAmount(String text) {
    // 「○万○千」の表記（例: 1万2千円）
    // 「1万2千」「1万」の表記。「千」は「万」の後の数字に付く
    final man = RegExp(r'(\d+)\s*万\s*(?:(\d+)\s*千)?').firstMatch(text);
    if (man != null) {
      final manValue = int.parse(man.group(1)!);
      final thousands = int.tryParse(man.group(2) ?? '') ?? 0;
      final value = manValue * 10000 + thousands * 1000;
      if (value > 0) return value;
    }

    // 円・¥ が付いた数字を優先
    final yen =
        RegExp(r'[¥￥]?\s*([\d,]+)\s*円').firstMatch(text) ??
        RegExp(r'[¥￥]\s*([\d,]+)').firstMatch(text);
    if (yen != null) return _toInt(yen.group(1)!);

    // 「円」がなくても、日付・数字の並びでない数字を金額とみなす
    final candidates = RegExp(r'\d[\d,]*')
        .allMatches(text)
        .where((m) => !_isDatePart(text, m))
        .map((m) => _toInt(m.group(0)!))
        .where((v) => v > 0)
        .toList();
    if (candidates.isEmpty) return null;
    return candidates.reduce((a, b) => a > b ? a : b);
  }

  /// 「5月3日」「5/3」「2025/5/3」などの日付の一部かどうか
  static bool _isDatePart(String text, RegExpMatch m) {
    final after = text.substring(m.end);
    final before = text.substring(0, m.start);
    if (RegExp(r'^\s*[月/／.-]').hasMatch(after)) return true;
    if (RegExp(r'[/／.-]\s*$').hasMatch(before)) return true;
    if (RegExp(r'^\s*日').hasMatch(after) && m.group(0)!.length <= 2) {
      return true;
    }
    return false;
  }

  static int _toInt(String s) => int.tryParse(s.replaceAll(',', '')) ?? 0;

  static EntryKind _extractKind(String text) {
    if (text.contains('収入') || text.contains('入金') || text.contains('補助')) {
      return EntryKind.income;
    }
    return EntryKind.expense;
  }

  /// 「今日」「昨日」「一昨日」「5月3日」「5/3」「2025年5月3日」を日付にする。見つからなければ null
  static DateTime? _extractDate(String text, DateTime today) {
    if (text.contains('一昨日')) return today.subtract(const Duration(days: 2));
    if (text.contains('昨日')) return today.subtract(const Duration(days: 1));
    if (text.contains('今日')) return today;

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

  static String? _categoryWord(String text) {
    for (final c in [...receiptCategories, ...incomeCategories]) {
      if (c != 'その他' && text.contains(c)) return c;
    }
    const aliases = {
      '電車': '交通費',
      'バス': '交通費',
      'タクシー': '交通費',
      'ガソリン': '交通費',
      '交通': '交通費',
      '食事': '食費',
      '昼食': '食費',
      '夕食': '食費',
      '飲み会': '交際費',
      '電話': '通信費',
      '携帯': '通信費',
      '文具': '消耗品費',
      '補助': '補助金',
    };
    for (final e in aliases.entries) {
      if (text.contains(e.key)) return e.value;
    }
    return null;
  }

  static String _extractCategory(String text, EntryKind kind) {
    final found = _categoryWord(text);
    if (found != null) return found;
    return kind == EntryKind.income ? '雑収入' : '雑費';
  }

  /// 摘要（店名・内容）。カテゴリ語・金額・日付・操作語を除いた残りを使う
  static String _extractStore(String text, EntryKind kind, String category) {
    var s = text;
    for (final w in [
      ..._addWords,
      '収入',
      '支出',
      '円',
      '¥',
      ...incomeCategories,
      ...receiptCategories,
    ]) {
      s = s.replaceAll(w, ' ');
    }
    s = s.replaceAll(RegExp(r'\d{4}[年/.\-]\d{1,2}[月/.\-]\d{1,2}日?'), ' ');
    s = s.replaceAll(RegExp(r'\d{1,2}\s*月\s*\d{1,2}\s*日?'), ' ');
    s = s.replaceAll(RegExp(r'\d{1,2}/\d{1,2}'), ' ');
    s = s.replaceAll(RegExp(r'[\d,]+'), ' ');
    s = s.replaceAll(RegExp(r'[今昨一]日|昨日|今日'), ' ');
    s = s.replaceAll(RegExp(r'[をのでにはがへ]'), ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
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
