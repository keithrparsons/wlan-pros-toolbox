// THE FOURTH FINDABILITY DEFECT (Keith, 2026-08-25), fixed 2026-09-17.
//
// His words: "searched inside a sub section for IPv4 and it only searched DOWN
// and thus didn't find those in network tools."
//
// Three of the four defects he found that day were fixed the same day. This one
// was not, and the worklist called it the most valuable of the four BECAUSE IT
// FAILS FOR EVERY TOOL IN THE APP rather than for three of them.
//
// These tests are written against THE WORDS A USER TYPES, not against tool ids.
// An id-based test would have passed on the broken build, which is the whole
// lesson of the 2026-08-25 fix.
//
// Measured on the shipping catalog the day this was written: "ipv4" scoped to
// Networking Tools returns ZERO while four tools match across two other
// categories. That is Keith's exact case, still reproducible on main.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_search.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

ToolCategory _cat(String id) =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == id);

Widget _harness(ToolCategory cat) => MaterialApp(
      theme: AppTheme.dark(),
      home: CategoryScreen(category: cat),
    );

Future<void> _searchIn(WidgetTester tester, String catId, String query) async {
  await tester.pumpWidget(_harness(_cat(catId)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).first, query);
  await tester.pumpAndSettle();
}

void main() {
  group('the catalog still reproduces the defect this fix exists for', () {
    test('"ipv4" is empty inside Networking Tools and non-empty globally', () {
      expect(searchTools('ipv4', categoryId: 'networking'), isEmpty,
          reason: 'if this ever stops being true the fixture is stale, not the '
              'feature: pick another query that reproduces a scoped miss');
      expect(searchTools('ipv4').length, greaterThan(1));
    });
  });

  group('a scoped miss says WHERE the tools are, not that there are none', () {
    testWidgets('Keith\'s case: ipv4 inside Networking Tools', (tester) async {
      await _searchIn(tester, 'networking', 'ipv4');

      // The honest half that was always right.
      expect(find.textContaining('No tools match "ipv4" here'), findsOneWidget);

      // The half that was missing. Two categories hold hits, so the sentence
      // names both rather than counting them.
      expect(find.textContaining('Calculators & Tools'), findsOneWidget);
      expect(find.textContaining('Quick Reference'), findsOneWidget);
      expect(find.text('Search all tools'), findsOneWidget);
    });

    testWidgets('one category holding hits reads as a plain sentence',
        (tester) async {
      await _searchIn(tester, 'networking', 'vlsm');
      // Exactly one tool, so singular. "1 tools" is the tell of a count that was
      // never read aloud.
      expect(find.textContaining('1 tool in Calculators & Tools'),
          findsOneWidget);
      expect(find.textContaining('1 tools'), findsNothing);
    });

    testWidgets('a plural within one category still names that category',
        (tester) async {
      // DERIVED, NOT HARDCODED, and it was hardcoded until 2026-09-17.
      //
      // This read "7 tools in Calculators & Tools" and went red the moment the
      // MTU & MSS Calculator was added, because that title contains the word
      // "calculator" and the count became 8. The feature under test is that
      // the sentence NAMES the category and agrees with the search; the
      // literal number is incidental to it and pinning one guarantees a false
      // failure every time the catalog grows.
      final int expected = searchTools('calculator').length;
      expect(expected, greaterThan(1), reason: 'fixture needs a plural');
      await _searchIn(tester, 'networking', 'calculator');
      expect(find.textContaining('$expected tools in Calculators & Tools'),
          findsOneWidget);
    });

    testWidgets('a genuine global miss offers nothing and claims nothing',
        (tester) async {
      await _searchIn(tester, 'networking', 'zzzqqqnotatool');
      expect(find.textContaining('No tools match'), findsOneWidget);
      // THE CASE THAT MUST NOT REGRESS INTO A LIE: when the query matches
      // nowhere, there is no elsewhere, and the screen must not offer a search
      // that will also come back empty.
      expect(find.text('Search all tools'), findsNothing);
      expect(find.textContaining('Found '), findsNothing);
    });
  });

  group('the offer carries the query with it', () {
    testWidgets('tapping through pushes /search with the typed term',
        (tester) async {
      String? pushedRoute;
      Object? pushedArgs;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: CategoryScreen(category: _cat('networking')),
          onGenerateRoute: (RouteSettings s) {
            pushedRoute = s.name;
            pushedArgs = s.arguments;
            return MaterialPageRoute<void>(
              builder: (_) => const SizedBox.shrink(),
              settings: s,
            );
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'ipv4');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Search all tools'));
      await tester.pumpAndSettle();

      expect(pushedRoute, '/search');
      // Handing the search screen an empty box after promising results is a
      // worse answer than not offering at all.
      expect(pushedArgs, 'ipv4');
    });
  });
}
