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
  late final GroupsState _groups;

  @override
  void initState() {
    super.initState();
    // One GroupsState for invites + joined groups so both stay in sync.
    _groups = GroupsState(GroupService(AuthScope.read(context)))..loadAll();
  }

  @override
  void dispose() {
    _groups.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const _CreateGroupSheet(),
    );
    if (message == null || !mounted) return;
    showMessage(context, message);
    await _groups.loadAll();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _groups,
      child: Scaffold(
        appBar: YuwoAppBar(
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton.filled(
                tooltip: 'Create group',
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.textPrimary,
                  foregroundColor: AppColors.surface,
                ),
                onPressed: _createGroup,
              ),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: _groups.loadAll,
          child: const PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  'Invites',
                  subtitle:
                      'Add a card and verify your payment details to join',
                ),
                SizedBox(height: AppSpacing.field),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  child: GroupInvite(),
                ),
                SizedBox(height: AppSpacing.section),
                SectionHeader(
                  'Your Groups',
                  subtitle: 'Tap a group to open its bill',
                ),
                SizedBox(height: AppSpacing.field),
                Joined(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opened from the + button. Closes with a message to show once the group
/// is created, or null if cancelled.
class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet();

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _formKey = GlobalKey<FormState>();
  final _groupName = TextEditingController();
  // Members can only come from search results, so they're real accounts.
  final _members = <Party>[];
  late final ApiNetworkRepository _network;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _network = ApiNetworkRepository(AuthScope.read(context));
  }

  @override
  void dispose() {
    _groupName.dispose();
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
    // Creating a group needs a card and payment verification; this asks for them.
    final created = await runWithPaymentSetup(context, () async {
      notFound = await GroupService(
        AuthScope.read(context),
      ).createGroup(groupName: name, members: _memberList);
    });
    if (!mounted) return;
    setState(() => _loading = false);
    if (!created) return;
    Navigator.of(context).pop(
      notFound.isEmpty
          ? 'Group "$name" created. Invites sent.'
          : 'Group "$name" created. No account for: ${notFound.join(', ')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keeps the form above the keyboard.
      padding: EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.page,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SectionHeader(
              'Create a Group',
              subtitle:
                  'Add a card and verify your payment details to create a group',
            ),
            const SizedBox(height: AppSpacing.gap),
            TextFormField(
              controller: _groupName,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(hintText: 'Group Name'),
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
    );
  }
}
