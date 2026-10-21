import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "groupstate.dart";
import "groupmodel.dart";

// ACCEPT OR REFUSE LIST GROUPS
// Now reads from the shared GroupsState instead of fetching its own future,
// so accepting/declining here is reflected immediately in Joined() too.
class GroupInvite extends StatelessWidget {
  const GroupInvite({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GroupsState>();

    if (state.isLoading && state.groups.isEmpty) {
      return const CircularProgressIndicator();
    }

    final pending = state.pending;

    if (pending.isEmpty) {
      // ASSUMPTION: previously this fell back to Icon(Icons.add_task_rounded)
      // for any non-pending group -- kept similar behavior as an empty-state.
      return const Icon(Icons.add_task_rounded);
    }

    return Row(
      children: pending.map((group) => _InviteCard(group: group)).toList(),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final GroupModel group;
  const _InviteCard({required this.group});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 400,
      height: 200,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white, width: 2.0),
      ),
      child: Column(
        children: [
          Container(
            height: 50,
            width: double.infinity,
            alignment: Alignment.topLeft,
            child: Text(group.groupname, style: const TextStyle(color: Colors.white)),
          ),
          Container(
            alignment: Alignment.center,
            // ASSUMPTION: no "invited by" field exists on Group yet.
            // Add an `invitedBy` field to Group/fromJson if your API sends one,
            // then swap this back to something like "${group.invitedBy} invited you...".
            child: Text(
              "You've been invited to join ${group.groupname}",
              style: const TextStyle(color: Colors.white),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ElevatedButton(
                    onPressed: () =>
                        context.read<GroupsState>().respond(group.groupname, false),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                    child: const Text("Decline", style: TextStyle(color: Colors.black)),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        context.read<GroupsState>().respond(group.groupname, true),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.white),
                    child: const Text("Accept", style: TextStyle(color: Colors.black)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}