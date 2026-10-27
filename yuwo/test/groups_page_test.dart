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

  Future<List<http.Request>> pumpGroups(WidgetTester tester) async {
    final requests = <http.Request>[];
    final auth = AuthService(
      client: ApiClient(
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.method == 'POST') {
            return http.Response(
              jsonEncode({'groupId': 1, 'invited': [], 'notFound': []}),
              201,
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
    await tester.enterText(find.byType(TextFormField).at(1), 'ben, cleo');
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
}
