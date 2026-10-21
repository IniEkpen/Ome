import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "groupstate.dart";

class Joined extends StatelessWidget {
  const Joined({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GroupsState>();

    if (state.isLoading && state.groups.isEmpty) {
      return const CircularProgressIndicator();
    }

    final accepted = state.accepted;

    if (accepted.isEmpty) {
      return const Text("Apart of No Groups");
    }

    // NOTE: kept your original Stack/Positioned layout. Since it's inside a
    // fixed-height SizedBox (245) in groupdesign.dart, more than ~2 groups
    // (index*95) will overflow below that box and get clipped. If you expect
    // more joined groups than that, consider a ListView instead of Stack --
    // happy to swap it if you want.
    return Stack(
      children: List.generate(accepted.length, (index) {
        final group = accepted[index];
        return Positioned(
          top: index * 95,
          left: 0,
          right: 0,
          child: Container(
            height: 120,
            decoration: BoxDecoration(
              color: Colors.orange,
              borderRadius: BorderRadius.circular(20),
            ),
            // ASSUMPTION: you'll want the group name visible here eventually --
            // left as a bare colored container to match your original exactly.
            child: Center(
              child: Text(group.groupname, style: const TextStyle(color: Colors.black)),
            ),
          ),
        );
      }),
    );
  }
}