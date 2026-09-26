// Presenter-mode test for Why Two Devices Disagree (spec 00 "Done means",
// spec 31 keys: Space re-sample, R reset). Held at 1920x1080, 1440x900 and
// 1470x923 in both themes, in the fullest state: answer revealed, offsets
// applied, four devices.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/devices_disagree_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<DevicesDisagreeController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
  void Function(DevicesDisagreeController c)? before,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const DevicesDisagreeScreen(),
    ),
  );
  await tester.pumpAndSettle();
  final DevicesDisagreeController c = tester
      .widget<DevicesDisagreeStage>(find.byType(DevicesDisagreeStage).first)
      .controller;
  before?.call(c);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return c;
}

Future<void> _expectFits(WidgetTester tester, Size window, String why) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull, reason: why);
  expect(pageScrollables(tester), isEmpty, reason: why);
  expect(controlsOverflow(tester), 0, reason: why);
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
      Size(1470, 923),
    ]) {
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'fullest state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final DevicesDisagreeController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        await _expectFits(tester, window, 'default');
        c
          ..reveal()
          ..applyOffsets = true;
        await _expectFits(tester, window, 'revealed, offsets applied');
        c.selectDevice(3);
        c.deviceCount = 2;
        await _expectFits(tester, window, 'two devices');
        // The readouts are on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('True power'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('state set before presenting is still set inside and after', (
    WidgetTester tester,
  ) async {
    final DevicesDisagreeController c = await _present(
      tester,
      window: const Size(1920, 1080),
      before: (DevicesDisagreeController c) {
        c
          ..distanceM = 20
          ..applyOffsets = true
          ..resample();
      },
    );
    expect(c.config.distanceM, 20);
    expect(c.applyOffsets, isTrue);
    expect(c.sampleSet, 2);
    expect(find.text('Sample set 2'), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(c.config.distanceM, 20);
    expect(c.sampleSet, 2);
  });

  testWidgets('Space re-samples, R resets, Up and Down move the AP', (
    WidgetTester tester,
  ) async {
    final DevicesDisagreeController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(c.sampleSet, 1);
    final List<double> first = c.result.traces.first.reportedDbm;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.sampleSet, 2);
    expect(c.result.traces.first.reportedDbm, isNot(first));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(c.config.distanceM, 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.distanceM, 9);
    c.reveal();
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(c.sampleSet, 1);
    expect(c.config.distanceM, 8);
    expect(c.revealed, isFalse);
    expect(c.result.traces.first.reportedDbm, first);
    // Right arrow (step) is not bound: nothing changes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.sampleSet, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shortcut list names Space as Re-sample', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(find.text('Re-sample'), findsWidgets);
    expect(find.text('Play or pause'), findsNothing);
    expect(find.text('AP distance up'), findsOneWidget);
  });

  testWidgets('the phone prose is gone and the folds open', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('Why the numbers differ'), findsNothing);
    expect(find.text('Spacing between devices'), findsNothing);
    await tester.tap(find.text('The spot: band, distance, spacing, devices'));
    await tester.pumpAndSettle();
    expect(find.text('Spacing between devices'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
