import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';
import 'package:yuwo/services/card_service.dart';
import 'package:yuwo/services/receipt_service.dart';
import 'package:yuwo/splits/split_checkout.dart';
import 'package:yuwo/splits/split_service.dart';
import 'package:yuwo/theme/app_theme.dart';

// A bill as the backend sends it: alice paying with her Mastercard (picked
// for this bill), bob on his default Visa, and a receipt attached.
Map<String, dynamic> _bill({bool aliceOnVisa = false}) => {
  'id': 7,
  'groupId': 1,
  'title': 'Tack Room',
  'receiptId': 42,
  'status': 'claiming',
  'mode': 'even',
  'currency': 'usd',
  'taxCents': 0,
  'tipCents': 0,
  'version': 1,
  'createdBy': 1,
  'items': [
    {
      'id': 10,
      'name': 'Burger',
      'quantity': 1,
      'unitPriceCents': 3000,
      'totalCents': 3000,
      'claimedBy': <int>[],
    },
  ],
  'participants': [
    {
      'userId': 1,
      'username': 'hostie',
      'isHost': true,
      'owedCents': 1000,
      'waivedCents': 0,
      'chargeCents': 0,
      'paymentStatus': 'pending',
      'cardOnFile': true,
      'card': {'brand': 'visa', 'last4': '1111', 'chosen': false},
    },
    {
      'userId': 2,
      'username': 'alice',
      'isHost': false,
      'owedCents': 1000,
      'waivedCents': 0,
      'chargeCents': 1000,
      'paymentStatus': 'pending',
      'cardOnFile': true,
      'card': aliceOnVisa
          ? {'brand': 'visa', 'last4': '4242', 'chosen': true}
          : {'brand': 'mastercard', 'last4': '4444', 'chosen': true},
    },
    {
      'userId': 3,
      'username': 'bob',
      'isHost': false,
      'owedCents': 1000,
      'waivedCents': 0,
      'chargeCents': 1000,
      'paymentStatus': 'pending',
      'cardOnFile': true,
      'card': {'brand': 'visa', 'last4': '1881', 'chosen': false},
    },
  ],
  'totals': {
    'subtotalCents': 3000,
    'totalCents': 3000,
    'collectedCents': 2000,
    'unclaimedItemIds': [10],
  },
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('members see whose card pays, change their own, and view the '
      'receipt', (tester) async {
    final requests = <http.Request>[];
    late final AuthService auth;
    auth = AuthService(
      client: ApiClient(
        tokenProvider: () => auth.session?.token,
        httpClient: MockClient((request) async {
          requests.add(request);
          return switch (request.url.path) {
            '/users/login' => http.Response(jsonEncode({'token': 't'}), 200),
            '/groups/1/events' => http.Response(
              'data: ${jsonEncode({'type': 'split', 'split': _bill()})}\n\n',
              200,
            ),
            '/payments/cards' => http.Response(
              jsonEncode({
                'cards': [
                  {
                    'id': 'pm_visa',
                    'brand': 'visa',
                    'last4': '4242',
                    'expMonth': 8,
                    'expYear': 2030,
                    'isDefault': true,
                  },
                  {
                    'id': 'pm_master',
                    'brand': 'mastercard',
                    'last4': '4444',
                    'expMonth': 1,
                    'expYear': 2031,
                  },
                ],
              }),
              200,
            ),
            '/splits/7/card' => http.Response(
              jsonEncode({'split': _bill(aliceOnVisa: true)}),
              200,
            ),
            '/receipts/42' => http.Response.bytes(_onePixelPng, 200),
            _ => http.Response('{}', 404),
          };
        }),
      ),
      devLogin: false,
    );
    await auth.login(username: 'alice', password: 'x');

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

    // Everyone's card shows; only my own row can change it.
    expect(find.textContaining('Mastercard •••• 4444'), findsOneWidget);
    expect(find.textContaining('Visa •••• 1881'), findsOneWidget);
    expect(
      find.textContaining('1111'),
      findsNothing,
      reason: 'host not charged',
    );
    expect(find.text('Change card'), findsOneWidget);

    await tester.tap(find.text('Change card'));
    await tester.pumpAndSettle();
    expect(find.text('Pay your share with'), findsOneWidget);
    await tester.tap(find.text('Visa •••• 4242'));
    await tester.pumpAndSettle();
    final change = requests.singleWhere((r) => r.url.path == '/splits/7/card');
    expect(change.method, 'PUT');
    expect(jsonDecode(change.body), {'paymentMethodId': 'pm_visa'});
    expect(find.textContaining('Visa •••• 4242'), findsOneWidget);

    await tester.tap(find.byTooltip('View receipt'));
    await tester.pumpAndSettle();
    expect(find.text('Receipt · Tack Room'), findsOneWidget);
    expect(find.bySemanticsLabel('Receipt photo'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    live.dispose();
  });

  test('receipt upload sends the photo and reads the draft', () async {
    late http.Request sent;
    final auth = AuthService(
      client: ApiClient(
        httpClient: MockClient((request) async {
          sent = request;
          return http.Response(
            jsonEncode({
              'receiptId': 5,
              'draft': {
                'merchantName': 'The Tack Room',
                'receiptDate': '2024-04-08',
                'items': [
                  {
                    'name': 'Fried Chicken Sandwich',
                    'quantity': 2,
                    'unitPriceCents': 1700,
                  },
                ],
                'taxCents': 711,
                'tipCents': null,
                'totalCents': 13211,
              },
              'scanError': null,
            }),
            201,
          );
        }),
      ),
      devLogin: false,
    );
    final upload = await ReceiptService(
      auth,
    ).upload([1, 2, 3], contentType: 'image/jpeg');
    expect(sent.url.path, '/receipts');
    expect(sent.url.queryParameters['scan'], '1');
    expect(sent.headers['Content-Type'], 'image/jpeg');
    expect(sent.bodyBytes, [1, 2, 3]);
    expect(upload.receiptId, 5);
    expect(upload.draft!.merchantName, 'The Tack Room');
    expect(upload.draft!.items.single.quantity, 2);
    expect(upload.draft!.items.single.unitPriceCents, 1700);
    expect(upload.draft!.taxCents, 711);
  });

  test('saved cards: labels, expiry and default', () async {
    final auth = AuthService(
      client: ApiClient(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'cards': [
                {
                  'id': 'pm_1',
                  'brand': 'amex',
                  'last4': '8431',
                  'expMonth': 3,
                  'expYear': 2029,
                  'isDefault': true,
                },
                {
                  'id': 'pm_2',
                  'brand': null,
                  'last4': '0005',
                  'expMonth': 1,
                  'expYear': 2020,
                  'expired': true,
                },
              ],
            }),
            200,
          ),
        ),
      ),
      devLogin: false,
    );
    final cards = await CardService(auth).list();
    expect(cards.first.label, 'Amex •••• 8431');
    expect(cards.first.expiry, '03/29');
    expect(cards.first.isDefault, isTrue);
    expect(cards.last.label, 'Card •••• 0005');
    expect(cards.last.expired, isTrue);
  });
}

// Smallest valid PNG, so the receipt viewer has something to decode.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
