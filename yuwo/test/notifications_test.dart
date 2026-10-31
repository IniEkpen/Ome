import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/main.dart';
import 'package:yuwo/pages/notifications.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';
import 'package:yuwo/theme/app_theme.dart';

Map<String, dynamic> _notification(
  int id,
  String kind,
  String title, {
  bool read = false,
  String target = 'payments',
}) => {
  'id': id,
  'kind': kind,
  'title': title,
  'body': 'Dinner',
  'target': target,
  'groupId': 3,
  'read': read,
  'at': DateTime.now().toUtc().toIso8601String(),
};

Future<AuthService> _signedIn(
  Future<http.Response> Function(http.Request) handler,
) async {
  late final AuthService auth;
  auth = AuthService(
    client: ApiClient(
      tokenProvider: () => auth.session?.token,
      httpClient: MockClient((request) async {
        if (request.url.path == '/users/login') {
          return http.Response(
            jsonEncode({'token': 't', 'id': 1, 'username': 'pat'}),
            200,
          );
        }
        return handler(request);
      }),
    ),
    devLogin: false,
  );
  await auth.login(username: 'pat', password: 'x');
  return auth;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('a live notification shows a banner and the bell badge', (
    tester,
  ) async {
    final auth = await _signedIn((request) async {
      if (request.url.path == '/users/me/events') {
        final events = [
          {'type': 'hello', 'unreadCount': 2},
          {
            'type': 'notification',
            'unreadCount': 3,
            'notification': _notification(
              9,
              'bill_opened',
              'ada opened The Tack Room',
              target: 'group',
            ),
          },
        ];
        return http.Response(
          events.map((e) => 'data: ${jsonEncode(e)}\n\n').join(),
          200,
        );
      }
      if (request.url.path == '/users/me/home') {
        return http.Response(jsonEncode({'bills': [], 'activity': []}), 200);
      }
      return http.Response('[]', 200);
    });
    await tester.pumpWidget(YuwoApp(auth: auth));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ada opened The Tack Room'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('3'), findsOneWidget, reason: 'badge on the bell');
    expect(find.byTooltip('Notifications, 3 unread'), findsOneWidget);

    // Sign out: the live connection and its timers stop.
    auth.logout();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 20));
  });

  testWidgets('the inbox lists notifications and marks them all read', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final auth = await _signedIn((request) async {
      requests.add(request);
      if (request.url.path == '/users/me/notifications') {
        return http.Response(
          jsonEncode({
            'items': [
              _notification(2, 'paid_you', 'ada paid you \$20.00'),
              _notification(
                1,
                'group_invite',
                'ada invited you to Dinner',
                read: true,
                target: 'groups',
              ),
            ],
            'unreadCount': 1,
            'nextBefore': null,
          }),
          200,
        );
      }
      if (request.url.path == '/users/me/notifications/read') {
        return http.Response(jsonEncode({'unreadCount': 0}), 200);
      }
      if (request.url.path == '/payments/history') {
        return http.Response(
          jsonEncode({'items': [], 'nextBefore': null}),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    await tester.pumpWidget(
      AuthScope(
        service: auth,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const NotificationsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ada paid you \$20.00'), findsOneWidget);
    expect(find.text('ada invited you to Dinner'), findsOneWidget);
    expect(find.textContaining('Just now'), findsNWidgets(2));
    final read = requests.singleWhere(
      (r) => r.url.path == '/users/me/notifications/read',
    );
    expect(jsonDecode(read.body), {'all': true});

    // Tapping a payment opens payment history.
    await tester.tap(find.text('ada paid you \$20.00'));
    await tester.pumpAndSettle();
    expect(find.text('Payment history'), findsOneWidget);
  });

  test('time ago', () {
    final now = DateTime(2026, 10, 31, 12);
    expect(
      timeAgo(now.subtract(const Duration(seconds: 20)), now: now),
      'Just now',
    );
    expect(
      timeAgo(now.subtract(const Duration(minutes: 5)), now: now),
      '5m ago',
    );
    expect(timeAgo(now.subtract(const Duration(hours: 3)), now: now), '3h ago');
    expect(timeAgo(now.subtract(const Duration(days: 2)), now: now), '2d ago');
    expect(timeAgo(DateTime(2026, 9, 1), now: now), '9/1/2026');
  });
}
