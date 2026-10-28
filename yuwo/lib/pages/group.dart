import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../groups/grouplists.dart';
import '../groups/groupstate.dart';
import '../groups/joinedgroups.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../services/network_service.dart';
import '../theme/app_theme.dart';
import '../transactiongraph.dart';
import '../utils/validators.dart';
import '../widgets/card_gate.dart';
import '../widgets/common.dart';
import '../widgets/username_search_field.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  final _formKey = GlobalKey<FormState>();
  final _groupName = TextEditingController();
  // Members can only come from search results, so they're real accounts.
  final _members = <Party>[];
  late final GroupsState _groups;
  late final ApiNetworkRepository _network;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    // One GroupsState for invites + joined groups so both stay in sync.
    _groups = GroupsState(GroupService(AuthScope.read(context)))..loadAll();
    _network = ApiNetworkRepository(AuthScope.read(context));
  }

  @override
  void dispose() {
    _groupName.dispose();
    _groups.dispose();
    super.dispose();
  }

  List<String> get _memberList => [for (final m in _members) m.label];

  Set<String> get _memberKeys => {
    for (final m in _members) m.label.toLowerCase(),
  };

  void _addMember(Party user) {
    if (_memberKeys.contains(user.label.toLowerCase())) return;
    setState(() => _members.add(user));
  }

  void _removeMember(Party user) => setState(() => _members.remove(user));

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
    setState(_members.clear);
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
                        UsernameSearchField(
                          hintText: 'Add members by username',
                          search: _network.searchUsers,
                          excluded: _memberKeys,
                          onSelected: _addMember,
                        ),
                        if (_members.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.field),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final member in _members)
                                InputChip(
                                  label: Text(member.label),
                                  tooltip: member.name,
                                  onDeleted: () => _removeMember(member),
                                ),
                            ],
                          ),
                        ],
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
