// Presenter-mode test for Multicast at the Basic Rate (spec 00 "Done
// means"): no overflow and no page scroll at 1920x1080, 1440x900 and 1470x923
// in both themes, in its fullest state (both lanes, power save on, the
// question revealed), and its keys: Space plays, Right moves to the next
// beacon, R resets, Up and Down change the basic rate (spec 30).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multicast_basic_rate_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/multicast_basic_rate_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<MulticastBasicRateController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final MulticastBasicRateController c = MulticastBasicRateController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MulticastBasicRateScreen(controller: c),
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
        final MulticastBasicRateController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.ask();
        c.view = McView.compare;
        c.powerSave = true;
        c.reveal();
        await tester.pump(kMcSweepDuration);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        // The lesson's numbers are on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('73.8%'),
          ),
          findsWidgets,
        );

        // The question asked, before Reveal: four choices and the button.
        c.ask();
        c.view = McView.compare;
        c.powerSave = true;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expect(find.text('Reveal'), findsOneWidget);
      });
    }
  }

  testWidgets('Space plays, Right steps a beacon, R resets, Up and Down set '
      'the basic rate', (WidgetTester tester) async {
    final MulticastBasicRateController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.playhead.value, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.playhead.value, closeTo(0.1024, 1e-9));

    expect(c.config.basicRate, BasicRate.r6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.basicRate, BasicRate.r12);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // 6 Mb/s is the slowest 5 GHz basic rate: Down stops there.
    expect(c.config.basicRate, BasicRate.r6);
    c.band = McBand.ghz24;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.basicRate, BasicRate.r5_5);
    expect(tester.takeException(), isNull);
  });
}
