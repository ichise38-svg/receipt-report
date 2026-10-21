import 'package:uuid/uuid.dart';

/// 参加者名簿の1名分
class Member {
  final String id;
  final String name;
  final String note; // 所属・区分など（任意）

  Member({String? id, required this.name, this.note = ''})
    : id = id ?? const Uuid().v4();

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'note': note};

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    note: json['note'] as String? ?? '',
  );
}
