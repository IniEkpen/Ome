import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:yuwo/main.dart';
import 'package:yuwo/services/api_client.dart';
import 'package:yuwo/services/auth_service.dart';

AuthService _authWith(MockClientHandler handler) {
  late final AuthService auth;
  auth = AuthService(
    client: ApiClient(
      httpClient: MockClient(handler),
      tokenProvider: () => auth.session?.token,
    ),
    // These tests check real login behaviour, not the dev bypass.
    devLogin: false,
  );
  return auth;
}

Future<void> _login(WidgetTester tester) async {
  await tester.enterText(find.byType(TextFormField).at(0), 'george');
  await tester.enterText(find.byType(TextFormField).at(1), 'Secret1!');
  await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('signed-out users see the login page', (tester) async {
    await tester.pumpWidget(
      YuwoApp(auth: _authWith((_) async => http.Response('', 500))),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('You Owe'), findsNothing);
  });

  testWidgets('empty form is not submitted', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      YuwoApp(
        auth: _authWith((_) async {
          requests++;
          return http.Response('', 200);
        }),
      ),
    );
    await tester.tap(find.widgetWithText(ElevatedButton, 'Login'));
    await tester.pumpAndSettle();

    expect(requests, 0);
    expect(find.text('Please enter your username'), findsOneWidget);
  });

  testWidgets('failed login shows a generic error', (tester) async {
    await tester.pumpWidget(
      YuwoApp(auth: _authWith((_) async => http.Response('', 500))),
    );
    await _login(tester);

    expect(find.text('Incorrect username or password.'), findsOneWidget);
    expect(find.text('You Owe'), findsNothing);
  });

  testWidgets('dev login lets any username and password in', (tester) async {
    final auth = AuthService(
      client: ApiClient(
        httpClient: MockClient((_) async => http.Response('', 401)),
      ),
      devLogin: true,
    );
    await tester.pumpWidget(YuwoApp(auth: auth));
    await _login(tester);

    expect(auth.session?.username, 'george');
    expect(find.text('You Owe'), findsOneWidget);
  });

  testWidgets('login sends password, shows home, logout returns', (
    tester,
  ) async {
    late Map<String, dynamic> sent;
    await tester.pumpWidget(
      YuwoApp(
        auth: _authWith((request) async {
          // The signed-in tabs also load groups and card status; answer
          // those with empty data and only record the login request.
          if (request.url.path != '/users/login') {
            return http.Response(
              request.url.path == '/groups' ? '[]' : '{}',
              200,
            );
          }
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode({'token': 'abc'}), 200);
        }),
      ),
    );
    await _login(tester);

    expect(sent, {'username': 'george', 'password': 'Secret1!'});
    expect(find.text('You Owe'), findsOneWidget);

    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Log Out'));
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome Back'), findsOneWidget);
  });
}
