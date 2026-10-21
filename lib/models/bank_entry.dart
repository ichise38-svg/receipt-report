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

class BankEntry {
  final String id;
  final DateTime date;
  final BankEntryKind kind;
  final String label; // 摘要（例: 1月、2月集金分）
  final int amount; // 円（正の値）

  const BankEntry({
    required this.id,
    required this.date,
    required this.kind,
    required this.label,
    required this.amount,
  });

  /// 口座残高への影響（入金は＋、出金・現金引出は－）
  int get balanceDelta => kind == BankEntryKind.deposit ? amount : -amount;

  BankEntry copyWith({
    DateTime? date,
    BankEntryKind? kind,
    String? label,
    int? amount,
  }) {
    return BankEntry(
      id: id,
      date: date ?? this.date,
      kind: kind ?? this.kind,
      label: label ?? this.label,
      amount: amount ?? this.amount,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'date': date.toIso8601String(),
    'kind': kind.name,
    'label': label,
    'amount': amount,
  };

  factory BankEntry.fromJson(Map<String, dynamic> json) => BankEntry(
    id: json['id'] as String,
    date: DateTime.tryParse(json['date'] as String? ?? '') ?? DateTime.now(),
    kind: BankEntryKind.fromName(json['kind'] as String?),
    label: json['label'] as String? ?? '',
    amount: (json['amount'] as num?)?.toInt() ?? 0,
  );
}
