import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../pages/group_detail.dart";
import "../theme/app_theme.dart";
import "groupstate.dart";

class Joined extends StatelessWidget {
  const Joined({super.key});

  // Each card peeks out [_offset] below the one before it, like a wallet.
  static const double _offset = 95;
  static const double _cardHeight = 120;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GroupsState>();

    if (state.isLoading && state.groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final accepted = state.accepted;

    if (accepted.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You're not part of any groups yet",
              style: AppText.sectionTitle,
            ),
            Text("Tap + at the top to create one", style: AppText.caption),
          ],
        ),
      );
    }

    // Kept the original Stack/Positioned layout. The stack now sizes itself
    // to fit every card, so groups past the second one no longer get clipped.
    return SizedBox(
      height: (accepted.length - 1) * _offset + _cardHeight,
      child: Stack(
        children: List.generate(accepted.length, (index) {
          final group = accepted[index];
          final colors =
              AppColors.groupCards[index % AppColors.groupCards.length];
          return Positioned(
            top: index * _offset,
            left: 0,
            right: 0,
            child: GestureDetector(
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => GroupDetailPage(group: group),
                  ),
                );
                if (context.mounted) context.read<GroupsState>().loadAll();
              },
              child: Container(
                height: _cardHeight,
                padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: colors,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  // A faint edge so stacked black cards don't merge.
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                  // The bottom card lifts the whole stack; the rest cast
                  // upward onto the card beneath them.
                  boxShadow: index == 0
                      ? AppShadows.tinted(colors.last)
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 16,
                            offset: const Offset(0, -4),
                          ),
                        ],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        group.groupname,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.pageTitle.copyWith(
                          color: AppColors.surface,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Text(
                        group.hasOpenSplit
                            ? "Bill open"
                            : "${group.people.length} "
                                  "${group.people.length == 1 ? "member" : "members"}",
                        style: AppText.sectionTitle.copyWith(
                          color: AppColors.surface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
