// Widget tests for the Wi-Fi Classroom FSPL Simulator screen.
//
// The math is pinned in test/services/wifi_lab/fspl_math_test.dart; these
// tests cover the screen contract: registration, the default readout, the
// empty state with every band off, the measured point (valid and invalid),
// cursor movement by drag and by slider, design targets read from Signal
// Thresholds, the stage/controls split, and the layout at 390 x 844 and
// 1280 wide in both themes without overflow or sideways scrolling.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/channel_frequency_data.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_chart.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_model.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_panels.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/fspl_simulator_stage.dart';
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
      home: const FsplSimulatorScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openSheet(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Show controls'));
  await tester.pumpAndSettle();
}

/// No horizontally scrolling Scrollable anywhere on screen.
void _expectNoSidewaysScroll(WidgetTester tester) {
  final Iterable<Scrollable> sideways = tester
      .widgetList<Scrollable>(find.byType(Scrollable))
      .where(
        (Scrollable s) =>
            // A single-line TextField scrolls its own text; that is the
            // field, not the page.
            s.restorationId != 'editable' &&
            (s.axisDirection == AxisDirection.left ||
                s.axisDirection == AxisDirection.right),
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

void main() {
  test('catalog registers fspl-simulator in Wi-Fi Classroom', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final int i = rf.tools.indexWhere(
      (ToolEntry t) => t.id == kFsplSimulatorToolId,
    );
    expect(i, isNonNegative);
    final ToolEntry e = rf.tools[i];
    expect(e.title, 'FSPL Simulator');
    expect(e.subgroup, 'RF and Propagation');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/fspl-simulator');
    // The two-input calculator is a separate, untouched entry.
    expect(
      kToolCategories.any(
        (ToolCategory c) => c.tools.any((ToolEntry t) => t.id == 'fspl'),
      ),
      isTrue,
    );
  });

  test('design targets are read from Signal Thresholds: -67 and -70 dBm', () {
    final List<FsplDesignTarget> t = fsplDesignTargets();
    expect(t.map((FsplDesignTarget x) => x.dbm), <double>[-67, -70]);
  });

  test('default channels are 2437, 5500 and 6135 MHz', () {
    final FsplSimModel m = FsplSimModel();
    addTearDown(m.dispose);
    expect(m.freq(WifiBand.band24), 2437);
    expect(m.freq(WifiBand.band5), 5500);
    expect(m.freq(WifiBand.band6), 6135);
    m.setChannel(WifiBand.band6, 117);
    expect(m.freq(WifiBand.band6), 6535);
  });

  test('switching to 100 m pulls a far cursor back onto the axis', () {
    final FsplSimModel m = FsplSimModel();
    addTearDown(m.dispose);
    m.setRange(FsplRange.km1);
    m.setCursor(600);
    m.setRange(FsplRange.m100);
    expect(m.cursorM, 100);
  });

  test('number parsing accepts comma decimals and the minus sign', () {
    expect(fsplParseNumber('-62,5'), -62.5);
    expect(fsplParseNumber('−70'), -70);
    expect(fsplParseNumber('abc'), isNull);
    expect(fsplParseNumber('  '), isNull);
  });

  testWidgets('default readout at 10 m matches the math', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('FSPL Simulator'), findsOneWidget);
    expect(find.text('At 10 m'), findsOneWidget);
    // 2437 MHz at 10 m = 60.18 dB; 20 dBm Tx, 0 dBi antennas = -40.2 dBm.
    expect(find.text('60.2 dB'), findsWidgets);
    expect(find.text('-40.2 dBm'), findsOneWidget);
    // 5500 MHz: 67.26 dB; 6135 MHz: 68.20 dB.
    expect(find.text('67.3 dB'), findsWidgets);
    expect(find.text('68.2 dB'), findsWidgets);
    // Band difference 2437 -> 5500 = 7.07 dB.
    expect(find.text('+7.1 dB'), findsOneWidget);
    // Why panel: identical spreading, aperture differs.
    expect(
      find.textContaining('31.0 spreading + 29.2 aperture'),
      findsOneWidget,
    );
    expect(
      find.textContaining('31.0 spreading + 36.3 aperture'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    '390 x 844: nothing clips or scrolls sideways, sheet shut and open',
    (WidgetTester tester) async {
      await _pump(tester);
      expect(tester.takeException(), isNull);
      _expectNoSidewaysScroll(tester);
      _expectTextInsideWidth(tester, 390);

      await _openSheet(tester);
      expect(find.byType(FsplControls), findsOneWidget);
      // Turn on the indoor model and add a measured point, the widest content.
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      final Finder fields = find.byType(TextField);
      await tester.ensureVisible(fields.first);
      await tester.enterText(fields.at(0), '-75');
      await tester.enterText(fields.at(1), '20');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      _expectNoSidewaysScroll(tester);
      _expectTextInsideWidth(tester, 390);
    },
  );

  testWidgets('every band off shows the empty state', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    for (final String b in <String>['2.4 GHz', '5 GHz', '6 GHz']) {
      await tester.tap(find.widgetWithText(FilterChip, b));
      await tester.pumpAndSettle();
    }
    expect(find.textContaining('No band is on.'), findsOneWidget);
    expect(
      find.textContaining('Turn on a band to split its loss'),
      findsOneWidget,
    );
    final Slider cursor = tester.widget<Slider>(find.byType(Slider).first);
    expect(cursor.onChanged, isNull, reason: 'cursor disabled when empty');
    expect(tester.takeException(), isNull);

    await tester.tap(find.widgetWithText(FilterChip, '5 GHz'));
    await tester.pumpAndSettle();
    expect(find.text('67.3 dB'), findsWidgets);
    expect(find.text('60.2 dB'), findsNothing);
  });

  testWidgets('measured point: gap to free space, and field errors', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    // Desktop: controls sit in the side panel, no sheet toggle.
    expect(find.byTooltip('Show controls'), findsNothing);
    final Finder fields = find.byType(TextField);
    await tester.ensureVisible(fields.first);
    // 5 GHz at 20 m: free space 73.28 dB -> -53.3 dBm; -70 is 16.7 dB below.
    await tester.enterText(fields.at(0), '-70');
    await tester.enterText(fields.at(1), '20');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Free space predicts -53.3 dBm'),
      findsOneWidget,
    );
    expect(find.textContaining('16.7 dB below free space'), findsOneWidget);
    expect(find.textContaining('exponent of n ='), findsOneWidget);

    await tester.enterText(fields.at(0), '12');
    await tester.enterText(fields.at(1), '0.5');
    await tester.pumpAndSettle();
    expect(find.text('Enter -120 to 0 dBm'), findsOneWidget);
    expect(find.text('Enter 1 to 1000 m'), findsOneWidget);
    expect(find.textContaining('Free space predicts'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dragging the chart and the cursor slider move the cursor', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final Finder chart = find.descendant(
      of: find.byType(FsplStage),
      matching: find.byWidgetPredicate(
        (Widget w) => w is CustomPaint && w.painter is FsplChartPainter,
      ),
    );
    final Rect r = tester.getRect(chart);
    // Tap near the right edge of the plot: close to 100 m.
    await tester.tapAt(
      Offset(r.right - FsplChartGeometry.padRight - 1, r.center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.text('At 10 m'), findsNothing);
    expect(find.textContaining(RegExp(r'^At (9\d|100) m$')), findsOneWidget);

    // Drag back to the left edge: 1 m.
    final TestGesture g = await tester.startGesture(
      Offset(r.center.dx, r.center.dy),
      kind: PointerDeviceKind.touch,
    );
    await g.moveBy(const Offset(-40, 0));
    await g.moveTo(Offset(r.left + FsplChartGeometry.padLeft, r.center.dy));
    await g.up();
    await tester.pumpAndSettle();
    expect(find.text('At 1.0 m'), findsOneWidget);

    // Keyboard / screen-reader path: the cursor slider.
    final Slider s = tester.widget<Slider>(find.byType(Slider).first);
    s.onChanged!(1); // log10(d) = 1 -> 10 m
    await tester.pumpAndSettle();
    expect(find.text('At 10 m'), findsOneWidget);
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(FsplStage), findsOneWidget);
    expect(find.byType(FsplControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(FsplStage),
        matching: find.byType(FsplControls),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(FsplControls),
        matching: find.byType(FsplStage),
      ),
      findsNothing,
    );
  });

  testWidgets('path loss view drops the design targets from the legend', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Design target'), findsOneWidget);
    await tester.tap(find.text('Path loss').first);
    await tester.pumpAndSettle();
    expect(find.text('Design target'), findsNothing);
    expect(
      find.text('Free-space path loss (dB) vs distance, log scale'),
      findsOneWidget,
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
        await _pump(tester, theme: theme(), size: size);
        expect(tester.takeException(), isNull);
        _expectNoSidewaysScroll(tester);
        _expectTextInsideWidth(tester, size.width);
        await tester.tap(find.text('1 km'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}
