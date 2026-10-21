import '../models/receipt.dart';

/// イベント別会計報告書の1行（収入の部・支出の部それぞれ）
class EventReportLine {
  final String label; // 項目（例: 会費、店舗名）
  final String note; // 補足（例: 日付、メモ）
  final int amount;

  const EventReportLine({
    required this.label,
    this.note = '',
    required this.amount,
  });
}

/// イベント別会計報告書の集計（25忘年会・旅行の形式）
///
/// 並び:
/// - 収入の部: 収入（kind = income）を項目（カテゴリ）ごとに合算
/// - 支出の部: 支出（kind = expense）を1件1行で日付順に表示
/// 総計・差引は収入総計 − 支出総計で求めます。
class EventReport {
  final String eventName;
  final List<Receipt> entries; // 対象イベントの全件（削除済みは含まない）
  final List<EventReportLine> incomeLines;
  final List<EventReportLine> expenseLines;

  EventReport._({
    required this.eventName,
    required this.entries,
    required this.incomeLines,
    required this.expenseLines,
  });

  /// 指定イベント名の登録だけを集計する（大文字小文字は区別、前後の空白は無視）
  factory EventReport.build(List<Receipt> all, String eventName) {
    final name = eventName.trim();
    final entries =
        all.where((r) => !r.deleted && r.event.trim() == name).toList()
          ..sort((a, b) => a.date.compareTo(b.date));

    // 収入は項目（カテゴリ）ごとにまとめる。出現順を保つ
    final incomeByCategory = <String, int>{};
    for (final r in entries.where((r) => r.isIncome)) {
      incomeByCategory[r.category] =
          (incomeByCategory[r.category] ?? 0) + r.amount;
    }
    final incomeLines = [
      for (final e in incomeByCategory.entries)
        EventReportLine(label: e.key, amount: e.value),
    ];

    final expenseLines = [
      for (final r in entries.where((r) => !r.isIncome))
        EventReportLine(
          label: r.storeName,
          note: [r.category, if (r.memo.isNotEmpty) r.memo].join('／'),
          amount: r.amount,
        ),
    ];

    return EventReport._(
      eventName: name,
      entries: entries,
      incomeLines: incomeLines,
      expenseLines: expenseLines,
    );
  }

  int get incomeTotal => incomeLines.fold(0, (s, l) => s + l.amount);
  int get expenseTotal => expenseLines.fold(0, (s, l) => s + l.amount);

  /// 差引金額（正なら一般会計へ残す額、負なら一般会計からの支出）
  int get balance => incomeTotal - expenseTotal;

  bool get isEmpty => entries.isEmpty;

  /// 日付の範囲（表示用）
  DateTime? get firstDate => entries.isEmpty ? null : entries.first.date;
  DateTime? get lastDate => entries.isEmpty ? null : entries.last.date;
}
