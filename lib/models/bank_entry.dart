import 'package:uuid/uuid.dart';

import 'receipt.dart';

/// 口座の出納（ATM入出金）1行
///
/// サンプルの「ATM入出金」表に対応する。
/// - deposit: 入金（集金など口座への入金）
/// - withdraw: 出金（口座からの引き落とし・振込など）
/// - cashOut: 現金引出（口座 → 手持ち現金。サンプルの「カード出金」）
///
/// 現金引出は口座残高を減らすが、収支（会計）の収入・支出にはしない。
enum BankEntryKind {
  deposit('入金'),
  withdraw('出金'),
  cashOut('現金引出');

  final String label;
  const BankEntryKind(this.label);

  static BankEntryKind fromName(String? name) {
    switch (name) {
      case 'withdraw':
        return BankEntryKind.withdraw;
      case 'cashOut':
        return BankEntryKind.cashOut;
      default:
        return BankEntryKind.deposit;
    }
  }
}

/// 口座の出納1行。削除は tombstone（deleted = true）として残し、同期で全員に伝える。
class BankEntry {
  final String id;
  final DateTime date;
  final BankEntryKind kind;
  final String label; // 摘要（例: 1月、2月集金分）
  final int amount; // 円（正の値）
  final DateTime updatedAt;
  final bool deleted;

  BankEntry({
    String? id,
    required this.date,
    required this.kind,
    required this.label,
    required this.amount,
    DateTime? updatedAt,
    this.deleted = false,
  }) : id = id ?? const Uuid().v4(),
       updatedAt = updatedAt ?? DateTime.now();

  /// 口座残高への影響（入金は＋、出金・現金引出は－）
  int get balanceDelta => kind == BankEntryKind.deposit ? amount : -amount;

  BankEntry copyWith({
    DateTime? date,
    BankEntryKind? kind,
    String? label,
    int? amount,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return BankEntry(
      id: id,
      date: date ?? this.date,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      amount: amount ?? this.amount,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'kind': kind.name,
    'label': label,
    'amount': amount,
    'updatedAt': isoMillis(updatedAt),
    'deleted': deleted,
  };

  factory BankEntry.fromJson(Map<String, dynamic> json) {
    final date =
        DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now();
    return BankEntry(
      id: json['id'] as String,
      date: date,
      kind: BankEntryKind.fromName(json['kind'] as String?),
      label: json['label'] as String? ?? '',
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? date,
      deleted: json['deleted'] as bool? ?? false,
    );
  }
}
