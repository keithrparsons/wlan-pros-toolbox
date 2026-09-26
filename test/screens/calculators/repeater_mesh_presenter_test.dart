// Presenter-mode test for Repeaters and Mesh Backhaul (spec 00 "Done
// means"): no overflow and no page scroll at 1920x1080, 1440x900 and
// 1470x923 in both themes, in its fullest state (three relays, the question
// asked, then revealed), and its keys (spec 36): Space plays, Up and Down
// change the number of relays, R resets.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/repeater_mesh_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/repeater_mesh_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<RepeaterMeshController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final RepeaterMeshController c = RepeaterMeshController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: RepeaterMeshScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return c;
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
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'fits with no overflow and no scroll', (WidgetTester tester) async {
        final RepeaterMeshController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.relayCount = 3;
        c.backhaul = RmBackhaul.dedicated;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);

        // The question asked: three choices and Reveal.
        c.ask();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expect(find.text('Reveal'), findsOneWidget);

        // Revealed: the answer, with the lesson's number on the stage.
        c.guess = RmGuess.sharedAir;
        c.reveal();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('77.2 Mb/s'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Space plays, Up and Down change the relays, R resets', (
    WidgetTester tester,
  ) async {
    final RepeaterMeshController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(const Duration(seconds: 1));
    expect(c.phase.value, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    expect(c.config.relayCount, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.relayCount, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    // Three is the most: Up stops there.
    expect(c.config.relayCount, kRmMaxRelays);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.relayCount, 2);

    c.backhaul = RmBackhaul.wired;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.config, RmConfig());
    expect(c.phase.value, 0);
    expect(tester.takeException(), isNull);
  });
}
