import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/pay_back_service.dart';
import '../theme/app_theme.dart';
import '../utils/money.dart';
import '../widgets/common.dart';

/// Every payment in or out (bills and pay-backs), newest first. A pay-back
/// someone sent you can be refunded from here.
class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key});

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
  final _items = <HistoryItem>[];
  String? _nextBefore;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  PayBackService get _service => PayBackService(AuthScope.read(context));

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final page = await _service.history();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextBefore = page.nextBefore;
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    final before = _nextBefore;
    if (before == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.history(before: before);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _nextBefore = page.nextBefore;
      });
    } on ApiException catch (e) {
      if (mounted) showMessage(context, e.message);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _open(HistoryItem item) async {
    final refunded = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _PaymentDetails(item: item, service: _service),
    );
    if (refunded == true && mounted) {
      showMessage(
        context,
        'Refunded ${Money.format(item.amountCents)} to ${item.otherUsername}',
      );
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Payment history',
          style: AppText.sectionTitle.copyWith(fontSize: 16),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: PageBody(child: _body()),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return AppCard(
        width: double.infinity,
        child: Text(_error!, style: AppText.body),
      );
    }
    if (_items.isEmpty) {
      return AppCard(
        width: double.infinity,
        child: Text(
          'No payments yet. Bills you pay and pay-backs show up here.',
          style: AppText.body.copyWith(color: AppColors.hint),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final item in _items)
                  _HistoryRow(item: item, onTap: () => _open(item)),
              ],
            ),
          ),
        ),
        if (_nextBefore != null) ...[
          const SizedBox(height: AppSpacing.field),
          LoadingButton(
            label: 'Load more',
            loading: _loadingMore,
            onPressed: _loadMore,
          ),
        ],
      ],
    );
  }
}

/// Status shown next to a payment that isn't simply done.
({String label, Color color})? _statusBadge(String status) => switch (status) {
  'refunded' => (label: 'Refunded', color: AppColors.hint),
  'failed' => (label: 'Failed', color: AppColors.error),
  'disputed' => (label: 'Disputed', color: AppColors.error),
  'processing' ||
  'requires_action' => (label: 'Pending', color: AppColors.hint),
  _ => null,
};

String _date(DateTime at) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[at.month - 1]} ${at.day}, ${at.year}';
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.onTap});

  final HistoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final badge = _statusBadge(item.status);
    final done = item.status == 'succeeded' || item.status == 'disputed';
    final amount =
        '${item.incoming ? '+' : '-'}${Money.format(item.amountCents)}';
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        child: Icon(item.incoming ? Icons.arrow_downward : Icons.arrow_upward),
      ),
      title: Text(item.title, style: AppText.body),
      subtitle: Text(
        [if (item.detail.isNotEmpty) item.detail, _date(item.at)].join(' · '),
        style: AppText.caption,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            amount,
            style: AppText.body.copyWith(
              fontWeight: FontWeight.bold,
              color: !done
                  ? AppColors.hint
                  : item.incoming
                  ? AppColors.contact
                  : AppColors.textPrimary,
              decoration: item.status == 'refunded' || item.status == 'failed'
                  ? TextDecoration.lineThrough
                  : null,
            ),
          ),
          if (badge != null)
            Text(
              badge.label,
              style: AppText.caption.copyWith(color: badge.color),
            ),
        ],
      ),
    );
  }
}

/// Details of one payment, with Refund for a pay-back you received.
class _PaymentDetails extends StatefulWidget {
  const _PaymentDetails({required this.item, required this.service});

  final HistoryItem item;
  final PayBackService service;

  @override
  State<_PaymentDetails> createState() => _PaymentDetailsState();
}

class _PaymentDetailsState extends State<_PaymentDetails> {
  bool _refunding = false;

  Future<void> _refund() async {
    final item = widget.item;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Refund ${Money.format(item.amountCents)} to ${item.otherUsername}?',
        ),
        content: const Text(
          'The full amount goes back to their card. This can\'t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Refund'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _refunding = true);
    try {
      await widget.service.refund(item.id);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _refunding = false);
      showMessage(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final badge = _statusBadge(item.status);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        0,
        AppSpacing.page,
        AppSpacing.page,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(Money.format(item.amountCents), style: AppText.amount),
          Text(item.title, style: AppText.sectionTitle.copyWith(fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            [
              if (item.detail.isNotEmpty) item.detail,
              _date(item.at),
              ?badge?.label,
            ].join(' · '),
            style: AppText.body.copyWith(color: AppColors.hint),
          ),
          if (item.kind == 'bill') ...[
            const SizedBox(height: AppSpacing.field),
            Text(
              'Part of a group bill.',
              style: AppText.caption.copyWith(color: AppColors.hint),
            ),
          ],
          if (item.canRefund) ...[
            const SizedBox(height: AppSpacing.gap),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: const BorderSide(color: AppColors.error),
              ),
              onPressed: _refunding ? null : _refund,
              child: Text(
                _refunding
                    ? 'Refunding…'
                    : 'Refund ${Money.format(item.amountCents)}',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
