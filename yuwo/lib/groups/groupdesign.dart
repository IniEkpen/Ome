import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "../theme/app_theme.dart";
import "../widgets/common.dart";
import "groupstate.dart";
import "grouplists.dart";
import "joinedgroups.dart";

class Group extends StatefulWidget {
  const Group({super.key});
  @override
  State<Group> createState() => _Grouping();
}

// When a user clicks create group button pop up should take up screen..to add groups users
// NOTE: behaviour left as you had it -- you said you'll fix this later. Only the styling changed.
class Popup extends StatefulWidget {
  const Popup({super.key});
  @override
  State<Popup> createState() => Popups();
}

class Popups extends State<Popup> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.ink,
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Create A Group",
            style: AppText.pageTitle.copyWith(
              color: AppColors.surface,
              fontSize: 22,
            ),
          ),
          Text("Search friends to add to your group", style: AppText.caption),
        ],
      ),
      content: SizedBox(
        width: AppSpacing.contentMaxWidth,
        child: TextField(
          style: AppText.body.copyWith(color: AppColors.surface),
          cursorColor: AppColors.surface,
          decoration: InputDecoration(
            hintText: "add users",
            fillColor: AppColors.inkSoft,
            prefixIcon: const Icon(Icons.search),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.control),
              borderSide: const BorderSide(color: AppColors.surface),
            ),
          ),
        ),
      ),
    );
  }
}

class _Grouping extends State<Group> {
  @override
  Widget build(BuildContext context) {
    // GroupsState created once here, above both GroupInvite and Joined,
    // so they share one list and one fetch instead of each fetching separately.
    return ChangeNotifierProvider(
      create: (_) => GroupsState()..loadAll(),
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.page),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Yuwo", style: AppText.brand),
                          const SizedBox(height: AppSpacing.field),
                          Text("Groups", style: AppText.pageTitle),
                          Text(
                            "Split costs with the people you share them with",
                            style: AppText.caption,
                          ),
                        ],
                      ),
                    ),
                    FloatingActionButton(
                      tooltip: "Create group",
                      onPressed: () => showDialog(
                        context: context,
                        builder: (BuildContext context) => const Popup(),
                      ),
                      child: const Icon(Icons.add),
                    ),
                  ],
                ),

                const SizedBox(height: AppSpacing.section),

                // Pending invites.
                const SectionHeader(
                  "Invites",
                  subtitle: "Groups waiting on your answer",
                ),
                const SizedBox(height: AppSpacing.field),
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: GroupInvite(),
                ),

                const SizedBox(height: AppSpacing.section),

                const SectionHeader(
                  "Groups",
                  subtitle: "Groups you've joined",
                ),
                const SizedBox(height: AppSpacing.field),
                const Joined(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
