// Widget tests for the Multipath Simulator screen (Wi-Fi Lab).
//
// The model has its own tests (test/services/wifi_lab/multipath_model_test
// .dart); these check the screen drives it: each scene renders its pieces,
// the band switch changes the node spacing live, the wall material changes
// the result, dragging and sliders move the receiver, the stage and controls
// are separate widgets sharing one controller, and the layout holds at phone
// width in both themes without the page scrolling sideways.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multipath_simulator_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multipath_simulator_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multipath_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multipath_simulator_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Widget _host({ThemeData? theme, MultipathMode? mode}) => MaterialApp(
  theme: theme ?? AppTheme.dark(),
  home: MultipathSimulatorScreen(initialMode: mode),
);

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('opens on One wall with a computed result', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host());
    await tester.pump();

    expect(find.text('Multipath Simulator'), findsOneWidget);
    expect(find.text('Seen from above'), findsOneWidget);
    expect(find.text('The copies add as arrows'), findsOneWidget);
    expect(find.text('Power along the 1 m track'), findsOneWidget);
    expect(find.text('How late the reflected copy arrives'), findsOneWidget);
    expect(
      find.text('At the receiver, against the direct copy alone'),
      findsOneWidget,
    );
    expect(find.text('within GI'), findsOneWidget);
    // Stage and controls are separate widgets on one controller.
    expect(find.byType(MultipathStage), findsOneWidget);
    expect(find.byType(MultipathControls), findsNWidgets(2));
  });

  testWidgets('the band switch changes the node spacing live', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host(mode: MultipathMode.standingWave));
    await tester.pump();
    expect(find.text('Walking toward the wall'), findsOneWidget);
    // Measured spacing between the dips, next to the half wavelength.
    expect(find.text('every 6.25 cm'), findsOneWidget);
    expect(find.text('6.25 cm'), findsOneWidget);

    await tester.tap(find.text('5.5 GHz'));
    await tester.pump();
    expect(find.text('every 2.73 cm'), findsOneWidget);

    await tester.tap(find.text('6.5 GHz'));
    await tester.pump();
    expect(find.text('every 2.31 cm'), findsOneWidget);
  });

  testWidgets('switching the wall to drywall shrinks the swing', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(
      find.textContaining('the two copies can cancel completely'),
      findsOneWidget,
    );

    await tester.tap(find.text('Metal (|Γ| 1.00)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drywall (|Γ| 0.10)').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('swings by up to 1.7 dB'), findsOneWidget);
  });

  testWidgets('dragging the plot moves the receiver', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 3000));
    await tester.pumpWidget(_host());
    await tester.pump();
    expect(find.text('30.0 cm'), findsOneWidget);

    final Finder plot = find.bySemanticsLabel(
      RegExp('^Plot of received power'),
    );
    final Rect r = tester.getRect(plot);
    await tester.tapAt(Offset(r.left + 40, r.center.dy));
    await tester.pump();
    expect(find.text('30.0 cm'), findsNothing);
  });

  testWidgets('Many paths shows histogram, diversity and a delay list', (
    WidgetTester tester,
  ) async {
    await _setSize(tester, const Size(800, 4000));
    await tester.pumpWidget(_host());
    await tester.pump();
    await tester.tap(find.text('One wall (two-ray)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Many paths (Rayleigh fading)').last);
    await tester.pumpAndSettle();

    expect(find.text('How often each power level shows up'), findsOneWidget);
    expect(find.text('Two antennas: how often below -10 dB'), findsOneWidget);
    expect(find.text('Both at once'), findsOneWidget);
    expect(find.text('Show all 12 paths'), findsOneWidget);
    expect(find.text('0 of 12'), findsOneWidget);

    // Far reflectors put copies past the guard interval, with the verdict in
    // words as well as color.
    await tester.tap(find.text('300 m'));
    await tester.pump();
    expect(find.text('past GI'), findsWidgets);
    expect(find.text('0 of 12'), findsNothing);

    String phasorLabel() => tester
        .getSemantics(find.bySemanticsLabel(RegExp(r'^\d+ arrows')))
        .label;
    final String before = phasorLabel();
    await tester.ensureVisible(find.text('New layout'));
    await tester.tap(find.text('New layout'));
    await tester.pump();
    expect(find.text('Layout 2'), findsOneWidget);
    expect(phasorLabel(), isNot(before));
  });

  testWidgets('the copy payload carries the scene and the result', (
    WidgetTester tester,
  ) async {
    final MultipathController c = MultipathController();
    addTearDown(c.dispose);
    expect(c.copyText(), contains('Mode: One wall'));
    expect(c.copyText(), contains('vs the direct path alone'));
    c.mode = MultipathMode.manyPaths;
    expect(c.copyText(), contains('Rayleigh prediction for one antenna: 9.5%'));
  });

  for (final (String name, ThemeData Function() theme) t
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final MultipathMode mode in MultipathMode.values) {
      testWidgets('390 px, ${t.$1}, ${mode.label}: no overflow, no sideways '
          'scroll', (WidgetTester tester) async {
        await _setSize(tester, const Size(390, 900));
        await tester.pumpWidget(_host(theme: t.$2(), mode: mode));
        await tester.pump();
        expect(tester.takeException(), isNull);
        // The only scroll view on the page scrolls vertically.
        for (final Scrollable s in tester.widgetList<Scrollable>(
          find.byType(Scrollable),
        )) {
          expect(s.axisDirection, anyOf(AxisDirection.down, AxisDirection.up));
        }
        // Scroll to the end to lay out every card at phone width.
        await tester.drag(
          find.byType(SingleChildScrollView).first,
          const Offset(0, -6000),
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
