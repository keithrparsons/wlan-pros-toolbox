// Render checks for the Date & Time Standards and Hash Lengths reference
// screens, which had no screen test. They pin each screen's table titles,
// column headers and a sample row at phone, tablet and desktop widths so the
// table card and header cell can be shared between reference screens without
// changing what these two show.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/datetime_standards_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/hash_lengths_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pumpAt(WidgetTester tester, double width, Widget screen) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(theme: AppTheme.dark(), home: screen));
  await tester.pump();
}

Finder _t(String s) => find.text(s, skipOffstage: false);

void main() {
  for (final double width in <double>[320, 375, 768, 1280]) {
    testWidgets('Date & Time Standards renders its tables at ${width}px', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, width, const DatetimeStandardsScreen());
      expect(_t('Date & Time Standards'), findsWidgets);
      expect(_t('ISO 8601 core formats'), findsOneWidget);
      expect(_t('UTC vs local offset notation'), findsOneWidget);
      for (final String h in <String>[
        'Concept',
        'Format',
        'Example',
        'Note',
        'Notation',
        'Meaning',
      ]) {
        expect(_t(h), findsWidgets, reason: 'column header $h');
      }
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    });

    testWidgets('Hash Lengths renders its table at ${width}px', (
      WidgetTester tester,
    ) async {
      await _pumpAt(tester, width, const HashLengthsScreen());
      expect(_t('Hash & Crypto Output Lengths'), findsWidgets);
      expect(_t('Hash output lengths'), findsOneWidget);
      for (final String h in <String>[
        'Algorithm',
        'Bits',
        'Bytes',
        'Hex',
        'Family',
        'Status',
      ]) {
        expect(_t(h), findsWidgets, reason: 'column header $h');
      }
      expect(_t('SHA-256'), findsWidgets);
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    });
  }
}
