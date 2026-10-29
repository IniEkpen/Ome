import 'package:flutter/material.dart';

import '../payment.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../services/profile_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

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
                subtitle: 'A valid card is required to create or join groups',
              ),
              const SizedBox(height: AppSpacing.field),
              const _PaymentCard(),
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
  bool _adding = false;

  PaymentService get _payments => PaymentService(AuthScope.read(context));

  @override
  void initState() {
    super.initState();
    _status = _payments.cardStatus();
  }

  Future<void> _addCard() async {
    setState(() => _adding = true);
    try {
      final card = await _payments.addCard();
      if (card != null && mounted) {
        setState(() => _status = Future.value(card));
        showMessage(context, 'Card saved');
      }
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
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
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    card.hasValidCard
                        ? Icons.credit_card
                        : Icons.credit_card_off,
                    color: card.hasValidCard
                        ? AppColors.textPrimary
                        : AppColors.hint,
                  ),
                  const SizedBox(width: AppSpacing.field),
                  Expanded(
                    child: Text(
                      loading
                          ? 'Checking…'
                          : snapshot.hasError
                          ? "Couldn't load your card"
                          : card.hasValidCard
                          ? card.label
                          : card.last4 == null
                          ? 'No card on file'
                          : '${card.label} (expired)',
                      style: AppText.body,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.field),
              LoadingButton(
                label: card.hasValidCard ? 'Replace card' : 'Add card',
                loading: _adding,
                onPressed: _addCard,
              ),
              const SizedBox(height: AppSpacing.field),
              // Hosts receive what members pay through Stripe Connect.
              TextButton(
                onPressed: () async {
                  await Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => const Pay()));
                  // Onboarding may have just finished; show the new status.
                  if (mounted) {
                    setState(() => _status = _payments.cardStatus());
                  }
                },
                child: Text(
                  card.payoutsEnabled
                      ? 'Payouts set up'
                      : 'Set up payouts (for hosts)',
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
