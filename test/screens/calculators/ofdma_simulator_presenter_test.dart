// Presenter-mode test for OFDMA Resource Units (spec 00 "Done means"): no
// overflow and no page scroll at 1920x1080, 1440x900 and 1470x923 in both
// themes, in its fullest states (eighteen clients at 80 MHz with one
// selected; and a set that does not fit, which adds the tray and the
// verdicts), and the keys it has: Right selects the next client, Up and Down
// change the client count.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_simulator_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/ofdma_simulator_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/ofdma_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<OfdmaSimulatorModel> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final OfdmaSimulatorModel m = OfdmaSimulatorModel();
  addTearDown(m.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: OfdmaSimulatorScreen(model: m),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return m;
}

void _expectFits(WidgetTester tester, Size window) {
  expect(tester.takeException(), isNull);
  expect(pageScrollables(tester), isEmpty);
  expect(controlsOverflow(tester), 0);
  expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
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
      final String size = '${window.width.toInt()}x${window.height.toInt()}';
      testWidgets('$name $size: eighteen clients at 80 MHz, one selected', (
        WidgetTester tester,
      ) async {
        final OfdmaSimulatorModel m = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        m.setWidth(80);
        m.setClientCount(kOfdmaMaxClients);
        m.equalRus();
        m.select(2);
        await tester.pumpAndSettle();
        expect(m.unplaced, isEmpty);
        _expectFits(tester, window);
        // The ratio, the lesson's number, is on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('SU / DL OFDMA'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('$name $size: a set that does not fit', (
        WidgetTester tester,
      ) async {
        final OfdmaSimulatorModel m = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        m.setWidth(80);
        m.setClientCount(kOfdmaMaxClients);
        m.setRuSize(RuSize.ru52);
        await tester.pumpAndSettle();
        expect(m.unplaced, isNotEmpty);
        _expectFits(tester, window);
      });
    }
  }

  testWidgets('Right selects the next client, Up and Down set the count', (
    WidgetTester tester,
  ) async {
    final OfdmaSimulatorModel m = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(m.selected, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.selected, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.selected, 1);

    final int n = m.clients;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.clients, n + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(m.clients, n - 1);
    expect(tester.takeException(), isNull);
  });
}
