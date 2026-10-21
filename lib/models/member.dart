import 'package:uuid/uuid.dart';

import 'receipt.dart';

/// 参加者名簿の1名分（削除は tombstone として残し、同期で他の端末へ伝えます）
class Member {
  final String id;
  final String name;
  final String note; // 所属・区分など（任意）
  final DateTime updatedAt;
  final bool deleted;

  Member({
    String? id,
    required this.name,
    this.note = '',
    DateTime? updatedAt,
    this.deleted = false,
  }) : id = id ?? const Uuid().v4(),
       updatedAt = updatedAt ?? DateTime.now();

  Member copyWith({
    String? name,
    String? note,
    DateTime? updatedAt,
    bool? deleted,
  }) {
    return Member(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'note': note,
    'updatedAt': isoMillis(updatedAt),
    'deleted': deleted,
  };

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    note: json['note'] as String? ?? '',
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    deleted: json['deleted'] as bool? ?? false,
  );
}
