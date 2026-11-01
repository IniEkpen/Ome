import 'dart:async';

import 'package:flutter/widgets.dart';

import 'auth_service.dart';

/// One entry in the in-app inbox.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.target,
    required this.read,
    required this.at,
    this.groupId,
    this.splitId,
    this.directPaymentId,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: (json['id'] as num).toInt(),
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String? ?? '',
        target: json['target'] as String? ?? 'payments',
        read: json['read'] == true,
        at: DateTime.parse(json['at'] as String).toLocal(),
        groupId: json['groupId'] as int?,
        splitId: json['splitId'] as int?,
        directPaymentId: json['directPaymentId'] as int?,
      );

  final int id;
  final String kind;
  final String title;
  final String body;

  /// Where tapping it goes: 'group' (that group's bill), 'groups' (the
  /// Groups tab) or 'payments' (payment history).
  final String target;
  final bool read;
  final DateTime at;
  final int? groupId;
  final int? splitId;
  final int? directPaymentId;

  AppNotification markedRead() => AppNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    target: target,
    read: true,
    at: at,
    groupId: groupId,
    splitId: splitId,
    directPaymentId: directPaymentId,
  );
}

class NotificationPage {
  const NotificationPage(this.items, this.unreadCount, this.nextBefore);

  final List<AppNotification> items;
  final int unreadCount;

  /// Pass to [NotificationService.list] for older ones; null at the end.
  final int? nextBefore;
}

class NotificationService {
  const NotificationService(this._auth);

  final AuthService _auth;

  Future<NotificationPage> list({int? before}) async {
    final json =
        (await _auth.client.get(
          '/users/me/notifications',
          query: {if (before != null) 'before': '$before'},
        )).orThrow("Couldn't load your notifications.").json ??
        const {};
    final items = json['items'];
    return NotificationPage(
      [
        for (final item in items is List ? items : const [])
          if (item is Map<String, dynamic>) AppNotification.fromJson(item),
      ],
      json['unreadCount'] as int? ?? 0,
      (json['nextBefore'] as num?)?.toInt(),
    );
  }

  /// Returns the new unread count.
  Future<int> markAllRead() async =>
      (await _auth.client.post(
            '/users/me/notifications/read',
            body: {'all': true},
          )).orThrow("Couldn't update your notifications.").json?['unreadCount']
          as int? ??
      0;
}

/// Keeps the unread count and delivers new notifications while the app is
/// open, over the server's live stream (reconnecting as needed). Created
/// once the user is signed in; see [NotificationScope].
class NotificationCenter extends ChangeNotifier {
  NotificationCenter(this._auth) {
    _connect();
  }

  final AuthService _auth;
  final _arrivals = StreamController<AppNotification>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Timer? _retry;
  int _failures = 0;
  bool _disposed = false;
  int _unread = 0;

  int get unreadCount => _unread;

  /// New notifications as they happen, for the in-app banner.
  Stream<AppNotification> get arrivals => _arrivals.stream;

  set unreadCount(int value) {
    if (value == _unread) return;
    _unread = value;
    notifyListeners();
  }

  void _connect() {
    // Dev sessions without a server token have nothing to listen to.
    if (_disposed || _auth.session?.token == null) return;
    _subscription = _auth.client
        .events('/users/me/events')
        .listen(
          (event) {
            _failures = 0;
            final count = event['unreadCount'];
            if (count is int) unreadCount = count;
            final json = event['notification'];
            if (event['type'] == 'notification' &&
                json is Map<String, dynamic>) {
              _arrivals.add(AppNotification.fromJson(json));
            }
          },
          onError: (Object _) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _failures++;
    final seconds = (1 << _failures.clamp(1, 4)).clamp(2, 15);
    _retry = Timer(Duration(seconds: seconds), _connect);
  }

  @override
  void dispose() {
    _disposed = true;
    _retry?.cancel();
    _subscription?.cancel();
    _arrivals.close();
    super.dispose();
  }
}

/// Makes the [NotificationCenter] available to every screen (it sits above
/// the navigator; see NotificationHost). [center] is null while signed out.
class NotificationScope extends InheritedNotifier<NotificationCenter> {
  const NotificationScope({
    super.key,
    required NotificationCenter? center,
    required super.child,
  }) : super(notifier: center);

  /// Null while signed out, and in tests of single pages.
  static NotificationCenter? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NotificationScope>()?.notifier;
}
