// Two-pane category view (Keith, 2026-11-07, iPhone Duo approach B).
//
// At or above AppSpacing.wideLayoutMinWidth a category shows its tool list
// beside the open tool, like the web and desktop layouts. Below it a tool
// opens full screen as before. Folding the Duo with a tool open keeps that
// tool and what was typed into it; Back then returns to the list.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/router/live_error_nav_gate.dart';
import 'package:wlan_pros_toolbox/screens/category_screen.dart';
import 'package:wlan_pros_toolbox/services/device/fold_state.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/presenter/large_screen_gate.dart';
import 'package:wlan_pros_toolbox/widgets/tool_row.dart';

const Size _duoOpenTurned = Size(951, 669);
const Size _duoOpenUpright = Size(669, 951);
const Size _duoClosed = Size(466, 678);

ToolCategory _cat(String id) =>
    kToolCategories.firstWhere((ToolCategory c) => c.id == id);

void _setWindow(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
}

Future<void> _pumpCategory(WidgetTester tester, Size size, String id) async {
  _setWindow(tester, size);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      routes: Map<String, WidgetBuilder>.of(AppRouter.routes)
        ..remove(Navigator.defaultRouteName),
      home: CategoryScreen(category: _cat(id)),
    ),
  );
  await tester.pump();
}

Future<void> _openTool(WidgetTester tester, String toolId) async {
  final Finder row = find.byKey(ValueKey<String>(toolId));
  // The tool list is the first vertical scroller; the tool pane follows it.
  final Finder list = find
      .byWidgetPredicate(
        (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      )
      .first;
  tester.state<ScrollableState>(list).position.jumpTo(0);
  await tester.pump();
  await tester.scrollUntilVisible(row, 200, scrollable: list);
  await tester.ensureVisible(row);
  await tester.pumpAndSettle();
  await tester.tap(row);
  await tester.pumpAndSettle();
}

bool _rootCanPop(WidgetTester tester) =>
    tester.state<NavigatorState>(find.byType(Navigator).first).canPop();

void main() {
  testWidgets('wide: the list sits beside a "Choose a tool" placeholder', (
    tester,
  ) async {
    await _pumpCategory(tester, _duoOpenTurned, 'rf-calculators');
    expect(find.text('Choose a tool'), findsOneWidget);
    expect(find.byType(ToolRow), findsWidgets);
  });

  for (final Size size in <Size>[_duoOpenTurned, _duoOpenUpright]) {
    testWidgets('wide ${size.width.toInt()}: a tool opens beside the list', (
      tester,
    ) async {
      await _pumpCategory(tester, size, 'rf-calculators');
      await _openTool(tester, 'eirp');

      expect(find.text('EIRP'), findsWidgets);
      expect(find.byType(ToolRow), findsWidgets);
      expect(find.text('Choose a tool'), findsNothing);
      expect(_rootCanPop(tester), isFalse);
    });
  }

  testWidgets('wide: choosing another tool replaces the open one', (
    tester,
  ) async {
    await _pumpCategory(tester, _duoOpenTurned, 'rf-calculators');
    await _openTool(tester, 'eirp');
    await _openTool(tester, 'fresnel');

    expect(find.text('TX Power'), findsNothing);
    expect(find.byType(ToolRow), findsWidgets);
  });

  testWidgets('wide: Back in the tool pane closes the tool', (tester) async {
    await _pumpCategory(tester, _duoOpenTurned, 'rf-calculators');
    await _openTool(tester, 'eirp');
    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.text('Choose a tool'), findsOneWidget);
    expect(find.byType(CategoryScreen), findsOneWidget);
  });

  testWidgets('narrow: a tool opens full screen as before', (tester) async {
    await _pumpCategory(tester, _duoClosed, 'rf-calculators');
    await _openTool(tester, 'eirp');

    expect(find.text('TX Power'), findsOneWidget);
    expect(find.byType(ToolRow), findsNothing);
    expect(_rootCanPop(tester), isTrue);
  });

  testWidgets('wide: the Wi-Fi Classroom opens its simulators full screen', (
    tester,
  ) async {
    final ToolEntry simulator = _cat(kWifiClassroomCategoryId).tools.firstWhere(
      (ToolEntry t) =>
          t.isLive && kWifiClassroomSimulatorSubgroups.contains(t.subgroup),
    );
    await _pumpCategory(tester, _duoOpenTurned, kWifiClassroomCategoryId);
    expect(find.text('Choose a tool'), findsNothing);
    await _openTool(tester, simulator.id);

    expect(_rootCanPop(tester), isTrue);
  });

  // A Live tool must stay on the root navigator: LiveErrorNavGate restores a
  // Shortcut run by route name from the root's CurrentRouteObserver, and a
  // tool hidden in the pane would be torn down and re-pushed fresh.
  for (final String route in LiveErrorNavGate.liveRoutes) {
    final ToolEntry? tool = kToolCategories
        .expand((ToolCategory c) => c.tools)
        .where((ToolEntry t) => t.routeName == route)
        .firstOrNull;
    if (tool == null) continue;
    final String categoryId = kToolCategories
        .firstWhere((ToolCategory c) => c.tools.contains(tool))
        .id;
    testWidgets('wide: Live tool ${tool.id} opens full screen', (tester) async {
      await _pumpCategory(tester, _duoOpenTurned, categoryId);
      await _openTool(tester, tool.id);

      expect(_rootCanPop(tester), isTrue);
    });
  }

  testWidgets('folding with a tool open keeps the tool and its input', (
    tester,
  ) async {
    await _pumpCategory(tester, _duoOpenUpright, 'rf-calculators');
    await _openTool(tester, 'eirp');
    await tester.enterText(find.byType(TextField).first, '17');
    await tester.pump();

    _setWindow(tester, _duoClosed);
    await tester.pumpAndSettle();

    expect(find.byType(ToolRow), findsNothing);
    expect(find.text('17'), findsOneWidget);

    _setWindow(tester, _duoOpenUpright);
    await tester.pumpAndSettle();

    expect(find.byType(ToolRow), findsWidgets);
    expect(find.text('17'), findsOneWidget);
  });

  testWidgets('folded with a tool open, Back returns to the list', (
    tester,
  ) async {
    await _pumpCategory(tester, _duoOpenUpright, 'rf-calculators');
    await _openTool(tester, 'eirp');
    _setWindow(tester, _duoClosed);
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(ToolRow), findsWidgets);
    expect(find.text('TX Power'), findsNothing);
    expect(_rootCanPop(tester), isFalse);
  });

  group('half-open Duo (approach C)', () {
    tearDown(() => foldState.value = FoldState.none);

    testWidgets('book pose: the divider moves onto the fold', (tester) async {
      foldState.value = const FoldState(
        status: HingeStatus.partiallyOpen,
        folds: <Rect>[Rect.fromLTWH(475, 0, 0, 669)],
      );
      await _pumpCategory(tester, _duoOpenTurned, 'rf-calculators');

      expect(tester.getTopLeft(find.byType(VerticalDivider)).dx, 475);
    });

    testWidgets('laptop pose: the tool sits above the fold, the list below', (
      tester,
    ) async {
      await _pumpCategory(tester, _duoOpenUpright, 'rf-calculators');
      await _openTool(tester, 'eirp');
      foldState.value = const FoldState(
        status: HingeStatus.partiallyOpen,
        folds: <Rect>[Rect.fromLTWH(0, 470, 669, 10)],
      );
      await tester.pumpAndSettle();

      expect(find.text('TX Power'), findsOneWidget);
      expect(tester.getTopLeft(find.text('TX Power')).dy, lessThan(470));
      expect(
        tester.getTopLeft(find.byType(ToolRow).first).dy,
        greaterThan(480),
      );
    });

    testWidgets('a pose change keeps what was typed in the tool', (
      tester,
    ) async {
      await _pumpCategory(tester, _duoOpenUpright, 'rf-calculators');
      await _openTool(tester, 'eirp');
      await tester.enterText(find.byType(TextField).first, '17');
      foldState.value = const FoldState(
        status: HingeStatus.partiallyOpen,
        folds: <Rect>[Rect.fromLTWH(0, 470, 669, 10)],
      );
      await tester.pumpAndSettle();
      expect(find.text('17'), findsOneWidget);

      foldState.value = FoldState.none;
      await tester.pumpAndSettle();
      expect(find.text('17'), findsOneWidget);
    });
  });
}
