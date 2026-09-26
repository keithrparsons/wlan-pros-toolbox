// Widget tests for the Wi-Fi Classroom Rate vs Range screen.
//
// The math is pinned in test/services/wifi_lab/rate_vs_range_math_test.dart;
// these tests cover the screen contract: registration, the default client
// readout, width and band switching, basic-rate labels (MCS-equivalent),
// dragging the client, the stage/controls split, the ring palette contrast,
// and the layout at 390 x 844 and 1280 wide in both themes without overflow
// or sideways scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_vs_range_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_vs_range_math.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

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

/// No horizontally scrolling Scrollable anywhere on screen.
void _expectNoSidewaysScroll(WidgetTester tester) {
  final Iterable<Scrollable> sideways = tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .where(
        (Scrollable s) =>
            s.axisDirection == AxisDirection.left ||
            s.axisDirection == AxisDirection.right,
      );
  expect(sideways, isEmpty, reason: 'nothing may scroll sideways');
}

/// Every laid-out Text sits inside the viewport width.
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
    expect(tl.dx, greaterThanOrEqualTo(-0.5));
  }
}

/// WCAG relative-luminance contrast ratio.
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('catalog registers rate-vs-range in Wi-Fi Classroom', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final ToolEntry e = rf.tools.firstWhere(
      (ToolEntry t) => t.id == kRateVsRangeToolId,
    );
    expect(kRateVsRangeToolId, 'rate-vs-range');
    expect(e.title, 'Rate vs Range');
    expect(e.subgroup, 'Wi-Fi Classroom');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/rate-vs-range');
  });

  test('every ring hue clears 3:1 on the stage in both themes', () {
    for (final AppColorScheme s in <AppColorScheme>[
      AppColorScheme.dark(),
      AppColorScheme.light(),
    ]) {
      final Set<Color> seen = <Color>{};
      for (int m = 0; m <= RateVsRangeMath.maxMcs; m++) {
        final Color c = RvrPalette.of(m, s);
        seen.add(c);
        expect(
          _contrast(c, s.surface2),
          greaterThanOrEqualTo(3),
          reason: 'MCS $m, light=${s.isLight}',
        );
      }
      expect(seen.length, RateVsRangeMath.maxMcs + 1);
    }
  });

  test('model defaults: 5 GHz ch 100, 20 MHz, client at 20 m reads MCS 4', () {
    final RateVsRangeModel m = RateVsRangeModel();
    addTearDown(m.dispose);
    expect(m.freqMHz, 5500);
    final RvrClientReading c = m.client;
    expect(c.receivedDbm, closeTo(-66.3, 0.05));
    expect(c.mcs, 4);
    expect(c.noiseFloorDbm, closeTo(-94.0, 0.05));
    expect(c.snrDb, closeTo(27.7, 0.05));
    expect(c.insideCell, isTrue);
    // Rate label comes from the MCS Index table: EHT MCS 4, 20 MHz, 2 SS.
    expect(c.rateMbps, closeTo(103.2, 0.05));
    expect(m.rings.first.radiusM, closeTo(66.8, 0.05));
    expect(m.viewRangeM, 80);
  });

  test('width and basic rate shrink rings without rescaling the view', () {
    final RateVsRangeModel m = RateVsRangeModel();
    addTearDown(m.dispose);
    final double view = m.viewRangeM;
    final List<double> at20 = m.rings.map((RvrRing r) => r.radiusM).toList();
    m.setWidth(80);
    expect(m.viewRangeM, view);
    for (int i = 0; i < at20.length; i++) {
      expect(m.rings[i].radiusM, lessThan(at20[i]));
    }
    final double edge6 = m.cellEdgeM;
    m.setBasicRate(RvrBasicRate.mbps24);
    expect(m.cellEdgeM, lessThan(edge6));
    expect(m.cellEdgeM, closeTo(36.2, 0.05));
    expect(m.viewRangeM, view);
    expect(m.beaconPercent / m.beaconPercentAt6, inInclusiveRange(0.25, 0.3));
  });

  test('band switch clamps the width to what the band allows', () {
    final RateVsRangeModel m = RateVsRangeModel();
    addTearDown(m.dispose);
    m.setBand(WifiBand.band6);
    m.setWidth(320);
    expect(m.widthMHz, 320);
    m.setBand(WifiBand.band24);
    expect(m.widthMHz, 40);
    m.setWidth(80); // not a 2.4 GHz width: ignored
    expect(m.widthMHz, 40);
  });

  test('basic-rate labels say MCS-equivalent for every rate but 6 Mbps', () {
    expect(basicRateLabel(RvrBasicRate.mbps6), '6 Mbps (-82 dBm)');
    for (final RvrBasicRate r in RvrBasicRate.values) {
      if (r == RvrBasicRate.mbps6) continue;
      expect(basicRateLabel(r), contains('MCS-equivalent'));
    }
    expect(
      basicRateLabel(RvrBasicRate.mbps24),
      '24 Mbps (MCS-equivalent: MCS 3, -74 dBm)',
    );
  });

  test('copy payload lists every ring and the client', () {
    final RateVsRangeModel m = RateVsRangeModel();
    addTearDown(m.dispose);
    final String t = m.copyText();
    expect(t, contains('0\t-82\t66.8\t'));
    expect(t, contains('13\t-46\t4.2\t'));
    expect(t, contains('MCS 4'));
    expect(t, contains('6 Mbps (same floor as MCS 0)'));
    m.setBasicRate(RvrBasicRate.mbps24);
    expect(m.copyText(), contains('24 Mbps (MCS-equivalent: MCS 3)'));
  });

  testWidgets('default screen shows the client readout and the floors note', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Rate vs Range'), findsOneWidget);
    expect(find.text('-66.3 dBm'), findsOneWidget);
    expect(find.text('MCS 4, 103 Mbps'), findsOneWidget);
    expect(find.textContaining('conformance floors'), findsWidgets);
    expect(find.textContaining('Beacons use 2.19% of airtime'), findsOneWidget);
  });

  testWidgets('choosing 80 MHz drops the client to a lower MCS', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    await tester.tap(find.text('80'));
    await tester.pumpAndSettle();
    expect(m.widthMHz, 80);
    // -66.3 dBm at 80 MHz clears MCS 3 (-68) but not MCS 4 (-64).
    expect(m.client.mcs, 3);
    expect(find.textContaining('MCS 3, 16-QAM 1/2'), findsOneWidget);
  });

  testWidgets('dragging on the stage moves the client', (
    WidgetTester tester,
  ) async {
    final RateVsRangeModel m = await _pump(tester, size: const Size(1280, 900));
    final Finder canvas = find.descendant(
      of: find.byType(RateVsRangeStage),
      matching: find.byType(CustomPaint),
    );
    final Rect r = tester.getRect(canvas.first);
    // Tap near the AP: a short distance and a high MCS.
    await tester.tapAt(r.center + const Offset(8, 0));
    await tester.pumpAndSettle();
    expect(m.clientDistanceM, lessThan(5));
    expect(m.client.mcs, greaterThanOrEqualTo(11));
    // Drag out toward the edge: past the MCS 0 ring.
    await tester.dragFrom(
      r.center + const Offset(8, 0),
      Offset(0, r.height / 2 - 12),
    );
    await tester.pumpAndSettle();
    expect(m.clientDistanceM, greaterThan(60));
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(RateVsRangeStage), findsOneWidget);
    expect(find.byType(RateVsRangeControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RateVsRangeStage),
        matching: find.byType(RateVsRangeControls),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(RateVsRangeControls),
        matching: find.byType(RateVsRangeStage),
      ),
      findsNothing,
    );
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(1280, 900),
    ]) {
      testWidgets('$name theme at ${size.width.toInt()} wide renders cleanly', (
        WidgetTester tester,
      ) async {
        final RateVsRangeModel m = await _pump(
          tester,
          theme: theme(),
          size: size,
        );
        // Widest content: 6 GHz, 320 MHz, 4 streams, a 54 Mbps basic rate.
        m.setBand(WifiBand.band6);
        m.setWidth(320);
        m.setStreams(4);
        m.setBasicRate(RvrBasicRate.mbps54);
        m.setSsids(16);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _expectNoSidewaysScroll(tester);
        _expectTextInsideWidth(tester, size.width);
      });
    }
  }
}
