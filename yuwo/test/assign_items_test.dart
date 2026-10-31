import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';
import 'package:yuwo/splits/assign_items.dart';
import 'package:yuwo/splits/split_service.dart';
import 'package:yuwo/theme/app_theme.dart';

// hostie hosts; alice and bob are members. Burger is unclaimed, Fries are bob's.
Map<String, dynamic> _bill({Map<int, List<int>> claims = const {}}) => {
  'id': 7,
  'groupId': 1,
  'title': 'Tack Room',
  'status': 'claiming',
  'mode': 'by_item',
  'currency': 'usd',
  'taxCents': 0,
  'tipCents': 0,
  'version': claims.length + 1,
  'createdBy': 1,
  'items': [
    for (final (id, name, price) in [
      (10, 'Burger', 1850),
      (11, 'Fries', 650),
      (12, 'Salad', 1400),
    ])
      {
        'id': id,
        'name': name,
        'quantity': 1,
        'unitPriceCents': price,
        'totalCents': price,
        'claimedBy': claims[id] ?? (id == 11 ? [3] : <int>[]),
      },
  ],
  'participants': [
    for (final (id, name, host) in [
      (1, 'hostie', true),
      (2, 'alice', false),
      (3, 'bob', false),
    ])
      {
        'userId': id,
        'username': name,
        'isHost': host,
        'owedCents': 0,
        'waivedCents': 0,
        'chargeCents': 0,
        'paymentStatus': 'pending',
        'cardOnFile': true,
      },
  ],
  'totals': {
    'subtotalCents': 3900,
    'totalCents': 3900,
    'collectedCents': 0,
    'unclaimedItemIds': [10, 12],
  },
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<(List<Map<String, dynamic>>, LiveSplit)> open(
    WidgetTester tester,
  ) async {
    final assigned = <Map<String, dynamic>>[];
    var claims = <int, List<int>>{};
    late final AuthService auth;
    auth = AuthService(
      client: ApiClient(
        tokenProvider: () => auth.session?.token,
        httpClient: MockClient((request) async {
          final path = request.url.path;
          if (path == '/users/login') {
            return http.Response(jsonEncode({'token': 't'}), 200);
          }
          if (path == '/groups/1/events') {
            return http.Response(
              'data: ${jsonEncode({'type': 'split', 'split': _bill()})}\n\n',
              200,
            );
          }
          final match = RegExp(
            r'/splits/7/items/(\d+)/assign',
          ).firstMatch(path);
          if (match != null) {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final itemId = int.parse(match.group(1)!);
            assigned.add({'itemId': itemId, ...body});
            final current = [...?claims[itemId]];
            body['claimed'] == true
                ? current.add(body['userId'] as int)
                : current.remove(body['userId']);
            claims = {...claims, itemId: current};
            return http.Response(
              jsonEncode({'split': _bill(claims: claims)}),
              200,
            );
          }
          return http.Response('{}', 404);
        }),
      ),
      devLogin: false,
    );
    await auth.login(username: 'hostie', password: 'x');
    tester.view
      ..physicalSize = const Size(430, 932)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final live = LiveSplit(auth, 1);
    await tester.pumpWidget(
      AuthScope(
        service: auth,
        child: MaterialApp(
          theme: AppTheme.light,
          home: AssignItemsPage(live: live),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    return (assigned, live);
  }

  Future<void> close(WidgetTester tester, LiveSplit live) async {
    await tester.pumpWidget(const SizedBox());
    live.dispose();
  }

  testWidgets('pick a person, swipe an item up, it goes on their share', (
    tester,
  ) async {
    final (assigned, live) = await open(tester);
    expect(find.text('Swipe an item up to give it to hostie'), findsOneWidget);

    // Spin to alice by tapping her on the wheel.
    await tester.tap(find.bySemanticsLabel('Give to alice'));
    await tester.pumpAndSettle();
    expect(find.text('Swipe an item up to give it to alice'), findsOneWidget);

    await tester.fling(find.text('Burger'), const Offset(0, -300), 1500);
    await tester.pumpAndSettle();

    expect(assigned, [
      {'itemId': 10, 'userId': 2, 'claimed': true},
    ]);
    expect(find.text('Burger → alice'), findsOneWidget);
    // Moves on to the next unclaimed item (Salad, skipping bob's Fries).
    expect(find.text('2 items still unclaimed'), findsNothing);
    expect(find.text('1 item still unclaimed'), findsOneWidget);
    await close(tester, live);
  });

  testWidgets('a short drag snaps back; the button sends too', (tester) async {
    final (assigned, live) = await open(tester);

    await tester.drag(find.text('Burger'), const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(assigned, isEmpty, reason: 'not far enough');

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send to hostie'));
    await tester.pumpAndSettle();
    expect(assigned.single, {'itemId': 10, 'userId': 1, 'claimed': true});
    await close(tester, live);
  });

  testWidgets('take someone off an item from its card', (tester) async {
    final (assigned, live) = await open(tester);
    await tester.drag(find.text('Burger'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(find.text('bob'), findsWidgets);

    await tester.tap(find.byTooltip('Take bob off'));
    await tester.pumpAndSettle();
    expect(assigned.single, {'itemId': 11, 'userId': 3, 'claimed': false});
    await close(tester, live);
  });
}
