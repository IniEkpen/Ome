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

  test('parses the /users/me/home response and skips unknown activity', () {
    final home = HomeData.fromJson({
      'bills': [
        {
          'groupName': 'Dinner',
          'title': 'Tack Room',
          'stage': 'charging',
          'amountCents': 1200,
          'people': 3,
          'isHost': false,
        },
      ],
      'activity': [
        {
          'kind': 'paid_you',
          'who': 'bob',
          'groupName': 'Dinner',
          'amountCents': 500,
          'at': '2026-10-20T12:00:00.000Z',
        },
        {'kind': 'something_new', 'at': '2026-10-20T12:00:00.000Z'},
      ],
    });

    expect(home.bills.single.stage, BillStage.charging);
    expect(home.youOweCents, 1200);
    expect(home.activity.single.kind, ActivityKind.paidYou);
    expect(home.isMock, isFalse);
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
