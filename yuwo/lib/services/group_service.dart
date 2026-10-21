import 'api_client.dart';
import 'auth_service.dart';

class GroupService {
  const GroupService(this._auth);

  final AuthService _auth;

  // The acting user always comes from the session, never from user input.
  String get _username {
    final session = _auth.session;
    if (session == null) {
      throw const ApiException('Please sign in again.', statusCode: 401);
    }
    return session.username;
  }

  Future<void> createGroup({
    required String groupName,
    required List<String> members,
  }) async {
    final response = await _auth.client.post(
      '/users/groups/create',
      body: {
        'username': _username,
        'groupName': groupName,
        'userList': members,
      },
    );
    if (!response.isSuccess) {
      throw ApiException(
        "We couldn't create that group. Please try again.",
        statusCode: response.statusCode,
      );
    }
    if (response.json?['Group Created'] != true) {
      throw const ApiException('Add a payment method before creating a group.');
    }
  }

  /// Only call after the user has confirmed in the UI.
  Future<void> deleteGroup(String groupName) async {
    final response = await _auth.client.post(
      '/users/groups/delete',
      body: {'username': _username, 'groupName': groupName, 'choice': 'yes'},
    );
    if (!response.isSuccess) {
      throw ApiException(
        "We couldn't delete that group.",
        statusCode: response.statusCode,
      );
    }
  }
}
