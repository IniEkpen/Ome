import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../theme/app_theme.dart';
import '../utils/validators.dart';
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
    try {
      await GroupService(
        AuthScope.read(context),
      ).createGroup(groupName: _groupName.text.trim(), members: _memberList);
      if (!mounted) return;
      showMessage(context, 'Group "${_groupName.text.trim()}" created');
      _formKey.currentState!.reset();
      _groupName.clear();
      _members.clear();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const YuwoAppBar(),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SectionHeader(
              'Your Groups',
              subtitle: 'People you split costs with',
            ),
            const SizedBox(height: AppSpacing.field),
            AppCard(
              width: double.infinity,
              child: Text(
                'No groups yet',
                style: AppText.body.copyWith(color: AppColors.hint),
              ),
            ),
            const SizedBox(height: AppSpacing.section),
            const SectionHeader(
              'Create a Group',
              subtitle: 'A payment method is required to create a group',
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
            ),
          ],
        ),
      ),
    );
  }
}
