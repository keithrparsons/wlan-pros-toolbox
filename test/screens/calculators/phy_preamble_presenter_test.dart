// Presenter-mode test for the PHY Preamble Reference (spec 00 "Done means":
// no overflow, no page scroll at the projector sizes; the keys the tool
// declares work). Held at 1920x1080, 1440x900 and 1470x923 (a MacBook Air in
// full screen) in both themes, in the fullest states: the longest bit tables
// open (HE SU HE-SIG-A, 22 fields; EHT MU U-SIG and EHT-SIG; HE MU HE-SIG-B)
// and the Which PHY? walk complete for EHT MU.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/phy_preamble_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/phy_preamble.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<PhyPreambleModel> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
  PpduType type = PpduType.heSu,
  PreambleMode mode = PreambleMode.explore,
  String? open,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: PhyPreambleScreen(
        initial: PreambleSettings(type: type),
        initialMode: mode,
        initialSelection: open,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester.widget<PhyPreambleStage>(find.byType(PhyPreambleStage)).model;
}

void _expectFits(WidgetTester tester, Size window) {
  expect(tester.takeException(), isNull);
  expect(pageScrollables(tester), isEmpty);
  expect(controlsOverflow(tester), 0);
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
      final String at = '${window.width.toInt()}x${window.height.toInt()}';
      for (final (PpduType t, String block) in const <(PpduType, String)>[
        (PpduType.heSu, 'HE-SIG-A'),
        (PpduType.ehtMu, 'U-SIG'),
        (PpduType.ehtMu, 'EHT-SIG'),
        (PpduType.heMu, 'HE-SIG-B'),
      ]) {
        testWidgets('$name $at ${t.name} $block open: fits with no overflow '
            'and no scroll', (WidgetTester tester) async {
          final PhyPreambleModel m = await _present(
            tester,
            window: window,
            theme: theme(),
            type: t,
            open: block,
          );
          expect(m.selectedBlock?.name, block);
          _expectFits(tester, window);
        });
      }
      testWidgets('$name $at Which PHY? walk complete: fits', (
        WidgetTester tester,
      ) async {
        final PhyPreambleModel m = await _present(
          tester,
          window: window,
          theme: theme(),
          type: PpduType.ehtMu,
          mode: PreambleMode.identify,
        );
        m.revealWalk();
        await tester.pump();
        expect(find.textContaining('Verdict:'), findsOneWidget);
        _expectFits(tester, window);
      });
    }
  }

  testWidgets('the preamble length is the stage headline; the block list is '
      'in the panel in Explore only', (WidgetTester tester) async {
    final PhyPreambleModel m = await _present(
      tester,
      window: const Size(1470, 923),
    );
    final Finder stage = find.byKey(PresenterLayout.stageKey);
    final Finder panel = find.byKey(PresenterLayout.controlsKey);
    expect(
      find.descendant(of: stage, matching: find.textContaining('43.2 µs')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: panel, matching: find.text('Blocks in order (µs)')),
      findsOneWidget,
    );
    m.mode = PreambleMode.identify;
    await tester.pump();
    expect(find.text('Blocks in order (µs)'), findsNothing);
    // The phone-only notes are folded.
    expect(
      find.textContaining('The IEEE 802.11 standard itself'),
      findsNothing,
    );
  });

  testWidgets('Right opens the next block, R closes it, Up and Down change '
      'the PPDU type; in Which PHY? Right asks and R starts over', (
    WidgetTester tester,
  ) async {
    final PhyPreambleModel m = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(m.selected, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.selectedBlock?.name, 'L-STF');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.selectedBlock?.name, 'L-SIG');
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(m.selected, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.type, PpduType.values[PpduType.values.indexOf(PpduType.heSu) + 1]);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(m.type, PpduType.heSu);

    m.mode = PreambleMode.identify;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.stepsShown, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(m.stepsShown, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in a mystery PPDU, Right skips the hidden blocks', (
    WidgetTester tester,
  ) async {
    final PhyPreambleModel m = await _present(
      tester,
      window: const Size(1920, 1080),
      mode: PreambleMode.identify,
    );
    m.newMystery();
    await tester.pump();
    expect(m.hidden, isTrue);
    for (int i = 0; i < 8; i++) {
      m.selectNext();
      expect(m.selectedBlock?.role, BlockRole.legacy);
    }
  });
}
