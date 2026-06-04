// Widget tests for the grouped CategoryScreen (Ticket 2, mockup 02).
//
// Covers: grouped categories render section headers + count chips + content-type
// chips; the in-category search filters to matching rows and shows the
// no-results state; tapping a live row navigates; the flat Test Network category
// renders its pinned order with NO section headers (the pin path is untouched).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_subgroups.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/section_header.dart';
import 'package:wlan_pros_toolbox/widgets/tool_row.dart';

ToolCategory _cat(String id) =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == id);

Widget _harness(ToolCategory cat, {Map<String, WidgetBuilder>? routes}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      home: CategoryScreen(category: cat),
      routes: routes ?? <String, WidgetBuilder>{},
    );

void main() {
  testWidgets('grouped category renders its section headers in order', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_harness(_cat('rf-calculators')));
    await tester.pump();

    expect(find.byType(SectionHeader), findsWidgets);
    // The first editorial section for rf-calculators is "RF & Propagation".
    // The section name also appears in the filter-chip row, so scope the
    // assertion to the SectionHeader to count only the header instance.
    expect(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.text('RF & Propagation'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SectionHeader),
        matching: find.text('Antenna & Coverage'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the in-category search field filters to matching rows', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_cat('rf-calculators')));
    await tester.pump();

    // Type a term that matches only a couple of tools.
    await tester.enterText(find.byType(TextField), 'fresnel');
    await tester.pump();

    // Filtering collapses section headers; the matching row(s) remain.
    expect(find.byType(SectionHeader), findsNothing);
    expect(find.byType(ToolRow), findsWidgets);
    expect(find.text('Fresnel Zone'), findsOneWidget);
  });

  testWidgets('a no-match in-category query shows the no-results state', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(_cat('rf-calculators')));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'zzzznotarealterm');
    await tester.pump();
    expect(find.textContaining('No tools match'), findsOneWidget);
    expect(find.byType(ToolRow), findsNothing);
  });

  testWidgets('tapping a live row navigates to its route', (tester) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    bool navigated = false;
    await tester.pumpWidget(
      _harness(
        _cat('rf-calculators'),
        routes: <String, WidgetBuilder>{
          '/tools/fspl': (_) {
            navigated = true;
            return const Scaffold(body: Text('FSPL'));
          },
        },
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Free Space Path Loss'));
    await tester.pumpAndSettle();
    expect(navigated, isTrue);
  });

  testWidgets('flat Test Network renders the pinned order with no headers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(_harness(_cat('test-network')));
    await tester.pump();

    // Flat category → no section headers.
    expect(find.byType(SectionHeader), findsNothing);

    // The grouping helper still returns the pinned order for the flat path.
    // Wave 4 (2026-06-04): the merged connection tile was removed from the
    // catalog (reached via the home hero), so Network Quality leads the pins.
    final List<ToolSection> sections = groupedCategoryTools(_cat('test-network'));
    expect(sections, hasLength(1));
    expect(sections.single.tools.first.id, 'net-quality');
  });
}
