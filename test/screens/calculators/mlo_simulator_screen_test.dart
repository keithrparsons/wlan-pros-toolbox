// Widget tests for the Wi-Fi Classroom "Multi-Link Operation" screen
// (mlo-simulator).
//
// The model is pinned in test/services/wifi_lab/mlo_model_test.dart; these
// cover the screen contract: catalog registration and route, the fresh
// state, the study label, the MLO-worse verdict, the driver fallback, one
// link, the last link staying on, overload, modes switched off, the stage
// and controls as separate widgets over one state, the copy text, and phone
// and desktop widths in both themes laying out with no overflow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mlo_simulator_state.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mlo_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  MloConfig? initial,
  MloPreset? preset,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, height)),
        child: MloSimulatorScreen(initial: initial, preset: preset),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

MloSimulatorState _state(WidgetTester tester) =>
    tester.widget<MloSimulatorStage>(find.byType(MloSimulatorStage)).state;

void main() {
  test('catalog registers mlo-simulator in Wi-Fi Classroom, with its route', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final ToolEntry e = rf.tools.firstWhere(
      (ToolEntry t) => t.id == kMloSimulatorToolId,
    );
    expect(e.title, 'Multi-Link Operation');
    expect(e.subgroup, 'Wi-Fi Classroom');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/mlo-simulator');
    expect(AppRouter.mloSimulator, '/tools/mlo-simulator');
  });

  testWidgets('fresh: equal links, MLO wins, study labeled', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Multi-Link Operation'), findsOneWidget);
    // Stage and controls are separate widgets over one state object.
    expect(find.byType(MloSimulatorStage), findsOneWidget);
    expect(find.byType(MloSimulatorControls), findsOneWidget);
    expect(
      tester
          .widget<MloSimulatorControls>(find.byType(MloSimulatorControls))
          .state,
      same(_state(tester)),
    );
    expect(_state(tester).preset, MloPreset.equal);
    expect(
      find.textContaining('Here MLO beats the best single link (6 GHz)'),
      findsOneWidget,
    );
    expect(find.text('Worse than the best single link'), findsNothing);
    expect(
      find.textContaining(
        'A model built on real traffic, not a field measurement.',
        findRichText: true,
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Lanes for STR, from 0 µs to 5.00 ms')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^STR\. Mean 583 µs')),
      findsOneWidget,
    );
  });

  testWidgets('slow-link lesson: STR is worse than the best single link', (
    WidgetTester tester,
  ) async {
    await _pump(tester, preset: MloPreset.slowLink);
    expect(
      find.textContaining('MLO is worse than the best single link (6 GHz)'),
      findsOneWidget,
    );
    expect(find.text('Worse than the best single link'), findsWidgets);
    expect(find.textContaining('STR 1.1x higher'), findsOneWidget);
  });

  testWidgets('EMLSR disabled by driver falls back to one link', (
    WidgetTester tester,
  ) async {
    await _pump(tester, preset: MloPreset.oneBusy);
    final MloSimulatorState s = _state(tester);
    s.laneMode = MloMode.emlsr;
    await tester.pumpAndSettle();
    final Finder sw = find.text('EMLSR disabled by driver');
    await tester.ensureVisible(sw);
    await tester.pumpAndSettle();
    await tester.tap(sw);
    await tester.pumpAndSettle();
    expect(s.config.emlsrDisabledByDriver, isTrue);
    expect(s.preset, isNull);
    expect(find.text('EMLSR (off: 6 GHz only)'), findsOneWidget);
    expect(
      find.textContaining('EMLSR disabled by driver: the client falls back'),
      findsOneWidget,
    );
    expect(s.run.result(MloMode.emlsr).singleLink, 1);
  });

  testWidgets('one link: every mode is the single link; it stays on', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final MloSimulatorState s = _state(tester);
    s.setBandEnabled(MloBand.ghz5, false);
    await tester.pumpAndSettle();
    expect(s.config.links.single.band, MloBand.ghz6);
    expect(
      find.textContaining('One link: every mode is the single link'),
      findsOneWidget,
    );
    expect(find.text('The last link stays on'), findsOneWidget);
    // The last link cannot be switched off.
    s.setBandEnabled(MloBand.ghz6, false);
    await tester.pumpAndSettle();
    expect(s.config.links.length, 1);
    final Switch last = tester.widget<Switch>(
      find.descendant(
        of: find
            .ancestor(of: find.text('6 GHz link'), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      ),
    );
    expect(last.onChanged, isNull);
    // The driver switch needs two links.
    expect(find.text('Needs two or more links'), findsOneWidget);
    // Switching 2.4 GHz back on restores two links, in band order.
    s.setBandEnabled(MloBand.ghz24, true);
    await tester.pumpAndSettle();
    expect(s.config.links.map((MloLinkConfig l) => l.band).toList(), <MloBand>[
      MloBand.ghz24,
      MloBand.ghz6,
    ]);
  });

  testWidgets('overload is named, not averaged', (WidgetTester tester) async {
    await _pump(
      tester,
      initial: const MloConfig(
        links: <MloLinkConfig>[
          MloLinkConfig(
            band: MloBand.ghz5,
            busyFraction: 0.95,
            meanBusyUs: 200,
          ),
        ],
        arrivalsPerSecond: 200,
      ),
    );
    expect(find.text('Overloaded'), findsWidgets);
    expect(
      find.textContaining('Overloaded: frames arrive faster'),
      findsOneWidget,
    );
  });

  testWidgets('all MLO modes off: the verdict asks for one', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final MloSimulatorState s = _state(tester);
    for (final MloMode m in kMloComparableModes) {
      s.setModeShown(m, false);
    }
    await tester.pumpAndSettle();
    expect(s.laneMode, MloMode.single);
    expect(
      find.textContaining('Switch on a mode below to compare it'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('new random traffic keeps the lesson and changes the run', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final MloSimulatorState s = _state(tester);
    final double before = s.run.result(MloMode.str).meanUs;
    final Finder b = find.text('New random traffic');
    await tester.ensureVisible(b);
    await tester.pumpAndSettle();
    await tester.tap(b);
    await tester.pumpAndSettle();
    expect(s.config.seed, 2);
    expect(s.preset, MloPreset.equal);
    expect(s.run.result(MloMode.str).meanUs, isNot(before));
  });

  test('copy text names the model and the study label', () {
    final MloSimulatorState s = MloSimulatorState();
    final String t = s.copyText();
    expect(t, contains('Multi-Link Operation (WLAN Pros Toolbox'));
    expect(t, contains('Link 5 GHz: busy 50%'));
    expect(t, contains('STR: mean 583 µs'));
    expect(t, contains('not a field measurement'));
    s.dispose();
  });

  for (final bool light in <bool>[false, true]) {
    for (final double w in <double>[390, 1280]) {
      for (final MloPreset p in MloPreset.values) {
        testWidgets(
          'lays out at $w px, ${light ? 'light' : 'dark'}, ${p.name}',
          (WidgetTester tester) async {
            await _pump(
              tester,
              width: w,
              theme: light ? AppTheme.light() : AppTheme.dark(),
              preset: p,
            );
            final MloSimulatorState s = _state(tester);
            for (final MloMode m in <MloMode>[
              MloMode.single,
              ...kMloComparableModes,
            ]) {
              s.laneMode = m;
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
            }
            s.window = MloWindow.ms20;
            s.windowStartUs = s.windowStartMaxUs;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}
