// Presenter-mode test for "Why a Long Wi-Fi Password Matters More on WPA2"
// (spec 00 "Done means": no overflow, no page scroll, the keys work). Held
// at 1920x1080, 1440x900 and 1470x923 in both themes, in the fullest state.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wpa2_password_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wpa2_password_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/wpa2_password_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<Wpa2PasswordController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const Wpa2PasswordScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<Wpa2PasswordStage>(find.byType(Wpa2PasswordStage).last)
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
          'fullest state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final Wpa2PasswordController k = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        for (final WpSecurity s in WpSecurity.values) {
          k
            ..setSecurity(s)
            ..setLength(63)
            ..setCharset(WpCharset.mixed)
            ..setRevealed(true);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: s.label);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0, reason: s.label);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        for (final String t in <String>[
          'Guesses tried  ',
          'Failed attempts the AP logged  ',
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

  testWidgets('Right tries one guess, 1 2 3 pick the security, Up and Down '
      'change the length, Space keeps guessing, P reveals, R resets', (
    WidgetTester tester,
  ) async {
    final Wpa2PasswordController k = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(k.guesses, 1);
    expect(k.apFailedAttempts, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(k.config.security, WpSecurity.wpa3);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(k.apFailedAttempts, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pump();
    expect(k.config.security, WpSecurity.transition);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(k.config.security, WpSecurity.wpa2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(k.config.length, 10);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(k.config.length, 9);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.playing, isTrue);
    await tester.pump(kWpOfflineGuessDrawn * 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(k.playing, isFalse);
    expect(k.guesses, greaterThanOrEqualTo(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.pump();
    expect(k.revealed, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pumpAndSettle();
    expect(k.config, const WpConfig());
    expect(k.guesses, 0);
    expect(k.revealed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
