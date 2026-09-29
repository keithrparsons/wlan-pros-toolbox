// Widget tests for the Rate set card in Rate vs Range (spec 44).
//
// The model is pinned in test/services/wifi_lab/rate_set_model_test.dart;
// these cover the screen: chips cycle, the minimum basic rate is derived, the
// verdict names status 18, DSSS chips are disabled outside 2.4 GHz, the
// every-rate-off state, the ACK table, keyboard use, the 390 px layout, and
// the presenter keys and layout.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_rate_set.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_set_model.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/presenter.dart';

import '../../widgets/presenter/presenter_test_support.dart';

Future<RateVsRangeModel> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: const RateVsRangeScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<RateVsRangeStage>(find.byType(RateVsRangeStage)).model;
}

Finder _chip(RsRate r) =>
    find.byWidgetPredicate((Widget w) => w is RvrRateChip && w.rate == r);

void _expectTextInsideWidth(WidgetTester tester, double width) {
  for (final Element e in find.byType(Text).evaluate()) {
    final RenderObject? ro = e.renderObject;
    if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
    final Offset tl = ro.localToGlobal(Offset.zero);
    expect(
      tl.dx + ro.size.width,
      lessThanOrEqualTo(width + 0.5),
      reason: 'text "${(e.widget as Text).data}" runs past $width px',
    );
  }
}

void main() {
  testWidgets('the Minimum basic rate select is gone; the rate is derived '
      'from the chips and the cell edge follows it', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(RvrRateChip), findsNWidgets(12));
    expect(find.text('Minimum basic rate (lowest basic)'), findsOneWidget);
    expect(m.minimumBasic, RsRate.r6);
    // 6 is basic: one tap turns it off, so 12 becomes the lowest basic rate.
    await tester.ensureVisible(_chip(RsRate.r6));
    await tester.tap(_chip(RsRate.r6));
    await tester.pumpAndSettle();
    expect(m.rateSet.stateOf(RsRate.r6), RsState.off);
    expect(m.minimumBasic, RsRate.r12);
    expect(m.basicRate, RvrBasicRate.mbps12);
    expect(m.cellEdgeDbm, -79);
    expect(find.textContaining('Beacons use'), findsWidgets);
    expect(find.textContaining('at 12 Mbps'), findsWidgets);
  });

  testWidgets('9 Mbps as the lowest basic rate: no cell edge, and the stage '
      'says why', (WidgetTester tester) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    m.cycleRate(RsRate.r9); // supported -> basic
    await tester.pumpAndSettle();
    expect(m.minimumBasic, RsRate.r6);
    m.cycleRate(RsRate.r6); // basic -> off
    await tester.pumpAndSettle();
    expect(m.minimumBasic, RsRate.r9);
    expect(m.basicRate, isNull);
    expect(m.cellEdgeM, isNull);
    expect(m.client.insideCell, isNull);
    expect(
      find.textContaining('9 Mbps has no sourced sensitivity'),
      findsWidgets,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the verdict names status 18 and says associate', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    m
      ..setBand(WifiBand.band24)
      ..setRsClient(RsClient.erpClass2);
    await tester.pumpAndSettle();
    expect(find.text('Refused: status 18'), findsWidgets);
    // The screen text may break after underscores; the label keeps the name.
    expect(
      find.bySemanticsLabel(RegExp('REFUSED_BASIC_RATES_MISMATCH')),
      findsWidgets,
    );
    expect(find.textContaining('it lacks 12 and 24 Mbps'), findsOneWidget);
    expect(find.textContaining('associate?'), findsOneWidget);
    for (final Element e in find.byType(Text).evaluate()) {
      final String? t = (e.widget as Text).data;
      if (t != null) expect(t.toLowerCase(), isNot(contains(' join')));
    }
  });

  testWidgets('802.11b device: it cannot decode OFDM beacons, and status 18 '
      'if it tried; a DSSS basic set lets it associate', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    m
      ..setBand(WifiBand.band24)
      ..setRsClient(RsClient.dot11b);
    await tester.pumpAndSettle();
    expect(find.textContaining('cannot decode the OFDM beacons'), findsOne);
    for (final RsRate r in <RsRate>[
      RsRate.r1,
      RsRate.r2,
      RsRate.r5_5,
      RsRate.r11,
    ]) {
      m.cycleRate(r); // supported -> basic
    }
    for (final RsRate r in <RsRate>[RsRate.r6, RsRate.r12, RsRate.r24]) {
      m.cycleRate(r); // basic -> off
    }
    await tester.pumpAndSettle();
    expect(m.association.associates, isTrue);
    expect(m.beacon!.rate, RsRate.r1);
    expect(find.text('Associates'), findsWidgets);
    // DSSS beacons take more airtime than the 6 Mbps comparison.
    expect(m.beaconPercent, greaterThan(m.beaconPercentAt6));
    expect(find.textContaining('times the same beacons at 6 Mbps'), findsOne);
  });

  // Keith, 2026-09-29: with the 802.11b client inside the cell the ring
  // card said "it can decode 6 Mbps beacons" while the verdict said it
  // cannot decode OFDM beacons. The ring card speaks to signal strength and
  // never contradicts the verdict.
  testWidgets('802.11b inside the cell: the ring card says strong enough, '
      'not can decode, and agrees with the verdict', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    m
      ..setBand(WifiBand.band24)
      ..setRsClient(RsClient.dot11b)
      ..setClientDistance(3);
    await tester.pumpAndSettle();
    expect(m.client.insideCell, isTrue);
    expect(m.beacon!.rate, RsRate.r6);
    expect(m.association.decodesBeacons, isFalse);
    expect(find.textContaining('cannot decode the OFDM beacons'), findsOne);
    final String ring = m.cellSentence();
    expect(ring, isNot(contains('can decode')));
    expect(ring, contains('strong enough for 6 Mbps beacons'));
    expect(ring, contains('this device cannot decode them'));
    expect(find.text(ring), findsOne);
    expect(find.textContaining('it can decode'), findsNothing);
    // A client that does decode them: strong enough, no caveat.
    m.setRsClient(RsClient.wifi6);
    await tester.pumpAndSettle();
    expect(m.association.decodesBeacons, isTrue);
    expect(
      m.cellSentence(),
      'Inside the cell: strong enough for 6 Mbps '
      'beacons here.',
    );
    expect(find.textContaining('it can decode'), findsNothing);
  });

  testWidgets('DSSS chips are disabled at 5 GHz and a tap does nothing', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    expect(m.band, WifiBand.band5);
    final RvrRateChip one = tester.widget<RvrRateChip>(_chip(RsRate.r1));
    expect(one.enabled, isFalse);
    await tester.ensureVisible(_chip(RsRate.r1));
    await tester.tap(_chip(RsRate.r1));
    await tester.pumpAndSettle();
    expect(m.rateSet.stateOf(RsRate.r1), RsState.off);
    expect(
      find.bySemanticsLabel(RegExp('^1 Mbps, not in this band')),
      findsOneWidget,
    );
    m.setBand(WifiBand.band24);
    await tester.pumpAndSettle();
    expect(tester.widget<RvrRateChip>(_chip(RsRate.r1)).enabled, isTrue);
    expect(m.rateSet.stateOf(RsRate.r1), RsState.supported);
  });

  testWidgets('every rate off is an explicit state', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    for (final RsRate r in m.phy.rates) {
      while (m.rateSet.stateOf(r) != RsState.off) {
        m.cycleRate(r);
      }
    }
    await tester.pumpAndSettle();
    expect(m.rateSet.isEmpty, isTrue);
    expect(find.text('No rates on'), findsWidgets);
    expect(find.textContaining('No beacons: every rate is off'), findsWidgets);
    expect(
      find.textContaining('nothing is sent and nothing is acknowledged'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the ACK table: basic {6, 12, 24} answers 18 at 12; HE rows '
      'for a Wi-Fi 6 client', (WidgetTester tester) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    expect(
      find.bySemanticsLabel(
        RegExp(r'^ACK to a frame sent at 18 Mbps: 12 Mbps, a basic rate'),
      ),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^ACK to a frame sent at HE MCS 7 ')),
      findsOneWidget,
    );
    m.setRsClient(RsClient.dot11g);
    await tester.pumpAndSettle();
    // 802.11g is 2.4 GHz only; no HE rows either way.
    expect(
      find.bySemanticsLabel(RegExp(r'^ACK to a frame sent at HE MCS')),
      findsNothing,
    );
  });

  testWidgets('a chip takes keyboard focus and Enter cycles it', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    await tester.ensureVisible(_chip(RsRate.r9));
    final FocusNode node = Focus.of(
      tester.element(
        find
            .descendant(of: _chip(RsRate.r9), matching: find.byType(Text))
            .first,
      ),
    );
    node.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(m.rateSet.stateOf(RsRate.r9), RsState.basic);
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    testWidgets('$name 390 px: the fullest rate set lays out cleanly', (
      WidgetTester tester,
    ) async {
      final RateVsRangeModel m = await _pump(tester, theme: theme());
      m
        ..setBand(WifiBand.band24)
        ..setRequirePhy(RsRequiredPhy.he)
        ..setSsids(RateVsRangeModel.ssidMax);
      for (final RsRate r in RsRate.ofClass(RsModClass.dsss)) {
        m.cycleRate(r); // supported -> basic
      }
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectTextInsideWidth(tester, 390);
    });
  }

  group('presenter', () {
    Future<RateVsRangeModel> present(
      WidgetTester tester,
      Size window, {
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

    testWidgets('B raises the minimum basic rate and wraps; C changes the '
        'client', (WidgetTester tester) async {
      final RateVsRangeModel m = await present(tester, const Size(1920, 1080));
      expect(m.minimumBasic, RsRate.r6);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(m.minimumBasic, RsRate.r12);
      for (int i = 0; i < 5; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      }
      await tester.pump();
      expect(m.minimumBasic, RsRate.r54);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.pump();
      expect(m.minimumBasic, RsRate.r6);
      expect(m.rsClient, RsClient.wifi6);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pump();
      expect(m.rsClient, RsClient.dot11b);
      // The verdict is on the stage.
      expect(
        find.descendant(
          of: find.byKey(PresenterLayout.stageKey),
          matching: find.byType(RateSetVerdict),
        ),
        findsOneWidget,
      );
    });

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
            'the longest verdict fits; the folds open without error', (
          WidgetTester tester,
        ) async {
          final RateVsRangeModel m = await present(
            tester,
            window,
            theme: theme(),
          );
          m
            ..setBand(WifiBand.band24)
            ..setRsClient(RsClient.dot11b)
            ..setStreams(RateVsRangeModel.streamsMax)
            ..setSsids(RateVsRangeModel.ssidMax);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(pageScrollables(tester), isEmpty);
          expect(controlsOverflow(tester), 0);
          expectOnScreen(tester, find.byKey(PresenterLayout.stageKey), window);
          expect(find.textContaining('cannot decode the OFDM'), findsWidgets);
          // Open both folds: the panel may scroll then, but nothing breaks.
          await tester.tap(find.text('Rate set and client'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('ACK to a frame sent at X'));
          await tester.pumpAndSettle();
          expect(find.byType(RvrRateChip), findsNWidgets(12));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
