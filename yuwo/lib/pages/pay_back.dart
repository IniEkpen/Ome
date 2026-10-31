import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/pay_back_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/card_gate.dart';
import '../widgets/common.dart';

/// Pay someone back for something outside a group: find them, say how much
/// and what it's for, confirm. Closes with a message for the caller to show.
class PayBackPage extends StatefulWidget {
  const PayBackPage({super.key});

  @override
  State<PayBackPage> createState() => _PayBackPageState();
}

class _PayBackPageState extends State<PayBackPage> {
  final _search = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  Timer? _debounce;
  List<Payee> _results = const [];
  bool _searching = false;
  Payee? _payee;
  bool _sending = false;
  // Kept until the server gives a definite answer, so retrying after a lost
  // connection can't charge twice.
  String _idempotencyKey = PayBackService.newIdempotencyKey();

  PayBackService get _service => PayBackService(AuthScope.read(context));

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _runSearch(text),
    );
  }

  Future<void> _runSearch(String text) async {
    setState(() => _searching = true);
    try {
      final results = await _service.search(text);
      // Ignore answers for an older query.
      if (mounted && text == _search.text) setState(() => _results = results);
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  String? _validateAmount(String? value) {
    final cents = Money.parse(value ?? '');
    if (cents == null) return 'Enter an amount, like 25 or 12.50';
    if (cents < PayBackService.minCents || cents > PayBackService.maxCents) {
      return 'Payments are between \$1 and \$1,000';
    }
    return null;
  }

  Future<void> _send() async {
    final payee = _payee;
    if (_sending || payee == null || !_formKey.currentState!.validate()) {
      return;
    }
    final cents = Money.parse(_amount.text)!;
    final note = _note.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pay ${payee.displayName} ${Money.format(cents)}?'),
        content: Text(
          'For "$note". Your saved card is charged now, and this can\'t be '
          'undone from the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pay'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    final service = _service;
    var definite = true;
    // Asks for a card or payment verification first if they're missing.
    final sent = await runWithPaymentSetup(context, () async {
      try {
        await service.pay(
          to: payee,
          amountCents: cents,
          note: note,
          idempotencyKey: _idempotencyKey,
        );
      } on ApiException catch (e) {
        definite = e.statusCode != null;
        rethrow;
      }
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (sent) {
      Navigator.of(
        context,
      ).pop('Paid ${payee.displayName} ${Money.format(cents)} for $note');
    } else if (definite) {
      // Declined or refused: the next try is a new payment.
      _idempotencyKey = PayBackService.newIdempotencyKey();
    }
  }

  @override
  Widget build(BuildContext context) {
    final payee = _payee;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Pay someone back',
          style: AppText.sectionTitle.copyWith(fontSize: 16),
        ),
      ),
      body: PageBody(
        child: payee == null ? _searchView() : _paymentForm(payee),
      ),
    );
  }

  Widget _searchView() {
    final query = _search.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          'Who are you paying?',
          subtitle: 'For something they covered, like tickets or a ride',
        ),
        const SizedBox(height: AppSpacing.field),
        TextField(
          controller: _search,
          autofocus: true,
          autocorrect: false,
          textInputAction: TextInputAction.search,
          onChanged: _onSearchChanged,
          decoration: InputDecoration(
            hintText: 'Search by name or username',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searching
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : null,
          ),
        ),
        const SizedBox(height: AppSpacing.gap),
        if (query.isNotEmpty && _results.isEmpty && !_searching)
          Text(
            'No one found for "$query"',
            style: AppText.body.copyWith(color: AppColors.hint),
          ),
        if (_results.isNotEmpty)
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Material(
              type: MaterialType.transparency,
              child: Column(
                children: [
                  for (final person in _results)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.background,
                        foregroundColor: AppColors.textPrimary,
                        child: Text(person.username[0].toUpperCase()),
                      ),
                      title: Text(person.displayName, style: AppText.body),
                      subtitle: Text(
                        '@${person.username}',
                        style: AppText.caption,
                      ),
                      onTap: () => setState(() => _payee = person),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _paymentForm(Payee payee) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppCard(
            padding: const EdgeInsets.fromLTRB(20, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: SectionHeader(
                    'Paying ${payee.displayName}',
                    subtitle: '@${payee.username}',
                  ),
                ),
                TextButton(
                  onPressed: _sending
                      ? null
                      : () => setState(() => _payee = null),
                  child: const Text('Change'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.gap),
          TextFormField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textInputAction: TextInputAction.next,
            style: AppText.pageTitle,
            decoration: const InputDecoration(
              hintText: '0.00',
              prefixText: '\$ ',
            ),
            validator: _validateAmount,
          ),
          const SizedBox(height: AppSpacing.field),
          TextFormField(
            controller: _note,
            maxLength: PayBackService.noteMax,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => _send(),
            decoration: const InputDecoration(
              hintText: "What's it for? e.g. Concert tickets",
            ),
            validator: (v) => (v ?? '').trim().isEmpty
                ? "Say what you're paying them back for"
                : null,
          ),
          const SizedBox(height: AppSpacing.field),
          Text(
            'Charged to your saved card. Up to \$1,000 per payment and '
            '\$2,000 a day.',
            style: AppText.caption.copyWith(color: AppColors.hint),
          ),
          const SizedBox(height: AppSpacing.gap),
          LoadingButton(label: 'Pay', loading: _sending, onPressed: _send),
        ],
      ),
    );
  }
}
