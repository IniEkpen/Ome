import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/payment_service.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Explains why a card is needed and opens Stripe's card sheet.
/// Returns true once a valid card is on file.
Future<bool> ensureCard(BuildContext context) async {
  final add = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Add a card first', style: AppText.sectionTitle),
      content: Text(
        'Everyone in a group keeps a card on file so bills can be split '
        "the moment they're confirmed. You're only charged for your share, "
        'after the host confirms.',
        style: AppText.body,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Add card'),
        ),
      ],
    ),
  );
  if (add != true || !context.mounted) return false;
  try {
    final card = await PaymentService(AuthScope.read(context)).addCard();
    return card?.hasValidCard ?? false;
  } on ApiException catch (e) {
    if (context.mounted) showMessage(context, e.message);
    return false;
  }
}

/// Runs [action]; if the server says a card is required, asks for one and
/// retries once. Other errors are shown as a snackbar. Returns true on success.
Future<bool> runWithCard(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
    return true;
  } on ApiException catch (e) {
    if (!context.mounted) return false;
    if (!e.isCardRequired) {
      showMessage(context, e.message);
      return false;
    }
    if (!await ensureCard(context) || !context.mounted) return false;
    try {
      await action();
      return true;
    } on ApiException catch (e) {
      if (context.mounted) showMessage(context, e.message);
      return false;
    }
  }
}
