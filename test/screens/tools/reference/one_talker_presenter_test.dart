// Presenter-mode test for One Talker per Channel (spec 48, "Done means" 3):
// no overflow and no page scroll at projector sizes, in both themes, in the
// fullest state (12 + 6 devices on one channel, slow device on); the keys do
// what the shortcut list says; state set on the lesson is the state
// presented.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/one_talker_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../../widgets/presenter/presenter_test_support.dart';

Future<OneTalkerController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.dark(), home: const OneTalkerScreen()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<OneTalkerStage>(find.byType(OneTalkerStage).last)
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
          'every scene fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final OneTalkerController k = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final SecondAp ap in SecondAp.values) {
          for (final bool slow in <bool>[false, true]) {
            k
              ..setSecondAp(ap)
              ..shiftClientsA(20)
              ..shiftClientsB(20)
              ..setSlowTalker(slow)
              ..nextTurn();
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: '$ap $slow');
            expect(pageScrollables(tester), isEmpty);
            expect(controlsOverflow(tester), 0, reason: '$ap $slow');
            expectOnScreen(
              tester,
              find.byKey(PresenterLayout.stageKey),
              window,
            );
          }
        }
        expect(find.text('Next turn (Right)'), findsOneWidget);
        expect(
          find.text('Devices on access point 1 (Up, Down)'),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Up and Down add and remove devices, Space swaps the channel, '
      'Right passes the turn, A and S, R resets', (WidgetTester tester) async {
    final OneTalkerController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(k.config.clientsA, kDefaultClientsA);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.config.clientsA, kDefaultClientsA + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(k.config.clientsA, kDefaultClientsA - 1);

    expect(k.config.secondAp, SecondAp.none);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.config.secondAp, SecondAp.sameChannel);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.config.secondAp, SecondAp.otherChannel);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(k.config.secondAp, SecondAp.none);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(k.turn, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.pump();
    expect(k.config.slowTalker, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(k.isDefault, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shortcut list says what each key does here', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    expect(
      find.text('Second access point: same channel or other channel'),
      findsOneWidget,
    );
    expect(find.text('Pass the turn'), findsOneWidget);
    expect(find.text('Devices on access point 1 up'), findsOneWidget);
    expect(find.text('Add or remove the second access point'), findsOneWidget);
    expect(find.text('Make device A slow, or fast again'), findsOneWidget);
    expect(find.text('Play or pause'), findsNothing);
  });

  testWidgets('state set on the lesson is what the room sees, and stays', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const OneTalkerScreen()),
    );
    await tester.pumpAndSettle();
    final OneTalkerController k = tester
        .widget<OneTalkerStage>(find.byType(OneTalkerStage))
        .controller;
    k
      ..shiftClientsA(3)
      ..setSecondAp(SecondAp.otherChannel);
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    final OneTalkerController inside = tester
        .widget<OneTalkerStage>(find.byType(OneTalkerStage).last)
        .controller;
    expect(identical(inside, k), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(k.config.clientsA, 7);
    expect(k.config.secondAp, SecondAp.otherChannel);
  });

  testWidgets('a phone-sized window offers no Present button', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const OneTalkerScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Present'), findsNothing);
  });
}
