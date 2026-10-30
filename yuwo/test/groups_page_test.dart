import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/pages/group.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';
import 'package:yuwo/theme/app_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<List<http.Request>> pumpGroups(
    WidgetTester tester, {
    bool verified = true,
  }) async {
    final requests = <http.Request>[];
    final auth = AuthService(
      client: ApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/payments/card') {
            return http.Response(
              jsonEncode({
                'card': {'hasValidCard': true, 'paymentsVerified': verified},
              }),
              200,
            );
          }
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({'groupId': 1, 'invited': [], 'notFound': []}),
              201,
            );
          }
          if (request.url.path == '/network/search') {
            const users = {'ben': 'Ben Ade', 'cleo': 'Cleo Moss'};
            final q = request.url.queryParameters['q'] ?? '';
            return http.Response(
              jsonEncode({
                'users': [
                  for (final e in users.entries)
                    if (e.key.startsWith(q))
                      {'id': e.key, 'label': e.key, 'name': e.value},
                ],
              }),
              200,
            );
          }
          return http.Response('[]', 200);
        }),
      ),
      devLogin: false,
    );
    await tester.pumpWidget(
      AuthScope(
        service: auth,
        child: MaterialApp(theme: AppTheme.light, home: const GroupsPage()),
      ),
    );
    await tester.pumpAndSettle();
    return requests;
  }

  testWidgets('empty state wording points at the + button', (tester) async {
    await pumpGroups(tester);
    expect(find.text("You're not part of any groups yet"), findsOneWidget);
    expect(find.text('Tap + at the top to create one'), findsOneWidget);
    expect(find.textContaining('Apart'), findsNothing);
  });

  testWidgets('+ opens the create form, which creates the group', (
    tester,
  ) async {
    final requests = await pumpGroups(tester);
    expect(find.text('Group Name'), findsNothing);

    await tester.tap(find.byTooltip('Create group'));
    await tester.pumpAndSettle();
    expect(find.text('Create a Group'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).at(0), 'Dinner');

    // Members are picked from username search results.
    final search = find.widgetWithText(TextField, 'Add members by username');
    for (final (query, name) in [('be', 'Ben Ade'), ('cl', 'Cleo Moss')]) {
      await tester.enterText(search, query);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
    expect(find.widgetWithText(InputChip, 'ben'), findsOneWidget);
    expect(find.widgetWithText(InputChip, 'cleo'), findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Create Group'));
    await tester.pumpAndSettle();

    final create = requests.singleWhere((r) => r.method == 'POST');
    expect(jsonDecode(create.body), {
      'groupName': 'Dinner',
      'members': ['ben', 'cleo'],
    });
    expect(find.text('Create a Group'), findsNothing, reason: 'sheet closes');
    expect(find.text('Group "Dinner" created. Invites sent.'), findsOneWidget);
  });

  testWidgets('without payment verification, + asks to verify first', (
    tester,
  ) async {
    final requests = await pumpGroups(tester, verified: false);
    await tester.tap(find.byTooltip('Create group'));
    await tester.pumpAndSettle();

    expect(find.text('Verify your payment details'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();

    expect(
      find.text('Create a Group'),
      findsNothing,
      reason: 'form never opens',
    );
    expect(requests.where((r) => r.method == 'POST'), isEmpty);
  });
}
