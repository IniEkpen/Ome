// ASSUMPTION: 'people' is a list of usernames (List<String>).
// If your API actually sends a list of objects like {"name": "...", "id": "..."},
// change `people` below to List<Map<String, dynamic>> and adjust fromJson.
class GroupModel {
  final String groupname;
  final List<String> people;
  final String status; // 'pending' | 'accepted' | 'rejected'

  GroupModel({
    required this.groupname,
    required this.people,
    required this.status,
  });

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      groupname: json['groupname'] as String,
      people: List<String>.from(json['people'] ?? []),
      status: json['status'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'groupname': groupname,
      'people': people,
      'status': status,
    };
  }

  // Handy for updating one group's status locally without refetching everything
  GroupModel copyWith({String? groupname, List<String>? people, String? status}) {
    return GroupModel(
      groupname: groupname ?? this.groupname,
      people: people ?? this.people,
      status: status ?? this.status,
    );
  }
}