// Presenter-mode test for MIMO and Beamforming (spec 00 "Done means": no
// overflow, no page scroll at the projector sizes; the keys the tool declares
// work). Held at 1920x1080, 1440x900 and 1470x923 (a MacBook Air in full
// screen) in both themes, in the fullest states: the 8-chain AP (the tallest
// streams diagram and the swap caveat), a 2-chain sniffer, and the uplink.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/mimo_beamforming_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/mimo_beamforming_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<MimoController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
  int apChains = 4,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MimoBeamformingScreen(initialApChains: apChains),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester.widget<MimoStage>(find.byType(MimoStage)).controller;
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
      for (final LinkDirection d in LinkDirection.values) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '8x2 ${d.name}: fits with no overflow and no scroll', (
          WidgetTester tester,
        ) async {
          final MimoController c = await _present(
            tester,
            window: window,
            theme: theme(),
            apChains: 8,
          );
          c.snifferChains = 2;
          c.direction = d;
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        });
      }
    }
  }

  testWidgets('the stream count and the sniffer verdict are on the stage', (
    WidgetTester tester,
  ) async {
    final MimoController c = await _present(
      tester,
      window: const Size(1470, 923),
    );
    final Finder stage = find.byKey(PresenterLayout.stageKey);
    expect(
      find.descendant(of: stage, matching: find.text('2 spatial streams')),
      findsOneWidget,
    );
    // A 1-chain sniffer cannot separate 2 streams: the verdict in words.
    expect(
      find.descendant(of: stage, matching: find.text('No')),
      findsOneWidget,
    );
    // Beamforming off: no sounding, said in words.
    c.beamforming = false;
    await tester.pump();
    expect(
      find.descendant(
        of: stage,
        matching: find.textContaining('Sounding: none'),
      ),
      findsOneWidget,
    );
    // The phone explainer is not in the panel.
    expect(find.text('What you are seeing'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Up and Down steer the client 5 degrees; R resets', (
    WidgetTester tester,
  ) async {
    final MimoController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(c.clientDeg, 20);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.clientDeg, 25);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.clientDeg, 15);

    c.apChains = 2;
    c.snifferChains = 3;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.clientDeg, 20);
    expect(c.apChains, 4);
    expect(c.snifferChains, 1);

    // Held at the limit.
    for (int i = 0; i < 30; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    expect(c.clientDeg, kMaxAngleDeg);
  });
}
