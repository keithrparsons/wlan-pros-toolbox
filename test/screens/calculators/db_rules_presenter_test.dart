// Presenter-mode test for Decibels in Your Head, the Rules of 3 and 10
// (spec 00 "Done means": no overflow and no page scroll at projector sizes;
// Up and Down move 1 dB, Right and Left 3 dB, Page Up and Page Down 10 dB,
// Space shows -67 against -70, P reveals, R resets). Held at 1920x1080,
// 1440x900 and 1470x923 in both themes, answer revealed.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/db_rules_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<DbRulesController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.dark(), home: const DbRulesScreen()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester.widget<DbRulesStage>(find.byType(DbRulesStage).last).controller;
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
          'the whole range fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final DbRulesController k = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        k.setRevealed(true);
        for (final int d in <int>[-80, -70, -69, -67, -60]) {
          k.setDbm(d);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$d');
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0, reason: '$d');
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        for (final String t in <String>[
          'What the step is worth',
          'Predict, then reveal',
        ]) {
          expect(
            find.descendant(
              of: find.byKey(PresenterLayout.stageKey),
              matching: find.text(t),
            ),
            findsOneWidget,
            reason: t,
          );
        }
      });
    }
  }

  testWidgets('the keys: Up and Down 1 dB, Right and Left 3, Page Up and '
      'Page Down 10, Space shows -67, P reveals, R resets', (
    WidgetTester tester,
  ) async {
    final DbRulesController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(k.dbm, -70);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.dbm, -69);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(k.dbm, -71);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(k.dbm, -68);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(k.dbm, -74);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(k.dbm, -64);
    await tester.sendKeyEvent(LogicalKeyboardKey.pageUp);
    await tester.pump();
    expect(k.dbm, -60, reason: 'clamped at the top');
    await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
    await tester.pump();
    expect(k.dbm, -70);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.dbm, -67);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pumpAndSettle();
    expect(k.revealed, isTrue);
    expect(find.text(DbRulesPredict.answer), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(k.dbm, -70);
    expect(k.revealed, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the shortcut list says what each key does here', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '?');
    await tester.pumpAndSettle();
    for (final String t in <String>[
      'Show -67 dBm against -70 dBm',
      'Add 3 dB',
      'Take away 3 dB',
      'Add 10 dB',
      'Take away 10 dB',
      'Show or hide the prediction answer',
      'Signal level up',
    ]) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('Play or pause'), findsNothing);
    expect(find.text('Step'), findsNothing);
  });

  testWidgets('the phone prose is gone and the key hints are on the labels', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.textContaining('The reference stays at'), findsNothing);
    expect(find.text('Signal level (Up, Down)'), findsOneWidget);
    expect(find.text('+3 dB (Right)'), findsOneWidget);
    expect(find.text('+10 dB (Page Up)'), findsOneWidget);
    expect(find.text('Reset (R)'), findsOneWidget);
  });

  testWidgets('state set before presenting is still set inside and after', (
    WidgetTester tester,
  ) async {
    setWindow(tester, const Size(1920, 1080));
    installFakeWindow();
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.dark(), home: const DbRulesScreen()),
    );
    await tester.pumpAndSettle();
    final DbRulesController k = tester
        .widget<DbRulesStage>(find.byType(DbRulesStage))
        .controller;
    k
      ..setDbm(-64)
      ..setRevealed(true);
    await tester.tap(find.text('Present'));
    await tester.pumpAndSettle();
    final DbRulesController inside = tester
        .widget<DbRulesStage>(find.byType(DbRulesStage).last)
        .controller;
    expect(identical(inside, k), isTrue);
    expect(inside.dbm, -64);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(PresenterLayout), findsNothing);
    expect(k.revealed, isTrue);
  });
}
