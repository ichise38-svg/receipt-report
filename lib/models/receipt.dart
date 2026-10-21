import 'package:uuid/uuid.dart';

/// 経費カテゴリ（支出）
const List<String> receiptCategories = [
  '交通費',
  '食費',
  '消耗品費',
  '通信費',
  '交際費',
  '雑費',
  'その他',
];

/// 収入カテゴリ
const List<String> incomeCategories = [
  '売上',
  '入金',
  '補助金',
  '立替金回収',
  '雑収入',
  'その他',
];

/// 収支区分
enum EntryKind {
  expense('支出'),
  income('収入');

  final String label;
  const EntryKind(this.label);

  static EntryKind fromName(String? name) =>
      name == 'income' ? EntryKind.income : EntryKind.expense;
}

/// 収支1件分のデータ（支出はレシート画像あり、収入は画像なしも可）
class Receipt {
  final String id;
  final EntryKind kind;
  final String imagePath; // 画像なしの場合は空文字
  final String storeName; // 支出: 店舗名 / 収入: 取引先・摘要
  final DateTime date;
  final int amount; // 税込合計（円）
  final String category;
  final String memo;
  final DateTime createdAt;

  Receipt({
    String? id,
    this.kind = EntryKind.expense,
    this.imagePath = '',
    required this.storeName,
    required this.date,
    required this.amount,
    required this.category,
    this.memo = '',
    DateTime? createdAt,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now();

  bool get isIncome => kind == EntryKind.income;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'imagePath': imagePath,
    'storeName': storeName,
    'date': date.toIso8601String(),
    'amount': amount,
    'category': category,
    'memo': memo,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Receipt.fromJson(Map<String, dynamic> json) {
    return Receipt(
      id: json['id'] as String,
      kind: EntryKind.fromName(json['kind'] as String?),
      imagePath: json['imagePath'] as String? ?? '',
      storeName: json['storeName'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'その他',
      memo: json['memo'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
