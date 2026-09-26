// Presenter-mode test for Adjacent Channels and AP Stacking (spec 00 "Done
// means": no overflow and no page scroll; spec 29: Up/Down neighbor distance,
// R reset). Held at 1920x1080, 1440x900 and 1470x923 in both themes, in the
// fullest state: 6 GHz, a 320 MHz neighbor, the link lost and energy detect
// busy, and again with every disclosure open is not required (they may
// scroll the panel), so the closed panel must fit.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/adjacent_channel_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/adjacent_channel_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<AdjacentChannelController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const AdjacentChannelScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<AdjacentChannelStage>(find.byType(AdjacentChannelStage).last)
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
          'fullest state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final AdjacentChannelController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final void Function() setup in <void Function()>[
          () {},
          () => c
            ..band = WifiBand.band6
            ..neighborWidthMHz = 320
            ..separation = AciSeparation.adjacent
            ..neighborDistanceM = 0.3,
          () => c.band = WifiBand.band24,
        ]) {
          setup();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        // The verdicts are on the stage, in headline type.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.byType(AciHeadline),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Up moves the neighbor away and Down brings it closer; four '
      'presses double the distance; R resets', (WidgetTester tester) async {
    final AdjacentChannelController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    c.neighborDistanceM = 2;
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.pump();
    expect(c.config.neighborDistanceM, closeTo(4, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.neighborDistanceM, closeTo(2.828, 1e-3));
    final double centerBefore = c.plan.receiverCenterMHz;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.config.neighborDistanceM, const AciConfig().neighborDistanceM);
    expect(c.plan.receiverCenterMHz, centerBefore);
    // Nothing animates: Space and Right do nothing and do not throw.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rejection fold opens, says illustrative, and state set '
      'before presenting is still set', (WidgetTester tester) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const AdjacentChannelScreen()),
    );
    await tester.pumpAndSettle();
    final AdjacentChannelController c = tester
        .widget<AdjacentChannelStage>(find.byType(AdjacentChannelStage))
        .controller;
    c.neighborPowerDbm = 7;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(c.config.neighborPowerDbm, 7);
    expect(find.text('7 dBm'), findsWidgets);
    await tester.tap(
      find.text('Adjacent-channel rejection (ACR), illustrative'),
    );
    await tester.pumpAndSettle();
    expect(find.text('MCS 0 to 2 (illustrative)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
