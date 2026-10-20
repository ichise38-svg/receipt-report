import 'package:uuid/uuid.dart';

/// 経費カテゴリ
const List<String> receiptCategories = [
  '交通費',
  '食費',
  '消耗品費',
  '通信費',
  '交際費',
  '雑費',
  'その他',
];

/// レシート1件分のデータ
class Receipt {
  final String id;
  final String imagePath;
  final String storeName;
  final DateTime date;
  final int amount; // 税込合計（円）
  final String category;
  final String memo;
  final DateTime createdAt;

  Receipt({
    String? id,
    required this.imagePath,
    required this.storeName,
    required this.date,
    required this.amount,
    required this.category,
    this.memo = '',
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();

  Receipt copyWith({
    String? imagePath,
    String? storeName,
    DateTime? date,
    int? amount,
    String? category,
    String? memo,
  }) {
    return Receipt(
      id: id,
      imagePath: imagePath ?? this.imagePath,
      storeName: storeName ?? this.storeName,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      memo: memo ?? this.memo,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
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
      imagePath: json['imagePath'] as String? ?? '',
      storeName: json['storeName'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'その他',
      memo: json['memo'] as String? ?? '',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
