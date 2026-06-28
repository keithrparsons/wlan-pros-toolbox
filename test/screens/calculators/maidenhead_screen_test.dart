// Widget smoke tests for the Maidenhead Grid screen. The locator math itself is
// covered exhaustively in test/data/maidenhead_data_test.dart; these confirm the
// screen pumps, the modes render, and a To-Grid entry produces a locator.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/maidenhead_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  testWidgets('renders title and the To-Grid prompt by default',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const MaidenheadScreen(),
      ),
    );
    expect(find.text('Maidenhead Grid'), findsWidgets);
    // To Grid default: latitude + longitude fields.
    expect(find.text('Latitude'), findsOneWidget);
    expect(find.text('Longitude'), findsOneWidget);
  });

  testWidgets('entering Berlin coordinates yields JO62', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const MaidenheadScreen(),
      ),
    );
    // Two coordinate fields in To-Grid mode.
    final Finder fields = find.byType(TextField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), '52.5'); // latitude
    await tester.enterText(fields.at(1), '13.4'); // longitude
    await tester.pump();
    // Default precision is 6-char; JO62 is the 4-char prefix.
    expect(find.textContaining('JO62'), findsWidgets);
  });
}
