import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/group_service.dart';
import '../services/notification_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import 'group.dart';
import 'group_detail.dart';
import 'payment_history.dart';

/// Opens whatever a notification is about: the group (where the bill pops
/// up), the Groups tab for invites, or payment history.
Future<void> openNotification(
  BuildContext context,
  AppNotification notification,
) async {
  final navigator = Navigator.of(context);
  switch (notification.target) {
    case 'group':
      final groupId = notification.groupId;
      if (groupId == null) return;
      try {
        final groups = await GroupService(AuthScope.read(context)).listGroups();
        final group = groups.where((g) => g.id == groupId).firstOrNull;
        if (group == null) {
          if (context.mounted) {
            showMessage(context, "You're no longer in that group.");
          }
          return;
        }
        await navigator.push(
          MaterialPageRoute(builder: (_) => GroupDetailPage(group: group)),
        );
      } on ApiException catch (e) {
        if (context.mounted) showMessage(context, e.message);
      }
    case 'groups':
      await navigator.push(
        MaterialPageRoute(builder: (_) => const GroupsPage()),
      );
    default:
      await navigator.push(
        MaterialPageRoute(builder: (_) => const PaymentHistoryPage()),
      );
  }
}

/// The inbox behind the bell. Opening it marks everything read.
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final _items = <AppNotification>[];
  int? _nextBefore;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  StreamSubscription<AppNotification>? _live;

  NotificationService get _service =>
      NotificationService(AuthScope.read(context));

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // New ones appear at the top while the inbox is open.
    _live ??= NotificationScope.maybeOf(context)?.arrivals.listen((n) {
      if (!mounted || _items.any((i) => i.id == n.id)) return;
      setState(() => _items.insert(0, n));
      _markAllRead();
    });
  }

  @override
  void dispose() {
    _live?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final page = await _service.list();
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page.items);
        _nextBefore = page.nextBefore;
        _error = null;
      });
      if (page.unreadCount > 0) await _markAllRead();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // The dots stay on screen this visit, so you can see what was new.
  Future<void> _markAllRead() async {
    try {
      final unread = await _service.markAllRead();
      if (!mounted) return;
      NotificationScope.maybeOf(context)?.unreadCount = unread;
    } on ApiException {
      // Not worth interrupting the inbox for; it's retried next visit.
    }
  }

  Future<void> _loadMore() async {
    final before = _nextBefore;
    if (before == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.list(before: before);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Notifications',
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
          "Nothing yet. You'll see new bills, payments and invites here.",
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
                for (final n in _items)
                  ListTile(
                    onTap: () => openNotification(context, n),
                    leading: CircleAvatar(
                      backgroundColor: AppColors.background,
                      foregroundColor: AppColors.textPrimary,
                      child: Icon(_icon(n.kind), size: 20),
                    ),
                    title: Text(
                      n.title,
                      style: AppText.body.copyWith(
                        fontWeight: n.read ? null : FontWeight.bold,
                      ),
                    ),
                    subtitle: Text(
                      [
                        if (n.body.isNotEmpty) n.body,
                        timeAgo(n.at),
                      ].join(' · '),
                      style: AppText.caption,
                    ),
                    trailing: n.read
                        ? null
                        : const CircleAvatar(
                            radius: 4,
                            backgroundColor: AppColors.viewer,
                          ),
                  ),
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

IconData _icon(String kind) => switch (kind) {
  'bill_opened' => Icons.receipt_long,
  'bill_cancelled' => Icons.cancel_outlined,
  'share_charged' => Icons.credit_card,
  'share_declined' => Icons.credit_card_off,
  'group_invite' => Icons.group_add,
  'payback_refunded' => Icons.undo,
  _ => Icons.arrow_downward, // someone paid you
};

/// "Just now", "5m ago", "3h ago", "2d ago", then the date.
String timeAgo(DateTime at, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(at);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${at.month}/${at.day}/${at.year}';
}
