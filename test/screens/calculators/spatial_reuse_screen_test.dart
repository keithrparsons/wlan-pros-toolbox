// Widget tests for the Wi-Fi Classroom Spatial Reuse screen.
//
// The math is pinned in test/services/wifi_lab/spatial_reuse_model_test.dart;
// these tests cover the screen contract: registration, the default decision,
// OBSS_PD and color changes reaching the readouts, the disabled state with
// coloring off, dragging a radio on the stage, the stage/controls split, the
// §8.15.2 hue contrast, and the layout at 390 x 844, 390 x 600 and 1280 wide
// in both themes without overflow or sideways scrolling.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_panels.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/spatial_reuse_state.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/spatial_reuse_model.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
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
      home: const SpatialReuseScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

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

SpatialReuseState _stateOf(WidgetTester tester) =>
    tester.widget<SpatialReuseStage>(find.byType(SpatialReuseStage)).state;

double _luminance(Color c) {
  double f(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _contrast(Color a, Color b) {
  final double x = _luminance(a), y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  test('catalog and router register spatial-reuse in Wi-Fi Classroom', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final ToolEntry e = rf.tools.firstWhere(
      (ToolEntry t) => t.id == kSpatialReuseToolId,
    );
    expect(e.title, 'Spatial Reuse');
    expect(e.subgroup, 'Wi-Fi Classroom');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/spatial-reuse');
    expect(AppRouter.spatialReuse, '/tools/spatial-reuse');
    expect(AppRouter.routes.containsKey('/tools/spatial-reuse'), isTrue);
  });

  test('state: OBSS_PD, color clash and coloring off', () {
    final SpatialReuseState s = SpatialReuseState();
    addTearDown(s.dispose);
    expect(s.analysis.together, isFalse);
    s.setObssPd(-72);
    expect(s.analysis.together, isTrue);
    expect(s.analysis.txPowerBDbm, 11);
    s.setColorB(s.scenario.colorA);
    expect(s.analysis.decision.rule, ReuseRule.intraBss);
    s.setColorB(40);
    s.setColoring(false);
    expect(s.analysis.decision.rule, ReuseRule.preambleDetect);
    s.move(ReuseNode.apB, 999);
    expect(s.position(ReuseNode.apB), kReuseLineM);
    s.reset();
    expect(s.scenario.obssPdDbm, -82);
    expect(s.copyText(), contains('SRG and parameterized spatial reuse'));
  });

  testWidgets('§8.15.2 BSS hues clear the contrast floor in both themes', (
    WidgetTester tester,
  ) async {
    for (final ThemeData theme in <ThemeData>[
      AppTheme.dark(),
      AppTheme.light(),
    ]) {
      late BssLook a, b;
      late Color surface;
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Builder(
            builder: (BuildContext context) {
              a = BssLook.of(context, const ReuseScenario(), bssA: true);
              b = BssLook.of(context, const ReuseScenario(), bssA: false);
              surface = context.colors.surface1;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(a.hue, isNot(b.hue));
      for (final BssLook l in <BssLook>[a, b]) {
        // The hue is drawn as a fill and as client letters on the card.
        expect(_contrast(l.hue, surface), greaterThanOrEqualTo(4.5));
        expect(_contrast(l.onHue, l.hue), greaterThanOrEqualTo(4.5));
      }
      expect(a.tag, 'BSS A, color 6');
      expect(b.tag, 'BSS B, color 26');
    }
  });

  testWidgets('default decision, then OBSS_PD -72 reaches the readouts', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.text('Spatial Reuse'), findsOneWidget);
    expect(find.text('AP B waits its turn'), findsOneWidget);
    expect(find.text('-77.7 dBm'), findsOneWidget);
    expect(find.text('2 frame-times'), findsOneWidget);
    _stateOf(tester).setObssPd(-72);
    await tester.pumpAndSettle();
    expect(find.text('AP B sends at the same time'), findsOneWidget);
    expect(find.text('11.0 dBm'), findsOneWidget);
    expect(find.text('1 frame-time'), findsOneWidget);
    expect(find.textContaining('caps its power at 11.0 dBm'), findsOneWidget);
    expect(find.textContaining('Out of scope: SRG'), findsOneWidget);
    expect(find.textContaining('Single source: TX_PWRref'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('MCS pickers and per-link verdicts', (WidgetTester tester) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.text('Link A MCS'), findsOneWidget);
    expect(find.text('Link B MCS'), findsOneWidget);
    // Default: both links hold MCS 7 in turn.
    expect(find.textContaining('Holds MCS 7: SINR 37.3 dB'), findsNWidgets(2));
    expect(find.textContaining('conformance floors'), findsOneWidget);
    final SpatialReuseState s = _stateOf(tester);
    s.setObssPd(-72);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Does not hold MCS 7: SINR 26.7 dB'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Best it supports: MCS 4 (16-QAM 3/4)'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Best it supports: not even MCS 0'),
      findsOneWidget,
    );
    s.setMcsA(4);
    await tester.pumpAndSettle();
    expect(find.textContaining('Holds MCS 4: SINR 26.7 dB'), findsOneWidget);
    expect(s.copyText(), contains('holds MCS 4'));
    s.setObssPd(-62);
    await tester.pumpAndSettle();
    expect(find.textContaining('SINR -1.0 dB, needs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('coloring off disables OBSS_PD and says why', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(_stateOf(tester).scenario.coloring, isFalse);
    final Iterable<Slider> sliders = tester.widgetList<Slider>(
      find.byType(Slider),
    );
    // The two color sliders and OBSS_PD are the first three.
    expect(sliders.take(3).every((Slider s) => s.onChanged == null), isTrue);
    expect(sliders.skip(3).every((Slider s) => s.onChanged != null), isTrue);
    expect(find.text('Turn BSS coloring on to use OBSS_PD.'), findsOneWidget);
    expect(
      find.textContaining('Wi-Fi preamble at or above -82 dBm'),
      findsOneWidget,
    );
  });

  testWidgets('drag AP B along the line', (WidgetTester tester) async {
    await _pump(tester, size: const Size(1280, 900));
    final SpatialReuseState s = _stateOf(tester);
    final Finder paint = find.descendant(
      of: find.byType(SpatialReuseStage),
      matching: find.byType(CustomPaint),
    );
    final Rect line = tester.getRect(paint.first);
    // AP B sits at 55 of 60 m on a line inset 36 px each side.
    final double x =
        line.left + 36 + (line.width - 72) * s.position(ReuseNode.apB) / 60;
    final Offset start = Offset(x, line.top + 52);
    await tester.dragFrom(start, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(s.position(ReuseNode.apB), lessThan(55));
    expect(s.analysis.heardByBDbm, greaterThan(-77.7));
  });

  testWidgets('stage and controls are separate widgets over one state', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    final SpatialReuseState stage = _stateOf(tester);
    expect(
      tester
          .widget<SpatialReuseControls>(find.byType(SpatialReuseControls))
          .state,
      same(stage),
    );
    expect(
      tester
          .widget<SpatialReuseReadouts>(find.byType(SpatialReuseReadouts))
          .state,
      same(stage),
    );
    expect(
      find.descendant(
        of: find.byType(SpatialReuseStage),
        matching: find.byType(SpatialReuseControls),
      ),
      findsNothing,
    );
  });

  for (final (String, ThemeData Function()) theme
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final Size size in <Size>[
      const Size(390, 844),
      const Size(390, 600),
      const Size(1280, 900),
    ]) {
      testWidgets('${theme.$1} ${size.width.round()} x ${size.height.round()}: '
          'no overflow, no sideways scroll', (WidgetTester tester) async {
        await _pump(tester, theme: theme.$2(), size: size);
        expect(tester.takeException(), isNull);
        _expectNoSidewaysScroll(tester);
        _expectTextInsideWidth(tester, size.width);
        // The concurrent case draws the most labels.
        _stateOf(tester).setObssPd(-62);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _expectTextInsideWidth(tester, size.width);
      });
    }
  }
}
