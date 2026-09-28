// Presenter-mode test for Voice Priority, End to End (spec 00 "Done
// means"): no overflow and no page scroll at 1920x1080, 1440x900 and
// 1470x923 in both themes, in its fullest state (loss at the tunnel, 256
// frames ahead, the question asked and revealed), and its keys: Space sends
// the packet or pauses, Right moves it one hop, R resets, Up and Down move
// where the marking is lost, D the download, M the mapping, P the question.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/voice_priority_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/voice_priority_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<VoicePriorityController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final VoicePriorityController c = VoicePriorityController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: VoicePriorityScreen(controller: c),
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
        final VoicePriorityController c = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        c.loss = MarkLoss.tunnel;
        c.framesAhead = 256;
        c.hop = 3;
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
        expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        // The queue and the path are on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Best effort (AC_BE)'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Marking lost here'),
          ),
          findsOneWidget,
        );

        c.ask();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(controlsOverflow(tester), 0);
        expect(find.text('Reveal'), findsOneWidget);
        c.guess = VpGuess.bestEffort;
        c.reveal();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(pageScrollables(tester), isEmpty);
        expect(controlsOverflow(tester), 0);
      });
    }
  }

  testWidgets('Space sends, Right steps, R resets, Up and Down move the '
      'loss, D, M and P', (WidgetTester tester) async {
    final VoicePriorityController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    await tester.pump(kVpHopDuration * 2);
    expect(c.hop, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.hop, 3);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.loss, MarkLoss.apMapping);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    // The end of the list: Up stops there.
    expect(c.config.loss, MarkLoss.isp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(c.config.loss, MarkLoss.tunnel);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.pump();
    expect(c.config.downloadRunning, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.pump();
    expect(c.config.mapping, ApMapping.topThreeBits);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(c.question, VpQuestion.asking);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(c.question, VpQuestion.revealed);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.hop, 0);
    expect(c.config, const VpConfig());
    expect(c.question, VpQuestion.idle);
    expect(tester.takeException(), isNull);
  });
}
