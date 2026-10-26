import 'auth_service.dart';

/// The signed-in user's account details from /users/me.
class UserProfile {
  const UserProfile({
    required this.username,
    this.firstName,
    this.lastName,
    this.email,
    this.phone,
    this.transactionsPrivate = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    username: json['username'] as String? ?? '',
    firstName: json['firstName'] as String?,
    lastName: json['lastName'] as String?,
    email: json['email'] as String?,
    phone: json['phone'] as String?,
    transactionsPrivate: json['transactionsPrivate'] == true,
  );

  final String username;
  final String? firstName;
  final String? lastName;
  final String? email;
  final String? phone;

  /// Payments this user makes stay off the public network map.
  final bool transactionsPrivate;

  /// "First Last", or the username when no name was given.
  String get displayName {
    final name = [firstName, lastName].whereType<String>().join(' ').trim();
    return name.isEmpty ? username : name;
  }
}

class ProfileService {
  const ProfileService(this._auth);

  final AuthService _auth;

  Future<UserProfile> load() async {
    final response = (await _auth.client.get(
      '/users/me',
    )).orThrow("Couldn't load your profile.");
    return UserProfile.fromJson(response.json ?? const {});
  }

  /// Changes whether new payments you make are private by default.
  Future<UserProfile> setTransactionsPrivate(bool private) async {
    final response = (await _auth.client.patch(
      '/users/me',
      body: {'transactionsPrivate': private},
    )).orThrow("Couldn't update your privacy setting.");
    return UserProfile.fromJson(response.json ?? const {});
  }
}
