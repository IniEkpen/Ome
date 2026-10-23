// 'people' is the usernames of everyone who has accepted.
class GroupModel {
  final int id;
  final String groupname;
  final List<String> people;
  final String status; // 'pending' | 'accepted'
  final String role; // 'owner' | 'member'
  final bool hasOpenSplit;

  GroupModel({
    required this.id,
    required this.groupname,
    required this.people,
    required this.status,
    this.role = 'member',
    this.hasOpenSplit = false,
  });

  bool get isOwner => role == 'owner';

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] as int,
      groupname: json['groupname'] as String,
      people: List<String>.from(json['people'] ?? []),
      status: json['status'] as String,
      role: json['role'] as String? ?? 'member',
      hasOpenSplit: json['hasOpenSplit'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'groupname': groupname,
      'people': people,
      'status': status,
      'role': role,
      'hasOpenSplit': hasOpenSplit,
    };
  }

  // Handy for updating one group's status locally without refetching everything
  GroupModel copyWith({
    String? groupname,
    List<String>? people,
    String? status,
  }) {
    return GroupModel(
      id: id,
      groupname: groupname ?? this.groupname,
      people: people ?? this.people,
      status: status ?? this.status,
      role: role,
      hasOpenSplit: hasOpenSplit,
    );
  }
}
