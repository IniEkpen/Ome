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
                  subtitle: 'A card on file is required to join',
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
  final _members = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _groupName.dispose();
    _members.dispose();
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
              subtitle: 'A card on file is required to create a group',
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
    );
  }
}
