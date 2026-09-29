// Presenter-mode test for the Multipath Simulator (spec 00 "Done means": a
// presenter test with no overflow and no page scroll). Held at 1920x1080,
// 1440x900 and 1470x923 in both themes, in every scene and band, with the
// most reflectors. Nothing animates, so the keys are the receiver position
// (a sixteenth of a wavelength per press).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multipath_simulator_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multipath_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multipath_simulator_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/multipath_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<MultipathController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
  MultipathMode mode = MultipathMode.oneWall,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MultipathSimulatorScreen(initialMode: mode),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<MultipathStage>(find.byType(MultipathStage).last)
      .controller;
}

void main() {
  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size window in const <Size>[
      Size(1920, 1080),
      Size(1440, 900),
      // A 13/15-inch MacBook Air in full screen, measured 2026-09-26.
      Size(1470, 923),
    ]) {
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'every scene fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final MultipathController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final MultipathMode mode in MultipathMode.values) {
          c.mode = mode;
          c.reflectorCount = 30;
          c.environment = ScatterEnvironment.outdoors;
          for (final MultipathBand band in MultipathBand.values) {
            c.band = band;
            await tester.pumpAndSettle();
            final String why = '${mode.name} ${band.name}';
            expect(tester.takeException(), isNull, reason: why);
            expect(pageScrollables(tester), isEmpty, reason: why);
            expect(controlsOverflow(tester), 0, reason: why);
            expectOnScreen(
              tester,
              find.byKey(PresenterLayout.stageKey),
              window,
            );
          }
        }
        // The fullest Many paths state: four antennas, each combining.
        c
          ..mode = MultipathMode.manyPaths
          ..antennaCount = 4;
        for (final CombineMethod m in CombineMethod.values) {
          c.combine = m;
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: m.name);
          expect(pageScrollables(tester), isEmpty, reason: m.name);
          expect(controlsOverflow(tester), 0, reason: m.name);
        }
        c
          ..combine = CombineMethod.aOnly
          ..antennaCount = 2;
        await tester.pumpAndSettle();
        // The fade figures are on the stage in Many paths.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Both at once'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Up and Down move the receiver a sixteenth of a wavelength', (
    WidgetTester tester,
  ) async {
    final MultipathController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    final double start = c.positionCm;
    final double step = c.band.wavelength * 100 / 16;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.positionCm, closeTo(start + step, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.positionCm, closeTo(start - step, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Combine sits on the stage, and C cycles it in Many paths', (
    WidgetTester tester,
  ) async {
    final MultipathController c = await _present(
      tester,
      window: const Size(1440, 900),
      mode: MultipathMode.manyPaths,
    );
    final Finder stage = find.byKey(PresenterLayout.stageKey);
    expect(
      find.descendant(of: stage, matching: find.text('MRC')),
      findsOneWidget,
    );
    // Not doubled in the controls panel.
    expect(find.text('MRC'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(c.combine, CombineMethod.selection);
    expect(
      find.descendant(of: stage, matching: find.text('Combined (Selection)')),
      findsOneWidget,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(c.combine, CombineMethod.mrc);
    expect(
      find.descendant(of: stage, matching: find.text('Gain at 1%')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stage, matching: find.text('11.7 dB')),
      findsOneWidget,
    );
    await tester.tap(find.descendant(of: stage, matching: find.text('A only')));
    await tester.pumpAndSettle();
    expect(c.combine, CombineMethod.aOnly);

    // Outside Many paths, C does nothing.
    c.mode = MultipathMode.oneWall;
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pumpAndSettle();
    expect(c.combine, CombineMethod.aOnly);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the explainer is gone and the delay fold opens', (
    WidgetTester tester,
  ) async {
    await _present(
      tester,
      window: const Size(1920, 1080),
      mode: MultipathMode.manyPaths,
    );
    expect(find.text('What you are seeing'), findsNothing);
    await tester.tap(find.text('How late each copy arrives'));
    await tester.pumpAndSettle();
    expect(find.text('How late each copy arrives (latest first)'), findsOne);
    expect(tester.takeException(), isNull);
  });
}
