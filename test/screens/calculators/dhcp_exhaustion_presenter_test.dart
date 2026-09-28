// Presenter-mode test for Conference Wi-Fi Runs Out of Addresses (spec 00
// "Done means"): no overflow and no page scroll at 1920x1080, 1440x900 and
// 1470x923 in both themes, in its fullest state (rotation on, a /19 pool,
// the question asked and revealed, the pool-and-crowd disclosure open), and
// its keys: Space plays the morning, Right moves 10 minutes, R resets, Up
// and Down change the lease, M rotation, P the question.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/dhcp_exhaustion_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/dhcp_exhaustion_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<DhcpExhaustionController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final DhcpExhaustionController c = DhcpExhaustionController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: DhcpExhaustionScreen(controller: c),
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
        final DhcpExhaustionController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.rotation = true;
        c.minute = 140;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('The pool ran dry at 09:19'),
          ),
          findsOneWidget,
        );

        c.ask();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controlsOverflow(tester), 0);
        expect(find.text('Reveal'), findsOneWidget);
        c.guess = DxGuess.leaseOrPool;
        c.reveal();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);

        c.prefix = 19;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Space plays, Right moves 10 min, R resets, Up and Down change '
      'the lease, M and P', (WidgetTester tester) async {
    final DhcpExhaustionController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(kDxTick * 2);
    expect(c.minute, 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.minute, 20);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.leaseMinutes, 720);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.leaseMinutes, 4320);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(c.config.rotation, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(c.question, DxQuestion.asking);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(c.question, DxQuestion.revealed);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.minute, 0);
    expect(c.config, const DxConfig());
    expect(c.question, DxQuestion.idle);
    expect(tester.takeException(), isNull);
  });
}
