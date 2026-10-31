import 'package:flutter/material.dart';

import '../payment.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/card_service.dart';
import '../services/payment_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'payment_history.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  /// Null until loaded, and for dev sessions the server didn't issue.
  UserProfile? _profile;
  bool _savingPrivacy = false;
  bool _deleting = false;

  ProfileService get _service => ProfileService(AuthScope.read(context));

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (AuthScope.read(context).session?.token == null) return;
    try {
      final profile = await _service.load();
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _setPrivate(bool private) async {
    setState(() => _savingPrivacy = true);
    try {
      final profile = await _service.setTransactionsPrivate(private);
      if (mounted) setState(() => _profile = profile);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _savingPrivacy = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your account, your saved card and your '
          'group memberships. Groups you own pass to their longest-standing '
          'member. People you paid still see those payments, from "Deleted '
          'user". This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final auth = AuthScope.read(context);
    final navigator = Navigator.of(context);
    setState(() => _deleting = true);
    try {
      await auth.deleteAccount();
      // Signed out now; the login screen replaces the shell.
      navigator.popUntil((route) => route.isFirst);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  void _logout(BuildContext context) {
    // Clear anything pushed above the shell before dropping the session so
    // no signed-in screen stays reachable with the back button.
    Navigator.of(context).popUntil((route) => route.isFirst);
    AuthScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final username = AuthScope.of(context).session?.username ?? '';
    final profile = _profile;
    final contact = [
      profile?.email,
      profile?.phone,
    ].whereType<String>().join(' · ');
    return Scaffold(
      appBar: const YuwoAppBar(),
      body: RefreshIndicator(
        onRefresh: _load,
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppCard(
                width: double.infinity,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.background,
                      foregroundColor: AppColors.textPrimary,
                      child: Text(
                        username.isEmpty ? '?' : username[0].toUpperCase(),
                        style: AppText.pageTitle.copyWith(fontSize: 22),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.gap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(
                            profile?.displayName ?? username,
                            subtitle: '@$username',
                          ),
                          if (contact.isNotEmpty)
                            Text(contact, style: AppText.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              const SectionHeader(
                'Privacy',
                subtitle: 'Who can see the payments you make',
              ),
              const SizedBox(height: AppSpacing.field),
              AppCard(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                // Own Material so the tile's ink isn't hidden by the card.
                child: Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(
                      'Keep my payments private',
                      style: AppText.body,
                    ),
                    subtitle: Text(
                      'Private payments stay off the network map. Only you '
                      'and the person you paid can see them.',
                      style: AppText.caption.copyWith(color: AppColors.hint),
                    ),
                    value: profile?.transactionsPrivate ?? false,
                    onChanged: profile == null || _savingPrivacy
                        ? null
                        : _setPrivate,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              const SectionHeader(
                'Payment',
                subtitle: 'Finish both steps to create or join groups',
              ),
              const SizedBox(height: AppSpacing.field),
              const _PaymentCard(),
              const SizedBox(height: AppSpacing.field),
              OutlinedButton.icon(
                icon: const Icon(Icons.receipt_long),
                label: const Text('Payment history'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PaymentHistoryPage()),
                ),
              ),
              const SizedBox(height: AppSpacing.section),
              OutlinedButton(
                onPressed: () => _logout(context),
                child: const Text('Log Out'),
              ),
              const SizedBox(height: AppSpacing.field),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppColors.error),
                onPressed: _deleting ? null : _deleteAccount,
                child: Text(_deleting ? 'Deleting…' : 'Delete Account'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentCard extends StatefulWidget {
  const _PaymentCard();

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  late Future<CardStatus> _status;
  List<SavedCard> _cards = const [];
  bool _adding = false;

  PaymentService get _payments => PaymentService(AuthScope.read(context));
  CardService get _cardService => CardService(AuthScope.read(context));

  @override
  void initState() {
    super.initState();
    _status = _payments.cardStatus();
    _loadCards();
  }

  Future<void> _loadCards() async {
    try {
      final cards = await _cardService.list();
      if (mounted) setState(() => _cards = cards);
    } on ApiException {
      // The card summary above still shows the default card.
    }
  }

  Future<void> _addCard() async {
    setState(() => _adding = true);
    try {
      final card = await _payments.addCard();
      if (card != null && mounted) {
        setState(() => _status = Future.value(card));
        showMessage(context, 'Card saved as your default');
        await _loadCards();
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _manage(SavedCard card) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(card.label, style: AppText.sectionTitle),
              subtitle: card.expiry.isEmpty
                  ? null
                  : Text('Expires ${card.expiry}', style: AppText.caption),
            ),
            if (!card.isDefault && !card.expired)
              ListTile(
                leading: const Icon(Icons.star_outline),
                title: const Text('Make default'),
                subtitle: const Text('Used for bills unless you pick another'),
                onTap: () => Navigator.pop(context, 'default'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.error),
              title: const Text(
                'Remove card',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    try {
      final cards = action == 'default'
          ? await _cardService.makeDefault(card)
          : await _cardService.remove(card);
      if (!mounted) return;
      setState(() {
        _cards = cards;
        // The default card is what the card check uses.
        _status = _payments.cardStatus();
      });
      showMessage(
        context,
        action == 'default'
            ? '${card.label} is now your default'
            : '${card.label} removed',
      );
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    }
  }

  Future<void> _verify() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const Pay()));
    // Onboarding may have just finished; show the new status.
    if (mounted) setState(() => _status = _payments.cardStatus());
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      width: double.infinity,
      child: FutureBuilder<CardStatus>(
        future: _status,
        builder: (context, snapshot) {
          final card = snapshot.data ?? CardStatus.none;
          final loading = snapshot.connectionState != ConnectionState.done;
          final failed = !loading && snapshot.hasError;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SetupStep(
                step: 1,
                title: 'Card',
                done: card.hasValidCard,
                detail: loading
                    ? 'Checking…'
                    : failed
                    ? "Couldn't load your card"
                    : card.hasValidCard
                    ? card.label
                    : card.last4 == null
                    ? 'No card on file. Used to pay your share of a bill.'
                    : '${card.label} (expired)',
              ),
              if (_cards.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.field),
                Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (final saved in _cards)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.credit_card),
                          title: Text(saved.label, style: AppText.body),
                          subtitle: Text(
                            [
                              if (saved.expiry.isNotEmpty)
                                'exp ${saved.expiry}',
                              if (saved.expired) 'Expired',
                            ].join(' · '),
                            style: AppText.caption,
                          ),
                          trailing: saved.isDefault
                              ? Text(
                                  'Default',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.path,
                                  ),
                                )
                              : const Icon(Icons.more_horiz),
                          onTap: () => _manage(saved),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.field),
              LoadingButton(
                label: _cards.isEmpty && !card.hasValidCard
                    ? 'Add card'
                    : 'Add another card',
                loading: _adding,
                onPressed: _addCard,
              ),
              const Divider(height: AppSpacing.gap * 2),
              // Everyone verifies with Stripe Connect, since anyone can host
              // a bill and be paid back. Groups need this and a card.
              _SetupStep(
                step: 2,
                title: 'Payment verification',
                done: card.paymentsVerified,
                detail: loading
                    ? 'Checking…'
                    : card.paymentsVerified
                    ? "Verified. Money you're paid back goes to your bank."
                    : 'Verify your identity and bank with Stripe so you can '
                          'be paid back when you host. Every step must be '
                          'completed.',
              ),
              const SizedBox(height: AppSpacing.field),
              card.paymentsVerified
                  ? OutlinedButton(
                      onPressed: _verify,
                      child: const Text('Update payment details'),
                    )
                  : ElevatedButton(
                      onPressed: loading ? null : _verify,
                      child: const Text('Start payment verification'),
                    ),
            ],
          );
        },
      ),
    );
  }
}

/// One numbered step of payment setup, with a tick once it's done.
class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.step,
    required this.title,
    required this.done,
    required this.detail,
  });

  final int step;
  final String title;
  final bool done;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: done ? AppColors.path : AppColors.divider,
          foregroundColor: done ? AppColors.surface : AppColors.textSoft,
          child: done
              ? const Icon(Icons.check, size: 16)
              : Text('$step', style: AppText.caption),
        ),
        const SizedBox(width: AppSpacing.field),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: AppText.sectionTitle.copyWith(fontSize: 16)),
              const SizedBox(height: 2),
              Text(detail, style: AppText.caption),
            ],
          ),
        ),
      ],
    );
  }
}
