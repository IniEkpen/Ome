import 'package:flutter/material.dart';

import '../pages/receipt_view.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/card_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';
import 'split_model.dart';
import 'split_service.dart';

/// Opens the synced payment popup. Everyone in the group sees the same
/// receipt at the same time and changes from any phone show up on all of them.
Future<void> showSplitCheckout(BuildContext context, LiveSplit live) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog.fullscreen(
      backgroundColor: AppColors.background,
      child: SplitCheckout(live: live),
    ),
  );
}

class SplitCheckout extends StatefulWidget {
  const SplitCheckout({super.key, required this.live});

  final LiveSplit live;

  @override
  State<SplitCheckout> createState() => _SplitCheckoutState();
}

class _SplitCheckoutState extends State<SplitCheckout> {
  // Own messenger so errors show on top of the popup, not behind it.
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final Set<int> _togglingItems = {};
  bool _busy = false;

  SplitService get _service => SplitService(AuthScope.read(context));
  String get _me => AuthScope.read(context).session?.username ?? '';

  void _show(String message) {
    _messenger.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<SplitBill?> Function() request) async {
    try {
      widget.live.apply(await request());
    } on ApiException catch (e) {
      _show(e.message);
    }
  }

  Future<void> _toggle(SplitBill split, SplitItem item, bool claimed) async {
    if (!_togglingItems.add(item.id)) return;
    setState(() {});
    await _run(() => _service.setClaim(split.id, item.id, claimed));
    if (mounted) setState(() => _togglingItems.remove(item.id));
  }

  Future<void> _hostAction(Future<SplitBill?> Function() request) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _run(request);
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _ask(String title, String message, String action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: AppText.sectionTitle.copyWith(fontSize: 16)),
        content: Text(message, style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _confirm(SplitBill split) async {
    final unclaimed = split.mode == SplitMode.byItem
        ? split.unclaimedItemIds.length
        : 0;
    final message = StringBuffer(
      "Each person's card is charged their share "
      '(${Money.format(split.collectedCents)} in total). '
      'Hosts cover the remaining ${Money.format(split.hostCoveredCents)}.',
    );
    if (unclaimed > 0) {
      message.write(
        '\n\n$unclaimed unclaimed ${unclaimed == 1 ? 'item is' : 'items are'} '
        'split between everyone.',
      );
    }
    if (await _ask('Confirm and charge?', message.toString(), 'Confirm')) {
      await _hostAction(() => _service.confirm(split.id));
    }
  }

  Future<void> _waive(SplitBill split, SplitParticipant person) async {
    final cents = await showDialog<int>(
      context: context,
      builder: (_) => _WaiveDialog(person: person),
    );
    if (cents != null) {
      await _hostAction(
        () => _service.setWaiver(split.id, person.userId, cents),
      );
    }
  }

  /// Pick which of your saved cards pays your share of this bill.
  Future<void> _chooseCard(SplitBill split, SplitParticipant me) async {
    final List<SavedCard> cards;
    try {
      cards = await CardService(AuthScope.read(context)).list();
    } on ApiException catch (e) {
      _show(e.message);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<SavedCard>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gap),
              child: SectionHeader(
                'Pay your share with',
                subtitle: 'Add or remove cards in Profile',
              ),
            ),
            const SizedBox(height: AppSpacing.field),
            for (final card in cards)
              ListTile(
                enabled: !card.expired,
                leading: const Icon(Icons.credit_card),
                title: Text(card.label, style: AppText.body),
                subtitle: Text(
                  [
                    if (card.expiry.isNotEmpty) 'exp ${card.expiry}',
                    if (card.isDefault) 'Default',
                    if (card.expired) 'Expired',
                  ].join(' · '),
                  style: AppText.caption,
                ),
                trailing:
                    me.card?.last4 == card.last4 && me.card?.label == card.label
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.pop(context, card),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await _run(() => _service.chooseCard(split.id, picked.id));
    }
  }

  Future<void> _cancel(SplitBill split) async {
    if (await _ask(
      'Cancel this bill?',
      'Nobody will be charged and the popup closes for everyone.',
      'Cancel bill',
    )) {
      await _hostAction(() => _service.cancel(split.id));
    }
  }

  /// Members pick their card while the bill is open, or after their card
  /// was declined so the host can retry on another one.
  static bool _canChangeCard(SplitBill split, SplitParticipant me) =>
      !me.isHost &&
      (split.isClaiming ||
          (split.isConfirmed &&
              const [
                'pending',
                'failed',
                'requires_action',
              ].contains(me.paymentStatus)));

  @override
  Widget build(BuildContext context) {
    return ScaffoldMessenger(
      key: _messenger,
      child: ListenableBuilder(
        listenable: widget.live,
        builder: (context, _) {
          final split = widget.live.split;
          final me = split?.participantNamed(_me);
          final isHost = me?.isHost ?? false;
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              leading: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              title: Text(
                split?.title ?? 'Bill',
                style: AppText.sectionTitle.copyWith(fontSize: 16),
              ),
              actions: [
                if (split?.receiptId != null)
                  IconButton(
                    tooltip: 'View receipt',
                    icon: const Icon(Icons.receipt_long),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReceiptViewPage(
                          receiptId: split!.receiptId!,
                          title: split.title,
                        ),
                      ),
                    ),
                  ),
                _LiveDot(connected: widget.live.connected),
                if (split != null && isHost && split.isClaiming)
                  PopupMenuButton<void>(
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        onTap: () => _cancel(split),
                        child: const Text('Cancel bill'),
                      ),
                    ],
                  ),
              ],
            ),
            body: split == null
                ? Center(
                    child: Text('This bill is closed.', style: AppText.body),
                  )
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.all(AppSpacing.gap),
                          children: [
                            _ModePicker(
                              split: split,
                              enabled: isHost && split.isClaiming && !_busy,
                              onChanged: (mode) => _hostAction(
                                () => _service.setMode(split.id, mode),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.field),
                            _Receipt(
                              split: split,
                              myId: me?.userId,
                              toggling: _togglingItems,
                              onToggle: (item, claimed) =>
                                  _toggle(split, item, claimed),
                            ),
                            const SizedBox(height: AppSpacing.gap),
                            _People(
                              split: split,
                              myId: me?.userId,
                              canWaive: isHost && split.isClaiming && !_busy,
                              onWaive: (person) => _waive(split, person),
                              onChangeCard:
                                  me == null || !_canChangeCard(split, me)
                                  ? null
                                  : () => _chooseCard(split, me),
                            ),
                          ],
                        ),
                      ),
                      _Footer(
                        split: split,
                        me: me,
                        busy: _busy,
                        onConfirm: () => _confirm(split),
                        onRetry: () =>
                            _hostAction(() => _service.retryCharges(split.id)),
                        onDone: () => Navigator.pop(context),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  const _LiveDot({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: connected ? AppColors.contact : AppColors.hint,
          ),
          const SizedBox(width: 4),
          Text(
            connected ? 'Live' : 'Reconnecting',
            style: AppText.caption.copyWith(color: AppColors.hint),
          ),
        ],
      ),
    );
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({
    required this.split,
    required this.enabled,
    required this.onChanged,
  });

  final SplitBill split;
  final bool enabled;
  final ValueChanged<SplitMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<SplitMode>(
          segments: [
            for (final mode in SplitMode.values)
              ButtonSegment(
                value: mode,
                label: Text('Split ${mode.label.toLowerCase()}'),
              ),
          ],
          selected: {split.mode},
          showSelectedIcon: false,
          onSelectionChanged: enabled ? (s) => onChanged(s.first) : null,
        ),
        if (split.mode == SplitMode.even && split.isClaiming)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              "Split evenly: everyone pays the same, whatever they tap.",
              style: AppText.caption.copyWith(color: AppColors.hint),
            ),
          ),
      ],
    );
  }
}

/// The shared receipt. The receipt icon next to each item is the "I had this" toggle.
class _Receipt extends StatelessWidget {
  const _Receipt({
    required this.split,
    required this.myId,
    required this.toggling,
    required this.onToggle,
  });

  final SplitBill split;
  final int? myId;
  final Set<int> toggling;
  final void Function(SplitItem item, bool claimed) onToggle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 8),
            child: SectionHeader(
              'Receipt',
              subtitle: split.isClaiming
                  ? 'Tap the receipt next to everything you had'
                  : 'Final',
            ),
          ),
          for (final item in split.items)
            _ReceiptLine(
              item: item,
              split: split,
              mine: myId != null && item.claimedBy.contains(myId),
              enabled:
                  split.isClaiming &&
                  myId != null &&
                  !toggling.contains(item.id),
              onToggle: (claimed) => onToggle(item, claimed),
            ),
          const Divider(height: 24, color: AppColors.divider),
          _TotalLine('Subtotal', split.subtotalCents),
          if (split.taxCents > 0) _TotalLine('Tax', split.taxCents),
          if (split.tipCents > 0) _TotalLine('Tip', split.tipCents),
          _TotalLine('Total', split.totalCents, bold: true),
        ],
      ),
    );
  }
}

class _ReceiptLine extends StatelessWidget {
  const _ReceiptLine({
    required this.item,
    required this.split,
    required this.mine,
    required this.enabled,
    required this.onToggle,
  });

  final SplitItem item;
  final SplitBill split;
  final bool mine;
  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final claimers = item.claimedBy.map(split.usernameOf).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: mine ? 'Remove from my items' : 'I had this',
            onPressed: enabled ? () => onToggle(!mine) : null,
            isSelected: mine,
            style: IconButton.styleFrom(
              backgroundColor: mine
                  ? AppColors.groupCards[0].first
                  : AppColors.background,
              foregroundColor: mine ? AppColors.surface : AppColors.hint,
              disabledBackgroundColor: mine
                  ? AppColors.groupCards[0].first.withValues(alpha: 0.6)
                  : AppColors.background,
            ),
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.quantity > 1
                      ? '${item.name} ×${item.quantity}'
                      : item.name,
                  style: AppText.body,
                ),
                Text(
                  claimers.isEmpty
                      ? 'Unclaimed'
                      : claimers.length == 1
                      ? claimers.first
                      : 'Shared: ${claimers.join(', ')}',
                  style: AppText.caption.copyWith(
                    color: claimers.isEmpty ? AppColors.error : AppColors.hint,
                  ),
                ),
              ],
            ),
          ),
          Text(Money.format(item.totalCents), style: AppText.body),
        ],
      ),
    );
  }
}

class _TotalLine extends StatelessWidget {
  const _TotalLine(this.label, this.cents, {this.bold = false});

  final String label;
  final int cents;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? AppText.body.copyWith(fontWeight: FontWeight.bold)
        : AppText.body.copyWith(color: AppColors.hint);
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(Money.format(cents), style: style),
        ],
      ),
    );
  }
}

class _People extends StatelessWidget {
  const _People({
    required this.split,
    required this.myId,
    required this.canWaive,
    required this.onWaive,
    this.onChangeCard,
  });

  final SplitBill split;
  final int? myId;
  final bool canWaive;
  final ValueChanged<SplitParticipant> onWaive;

  /// Set when you can change which card pays your share.
  final VoidCallback? onChangeCard;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.gap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            'Who pays what',
            subtitle: split.isClaiming
                ? 'Updates live as people pick their items'
                : 'Locked in by the host',
          ),
          const SizedBox(height: AppSpacing.field),
          for (final person in split.participants)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: person.isHost
                        ? AppColors.textPrimary
                        : AppColors.background,
                    foregroundColor: person.isHost
                        ? AppColors.surface
                        : AppColors.textPrimary,
                    child: Text(
                      person.username[0].toUpperCase(),
                      style: AppText.sectionTitle.copyWith(color: null),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.field),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.userId == myId
                              ? '${person.username} (you)'
                              : person.username,
                          style: AppText.body,
                        ),
                        Text(
                          _subtitle(person),
                          style: AppText.caption.copyWith(
                            color: !person.isHost && !person.cardOnFile
                                ? AppColors.error
                                : AppColors.hint,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (person.userId == myId && onChangeCard != null)
                    TextButton(
                      onPressed: onChangeCard,
                      child: const Text('Change card'),
                    ),
                  if (canWaive && !person.isHost && person.owedCents > 0)
                    TextButton(
                      onPressed: () => onWaive(person),
                      child: const Text('Waive'),
                    ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Money.format(person.chargeCents),
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (person.waivedCents > 0 || person.isHost)
                        Text(
                          person.isHost
                              ? 'share ${Money.format(person.owedCents)}'
                              : 'of ${Money.format(person.owedCents)}',
                          style: AppText.caption.copyWith(
                            color: AppColors.hint,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle(SplitParticipant person) {
    // Members show the card their share goes on, so everyone can see it.
    final card = person.isHost ? null : person.card?.label;
    if (!split.isClaiming) {
      return [person.paymentLabel, ?card].join(' · ');
    }
    if (person.isHost) return 'Host · paying the bill';
    if (!person.cardOnFile && !(person.card?.chosen ?? false)) {
      return 'No valid card on file';
    }
    return [
      card ?? 'Member',
      if (person.waivedCents > 0)
        '${Money.format(person.waivedCents)} waived by host',
    ].join(' · ');
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.split,
    required this.me,
    required this.busy,
    required this.onConfirm,
    required this.onRetry,
    required this.onDone,
  });

  final SplitBill split;
  final SplitParticipant? me;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback onRetry;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final isHost = me?.isHost ?? false;
    final unpaid = split.participants.any(
      (p) =>
          p.chargeCents > 0 &&
          const {
            'pending',
            'failed',
            'requires_action',
          }.contains(p.paymentStatus),
    );

    final (
      String headline,
      String detail,
      Widget? action,
    ) = switch (split.status) {
      'claiming' when isHost => (
        'Members pay ${Money.format(split.collectedCents)}',
        'You cover ${Money.format(split.hostCoveredCents)} · only hosts can confirm',
        LoadingButton(
          label: 'Confirm & charge',
          loading: busy,
          onPressed: onConfirm,
        ),
      ),
      'claiming' => (
        'Your share: ${Money.format(me?.chargeCents ?? 0)}',
        'Waiting for the host to confirm',
        null,
      ),
      'confirmed' => (
        isHost
            ? 'Collecting ${Money.format(split.collectedCents)}'
            : 'You pay ${Money.format(me?.chargeCents ?? 0)}',
        isHost ? 'Charging cards on file' : (me?.paymentLabel ?? ''),
        isHost && unpaid
            ? OutlinedButton(
                onPressed: busy ? null : onRetry,
                child: const Text('Retry unpaid charges'),
              )
            : null,
      ),
      'settled' => (
        "Everyone's paid",
        'Total ${Money.format(split.totalCents)}',
        ElevatedButton(onPressed: onDone, child: const Text('Done')),
      ),
      _ => (
        'Bill cancelled',
        'Nobody was charged',
        ElevatedButton(onPressed: onDone, child: const Text('Close')),
      ),
    };

    return Material(
      color: AppColors.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gap),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(headline, style: AppText.pageTitle.copyWith(fontSize: 20)),
              Text(
                detail,
                style: AppText.caption.copyWith(color: AppColors.hint),
              ),
              if (action != null) ...[
                const SizedBox(height: AppSpacing.field),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Host picks how much of someone's share to forgive.
class _WaiveDialog extends StatefulWidget {
  const _WaiveDialog({required this.person});

  final SplitParticipant person;

  @override
  State<_WaiveDialog> createState() => _WaiveDialogState();
}

class _WaiveDialogState extends State<_WaiveDialog> {
  late final _amount = TextEditingController(
    text: widget.person.waivedCents > 0
        ? Money.format(widget.person.waivedCents).substring(1)
        : '',
  );
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _save() {
    final cents = Money.parse(_amount.text.isEmpty ? '0' : _amount.text);
    if (cents == null) {
      setState(() => _error = 'Enter an amount like 5.00');
      return;
    }
    Navigator.pop(context, cents.clamp(0, widget.person.owedCents));
  }

  @override
  Widget build(BuildContext context) {
    final owed = widget.person.owedCents;
    return AlertDialog(
      title: Text(
        'Waive for ${widget.person.username}',
        style: AppText.sectionTitle.copyWith(fontSize: 16),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Their share is ${Money.format(owed)}.', style: AppText.body),
          const SizedBox(height: AppSpacing.field),
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: 'Amount to waive',
              prefixText: '\$ ',
              errorText: _error,
            ),
            onSubmitted: (_) => _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, 0),
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, owed),
          child: const Text('Waive all'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
