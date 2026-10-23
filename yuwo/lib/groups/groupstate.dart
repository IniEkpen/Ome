import "package:flutter/material.dart";
import "../services/api_client.dart";
import "../services/group_service.dart";
import "groupmodel.dart";

// Single source of truth for group data. Create ONE instance of this above
// both GroupInvite and Joined so accepting/declining an invite in one widget
// instantly updates the other -- no separate fetches.
class GroupsState extends ChangeNotifier {
  GroupsState(this._service);

  final GroupService _service;
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
    try {
      _groups = await _service.listGroups();
    } on ApiException catch (e) {
      error = e.message;
    }
    isLoading = false;
    notifyListeners();
  }

  // Accept (true) or decline (false) a pending invite. Rethrows so the UI can
  // send the user to add a card when the server answers `card_required`.
  Future<void> respond(GroupModel group, bool accept) async {
    await _service.respondToInvite(group.id, accept: accept);
    await loadAll();
  }
}
