import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yuwo/pages/home.dart';
import 'package:yuwo/pages/home_data.dart';
import 'package:yuwo/theme/app_theme.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('home shows balances, open bills and activity on a phone', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(360, 1800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const HomePage()),
    );

    // Members' unpaid shares: 37.95 + 22.10. Hosting: 86.40 still coming in.
    expect(find.text('You Owe'), findsOneWidget);
    expect(find.text('\$60.05'), findsOneWidget);
    expect(find.text('\$86.40'), findsWidgets);
    expect(find.text('The Tack Room'), findsOneWidget);
    expect(find.text('Pick your items'), findsOneWidget);
    expect(find.text('bob paid you'), findsOneWidget);
    expect(find.text('Sample data'), findsOneWidget);
  });

  testWidgets('empty home shows settled-up states', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const HomePage(
          data: HomeData(bills: [], activity: []),
        ),
      ),
    );

    expect(find.text('\$0.00'), findsNWidgets(2));
    expect(find.text("You're all settled up"), findsOneWidget);
    expect(find.text('Sample data'), findsNothing);
  });
}
