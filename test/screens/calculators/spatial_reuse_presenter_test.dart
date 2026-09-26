// Presenter-mode test for Spatial Reuse (spec 00 "Done means": no overflow,
// no page scroll at the projector sizes; the keys the tool declares work).
// Held at 1920x1080, 1440x900 and 1470x923 (a MacBook Air in full screen) in
// both themes, in the fullest state: OBSS_PD raised so AP B sends together
// at reduced power and both links carry interference and a verdict.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_state.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<SpatialReuseState> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const SpatialReuseScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester.widget<SpatialReuseStage>(find.byType(SpatialReuseStage)).state;
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
      Size(1470, 923),
    ]) {
      for (final double obssPd in const <double>[-82, -70]) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            'OBSS_PD $obssPd: fits with no overflow and no scroll', (
          WidgetTester tester,
        ) async {
          final SpatialReuseState s = await _present(
            tester,
            window: window,
            theme: theme(),
          );
          s.setObssPd(obssPd);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        });
      }
    }
  }

  testWidgets('the decision and both links are on the stage, not the panel', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1470, 923));
    final Finder stage = find.byKey(PresenterLayout.stageKey);
    final Finder panel = find.byKey(PresenterLayout.controlsKey);
    expect(
      find.descendant(of: stage, matching: find.text('AP B waits its turn')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: stage, matching: find.text('2 frame-times')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: stage,
        matching: find.text('Link A: AP A to client A'),
      ),
      findsOneWidget,
    );
    // The phone readouts card is not repeated in the panel.
    expect(
      find.descendant(of: panel, matching: find.text('Decision')),
      findsNothing,
    );
    // The folded settings open inside the panel.
    await tester.tap(find.text('Positions (or drag a radio on the stage)'));
    await tester.pump();
    expect(find.text('Client B'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Up and Down move OBSS_PD, R resets, and with coloring off the '
      'keys leave OBSS_PD alone', (WidgetTester tester) async {
    final SpatialReuseState s = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(s.scenario.obssPdDbm, -82);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(s.scenario.obssPdDbm, -80);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(s.scenario.obssPdDbm, -81);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(s.scenario.obssPdDbm, -82);

    s.setColoring(false);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(s.scenario.obssPdDbm, -82);

    // No clock: Space and Right do nothing and are off the "?" list.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.text('Play or pause'), findsNothing);
    expect(find.text('OBSS_PD up'), findsOneWidget);
  });
}
