import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../groups/grouplists.dart';
import '../groups/groupstate.dart';
import '../groups/joinedgroups.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
import '../widgets/card_gate.dart';
import '../widgets/common.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  final _formKey = GlobalKey<FormState>();
  final _groupName = TextEditingController();
  final _members = TextEditingController();
  late final GroupsState _groups;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // One GroupsState for invites + joined groups so both stay in sync.
    _groups = GroupsState(GroupService(AuthScope.read(context)))..loadAll();
  }

  @override
  void dispose() {
    _groupName.dispose();
    _members.dispose();
    _groups.dispose();
    super.dispose();
  }

  List<String> get _memberList => _members.text
      .split(',')
      .map((m) => m.trim())
      .where((m) => m.isNotEmpty)
      .toSet()
      .toList();

  String? _validateMembers(String? _) {
    for (final member in _memberList) {
      if (Validators.username(member) != null) {
        return '"$member" is not a valid username';
      }
    }
    return null;
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final name = _groupName.text.trim();
    var notFound = const <String>[];
    // Creating a group needs a valid card; runWithCard asks for one if missing.
    final created = await runWithCard(context, () async {
      notFound = await GroupService(
        AuthScope.read(context),
      ).createGroup(groupName: name, members: _memberList);
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (!created) return;
    showMessage(
      context,
      notFound.isEmpty
          ? 'Group "$name" created. Invites sent.'
          : 'Group "$name" created. No account for: ${notFound.join(', ')}',
    );
    _formKey.currentState!.reset();
    _groupName.clear();
    _members.clear();
    await _groups.loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _groups,
      child: Scaffold(
        appBar: const YuwoAppBar(),
        body: RefreshIndicator(
          onRefresh: _groups.loadAll,
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionHeader(
                  'Invites',
                  subtitle: 'A card on file is required to join',
                ),
                const SizedBox(height: AppSpacing.field),
                const SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: GroupInvite(),
                ),
                const SizedBox(height: AppSpacing.section),
                const SectionHeader(
                  'Your Groups',
                  subtitle: 'Tap a group to open its bill',
                ),
                const SizedBox(height: AppSpacing.field),
                const Joined(),
                const SizedBox(height: AppSpacing.section),
                const SectionHeader(
                  'Create a Group',
                  subtitle: 'A card on file is required to create a group',
                ),
                const SizedBox(height: AppSpacing.field),
                AppCard(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextFormField(
                          controller: _groupName,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            hintText: 'Group Name',
                          ),
                          validator: Validators.name,
                        ),
                        const SizedBox(height: AppSpacing.field),
                        TextFormField(
                          controller: _members,
                          autocorrect: false,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            hintText: 'Members (usernames, comma separated)',
                          ),
                          validator: _validateMembers,
                        ),
                        const SizedBox(height: AppSpacing.gap),
                        LoadingButton(
                          label: 'Create Group',
                          loading: _loading,
                          onPressed: _submit,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
