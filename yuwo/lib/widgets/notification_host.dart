import 'dart:async';

import 'package:flutter/material.dart';

import '../pages/notifications.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

/// Sits just inside MaterialApp (above every screen): starts the
/// [NotificationCenter] when someone signs in, stops it when they sign out,
/// and shows a banner with "Open" when a notification arrives.
class NotificationHost extends StatefulWidget {
  const NotificationHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  /// The app's navigator, for opening what a banner is about.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost> {
  NotificationCenter? _center;
  StreamSubscription<AppNotification>? _arrivals;
  String? _token;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = AuthScope.of(context).session?.token;
    if (token == _token) return;
    _token = token;
    _stop();
    if (token != null) {
      final center = NotificationCenter(AuthScope.read(context));
      _arrivals = center.arrivals.listen(_banner);
      _center = center;
    }
  }

  void _banner(AppNotification n) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(n.title),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () {
              final navigatorContext = widget.navigatorKey.currentContext;
              if (navigatorContext != null) {
                openNotification(navigatorContext, n);
              }
            },
          ),
        ),
      );
  }

  void _stop() {
    _arrivals?.cancel();
    _arrivals = null;
    _center?.dispose();
    _center = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationScope(center: _center, child: widget.child);
}
