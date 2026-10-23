import 'package:flutter/material.dart';

import '../groups/groupmodel.dart';
import '../services/auth_service.dart';
import '../splits/split_checkout.dart';
import '../splits/split_model.dart';
import '../splits/split_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
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

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          group.groupname,
          style: AppText.sectionTitle.copyWith(fontSize: 16),
        ),
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
