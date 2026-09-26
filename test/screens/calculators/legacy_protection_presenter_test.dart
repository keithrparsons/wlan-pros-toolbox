// Presenter-mode test for Legacy Protection Cost (spec 00 "Done means"): no
// overflow and no page scroll at 1920x1080, 1440x900 and 1470x923 in both
// themes, in its fullest state (associated and heard, the neighbor switches
// showing, RTS/CTS, CWmin 31, the question revealed), and its keys: Space
// plays, Right moves to the next send cycle, R resets, Up and Down change
// the protection frame's rate (spec 39).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/legacy_protection_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dsss_timing.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/legacy_protection_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<LegacyProtectionController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final LegacyProtectionController c = LegacyProtectionController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: LegacyProtectionScreen(controller: c),
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
        final LegacyProtectionController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.ask();
        c.guess = LpGuess.aboutHalf;
        c.reveal();
        c.heard = true;
        c.protectionKind = ProtectionKind.rtsCts;
        c.cwMin = LpCwMin.cw31;
        c.pickProtection(ProtectionRate.r11, DsssPreamble.short);
        await tester.pump(kLpSweepDuration);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);

        // The question asked, before Reveal: the choices and the button.
        c.ask();
        c.heard = true;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expect(find.text('Reveal'), findsOneWidget);

        // Default state: the lesson's numbers are on the stage.
        c.dismissQuestion();
        c.heard = false;
        await tester.pumpAndSettle();
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('14.8 Mb/s'),
          ),
          findsWidgets,
        );
        expect(tester.takeException(), isNull);
        expect(controlsOverflow(tester), 0);
      });
    }
  }

  testWidgets('Space plays, Right steps a cycle, R resets, Up and Down set '
      'the protection rate', (WidgetTester tester) async {
    final LegacyProtectionController c = await _present(
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
    expect(c.playhead.value, closeTo(812 / 3000, 1e-9));

    expect(c.config.protection.rate, ProtectionRate.r1);
    // 1 Mb/s long is the slowest: Down stays there.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.protection.rate, ProtectionRate.r1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.protection.rate, ProtectionRate.r2);
    expect(c.config.protection.preamble, DsssPreamble.long);
    for (int i = 0; i < 8; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.pump();
    // The fastest pair: 11 Mb/s short. Never 1 Mb/s short on the way.
    expect(c.config.protection.rate, ProtectionRate.r11);
    expect(c.config.protection.preamble, DsssPreamble.short);
    expect(tester.takeException(), isNull);
  });
}
