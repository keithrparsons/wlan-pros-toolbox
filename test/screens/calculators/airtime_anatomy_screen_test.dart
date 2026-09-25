// Widget tests for Airtime Anatomy (Wi-Fi Lab).
//
// The math has its own tests (test/services/wifi_lab/airtime_anatomy_test
// .dart); these check the screen: it opens on two spreadsheet defaults,
// presets and inputs change the scenario under edit, an invalid combination
// is not drawn and says why, selecting a segment shows its formula, and the
// layout holds at phone width in both themes without sideways scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_timeline.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _host({ThemeData? theme}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: const AirtimeAnatomyScreen(),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

void main() {
  testWidgets('opens on Legacy 6 Mbps vs HE 32 aggregated', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3600));
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('Airtime Anatomy'), findsOneWidget);
    expect(find.byType(AirtimeAnatomyStage), findsOneWidget);
    expect(find.byType(AirtimeAnatomyControls), findsOneWidget);
    // Totals, straight from the spreadsheet defaults.
    expect(find.text('2242.5 µs'), findsWidgets);
    expect(find.text('548.9 µs'), findsWidgets);
    expect(find.text('Check A: OK'), findsOneWidget);
    expect(find.text('Check B: OK'), findsOneWidget);
    expect(find.text('1200.96'), findsOneWidget);
    expect(find.text('16333'), findsOneWidget);
    expect(find.textContaining('Tap or hover a segment'), findsOneWidget);
  });

  testWidgets('a preset replaces the scenario under edit', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3600));
    await tester.pumpWidget(_host());
    await _tap(tester, find.widgetWithText(OutlinedButton, 'VHT one frame'));
    expect(find.text('214.5 µs'), findsWidgets);
    expect(find.text('2242.5 µs'), findsNothing);
    expect(find.text('866.67'), findsOneWidget);

    // Edit B instead, then load VHT 32 aggregated into it.
    await _tap(tester, find.text('B').last);
    await _tap(
      tester,
      find.widgetWithText(OutlinedButton, 'VHT 32 aggregated'),
    );
    expect(find.text('666.5 µs'), findsWidgets);
    expect(find.text('548.9 µs'), findsNothing);
  });

  testWidgets('6 GHz with VHT is not drawn and says why', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3600));
    await tester.pumpWidget(_host());
    await _tap(tester, find.widgetWithText(OutlinedButton, 'VHT one frame'));
    await _tap(tester, find.text('6 GHz'));
    expect(find.text('Not drawn. 6 GHz requires HE.'), findsOneWidget);
    expect(find.text('Check A: 6 GHz requires HE'), findsOneWidget);
    expect(find.text('Custom'), findsOneWidget);
  });

  testWidgets('selecting a segment shows its duration and formula', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3600));
    await tester.pumpWidget(_host());
    // The breakdown table: B's data cell.
    await _tap(tester, find.widgetWithText(TextButton, '340'));
    expect(find.text('B · Data'), findsOneWidget);
    expect(find.text('340 µs, 61.9 % of this TXOP'), findsOneWidget);
    expect(find.textContaining('25 symbols x 13.6 µs'), findsOneWidget);
    // Selecting it again clears it.
    await _tap(tester, find.widgetWithText(TextButton, '340'));
    expect(find.text('B · Data'), findsNothing);
  });

  testWidgets('tapping the bar selects the segment under the finger', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3600));
    await tester.pumpWidget(_host());
    await tester.pump();
    // Legacy's data block is most of bar A; tap the middle of the first bar.
    final Finder bar = find
        .byWidgetPredicate(
          (Widget w) => w is CustomPaint && w.painter is AirtimeBarPainter,
        )
        .first;
    final Rect r = tester.getRect(bar);
    // Middle of the bar itself, above any leader-label rows.
    await tester.tapAt(
      Offset(r.center.dx, r.top + AirtimeBarGeometry.barHeight / 2),
    );
    await tester.pump();
    expect(find.text('A · Data'), findsOneWidget);
  });

  testWidgets('compare off shows one scenario', (WidgetTester tester) async {
    await _setSize(tester, const Size(800, 3600));
    await tester.pumpWidget(_host());
    await _tap(tester, find.text('Compare with scenario B'));
    expect(find.text('548.9 µs'), findsNothing);
    expect(find.text('Check B: OK'), findsNothing);
    expect(find.text('Edit scenario'), findsNothing);
  });

  testWidgets('Legacy disables the inputs it ignores; More opens', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    expect(find.textContaining('Legacy is 20 MHz, one stream'), findsOneWidget);
    expect(find.text('Access category'), findsNothing);
    await _tap(tester, find.text('More settings'));
    expect(find.text('Access category'), findsOneWidget);
    expect(find.text('RTS/CTS protection'), findsOneWidget);
    await _tap(tester, find.text('RTS/CTS protection'));
    // RTS 28 + SIFS 16 + CTS 28 + SIFS 16 = 88 us added to A.
    expect(find.text('2330.5 µs'), findsWidgets);
  });

  for (final (String name, ThemeData Function() theme) variant
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double width in <double>[320, 390]) {
      testWidgets(
        '${variant.$1}: ${width.toInt()} px lays out with no overflow',
        (WidgetTester tester) async {
          await _setSize(tester, Size(width, 4400));
          await tester.pumpWidget(_host(theme: variant.$2()));
          await tester.pump();
          await _tap(tester, find.text('More settings'));
          expect(tester.takeException(), isNull);
          final Iterable<Scrollable> horizontal = tester
              .widgetList<Scrollable>(find.byType(Scrollable))
              .where(
                (Scrollable s) =>
                    s.axisDirection == AxisDirection.right ||
                    s.axisDirection == AxisDirection.left,
              );
          expect(horizontal, isEmpty);
        },
      );
    }
  }
}
