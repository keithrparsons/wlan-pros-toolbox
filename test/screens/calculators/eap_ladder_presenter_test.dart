// Presenter-mode test for the 802.1X and EAP Ladder (spec 00 "Done means":
// no overflow, no page scroll, keyboard play and step). Held at 1920x1080,
// 1440x900 and 1470x923 in both themes, on every method, part way down the
// ladder. The ladder's own viewport is the one scroll the stage may have
// (long sequences); it must follow the latest message, and nothing else on
// the page may scroll.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/eap_ladder_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/eap_ladder.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<EapLadderController> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(theme: theme ?? AppTheme.dark(), home: const EapLadderScreen()),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<EapLadderStage>(find.byType(EapLadderStage).last)
      .controller;
}

/// The ladder's own scroll state on the presenter stage.
ScrollableState _ladder(WidgetTester tester) => tester.state<ScrollableState>(
  find.descendant(
    of: find.descendant(
      of: find.byKey(PresenterLayout.stageKey),
      matching: find.byKey(EapLadderStage.ladderScrollKey),
    ),
    matching: find.byType(Scrollable),
  ),
);

/// Page scrollables other than the ladder's own viewport.
List<ScrollableState> _pageScrollsBesidesLadder(WidgetTester tester) {
  final ScrollableState ladder = _ladder(tester);
  return pageScrollables(
    tester,
  ).where((ScrollableState s) => s != ladder).toList();
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
      for (final LadderMethod method in LadderMethod.values) {
        testWidgets('$name ${window.width.toInt()}x${window.height.toInt()} '
            '${method.name}: fits with no overflow and no page scroll', (
          WidgetTester tester,
        ) async {
          final EapLadderController c = await _present(
            tester,
            window: window,
            theme: theme(),
          );
          c.method = method;
          c.certFragments = kMaxCertFragments.toDouble();
          // The fullest caption: the TTLS inner method row shows, and a
          // message part way down has a long description.
          for (int i = 0; i < c.sequence.length * 2 ~/ 3; i++) {
            c.step();
          }
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull);
          expect(_pageScrollsBesidesLadder(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        });
      }
    }
  }

  testWidgets('the ladder follows the latest message inside its own view', (
    WidgetTester tester,
  ) async {
    final EapLadderController c = await _present(
      tester,
      window: const Size(1470, 923),
    );
    c.method = LadderMethod.eapTls;
    c.certFragments = kMaxCertFragments.toDouble();
    await tester.pump();
    expect(_ladder(tester).position.maxScrollExtent, greaterThan(0));
    expect(_ladder(tester).position.pixels, 0);
    for (int i = 0; i < c.sequence.length - 2; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    }
    // Build, then the follow's post-frame scroll starts, then it runs.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 400));
    expect(_ladder(tester).position.pixels, greaterThan(0));
    // Reset jumps back to the top.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(_ladder(tester).position.pixels, 0);
  });

  testWidgets('Space plays and pauses, Right steps, Left goes back, R '
      'resets, Up and Down change the certificate size', (
    WidgetTester tester,
  ) async {
    final EapLadderController c = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    c.method = LadderMethod.eapTls;
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(c.shown, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(c.shown, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isTrue);
    // The clock runs under the presenter route (the controller owns it).
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
    expect(c.shown, greaterThan(2));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(c.playing, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(c.shown, 0);

    final int frags = c.config.certFragments;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.certFragments, frags + 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(c.config.certFragments, frags);

    // PSK sends no certificate: the size keys do nothing.
    c.method = LadderMethod.psk;
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(c.config.certFragments, frags);
    expect(tester.takeException(), isNull);
  });
}
