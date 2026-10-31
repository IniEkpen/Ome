import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/pages/payment_history.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';
import 'package:yuwo/theme/app_theme.dart';

Map<String, dynamic> _item(
  int id,
  String kind,
  String direction,
  String status, {
  String note = 'Concert tickets',
  bool canRefund = false,
  String? groupName,
}) => {
  'kind': kind,
  'id': id,
  'direction': direction,
  'other': {'id': '7', 'username': 'ada'},
  'amountCents': 2500,
  'note': note,
  'groupName': groupName,
  'status': status,
  'at': '2026-10-30T12:00:00.000Z',
  'canRefund': canRefund,
};

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<List<http.Request>> open(
    WidgetTester tester,
    Future<http.Response> Function(http.Request) handler,
  ) async {
    tester.view
      ..physicalSize = const Size(430, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final requests = <http.Request>[];
    final auth = AuthService(
      client: ApiClient(
        httpClient: MockClient((request) {
          requests.add(request);
          return handler(request);
        }),
      ),
      devLogin: false,
    );
    await tester.pumpWidget(
      AuthScope(
        service: auth,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const PaymentHistoryPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return requests;
  }

  testWidgets('lists bills and pay-backs with their status, and loads more', (
    tester,
  ) async {
    final requests = await open(tester, (request) async {
      final before = request.url.queryParameters['before'];
      return http.Response(
        jsonEncode(
          before == null
              ? {
                  'items': [
                    _item(1, 'payback', 'out', 'succeeded'),
                    _item(2, 'payback', 'out', 'failed', note: 'Lunch'),
                    _item(3, 'payback', 'in', 'refunded', note: 'Train'),
                  ],
                  'nextBefore': '2026-10-30T11:00:00.000000Z',
                }
              : {
                  'items': [
                    _item(
                      4,
                      'bill',
                      'in',
                      'succeeded',
                      note: 'Pizza night',
                      groupName: 'Book Club',
                    ),
                  ],
                  'nextBefore': null,
                },
        ),
        200,
      );
    });

    expect(find.text('You paid ada'), findsNWidgets(2));
    expect(find.text('ada paid you'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget);
    expect(find.text('-\$25.00'), findsNWidgets(2));
    expect(find.text('+\$25.00'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Load more'));
    await tester.pumpAndSettle();
    expect(
      requests.last.url.queryParameters['before'],
      '2026-10-30T11:00:00.000000Z',
    );
    expect(find.textContaining('Pizza night · Book Club'), findsOneWidget);
    expect(find.text('Load more'), findsNothing, reason: 'that was the end');
  });

  testWidgets('refund a pay-back you received, after confirming', (
    tester,
  ) async {
    var refunded = false;
    final requests = await open(tester, (request) async {
      if (request.method == 'POST') {
        refunded = true;
        return http.Response(
          jsonEncode({
            'payment': {'id': 9, 'status': 'refunded'},
          }),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'items': [
            refunded
                ? _item(9, 'payback', 'in', 'refunded')
                : _item(9, 'payback', 'in', 'succeeded', canRefund: true),
          ],
          'nextBefore': null,
        }),
        200,
      );
    });

    await tester.tap(find.text('ada paid you'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Refund \$25.00'));
    await tester.pumpAndSettle();
    expect(find.text('Refund \$25.00 to ada?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Refund'));
    await tester.pumpAndSettle();

    expect(
      requests.singleWhere((r) => r.method == 'POST').url.path,
      '/payments/direct/9/refund',
    );
    expect(find.text('Refunded \$25.00 to ada'), findsOneWidget);
    expect(find.text('Refunded'), findsOneWidget, reason: 'list reloaded');
  });

  testWidgets('no refund option on payments you sent or bill payments', (
    tester,
  ) async {
    await open(
      tester,
      (_) async => http.Response(
        jsonEncode({
          'items': [
            _item(1, 'payback', 'out', 'succeeded'),
            _item(2, 'bill', 'in', 'succeeded', note: 'Pizza night'),
          ],
          'nextBefore': null,
        }),
        200,
      ),
    );
    for (final title in ['You paid ada', 'ada paid you']) {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.textContaining('Refund \$'), findsNothing, reason: title);
      await tester.tapAt(const Offset(10, 10)); // close the sheet
      await tester.pumpAndSettle();
    }
  });

  testWidgets('an empty history says so', (tester) async {
    await open(
      tester,
      (_) async =>
          http.Response(jsonEncode({'items': [], 'nextBefore': null}), 200),
    );
    expect(find.textContaining('No payments yet'), findsOneWidget);
  });
}
