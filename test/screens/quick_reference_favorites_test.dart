// Widget tests for Favorites and Recents on the Quick Reference screen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/services/quick_reference_prefs.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

ToolCategory _cat(String id) =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == id);

Future<void> _pump(WidgetTester tester, String categoryId) async {
  tester.view.physicalSize = const Size(1200, 6000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: CategoryScreen(category: _cat(categoryId)),
      onGenerateRoute: (RouteSettings s) => MaterialPageRoute<void>(
        settings: s,
        builder: (_) => Scaffold(body: Text('opened ${s.name}')),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  testWidgets('no Favorites or Recents group until something is added', (
    WidgetTester tester,
  ) async {
    await _pump(tester, 'quick-reference');
    expect(find.text('Favorites'), findsNothing);
    expect(find.text('Recents'), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('star-db-reference')),
      findsOneWidget,
    );
  });

  testWidgets('starring an item shows it in Favorites at the top, and it is '
      'saved', (WidgetTester tester) async {
    await _pump(tester, 'quick-reference');
    await tester.tap(find.byKey(const ValueKey<String>('star-db-reference')));
    await tester.pumpAndSettle();

    expect(find.text('Favorites'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('favorite-db-reference')),
      findsOneWidget,
    );
    // Favorites sits above the first regular section.
    expect(
      tester.getTopLeft(find.text('Favorites')).dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('db-reference')))
            .dy,
      ),
    );
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(QuickReferencePrefs.favoritesKey), <String>[
      'db-reference',
    ]);

    // Unstar from the Favorites copy: the group goes away.
    await tester.tap(
      find.byKey(const ValueKey<String>('favorite-star-db-reference')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Favorites'), findsNothing);
  });

  testWidgets('opening an item adds it to Recents; Clear empties it', (
    WidgetTester tester,
  ) async {
    await _pump(tester, 'quick-reference');
    await tester.tap(find.byKey(const ValueKey<String>('mcs-index')));
    await tester.pumpAndSettle();
    expect(find.text('opened /tools/mcs-index'), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('Recents'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('recent-mcs-index')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('clear-recents')));
    await tester.pumpAndSettle();
    expect(find.text('Recents'), findsNothing);
  });

  testWidgets('saved lists come back on the next visit', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      QuickReferencePrefs.favoritesKey: <String>['wpa-security'],
      QuickReferencePrefs.recentsKey: <String>['osi-model', 'mcs-index'],
    });
    await _pump(tester, 'quick-reference');
    expect(find.text('Favorites'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('favorite-wpa-security')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey<String>('recent-osi-model')))
          .dy,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey<String>('recent-mcs-index')))
            .dy,
      ),
    );
  });

  testWidgets('other categories have no stars', (WidgetTester tester) async {
    await _pump(tester, 'networking');
    expect(find.byIcon(Icons.star_border), findsNothing);
  });
}
