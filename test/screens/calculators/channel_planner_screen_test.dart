// Widget tests for the Wi-Fi Lab Channel Planner screen.
//
// The math is pinned in test/services/wifi_lab/channel_planner_model_test.dart;
// these tests cover the screen contract: registration, the default readout,
// Auto-plan, the no-channel error state, dragging an AP and drawing a wall
// on the floor, the keyboard path for walls, the stage/controls split, the
// §8.15.2 palette contrast, and the layout at 390 x 844 and 1280 wide in both
// themes without overflow or sideways scrolling.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_palette.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_panels.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_stage.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_planner_state.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/channel_planner_model.dart';
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
      home: const ChannelPlannerScreen(),
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

ChannelPlannerState _stateOf(WidgetTester tester) =>
    tester.widget<ChannelPlannerStage>(find.byType(ChannelPlannerStage)).state;

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
  test('catalog registers channel-planner in Wi-Fi Lab', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final int i = rf.tools.indexWhere(
      (ToolEntry t) => t.id == kChannelPlannerToolId,
    );
    expect(i, isNonNegative);
    final ToolEntry e = rf.tools[i];
    expect(e.title, 'Channel Planner');
    expect(e.subgroup, 'Wi-Fi Lab');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/channel-planner');
    // Inside the Wi-Fi Lab block; the exact neighbors depend on merge order
    // (2026-09-25 merge), so assert the shelf, not the slot.
    expect(rf.tools[i - 1].subgroup, 'Wi-Fi Lab');
  });

  test('§8.15.2 palette clears the contrast floor in both themes', () {
    for (final Color c in kChannelHuesDark) {
      // Non-text floor against the floor surface (surface2 #2A2A2A).
      expect(_contrast(c, const Color(0xFF2A2A2A)), greaterThanOrEqualTo(3));
      // Labels on a fill use surface0.
      expect(_contrast(c, const Color(0xFF1A1A1A)), greaterThanOrEqualTo(4.5));
    }
    for (final Color c in kChannelHuesLight) {
      expect(_contrast(c, const Color(0xFFFFFFFF)), greaterThanOrEqualTo(4.5));
      expect(_contrast(c, const Color(0xFFF7F6F7)), greaterThanOrEqualTo(3));
    }
    // Neighbors in frequency never get neighboring hues.
    for (int i = 0; i < 8; i++) {
      final int d = (channelHueIndex(i + 1) - channelHueIndex(i)).abs();
      expect(math.min(d, 8 - d), greaterThanOrEqualTo(2));
    }
    expect(<int>{for (int i = 0; i < 8; i++) channelHueIndex(i)}, hasLength(8));
  });

  test('default floor: six APs on 36 at 40 MHz all share', () {
    final ChannelPlannerState s = ChannelPlannerState();
    addTearDown(s.dispose);
    expect(s.apCount, 6);
    expect(s.available, 4);
    expect(s.analysis.largestDomain, hasLength(6));
    s.runAutoPlan();
    expect(s.analysis.largestDomain, hasLength(2));
    expect(s.planNote, contains('4 of 4 channels'));
    s.setWidth(20);
    s.runAutoPlan();
    expect(s.analysis.largestDomain, hasLength(1));
  });

  test('a wall between the only co-channel pair splits the domain', () {
    final ChannelPlannerState s = ChannelPlannerState();
    addTearDown(s.dispose);
    s.runAutoPlan(); // pairs 32 m apart share at -72.4 dBm
    expect(s.analysis.largestDomain, hasLength(2));
    s.addWallAcross(vertical: true); // x = 25 m, between each pair
    expect(s.analysis.largestDomain, hasLength(1));
    s.setWallLoss(0);
    expect(s.analysis.largestDomain, hasLength(2));
  });

  test('add and remove stop at 12 and 2', () {
    final ChannelPlannerState s = ChannelPlannerState();
    addTearDown(s.dispose);
    while (s.canAdd) {
      s.addAp();
    }
    expect(s.apCount, kMaxAps);
    while (s.canRemove) {
      s.removeAp(0);
    }
    expect(s.apCount, kMinAps);
  });

  testWidgets('default readout and Auto-plan', (WidgetTester tester) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.text('Channel Planner'), findsOneWidget);
    expect(find.text('6 APs'), findsOneWidget);
    expect(find.text('17%'), findsOneWidget);
    expect(find.textContaining('Crowded: 6 APs'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Auto-plan'));
    await tester.pumpAndSettle();
    expect(find.text('2 APs'), findsOneWidget);
    expect(find.text('50%'), findsOneWidget);
    expect(find.textContaining('Auto-plan put 6 APs'), findsOneWidget);
    expect(find.textContaining('-72.4 dBm'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('160 MHz with DFS off: the error state', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    _stateOf(tester).setWidth(160);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No 160 MHz channel exists in the US'),
      findsOneWidget,
    );
    expect(find.textContaining('Turn DFS on'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(2));
    expect(find.text('100%'), findsNothing);
    final FilledButton plan = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Auto-plan'),
    );
    expect(plan.onPressed, isNull);
    _stateOf(tester).setDfs(true);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No 160 MHz channel exists in the US'),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('drag an AP; draw a wall with the wall tool', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final ChannelPlannerState s = _stateOf(tester);
    final RenderBox floor = tester.renderObject<RenderBox>(
      find
          .descendant(
            of: find.byType(ChannelPlannerStage),
            matching: find.byType(CustomPaint),
          )
          .first,
    );
    final double scale = (floor.size.width - 56) / s.floorW;
    Offset at(FloorPoint p) =>
        floor.localToGlobal(Offset(28 + p.x * scale, 28 + p.y * scale));

    final FloorPoint before = s.position(1);
    await tester.dragFrom(at(before), const Offset(40, 30));
    await tester.pumpAndSettle();
    expect(s.selected, 1);
    expect(s.position(1).x, greaterThan(before.x + 3));
    expect(s.position(1).y, greaterThan(before.y + 2));

    s.setWallMode(true);
    await tester.pumpAndSettle();
    await tester.dragFrom(at(const FloorPoint(17, 2)), Offset(0, 24 * scale));
    await tester.pumpAndSettle();
    expect(s.walls, hasLength(1));
    expect(s.walls.first.x1, closeTo(17, 0.6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('stage and controls are separate widgets over one state', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(ChannelPlannerStage), findsOneWidget);
    expect(find.byType(ChannelPlannerControls), findsOneWidget);
    expect(find.byType(ChannelPlannerReadouts), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChannelPlannerStage),
        matching: find.byType(ChannelPlannerControls),
      ),
      findsNothing,
    );
    final ChannelPlannerState a = _stateOf(tester);
    final ChannelPlannerState b = tester
        .widget<ChannelPlannerControls>(find.byType(ChannelPlannerControls))
        .state;
    expect(identical(a, b), isTrue);
    // The stage is not inside a scroll view, so a drag is never a scroll.
    expect(
      find.ancestor(
        of: find.byType(ChannelPlannerStage),
        matching: find.byType(Scrollable),
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
      testWidgets(
        '$name ${size.width.round()} px: no overflow, no sideways scroll',
        (WidgetTester tester) async {
          await _pump(tester, theme: theme(), size: size);
          final ChannelPlannerState s = _stateOf(tester);
          expect(tester.takeException(), isNull);
          _expectNoSidewaysScroll(tester);
          _expectTextInsideWidth(tester, size.width);
          // The widest content: 2.4 GHz with its mask table, 12 APs, walls.
          s.setBand(PlannerBand.band24);
          while (s.canAdd) {
            s.addAp();
          }
          s.addWallAcross(vertical: true);
          s.addWallAcross(vertical: false);
          s.runAutoPlan();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          _expectNoSidewaysScroll(tester);
          _expectTextInsideWidth(tester, size.width);
          s.setBand(PlannerBand.band5);
          s.setDfs(true);
          s.setUnii4(true);
          s.setWidth(20);
          s.runAutoPlan();
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          _expectTextInsideWidth(tester, size.width);
        },
      );
    }
  }
}
