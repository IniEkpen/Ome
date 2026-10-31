import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/pages/pay_back.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';
import 'package:yuwo/theme/app_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Opens PayBackPage from a button so its result message can be checked.
  Future<List<http.Request>> open(
    WidgetTester tester, {
    required Future<http.Response> Function(http.Request) pay,
  }) async {
    final requests = <http.Request>[];
    final auth = AuthService(
      client: ApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/network/search') {
            return http.Response(
              jsonEncode({
                'users': [
                  {'id': '7', 'label': 'ada', 'name': 'Ada Lovelace'},
                ],
              }),
              200,
            );
          }
          return pay(request);
        }),
      ),
      devLogin: false,
    );
    String? result;
    await tester.pumpWidget(
      AuthScope(
        service: auth,
        child: MaterialApp(
          theme: AppTheme.light,
          home: Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: [
                  TextButton(
                    onPressed: () async {
                      result = await Navigator.of(context).push<String>(
                        MaterialPageRoute(builder: (_) => const PayBackPage()),
                      );
                    },
                    child: const Text('open'),
                  ),
                  Builder(builder: (_) => Text('result: $result')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return requests;
  }

  Future<void> pickAda(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'ada love');
    await tester.pump(const Duration(milliseconds: 350)); // debounce
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();
  }

  Future<void> fillAndPay(
    WidgetTester tester,
    String amount,
    String note,
  ) async {
    await tester.enterText(find.byType(TextFormField).at(0), amount);
    await tester.enterText(find.byType(TextFormField).at(1), note);
    await tester.tap(find.widgetWithText(ElevatedButton, 'Pay'));
    await tester.pumpAndSettle();
  }

  testWidgets('search by name, pay with a note, and come back', (tester) async {
    final requests = await open(
      tester,
      pay: (_) async => http.Response(jsonEncode({'payment': {}}), 201),
    );
    await pickAda(tester);
    expect(find.text('Paying Ada Lovelace'), findsOneWidget);

    await fillAndPay(tester, '25', 'Concert tickets');
    expect(find.text('Pay Ada Lovelace \$25.00?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Pay'));
    await tester.pumpAndSettle();

    final pay = requests.singleWhere((r) => r.url.path == '/payments/direct');
    final body = jsonDecode(pay.body) as Map<String, dynamic>;
    expect(body['recipientId'], 7);
    expect(body['amountCents'], 2500);
    expect(body['note'], 'Concert tickets');
    expect(body['idempotencyKey'], isA<String>());
    expect(find.byType(PayBackPage), findsNothing);
  });

  testWidgets('needs an amount between \$1 and \$1,000 and a note', (
    tester,
  ) async {
    final requests = await open(
      tester,
      pay: (_) async => http.Response('{}', 201),
    );
    await pickAda(tester);
    await fillAndPay(tester, '0.50', '');
    expect(find.text('Payments are between \$1 and \$1,000'), findsOneWidget);
    expect(find.text("Say what you're paying them back for"), findsOneWidget);
    await fillAndPay(tester, '1500', 'Rent');
    expect(find.text('Payments are between \$1 and \$1,000'), findsOneWidget);
    expect(requests.where((r) => r.url.path == '/payments/direct'), isEmpty);
  });

  testWidgets('a lost connection keeps the same key so a retry cannot '
      'charge twice; a decline gets a new key', (tester) async {
    var attempt = 0;
    final requests = await open(
      tester,
      pay: (_) async {
        attempt++;
        if (attempt == 1) throw http.ClientException('connection lost');
        return http.Response(
          jsonEncode({
            'error': 'Your card was declined. Try another card from Profile.',
            'code': 'payment_declined',
          }),
          402,
        );
      },
    );
    await pickAda(tester);
    Future<void> payOnce() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Pay'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Pay'));
      await tester.pumpAndSettle();
    }

    await tester.enterText(find.byType(TextFormField).at(0), '12.50');
    await tester.enterText(find.byType(TextFormField).at(1), 'Lunch');
    await payOnce(); // connection lost
    expect(
      find.text('Could not reach the server. Check your connection.'),
      findsOneWidget,
    );
    await payOnce(); // declined
    expect(
      find.text('Your card was declined. Try another card from Profile.'),
      findsOneWidget,
    );
    await payOnce(); // declined again, with a fresh key

    final keys = [
      for (final r in requests.where((r) => r.url.path == '/payments/direct'))
        (jsonDecode(r.body) as Map<String, dynamic>)['idempotencyKey'],
    ];
    expect(keys, hasLength(3));
    expect(keys[1], keys[0], reason: 'retry after lost connection');
    expect(keys[2], isNot(keys[1]), reason: 'new attempt after a decline');
    expect(find.byType(PayBackPage), findsOneWidget, reason: 'stays open');
  });
}
