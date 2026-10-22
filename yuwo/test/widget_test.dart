import 'package:flutter_test/flutter_test.dart';

import 'package:yuwo/main.dart';

void main() {
  testWidgets('App opens on the login page', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Login'), findsOneWidget);
    expect(find.text('Create Account'), findsOneWidget);
  });
}
