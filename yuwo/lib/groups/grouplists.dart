import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../theme/app_theme.dart";
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
      return const SizedBox(
        width: 400,
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final pending = state.pending;

    if (pending.isEmpty) {
      // ASSUMPTION: previously this fell back to Icon(Icons.add_task_rounded)
      // for any non-pending group -- kept the icon as an empty-state card.
      return Container(
        width: 400,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_task_rounded, color: AppColors.hint),
            const SizedBox(width: AppSpacing.field),
            Text("You're all caught up", style: AppText.sectionTitle),
          ],
        ),
      );
    }

    return Row(
      spacing: AppSpacing.field,
      children: pending.map((group) => _InviteCard(group: group)).toList(),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final GroupModel group;
  const _InviteCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final buttonShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.control),
    );

    return Container(
      width: 400,
      height: 200,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.textPrimary,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  group.groupname,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.pageTitle.copyWith(
                    color: AppColors.surface,
                    fontSize: 22,
                  ),
                ),
              ),
              _MemberStack(people: group.people),
            ],
          ),
          // ASSUMPTION: no "invited by" field exists on Group yet.
          // Add an `invitedBy` field to Group/fromJson if your API sends one,
          // then swap this back to something like "${group.invitedBy} invited you...".
          Text(
            "You've been invited to join ${group.groupname}",
            style: AppText.caption,
          ),
          const Spacer(),
          Row(
            spacing: AppSpacing.field,
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () =>
                      context.read<GroupsState>().respond(group.groupname, false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.hint),
                    minimumSize: const Size(0, 44),
                    shape: buttonShape,
                  ),
                  child: const Text("Decline"),
                ),
              ),
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      context.read<GroupsState>().respond(group.groupname, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textPrimary,
                    minimumSize: const Size(0, 44),
                    shape: buttonShape,
                  ),
                  child: const Text("Accept"),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Overlapping initials for the first few members of a group.
class _MemberStack extends StatelessWidget {
  const _MemberStack({required this.people});

  final List<String> people;

  @override
  Widget build(BuildContext context) {
    final shown = people.take(3).toList();
    if (shown.isEmpty) return const SizedBox.shrink();

    const size = 28.0;
    return SizedBox(
      width: size + (shown.length - 1) * 18,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * 18,
              child: CircleAvatar(
                radius: size / 2,
                backgroundColor: AppColors.textPrimary,
                child: CircleAvatar(
                  radius: size / 2 - 2,
                  backgroundColor: AppColors.groupCards[i % AppColors.groupCards.length].first,
                  child: Text(
                    shown[i].isEmpty ? "?" : shown[i][0].toUpperCase(),
                    style: AppText.sectionTitle.copyWith(color: AppColors.surface),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
