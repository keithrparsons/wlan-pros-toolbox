// Presenter-mode test for Airtime Anatomy (spec 00 "Done means"): no
// overflow and no page scroll at 1920x1080, 1440x900 and 1470x923 in both
// themes, in its fullest states (two scenarios with RTS/CTS and a selected
// segment; and a scenario the Check refuses, which adds a second verdict
// line), and the keys it has: Right walks the TXOP segment by segment, Up
// and Down change the edited scenario's rate.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/airtime_anatomy_screen.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/airtime_anatomy.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<AirtimeAnatomyModel> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  final AirtimeAnatomyModel m = AirtimeAnatomyModel();
  addTearDown(m.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: AirtimeAnatomyScreen(model: m),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return m;
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
      // A 13/15-inch MacBook Air in full screen, measured 2026-09-26.
      Size(1470, 923),
    ]) {
      final String size = '${window.width.toInt()}x${window.height.toInt()}';
      testWidgets('$name $size: two scenarios, RTS/CTS, a selection', (
        WidgetTester tester,
      ) async {
        final AirtimeAnatomyModel m = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        m.setEditing(1);
        m.edit((AirtimeScenario s) => s.copyWith(rtsCts: true));
        m.select(1, TxopSegmentKind.data);
        await tester.pumpAndSettle();
        _expectFits(tester, window);
        // The lesson's number is on the stage.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Throughput'),
          ),
          findsNWidgets(2),
        );
      });

      testWidgets('$name $size: a refused scenario and its verdicts', (
        WidgetTester tester,
      ) async {
        final AirtimeAnatomyModel m = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        m.setEditing(1);
        // VHT is not allowed at 6 GHz.
        m.edit(
          (AirtimeScenario s) =>
              s.copyWith(phy: AirtimePhy.vht, band: AirtimeBand.ghz6),
        );
        await tester.pumpAndSettle();
        expect(m.result(1).check.isOk, isFalse);
        _expectFits(tester, window);
      });
    }
  }

  testWidgets('Right walks the TXOP, Up and Down change the rate', (
    WidgetTester tester,
  ) async {
    final AirtimeAnatomyModel m = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    expect(m.selection, isNull);
    // Scenario A (Legacy 6 Mbps) is edited: AIFS first.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.selection, (scenario: 0, kind: TxopSegmentKind.aifs));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(m.selection, (scenario: 0, kind: TxopSegmentKind.backoff));
    // The formula panel follows the selection.
    expect(find.textContaining('A · Backoff'), findsOneWidget);

    // Legacy: the data rate steps through the legacy rates.
    expect(m.scenario(0).legacyRateMbps, 6);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(m.scenario(0).legacyRateMbps, 9);
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.pump();
    expect(m.scenario(0).legacyRateMbps, 6);

    // HE: the MCS.
    m.setEditing(1);
    final int mcs = m.scenario(1).mcs;
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(m.scenario(1).mcs, mcs - 1);
    expect(tester.takeException(), isNull);
  });
}
