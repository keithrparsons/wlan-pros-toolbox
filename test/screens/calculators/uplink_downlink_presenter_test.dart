// Presenter-mode test for Uplink vs Downlink (spec 00 "Done means": a
// presenter test with no overflow and no page scroll; spec 28: Up and Down
// move the client, R resets). Held at 1920x1080, 1440x900 and 1470x923 in
// both themes, in the fullest state. Nothing animates, so there is no play
// or step.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/uplink_downlink_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<UplinkDownlinkController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const UplinkDownlinkScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<UplinkDownlinkStage>(find.byType(UplinkDownlinkStage).last)
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
        final UplinkDownlinkController k = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        k
          ..setPreset(UdPreset.usGvp)
          ..setWidth(320)
          ..setApGain(0)
          ..setApTx(18)
          ..matchApToClient()
          ..setRevealed(true);
        for (final double d in <double>[1, 5000]) {
          k.setClientDistance(d);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'client at $d m');
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0, reason: 'client at $d m');
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        // Both directions' numbers and the prediction are on the stage.
        for (final String t in <String>[
          'Downlink, AP to client',
          'Uplink, client to AP',
          'Predict, then reveal',
        ]) {
          expect(
            find.descendant(
              of: find.byKey(PresenterLayout.stageKey),
              matching: find.text(t),
            ),
            findsOneWidget,
            reason: t,
          );
        }
      });
    }
  }

  testWidgets('Up moves the client out, Down brings it in; R resets', (
    WidgetTester tester,
  ) async {
    final UplinkDownlinkController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    k.setClientDistance(10);
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.pump();
    expect(k.config.clientDistanceM, closeTo(20, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(k.config.clientDistanceM, closeTo(14.142, 1e-3));

    k
      ..setApTx(27)
      ..setPreset(UdPreset.euLpi);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(k.config.apTxDbm, UdConfig.defaultApTxDbm);
    expect(k.config.preset, UdPreset.custom);

    // Space and Right do nothing here (nothing animates) and must not throw.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('P reveals the answer and M matches and puts the AP back', (
    WidgetTester tester,
  ) async {
    final UplinkDownlinkController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(k.revealed, isTrue);
    expect(find.textContaining('Not necessarily'), findsOneWidget);
    final double ul = k.config.uplink.rssiDbm;
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(k.config.isMatched, isTrue);
    expect(k.config.uplink.rssiDbm, closeTo(ul, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pumpAndSettle();
    expect(k.config.isMatched, isFalse);
  });

  testWidgets('the phone prose is gone and the fold opens', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('What the two rings say'), findsNothing);
    expect(find.textContaining('Defaults are illustrative'), findsNothing);
    expect(find.text('AP antenna gain'), findsNothing);
    // The illustrative label survives presenter mode.
    expect(find.text('Radios (illustrative values)'), findsOneWidget);
    await tester.tap(find.text('Antenna gains and path-loss exponent'));
    await tester.pumpAndSettle();
    expect(find.text('AP antenna gain'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('state set before presenting is still set inside and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const UplinkDownlinkScreen()),
    );
    await tester.pumpAndSettle();
    final UplinkDownlinkController k = tester
        .widget<UplinkDownlinkStage>(find.byType(UplinkDownlinkStage))
        .controller;
    k
      ..setApTx(26)
      ..setClientDistance(42);
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    final UplinkDownlinkController inside = tester
        .widget<UplinkDownlinkStage>(find.byType(UplinkDownlinkStage).last)
        .controller;
    expect(identical(inside, k), isTrue);
    expect(inside.config.apTxDbm, 26);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(k.config.clientDistanceM, closeTo(42, 1e-9));
  });
}
