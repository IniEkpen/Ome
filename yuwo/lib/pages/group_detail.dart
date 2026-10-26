import 'package:flutter/material.dart';

import '../groups/groupmodel.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../splits/split_checkout.dart';
import '../splits/split_model.dart';
import '../splits/split_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../utils/validators.dart';
import '../widgets/common.dart';
import 'new_bill.dart';

/// One group. While this screen is open it stays connected to the group's
/// live channel, so when the owner opens a bill the payment popup appears on
/// every member's phone at the same time.
class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({super.key, required this.group});

  final GroupModel group;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  late final LiveSplit _live;
  // Each bill pops up on its own once; after that it's reopened from the card.
  final Set<int> _autoOpened = {};
  bool _popupOpen = false;

  @override
  void initState() {
    super.initState();
    _live = LiveSplit(AuthScope.read(context), widget.group.id)
      ..addListener(_maybeOpenPopup);
  }

  @override
  void dispose() {
    _live
      ..removeListener(_maybeOpenPopup)
      ..dispose();
    super.dispose();
  }

  void _maybeOpenPopup() {
    final split = _live.split;
    if (split == null || !split.isClaiming || _popupOpen) return;
    if (!_autoOpened.add(split.id)) return;
    _openPopup();
  }

  Future<void> _openPopup() async {
    if (_popupOpen || !mounted) return;
    _popupOpen = true;
    await showSplitCheckout(context, _live);
    _popupOpen = false;
  }

  Future<void> _startBill() async {
    final split = await Navigator.of(context).push<SplitBill>(
      MaterialPageRoute(builder: (_) => NewBillPage(group: widget.group)),
    );
    // The live channel delivers it too; applying it here just avoids waiting.
    if (split != null) _live.apply(split);
  }

  Future<void> _invite() async {
    final members = await showDialog<List<String>>(
      context: context,
      builder: (_) => const _InviteDialog(),
    );
    if (members == null || members.isEmpty || !mounted) return;
    try {
      final invited = await GroupService(
        AuthScope.read(context),
      ).inviteMembers(widget.group.id, members);
      if (!mounted) return;
      showMessage(
        context,
        invited == 0
            ? 'No new invites sent. Check the usernames, or they may already be in the group.'
            : 'Sent $invited invite${invited == 1 ? '' : 's'}.',
      );
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this group?'),
        content: Text(
          "You won't see ${widget.group.groupname}'s bills any more. The owner "
          'can invite you back.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await GroupService(AuthScope.read(context)).leaveGroup(widget.group.id);
      // The groups list reloads when this page closes.
      if (mounted) Navigator.of(context).pop();
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          group.groupname,
          style: AppText.sectionTitle.copyWith(fontSize: 16),
        ),
        actions: [
          if (group.isOwner)
            IconButton(
              tooltip: 'Invite people',
              icon: const Icon(Icons.person_add_alt),
              onPressed: _invite,
            )
          else
            IconButton(
              tooltip: 'Leave group',
              icon: const Icon(Icons.logout),
              onPressed: _leave,
            ),
        ],
      ),
      body: PageBody(
        child: ListenableBuilder(
          listenable: _live,
          builder: (context, _) {
            final split = _live.split;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SectionHeader(
                  'Bill',
                  subtitle: _live.connected ? 'Live' : 'Connecting…',
                ),
                const SizedBox(height: AppSpacing.field),
                AppCard(
                  width: double.infinity,
                  child: split == null || split.isFinished
                      ? _NoBill(isOwner: group.isOwner, onStart: _startBill)
                      : _BillSummary(split: split, onOpen: _openPopup),
                ),
                const SizedBox(height: AppSpacing.section),
                SectionHeader(
                  'Members',
                  subtitle: '${group.people.length} in this group',
                ),
                const SizedBox(height: AppSpacing.field),
                AppCard(
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final name in group.people)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(name, style: AppText.body),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Asks for usernames and returns them, or null when cancelled.
class _InviteDialog extends StatefulWidget {
  const _InviteDialog();

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _formKey = GlobalKey<FormState>();
  final _members = TextEditingController();

  @override
  void dispose() {
    _members.dispose();
    super.dispose();
  }

  List<String> get _memberList => _members.text
      .split(',')
      .map((m) => m.trim())
      .where((m) => m.isNotEmpty)
      .toSet()
      .toList();

  String? _validate(String? _) {
    if (_memberList.isEmpty) return 'Enter at least one username';
    for (final member in _memberList) {
      if (Validators.username(member) != null) {
        return '"$member" is not a valid username';
      }
    }
    return null;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_memberList);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Invite people'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _members,
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _submit(),
          decoration: const InputDecoration(
            hintText: 'Usernames, comma separated',
          ),
          validator: _validate,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Invite')),
      ],
    );
  }
}

class _NoBill extends StatelessWidget {
  const _NoBill({required this.isOwner, required this.onStart});

  final bool isOwner;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    if (!isOwner) {
      return Text(
        "No open bill. When the owner starts one, it'll pop up here for everyone.",
        style: AppText.body.copyWith(color: AppColors.hint),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Paying for the group? Enter the bill and it pops up on everyone's "
          'phone so they can pick what they had.',
          style: AppText.body.copyWith(color: AppColors.hint),
        ),
        const SizedBox(height: AppSpacing.field),
        ElevatedButton(onPressed: onStart, child: const Text('Start a bill')),
      ],
    );
  }
}

class _BillSummary extends StatelessWidget {
  const _BillSummary({required this.split, required this.onOpen});

  final SplitBill split;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(split.title, style: AppText.pageTitle.copyWith(fontSize: 22)),
        Text(
          split.isClaiming
              ? 'Open · ${Money.format(split.totalCents)} · pick your items'
              : 'Confirmed · ${Money.format(split.totalCents)} · collecting payments',
          style: AppText.caption.copyWith(color: AppColors.hint),
        ),
        const SizedBox(height: AppSpacing.field),
        ElevatedButton(onPressed: onOpen, child: const Text('Open bill')),
      ],
    );
  }
}
