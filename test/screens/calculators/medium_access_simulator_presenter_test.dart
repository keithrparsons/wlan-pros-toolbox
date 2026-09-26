// Presenter-mode test for the Medium Access Simulator (spec 00 "Done means":
// a presenter test at 1920x1080 with no overflow, no page scroll, and
// keyboard play/step). Also held at 1440x900, both themes, with 3 and with
// 10 stations under EDCA with hidden node and RTS/CTS on.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/medium_access_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/medium_access_simulator_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/medium_access_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<MediumAccessSimulatorController> _open(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
  bool present = true,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const MediumAccessSimulatorScreen(),
    ),
  );
  await tester.pump();
  final MediumAccessSimulatorController c = tester
      .widget<MediumAccessSimulatorStage>(
        find.byType(MediumAccessSimulatorStage),
      )
      .controller;
  if (present) {
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsOneWidget);
  }
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
      // A 13/15-inch MacBook Air in full screen, measured 2026-09-26.
      Size(1470, 923),
    ]) {
      for (final bool crowded in <bool>[false, true]) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '${crowded ? '10 stations, EDCA, hidden, RTS' : '3 stations'}: '
            'fits with no overflow and no scroll', (WidgetTester tester) async {
          final MediumAccessSimulatorController c = await _open(
            tester,
            window: window,
            theme: theme(),
          );
          if (crowded) {
            for (int i = 3; i < 10; i++) {
              c.addStation();
            }
            c.setMode(AccessMode.edca);
            c.setHidden(true);
            c.setRts(true);
          }
          for (int i = 0; i < 200; i++) {
            c.step();
          }
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          // The one horizontal scroller is the timeline in the stage.
          final Iterable<Scrollable> horizontal = tester
              .widgetList<Scrollable>(
                find.descendant(
                  of: find.byKey(PresenterLayout.stageKey),
                  matching: find.byType(Scrollable),
                ),
              )
              .where((Scrollable s) => s.axisDirection == AxisDirection.right);
          expect(horizontal, hasLength(1));
        });
      }
    }
  }

  testWidgets('Right steps one slot, Space plays and pauses, R resets', (
    WidgetTester tester,
  ) async {
    final MediumAccessSimulatorController c = await _open(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.engine.nowUs, 9);
    expect(find.text('t = 0.009 ms'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    final int running = c.engine.nowUs;
    expect(running, greaterThan(9));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.engine.nowUs, 0);
  });

  testWidgets('Up and Down step the speed', (WidgetTester tester) async {
    final MediumAccessSimulatorController c = await _open(
      tester,
      window: const Size(1440, 900),
    );
    expect(c.speed, SimSpeed.crawl);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.speed, SimSpeed.normal);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.speed, SimSpeed.slow);
  });

  testWidgets(
    'a run started on the phone screen keeps running when presented',
    (WidgetTester tester) async {
      final MediumAccessSimulatorController c = await _open(
        tester,
        window: const Size(1440, 900),
        present: false,
      );
      await tester.tap(find.text('Play'));
      await tester.pump();
      await tester.tap(find.text('Present'));
      // The clock never settles while it runs: pump past the fade instead.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PresenterLayout), findsOneWidget);
      final int before = c.engine.nowUs;
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(c.engine.nowUs, greaterThan(before));
      expect(c.playing, isTrue);
      // Still running on the phone screen after Esc.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PresenterLayout), findsNothing);
      final int after = c.engine.nowUs;
      await tester.pump(const Duration(seconds: 1));
      expect(c.engine.nowUs, greaterThan(after));
      await tester.tap(find.text('Pause'));
      await tester.pump();
    },
  );

  testWidgets('zoom sits on the stage in presenter mode', (
    WidgetTester tester,
  ) async {
    final MediumAccessSimulatorController c = await _open(
      tester,
      window: const Size(1920, 1080),
    );
    expect(
      find.descendant(
        of: find.byKey(PresenterLayout.stageKey),
        matching: find.text('Frames'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Frames'));
    await tester.pump();
    expect(c.zoom.label, 'Frames');
  });
}
