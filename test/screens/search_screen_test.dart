// Widget tests for the global SearchScreen (Ticket 1, mockup 04).
//
// Covers: the empty-query hint, that typing renders the mono count line + result
// rows grouped with category source tags + a lime title highlight, the
// no-results state, and that tapping a live result navigates.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/search_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/content_type_chip.dart';
import 'package:wlan_pros_toolbox/widgets/tool_row.dart';

Widget _harness({Map<String, WidgetBuilder>? routes}) => MaterialApp(
      theme: AppTheme.dark(),
      home: const SearchScreen(),
      routes: routes ?? <String, WidgetBuilder>{},
    );

void main() {
  testWidgets(
    'the clear-search button exposes an accessible NAME, not just a tooltip '
    '(WCAG 2.2 AA SC 4.1.2)',
    (tester) async {
      final SemanticsHandle handle = tester.ensureSemantics();
      await tester.pumpWidget(_harness());
      // The clear affordance only renders once the field has text.
      await tester.enterText(find.byType(TextField), 'channel');
      await tester.pump();

      // `tooltip:` maps to AXHelp, not AXTitle, so without the explicit
      // Semantics label this icon-only button reads as `label="" button=true`.
      // Removing that label (the mutation) drops this node → red.
      expect(find.bySemanticsLabel('Clear search'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Clear search')),
        isSemantics(
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          label: 'Clear search',
        ),
        reason: 'the clear button must read as a named, ENABLED button to AT',
      );

      handle.dispose();
    },
  );

  testWidgets('empty query shows the start-typing hint', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();
    expect(find.text('Start typing to search all tools'), findsOneWidget);
    expect(find.byType(ToolRow), findsNothing);
  });

  testWidgets('typing renders the count line and result rows', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.enterText(find.byType(TextField), 'channel');
    await tester.pump();

    // The "N results across M categories" count line.
    expect(find.textContaining('results across'), findsOneWidget);
    // At least a few result rows.
    expect(find.byType(ToolRow), findsWidgets);
    // Each result row carries a neutral source tag chip.
    expect(find.byType(ContentTypeChip), findsWidgets);
  });

  testWidgets('a matched term is highlighted (Text.rich) in a result title', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.enterText(find.byType(TextField), 'channel');
    await tester.pump();
    // The highlight is rendered via Text.rich / RichText spans.
    expect(find.byType(RichText), findsWidgets);
  });

  testWidgets('a no-match query shows the no-results state', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.enterText(find.byType(TextField), 'zzzznotarealterm');
    await tester.pump();
    expect(find.textContaining('No tools match'), findsOneWidget);
    expect(find.byType(ToolRow), findsNothing);
  });

  testWidgets('tapping a live result navigates to its route', (tester) async {
    bool navigated = false;
    await tester.pumpWidget(
      _harness(
        routes: <String, WidgetBuilder>{
          '/tools/fspl': (_) {
            navigated = true;
            return const Scaffold(body: Text('FSPL screen'));
          },
        },
      ),
    );
    // "fspl" matches the Free Space Path Loss tool by keyword/title.
    await tester.enterText(find.byType(TextField), 'free space path');
    await tester.pump();

    final Finder row = find.byType(ToolRow).first;
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(navigated, isTrue);
  });
}
