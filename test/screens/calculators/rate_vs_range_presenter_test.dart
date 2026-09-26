// Presenter-mode test for Rate vs Range (spec 00 "Done means": a presenter
// test with no overflow and no page scroll). Held at 1920x1080, 1440x900 and
// 1470x923 in both themes, in the fullest state: 6 GHz with its five widths,
// four streams, the longest basic-rate label, and the client both inside and
// outside the cell. Nothing animates, so the keys are the client distance.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<RateVsRangeModel> _present(
  WidgetTester tester, {
  required Size window,
  ThemeData? theme,
}) async {
  setWindow(tester, window);
  installFakeWindow();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const RateVsRangeScreen(),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Present'));
  await tester.pumpAndSettle();
  expect(find.byType(PresenterLayout), findsOneWidget);
  return tester
      .widget<RateVsRangeStage>(find.byType(RateVsRangeStage).last)
      .model;
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
      testWidgets('$name ${window.width.toInt()}x${window.height.toInt()}: '
          'fullest state fits with no overflow and no scroll', (
        WidgetTester tester,
      ) async {
        final RateVsRangeModel m = await _present(
          tester,
          window: window,
          theme: theme(),
        );
        m
          ..setBand(WifiBand.band6)
          ..setStreams(RateVsRangeModel.streamsMax)
          ..setBasicRate(RvrBasicRate.mbps24)
          ..setSsids(RateVsRangeModel.ssidMax);
        for (final double d in <double>[3, 1000]) {
          m.setClientDistance(d);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'client at $d m');
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0, reason: 'client at $d m');
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
        }
        // What the client reads is on the stage, in headline type.
        expect(
          find.descendant(
            of: find.byKey(PresenterLayout.stageKey),
            matching: find.text('Below MCS 0'),
          ),
          findsOneWidget,
        );
      });
    }
  }

  testWidgets('Up moves the client out and Down brings it in; four presses '
      'double the distance', (WidgetTester tester) async {
    final RateVsRangeModel m = await _present(
      tester,
      window: const Size(1920, 1080),
    );
    m.setClientDistance(10);
    await tester.pump();
    for (int i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    }
    await tester.pump();
    expect(m.clientDistanceM, closeTo(20, 1e-9));
    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(m.clientDistanceM, closeTo(14.142, 1e-3));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the phone prose is gone and the fold opens', (
    WidgetTester tester,
  ) async {
    await _present(tester, window: const Size(1920, 1080));
    expect(find.text('What the rings say'), findsNothing);
    expect(find.textContaining('n = 2 is free space'), findsNothing);
    expect(find.text('Client antenna gain'), findsNothing);
    await tester.tap(find.text('Client antenna gain and margin'));
    await tester.pumpAndSettle();
    expect(find.text('Client antenna gain'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
