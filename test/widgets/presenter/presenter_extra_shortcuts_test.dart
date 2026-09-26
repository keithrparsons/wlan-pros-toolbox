// PresenterActions.extra: tool-specific keys beyond the fixed set
// (PresenterExtraKey, added to the shell on wifi-lab/preview for DFS and used
// here by Fourier and FFT for its four modes). The DFS presenter test covers
// its one key; this holds the shell rules a mode switch relies on: several
// extras fire and are listed, the fixed keys always win, none by default.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import 'presenter_test_support.dart';

Future<void> _pump(WidgetTester tester, PresenterActions actions) async {
  setWindow(tester, const Size(1920, 1080));
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: PresenterLayout(
        title: 'Extras',
        stage: const SizedBox.expand(),
        controls: const Text('controls'),
        actions: actions,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('an extra key fires its callback and is listed under its words', (
    WidgetTester tester,
  ) async {
    int ones = 0;
    int twos = 0;
    await _pump(
      tester,
      PresenterActions(
        extra: <PresenterExtraKey>[
          PresenterExtraKey(
            key: LogicalKeyboardKey.digit1,
            keyLabel: '1',
            description: 'First mode',
            onPressed: () => ones++,
          ),
          PresenterExtraKey(
            key: LogicalKeyboardKey.digit2,
            keyLabel: '2',
            description: 'Second mode',
            onPressed: () => twos++,
          ),
        ],
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect((ones, twos), (1, 2));

    await tester.tap(find.text('Shortcuts'));
    await tester.pump();
    expect(find.text('First mode'), findsOneWidget);
    expect(find.text('Second mode'), findsOneWidget);
  });

  testWidgets('the fixed keys win over an extra bound to the same key', (
    WidgetTester tester,
  ) async {
    int plays = 0;
    int extras = 0;
    await _pump(
      tester,
      PresenterActions(
        playPause: () => plays++,
        extra: <PresenterExtraKey>[
          PresenterExtraKey(
            key: LogicalKeyboardKey.space,
            keyLabel: 'Space',
            description: 'Never reached',
            onPressed: () => extras++,
          ),
        ],
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect((plays, extras), (1, 0));
  });

  testWidgets('no extras: an unbound digit does nothing', (
    WidgetTester tester,
  ) async {
    await _pump(tester, PresenterActions.none);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    expect(tester.takeException(), isNull);
    expect(PresenterActions.none.extra, isEmpty);
  });
}
