import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';
import 'package:yuwo/splits/split_checkout.dart';
import 'package:yuwo/splits/split_service.dart';
import 'package:yuwo/theme/app_theme.dart';

// Same shape the backend broadcasts: hostie hosts, alice and bob are members.
Map<String, dynamic> _snapshot({List<int> burgerClaims = const []}) => {
  'id': 7,
  'groupId': 1,
  'title': 'Tack Room',
  'status': 'claiming',
  'mode': 'by_item',
  'currency': 'usd',
  'taxCents': 490,
  'tipCents': 0,
  'version': burgerClaims.isEmpty ? 1 : 2,
  'createdBy': 1,
  'items': [
    {
      'id': 10,
      'name': 'Burger',
      'quantity': 1,
      'unitPriceCents': 3000,
      'totalCents': 3000,
      'claimedBy': burgerClaims,
    },
    {
      'id': 11,
      'name': 'Fries',
      'quantity': 2,
      'unitPriceCents': 500,
      'totalCents': 1000,
      'claimedBy': [3],
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
        'owedCents': 1000,
        'waivedCents': 0,
        'chargeCents': host ? 0 : 1000,
        'paymentStatus': 'pending',
        'cardOnFile': true,
      },
  ],
  'totals': {
    'subtotalCents': 4000,
    'totalCents': 4490,
    'collectedCents': 2000,
    'unclaimedItemIds': burgerClaims.isEmpty ? [10] : [],
  },
};

/// Signs in as [username] against a fake server that streams [_snapshot]
/// and records claim requests.
Future<(AuthService, List<Map<String, dynamic>>)> _signedIn(
  String username,
) async {
  final claims = <Map<String, dynamic>>[];
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
          final event = jsonEncode({'type': 'split', 'split': _snapshot()});
          return http.Response('data: $event\n\n', 200);
        }
        if (path == '/splits/7/items/10/claim') {
          claims.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(
            jsonEncode({
              'split': _snapshot(burgerClaims: [2]),
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    ),
  );
  await auth.login(username: username, password: 'x');
  return (auth, claims);
}

Future<LiveSplit> _openPopup(WidgetTester tester, AuthService auth) async {
  tester.view
    ..physicalSize = const Size(800, 1600)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final live = LiveSplit(auth, 1);
  await tester.pumpWidget(
    AuthScope(
      service: auth,
      child: MaterialApp(
        theme: AppTheme.light,
        home: SplitCheckout(live: live),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return live;
}

Future<void> _close(WidgetTester tester, LiveSplit live) async {
  await tester.pumpWidget(const SizedBox());
  live.dispose();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('members see the shared receipt and can claim items', (
    tester,
  ) async {
    final (auth, claims) = await _signedIn('alice');
    final live = await _openPopup(tester, auth);

    expect(find.text('Burger'), findsOneWidget);
    expect(find.text('Unclaimed'), findsOneWidget);
    expect(find.text('Waiting for the host to confirm'), findsOneWidget);
    expect(find.text('Confirm & charge'), findsNothing);
    expect(find.text('Waive'), findsNothing);

    await tester.tap(find.byTooltip('I had this').first);
    await tester.pump();
    await tester.pump();

    expect(claims, [
      {'claimed': true},
    ]);
    expect(find.text('Unclaimed'), findsNothing);
    expect(find.byTooltip('Remove from my items'), findsOneWidget);

    await _close(tester, live);
  });

  testWidgets('only hosts get waive and confirm controls', (tester) async {
    final (auth, _) = await _signedIn('hostie');
    final live = await _openPopup(tester, auth);

    expect(find.text('Confirm & charge'), findsOneWidget);
    expect(find.text('Waive'), findsNWidgets(2));
    expect(find.text('Members pay \$20.00'), findsOneWidget);

    await _close(tester, live);
  });
}
