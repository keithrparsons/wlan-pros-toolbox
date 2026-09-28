// Presenter-mode test for What an Interferer Costs (spec 00 "Done means": no
// overflow and no page scroll; this tool: Up/Down the source level, N next
// source, C next channel, R reset). Held at 1920x1080, 1440x900 and 1470x923
// in both themes, in the fullest states: the oven with the mains toggle, 5
// GHz at 160 MHz with the width toggle, and the video sender.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/interferer_cost_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/interferer_cost_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<InterfererCostController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const InterfererCostScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<InterfererCostStage>(find.byType(InterfererCostStage).last)
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
      Size(1470, 923),
    ]) {
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'fullest states fit with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final InterfererCostController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final void Function() setup in <void Function()>[
          () {},
          () => c.source = IcSource.microwave,
          () => c
            ..channel = IcChannel.ch36
            ..widthMHz = 160,
          () => c
            ..channel = IcChannel.ch11
            ..source = IcSource.videoSender
            ..level = -30,
          c.reveal,
        ]) {
          setup();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.byType(IcHeadline),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Up and Down move the level 1 dB; N and C step; R resets; '
      'Space and Right do nothing', (WidgetTester tester) async {
    final InterfererCostController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.pump();
    expect(c.config.wifiLevelDbm, -82);
    // At -82 it is still heard; one more press and it is not.
    expect(c.result.selected.heard, IcHeard.preamble);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.result.selected.heard, IcHeard.notHeard);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.wifiLevelDbm, -82);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pump();
    expect(c.config.source, IcSource.microwave);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.pump();
    expect(c.config.channel, IcChannel.ch36);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.config, const IcConfig());
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('state set before presenting is still set, and the settings '
      'fold opens', (WidgetTester tester) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const InterfererCostScreen()),
    );
    await tester.pumpAndSettle();
    final InterfererCostController c = tester
        .widget<InterfererCostStage>(find.byType(InterfererCostStage))
        .controller;
    c.source = IcSource.bluetooth;
    await tester.pumpAndSettle();
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(c.config.source, IcSource.bluetooth);
    await tester.tap(find.text('Neighbor airtime, path loss, reset'));
    await tester.pumpAndSettle();
    expect(find.text('Neighbor airtime (illustrative)'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
