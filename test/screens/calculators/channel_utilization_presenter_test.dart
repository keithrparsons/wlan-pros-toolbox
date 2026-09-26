// Presenter-mode test for the Channel Utilization Meter (spec 00 "Done
// means"): no overflow and no page scroll at 1920x1080, 1440x900 and
// 1470x923 in both themes, in its fullest state (neighbor and non-Wi-Fi on,
// many senders, the question asked and revealed), and its keys: Space runs,
// Right runs one beacon interval, R resets, Up and Down change the senders
// (spec 37), B adds a burst, W skips a window.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_utilization_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_utilization_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/channel_utilization_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<ChannelUtilizationController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final ChannelUtilizationController c = ChannelUtilizationController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: ChannelUtilizationScreen(controller: c),
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
        final ChannelUtilizationController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        // Asked: four choices and Reveal.
        c.ask();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expect(find.text('Reveal'), findsOneWidget);

        // Revealed, with everything on the channel.
        c.guess = CuGuess.about75;
        c.reveal();
        c.senders = 20;
        c.neighbor = true;
        c.nonWifi = true;
        c.idleStations = 40;
        c.skipWindow();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        // The two drawings keep a readable height: a wrapped headline once
        // squeezed them to a few pixels with nothing overflowing.
        for (final (Type painter, double floor) in <(Type, double)>[
          (CuStripPainter, 48),
          (CuWindowPainter, 80),
        ]) {
          final Finder paint = find.byWidgetPredicate(
            (Widget w) => w is CustomPaint && w.painter.runtimeType == painter,
          );
          expect(paint, findsOneWidget, reason: '$painter');
          expect(
            tester.getSize(paint).height,
            greaterThanOrEqualTo(floor),
            reason: '$painter height',
          );
        }
        // The meter is on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Channel utilization'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Space runs, Right steps an interval, R resets, Up and Down '
      'set the senders, B bursts, W skips a window', (
    WidgetTester tester,
  ) async {
    final ChannelUtilizationController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(const Duration(milliseconds: 300));
    expect(c.sim.nowTenths, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.sim.nowTenths, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.sim.completedIntervals, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.pump();
    expect(c.sim.completedIntervals, 1 + kCuDefaultWindow);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    c.stepInterval();
    expect(c.sim.intervals.last[CuSpan.nonWifi], kCuIntervalTenths);

    expect(c.config.senders, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.senders, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // One sender is the fewest: Down stops there.
    expect(c.config.senders, 1);
    expect(tester.takeException(), isNull);
  });
}
