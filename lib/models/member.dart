import 'package:uuid/uuid.dart';

import 'receipt.dart';

/// 参加者名簿の1名分（削除は tombstone として残し、同期で他の端末へ伝えます）
class Member {
  final String id;
  final String name;
  final String note; // 所属・区分など（任意）
  final DateTime updatedAt;
  final bool deleted;

  /// イベント名 → 参加したかどうか。未登録のイベントは「参加」として扱う。
  final Map<String, bool> eventAttendance;

  Member({
    String? id,
    required this.name,
    this.note = '',
    DateTime? updatedAt,
    this.deleted = false,
    Map<String, bool>? eventAttendance,
  }) : id = id ?? const Uuid().v4(),
       updatedAt = updatedAt ?? DateTime.now(),
       eventAttendance = Map.unmodifiable(eventAttendance ?? const {});

  /// そのイベントに参加者として数えるか（未設定は参加）
  bool attendsEvent(String eventName) => eventAttendance[eventName] ?? true;

  Member copyWith({
    String? name,
    String? note,
    DateTime? updatedAt,
    bool? deleted,
    Map<String, bool>? eventAttendance,
  }) {
    return Member(
      id: id,
      name: name ?? this.name,
      note: note ?? this.note,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      eventAttendance: eventAttendance ?? this.eventAttendance,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'note': note,
    'updatedAt': isoMillis(updatedAt),
    'deleted': deleted,
    'eventAttendance': eventAttendance,
  };

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    note: json['note'] as String? ?? '',
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    deleted: json['deleted'] as bool? ?? false,
    eventAttendance: _parseAttendance(json['eventAttendance']),
  );

  static Map<String, bool> _parseAttendance(Object? raw) {
    if (raw is! Map) return {};
    return {
      for (final e in raw.entries)
        if (e.value is bool) e.key.toString(): e.value as bool,
    };
  }
}
