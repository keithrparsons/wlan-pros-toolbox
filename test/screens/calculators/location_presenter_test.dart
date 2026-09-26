// Presenter-mode test for "Where Am I?" (spec 00 "Done means" and spec 33
// keys: Space re-sample, Tab switch method, R reset). Held at 1920x1080,
// 1440x900 and 1470x923 in both themes, fresh and in the fullest state (both
// methods side by side, 6 APs, blocked paths, the lesson revealed), and with
// each fold open.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/location_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/location_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/location_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<LocationController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final LocationController c = LocationController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: LocationScreen(controller: c),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return c;
}

void _expectFits(WidgetTester tester, Size window) {
  expect(tester.takeException(), isNull);
  expect(pageScrollables(tester), isEmpty);
  expect(controlsOverflow(tester), 0);
  expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
}

Future<void> _fullest(WidgetTester tester, LocationController c) async {
  c.apCount = 6;
  c.toggleBlocked(0);
  c.toggleBlocked(3);
  c.blockedBiasM = 10;
  c.sigmaDb = 10;
  c.nextReveal();
  c.nextReveal();
  c.device = (x: 28, y: 18);
  await tester.pump();
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
      final String size = '${window.width.toInt()}x${window.height.toInt()}';
      testWidgets('$name $size fullest state: fits with no overflow and no '
          'scroll', (WidgetTester tester) async {
        final LocationController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        await _fullest(tester, c);
        expect(c.view, LocView.both);
        expect(c.lesson, LocLessonStep.revealed);
        _expectFits(tester, window);
        // The numbers the lesson is about sit on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('One-sigma distance factor'),
          ),
          findsOneWidget,
        );
      });

      testWidgets('$name $size fresh: fits', (WidgetTester tester) async {
        await _present(tester, window: window, theme: theme());
        _expectFits(tester, window);
      });
    }
  }

  testWidgets('Space re-samples, Tab switches the method, R resets, Up and '
      'Down move sigma, M, B and P do their jobs', (WidgetTester tester) async {
    final LocationController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    final int seed = c.settings.seed;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.settings.seed, seed + 1);

    expect(c.view, LocView.both);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.view, LocView.signal);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.view, LocView.ftm);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(c.view, LocView.both);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.settings.sigmaDb, kLocDefaultSigmaDb + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.settings.sigmaDb, kLocDefaultSigmaDb - 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.pump();
    expect(c.isBlocked(0), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(c.lesson, LocLessonStep.predict);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.settings.seed, 1);
    expect(c.settings.sigmaDb, kLocDefaultSigmaDb);
    expect(c.isBlocked(0), isFalse);
    expect(c.lesson, LocLessonStep.off);
    expect(c.view, LocView.both);
    expect(tester.takeException(), isNull);
  });

  testWidgets('once a control has focus, Tab moves focus instead of '
      'switching the method', (WidgetTester tester) async {
    final LocationController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    // Shift+Tab from the idle presenter moves into the controls.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(c.view, LocView.both);
    final FocusNode? first = FocusManager.instance.primaryFocus;
    expect(first, isNotNull);
    expect(first!.children, isEmpty, reason: 'a control, not the key node');
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(c.view, LocView.both);
    expect(FocusManager.instance.primaryFocus, isNot(same(first)));
  });

  testWidgets('state set before presenting is still set inside and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1440, 900));
    installFakeWindow();
    final LocationController c = LocationController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: LocationScreen(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    c.view = LocView.ftm;
    c.sigmaDb = 3;
    c.device = (x: 20, y: 12);
    await tester.pump();
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(c.view, LocView.ftm);
    expect(c.settings.sigmaDb, 3);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(c.view, LocView.ftm);
    expect(c.device, (x: 20.0, y: 12.0));
  });

  for (final String fold in <String>[
    'Distances per AP',
    'Worked example and the speed of light',
    'The floor: APs and device position',
  ]) {
    testWidgets('the "$fold" fold opens without an exception', (
      WidgetTester tester,
    ) async {
      await _present(tester, window: const Size(1440, 900));
      await tester.tap(find.text(fold));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(pageScrollables(tester), isEmpty);
    });
  }

  testWidgets('the phone prose stays off the presenter', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('What this models, and what it leaves out'), findsNothing);
    expect(find.textContaining('Drag the device on the floor.'), findsNothing);
  });
}
