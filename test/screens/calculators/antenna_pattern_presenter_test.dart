// Presenter-mode test for the Antenna Pattern tool (spec 00 "Done means": no
// overflow, no page scroll at the projector sizes; the keys the tool declares
// work). Held at 1920x1080, 1440x900 and 1470x923 (a MacBook Air in full
// screen) in both themes, for every antenna, the imported one with a file
// read (the fullest panel).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_mesh.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/antenna_pattern_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<AntennaPatternLab> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
  AntennaModelKind kind = AntennaModelKind.omni,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: AntennaPatternScreen(initialKind: kind),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<AntennaPatternStage>(find.byType(AntennaPatternStage))
      .lab;
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
      for (final AntennaModelKind kind in AntennaModelKind.values) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '${kind.name}: fits with no overflow and no scroll', (
          WidgetTester tester,
        ) async {
          final AntennaPatternLab lab = await _present(
            tester,
            window: window,
            theme: theme(),
            kind: kind,
          );
          if (kind == AntennaModelKind.imported) {
            lab.loadExample(PatternExample.tiltedSector);
            await tester.pump();
            expect(lab.parsed, isNotNull);
          }
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        });
      }
    }
  }

  testWidgets('the peak gain is on the stage and the 3D takes the height', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    final Finder stage = find.byKey(PresenterLayout.stageKey);
    expect(
      find.descendant(of: stage, matching: find.text('8.0 dBi')),
      findsOneWidget,
    );
    // The 3D view is far taller than the desktop screen's 400 px.
    final Finder view = find.bySemanticsLabel(RegExp(r'3D antenna pattern'));
    expect(tester.getSize(view).height, greaterThan(600));
    // The phone explainer is folded.
    expect(find.textContaining('Gain is not power.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Space spins the view and stops it, Right turns it one step, '
      'R resets it', (WidgetTester tester) async {
    final AntennaPatternLab lab = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    final double yaw0 = lab.view.value.yawDeg;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(lab.spinning, isTrue);
    expect(find.text('Stop'), findsOneWidget);
    // Pump fixed frames: the spin never settles.
    for (int i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final double turned = (yaw0 - lab.view.value.yawDeg) % 360;
    expect(turned, closeTo(AntennaPatternLab.spinDegPerSecond * 0.464, 3));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(lab.spinning, isFalse);

    final double yaw1 = lab.view.value.yawDeg;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(
      (yaw1 - lab.view.value.yawDeg) % 360,
      closeTo(AntennaPatternLab.stepDeg, 1e-9),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(lab.spinning, isFalse);
    expect(lab.view.value, OrbitView.initial);
  });

  testWidgets('Up and Down move the main setting, and the "?" list names it '
      'for the antenna shown', (WidgetTester tester) async {
    final AntennaPatternLab lab = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(lab.omniGainDbi, 8);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(lab.omniGainDbi, 9);
    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.text('Gain up'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    lab.setKind(AntennaModelKind.collinear);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketRight);
    await tester.pump();
    expect(lab.elements, 5);
    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.text('Elements up'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    // The dipole has no parameter: no slider keys, none listed.
    lab.setKind(AntennaModelKind.dipole);
    await tester.pump();
    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.textContaining(' up'), findsNothing);
    expect(find.text('Play or pause'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the view stops the spin', (WidgetTester tester) async {
    final AntennaPatternLab lab = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    lab.startSpin();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.drag(
      find.bySemanticsLabel(RegExp(r'3D antenna pattern')),
      const Offset(60, 0),
    );
    await tester.pump();
    expect(lab.spinning, isFalse);
  });
}
