import "package:flutter/material.dart";
import "package:provider/provider.dart";
import "groupstate.dart";
import "grouplists.dart";
import "joinedgroups.dart";

class Group extends StatefulWidget {
  const Group({super.key});
  @override
  State<Group> createState() => _Grouping();
}

// When a user clicks create group button pop up should take up screen..to add groups users
// NOTE: left exactly as you had it -- you said you'll fix this later.
class Popup extends StatefulWidget {
  const Popup({super.key});
  @override
  State<Popup> createState() => Popups();
}

class Popups extends State<Popup> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("Create A Group", style: TextStyle(color: Colors.white)),
      content: Container(
        alignment: Alignment.topRight,
        decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Colors.black,
            border: Border.all(color: Colors.white, width: 3.0)),
        child: TextField(
          style: TextStyle(color: Colors.white),
          decoration: InputDecoration(
              hintText: "add users",
              hintStyle: TextStyle(color: Colors.grey),
              prefixIcon: Icon(Icons.search)),
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
        body: SingleChildScrollView(
          child: Column(
            children: [
              Container(
                width: double.infinity,
                height: 200,
                alignment: Alignment.topRight,
                child: FloatingActionButton(
                  onPressed: () => showDialog(
                      context: context, builder: (BuildContext context) => const Popup()),
                  child: Icon(Icons.add),
                ),
              ),

              // Un-commented: was previously disabled, now shows pending invites.
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: GroupInvite(),
              ),

              SizedBox(width: double.infinity, height: 40),

              Text("Groups", style: TextStyle(color: Colors.grey)),

              SizedBox(width: double.infinity, height: 10),

              SizedBox(height: 245, child: Joined()),
            ],
          ),
        ),
      ),
    );
  }
}