import 'package:flutter/material.dart';

import '../payment.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  void _logout(BuildContext context) {
    // Clear anything pushed above the shell before dropping the session so
    // no signed-in screen stays reachable with the back button.
    Navigator.of(context).popUntil((route) => route.isFirst);
    AuthScope.read(context).logout();
  }

  @override
  Widget build(BuildContext context) {
    final username = AuthScope.of(context).session?.username ?? '';
    return Scaffold(
      appBar: const YuwoAppBar(),
      body: PageBody(
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
                    child: SectionHeader(username, subtitle: 'Signed in'),
                  ),
                ],
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
          ],
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
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const Pay())),
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
