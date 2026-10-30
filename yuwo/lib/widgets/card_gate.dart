import 'package:flutter/material.dart';

import '../payment.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import 'common.dart';

Future<bool> _askToContinue(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: AppText.sectionTitle),
      content: Text(message, style: AppText.body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return go == true && context.mounted;
}

/// Explains why a card is needed and opens Stripe's card sheet.
/// Returns true once a valid card is on file.
Future<bool> ensureCard(BuildContext context) async {
  final add = await _askToContinue(
    context,
    title: 'Add a card first',
    message:
        'Everyone in a group keeps a card on file so bills can be split '
        "the moment they're confirmed. You're only charged for your share, "
        'after the host confirms.',
    action: 'Add card',
  );
  if (!add || !context.mounted) return false;
  try {
    final card = await PaymentService(AuthScope.read(context)).addCard();
    return card?.hasValidCard ?? false;
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return false;
  }
}

/// Explains why verification is needed and opens Stripe's onboarding.
/// Returns true once Stripe reports the account as fully verified.
Future<bool> ensurePaymentVerification(BuildContext context) async {
  final verify = await _askToContinue(
    context,
    title: 'Verify your payment details',
    message:
        'Anyone in a group can host a bill and be paid back, so everyone '
        'verifies with Stripe once: your legal name, date of birth and the '
        "bank account you're paid into. Every step must be completed before "
        'you can create or join a group.',
    action: 'Start verification',
  );
  if (!verify || !context.mounted) return false;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const Pay()));
  if (!context.mounted) return false;
  try {
    final status = await PaymentService(
      AuthScope.read(context),
    ).statusAfterVerification();
    if (!status.paymentsVerified && context.mounted) {
      showMessage(
        context,
        'Payment verification isn\'t finished yet. Complete every step, '
        'then try again.',
      );
    }
    return status.paymentsVerified;
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return false;
  }
}

/// Runs [action]. If the server says payment setup is incomplete (no card,
/// or Stripe verification unfinished), walks the user through the missing
/// step and retries. Other errors are shown as a snackbar. Returns true on
/// success.
Future<bool> runWithPaymentSetup(
  BuildContext context,
  Future<void> Function() action,
) async {
  // At most one card fix and one verification fix, then a final attempt.
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      if (!context.mounted) return false;
      final fixed = e.isCardRequired && attempt < 2
          ? await ensureCard(context)
          : e.isPaymentVerificationRequired && attempt < 2
          ? await ensurePaymentVerification(context)
          : null;
      if (!context.mounted) return false;
      if (fixed == null) {
        showMessage(context, e.message);
        return false;
      }
      if (!fixed) return false;
    }
  }
  return false;
}
