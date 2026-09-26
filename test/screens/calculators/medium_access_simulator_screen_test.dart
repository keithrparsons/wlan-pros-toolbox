// Widget tests for the Medium Access Simulator screen (Wi-Fi Classroom).
//
// The engine has its own tests (test/services/wifi_lab/); these check the
// screen drives it: paused by default, Step moves exactly one slot, Play runs
// the clock, configuration changes rebuild the run, and the layout holds at
// phone width in both themes without the page scrolling sideways.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/medium_access_simulator_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _host({ThemeData? theme, bool reducedMotion = false}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: Builder(
    builder: (BuildContext context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
      child: const MediumAccessSimulatorScreen(),
    ),
  ),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders paused at time zero with an empty-state prompt', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 2400));
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('Medium Access Simulator'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.text('t = 0.000 ms'), findsOneWidget);
    expect(find.text('Press Play or Step to start the clock.'), findsOneWidget);
    expect(find.text('Stations (3 of 10)'), findsOneWidget);
    // The legacy-OFDM statement the spec requires on screen.
    expect(find.textContaining('Timing is legacy OFDM'), findsOneWidget);
  });

  testWidgets('Step advances exactly one 9 us slot', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 2400));
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Step 1 slot'));
    await tester.pump();
    expect(find.text('t = 0.009 ms'), findsOneWidget);
    await tester.tap(find.text('Step 1 slot'));
    await tester.pump();
    expect(find.text('t = 0.018 ms'), findsOneWidget);
    expect(find.textContaining('Over 0.018 ms'), findsOneWidget);
  });

  testWidgets('Play runs the clock and Pause freezes it', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 2400));
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('t = 0.000 ms'), findsNothing);

    await tester.tap(find.text('Pause'));
    await tester.pump();
    final String frozen = tester
        .widget<Text>(find.textContaining('t = ').first)
        .data!;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<Text>(find.textContaining('t = ').first).data, frozen);
  });

  testWidgets('reduced motion: still paused on open, Step still works', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 2400));
    await tester.pumpWidget(_host(reducedMotion: true));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('t = 0.000 ms'), findsOneWidget);
    expect(find.textContaining('Reduced motion is on'), findsOneWidget);
    await tester.tap(find.text('Step 1 slot'));
    await tester.pump();
    expect(find.text('t = 0.009 ms'), findsOneWidget);
  });

  testWidgets('adding stations stops at 10; changing config resets the run', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Step 1 slot'));
    await tester.pump();
    expect(find.text('t = 0.009 ms'), findsOneWidget);

    for (int i = 3; i < 10; i++) {
      await tester.ensureVisible(find.text('Add station'));
      await tester.tap(find.text('Add station'));
      await tester.pump();
    }
    expect(find.text('Stations (10 of 10)'), findsOneWidget);
    expect(find.text('t = 0.000 ms'), findsOneWidget);
    final OutlinedButton add = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Add station'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(add.onPressed, isNull);
  });

  testWidgets('EDCA mode shows the access-category table', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host());
    expect(find.text('CWmin'), findsNothing);
    await tester.ensureVisible(find.text('EDCA'));
    await tester.tap(find.text('EDCA'));
    await tester.pump();
    expect(find.text('CWmin'), findsOneWidget);
    expect(find.text('79 µs'), findsOneWidget); // AC_BK AIFS
  });

  for (final (String name, ThemeData Function() theme) variant
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    testWidgets('${variant.$1}: phone width lays out with no overflow', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, const Size(320, 3200));
      await tester.pumpWidget(_host(theme: variant.$2()));
      for (int i = 0; i < 60; i++) {
        await tester.tap(find.text('Step 1 slot'));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      // The only horizontal scrollable is the timeline inside its card.
      final Iterable<Scrollable> horizontal = tester
          .widgetList<Scrollable>(find.byType(Scrollable))
          .where((Scrollable s) => s.axisDirection == AxisDirection.right);
      expect(horizontal, hasLength(1));
    });
  }
}
