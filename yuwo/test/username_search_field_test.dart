import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yuwo/transactiongraph.dart';
import 'package:yuwo/widgets/username_search_field.dart';

const _alice = Party(id: '1', label: 'alice', name: 'Alice Smith');
const _alan = Party(id: '2', label: 'alan');

Future<List<Party>> Function(String) _fixed(
  List<Party> users, [
  List<String>? log,
]) => (query) async {
  log?.add(query);
  return users;
};

Future<List<Party>> _pump(
  WidgetTester tester, {
  required Future<List<Party>> Function(String) search,
  Set<String> excluded = const {},
}) async {
  final selected = <Party>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: UsernameSearchField(
            search: search,
            excluded: excluded,
            onSelected: selected.add,
          ),
        ),
      ),
    ),
  );
  return selected;
}

/// The plain text the field paints, including any ghost suffix.
String _paintedText(WidgetTester tester) => tester
    .widget<EditableText>(find.byType(EditableText))
    .controller
    .buildTextSpan(
      context: tester.element(find.byType(EditableText)),
      withComposing: false,
    )
    .toPlainText();

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('match indices prefer a contiguous match, then in-order letters', () {
    expect(usernameMatchIndices('alice', 'LI'), {1, 2});
    expect(usernameMatchIndices('alice', 'ace'), {0, 3, 4});
    expect(usernameMatchIndices('alice', 'xyz'), isEmpty);
  });

  testWidgets('debounces, lists results and adds the tapped user', (
    tester,
  ) async {
    final queries = <String>[];
    final selected = await _pump(
      tester,
      search: _fixed([_alice, _alan], queries),
    );

    await tester.enterText(find.byType(TextField), 'a');
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump(const Duration(milliseconds: 100));
    expect(queries, isEmpty);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();

    expect(queries, ['al']);
    expect(find.text('Alice Smith'), findsOneWidget);

    await tester.tap(find.text('Alice Smith'));
    await tester.pump();

    expect(selected, [_alice]);
    expect(find.text('Alice Smith'), findsNothing);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('ignores responses for older queries', (tester) async {
    final pending = <String, Completer<List<Party>>>{};
    await _pump(
      tester,
      search: (q) => (pending[q] = Completer<List<Party>>()).future,
    );

    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'ala');
    await tester.pump(const Duration(milliseconds: 300));

    pending['ala']!.complete([_alan]);
    await tester.pump();
    pending['al']!.complete([_alice]);
    await tester.pump();

    expect(find.text('alice', findRichText: true), findsNothing);
    expect(find.text('alan', findRichText: true), findsOneWidget);
  });

  testWidgets('shows the empty state, errors and hides added users', (
    tester,
  ) async {
    var fail = false;
    await _pump(
      tester,
      excluded: {'alice'},
      search: (q) async {
        if (fail) throw Exception('offline');
        return [_alice];
      },
    );

    await tester.enterText(find.byType(TextField), 'ali');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('No users found'), findsOneWidget);

    fail = true;
    await tester.enterText(find.byType(TextField), 'alic');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.textContaining("Couldn't search users"), findsOneWidget);
  });

  testWidgets('ghost text completes with Tab and Enter adds the user', (
    tester,
  ) async {
    final selected = await _pump(tester, search: _fixed([_alice]));

    await tester.tap(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Al');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(_paintedText(tester), 'Alice');

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final controller = tester.widget<TextField>(find.byType(TextField));
    expect(controller.controller!.text, 'alice');

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    expect(selected, [_alice]);
  });
}
