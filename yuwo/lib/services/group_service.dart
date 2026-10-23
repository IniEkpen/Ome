import '../groups/groupmodel.dart';
import 'api_client.dart';
import 'auth_service.dart';

class GroupService {
  const GroupService(this._auth);

  final AuthService _auth;

  // The acting user always comes from the session token, never from user input.

  Future<List<GroupModel>> listGroups() async {
    final response = (await _auth.client.get(
      '/groups',
    )).orThrow("Couldn't load groups");
    final rows = response.body is List ? response.body as List : const [];
    return rows
        .map((g) => GroupModel.fromJson(g as Map<String, dynamic>))
        .toList();
  }

  /// Throws an [ApiException] with `isCardRequired` when there's no valid card.
  /// Returns the usernames that couldn't be found.
  Future<List<String>> createGroup({
    required String groupName,
    required List<String> members,
  }) async {
    final response = (await _auth.client.post(
      '/groups',
      body: {'groupName': groupName, 'members': members},
    )).orThrow("We couldn't create that group. Please try again.");
    return List<String>.from(response.json?['notFound'] ?? const []);
  }

  /// Accepting needs a valid card (`isCardRequired` otherwise).
  Future<void> respondToInvite(int groupId, {required bool accept}) async {
    (await _auth.client.post(
      '/groups/$groupId/invites/respond',
      body: {'accept': accept},
    )).orThrow("Couldn't update that invite.");
  }

  /// Only call after the user has confirmed in the UI.
  Future<void> deleteGroup(int groupId) async {
    (await _auth.client.delete(
      '/groups/$groupId',
    )).orThrow("We couldn't delete that group.");
  }
}
