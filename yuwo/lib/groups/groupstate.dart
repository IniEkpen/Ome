import "package:flutter/material.dart";
import "groupmodel.dart";
import "grouplogic.dart";

// Single source of truth for group data. Create ONE instance of this above
// both GroupInvite and Joined (see groupdesign.dart) so accepting/declining
// an invite in one widget instantly updates the other -- no separate fetches.
class GroupsState extends ChangeNotifier {
  List<GroupModel> _groups = [];
  bool isLoading = false;
  String? error;

  List<GroupModel> get groups => _groups;
  List<GroupModel> get pending =>
      _groups.where((g) => g.status == 'pending').toList();
  List<GroupModel> get accepted =>
      _groups.where((g) => g.status == 'accepted').toList();

  Future<void> loadAll() async {
    isLoading = true;
    error = null;
    notifyListeners();

    final result = await loadGroups();

    isLoading = false;
    if (result != null) {
      _groups = result;
    } else {
      error = "Couldn't load groups";
    }
    notifyListeners();
  }

  // Accept (true) or decline (false) a pending invite.
  Future<void> respond(String groupname, bool accept) async {
    final result = await groupChoice(accept, groupname: groupname);

    if (result != null) {
      // Server sent back the authoritative full list -- use it.
      _groups = result;
      notifyListeners();
    } else {
      // ASSUMPTION: on failure we leave state untouched so the invite
      // stays visible and the user can retry. Swap `error` for a
      // SnackBar/toast trigger if you'd rather surface this directly.
      error = "Couldn't update $groupname";
      notifyListeners();
    }
  }

  Future<void> create(String groupname, List<String> people) async {
    final result = await createGroup(groupname, people);
    if (result != null) {
      _groups = result;
      notifyListeners();
    } else {
      error = "Couldn't create $groupname";
      notifyListeners();
    }
  }
}