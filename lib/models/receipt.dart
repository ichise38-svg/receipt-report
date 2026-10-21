import 'package:uuid/uuid.dart';

/// 同期用：UTC・ミリ秒精度の文字列（Apps Script 側の比較と揃える）
String isoMillis(DateTime d) {
  final u = d.toUtc();
  return DateTime.utc(
    u.year,
    u.month,
    u.day,
    u.hour,
    u.minute,
    u.second,
    u.millisecond,
  ).toIso8601String();
}

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

/// 支払方法（支出のみ使用。収入は現金扱いで保存）
///
/// デビットカードは即時引き落としのため、購入日＝口座の出金日として照合する。
enum PaymentMethod {
  cash('現金'),
  bank('口座・デビット');

  final String label;
  const PaymentMethod(this.label);

  /// 既存データ（項目なし）は現金として扱う
  static PaymentMethod fromName(String? name) =>
      name == 'bank' ? PaymentMethod.bank : PaymentMethod.cash;
}

/// 収支1件分のデータ（支出はレシート画像あり、収入は画像なしも可）
///
/// - 削除は tombstone（deleted = true）として残し、同期時に他の端末へ削除を伝えます。
/// - 変更日時 updatedAt が新しい方を優先します（最後の更新優先）。
/// - imageUrl は共有先に保存済みの画像URL。空なら未送信またはなし。
class Receipt {
  final String id;
  final EntryKind kind;
  final String imagePath; // 端末内の画像パス。画像なしは空文字
  final String storeName; // 支出: 店舗名 / 収入: 取引先・摘要
  final DateTime date;
  final int amount; // 税込合計（円）
  final String category;
  final String memo;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool deleted;
  final String imageUrl;
  final String event; // イベント名（任意）。例: 25忘年会。空なら通常の年間集計のみ
  final PaymentMethod payment; // 支払方法（支出のみ使用。既定は現金）

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
    DateTime? updatedAt,
    this.deleted = false,
    this.imageUrl = '',
    this.event = '',
    this.payment = PaymentMethod.cash,
  }) : id = id ?? const Uuid().v4(),
       createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? DateTime.now();

  bool get isIncome => kind == EntryKind.income;

  Receipt copyWith({
    EntryKind? kind,
    String? imagePath,
    String? storeName,
    DateTime? date,
    int? amount,
    String? category,
    String? memo,
    DateTime? updatedAt,
    bool? deleted,
    String? imageUrl,
    String? event,
    PaymentMethod? payment,
  }) {
    return Receipt(
      id: id,
      kind: kind ?? this.kind,
      imagePath: imagePath ?? this.imagePath,
      storeName: storeName ?? this.storeName,
      date: date ?? this.date,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      memo: memo ?? this.memo,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      imageUrl: imageUrl ?? this.imageUrl,
      event: event ?? this.event,
      payment: payment ?? this.payment,
    );
  }

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
    'updatedAt': isoMillis(updatedAt),
    'deleted': deleted,
    'imageUrl': imageUrl,
    'event': event,
    'payment': payment.name,
  };

  factory Receipt.fromJson(Map<String, dynamic> json) {
    final createdAt =
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now();
    return Receipt(
      id: json['id'] as String,
      kind: EntryKind.fromName(json['kind'] as String?),
      imagePath: json['imagePath'] as String? ?? '',
      storeName: json['storeName'] as String? ?? '',
      date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? 'その他',
      memo: json['memo'] as String? ?? '',
      createdAt: createdAt,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? createdAt,
      deleted: json['deleted'] as bool? ?? false,
      imageUrl: json['imageUrl'] as String? ?? '',
      event: json['event'] as String? ?? '',
      payment: PaymentMethod.fromName(json['payment'] as String?),
    );
  }
}
