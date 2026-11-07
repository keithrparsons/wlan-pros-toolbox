// iPhone Duo layout sweep (Keith, 2026-11-07).
//
// Opens every live tool at the Duo's screen sizes and fails on any layout
// overflow. The big-screen breakpoint moved from 720 to 600 so the open Duo
// (669pt wide upright) gets the wide layouts; this sweep is the net that
// catches a wide layout that does not fit between 600 and 720.
//
// Sizes: Xcode 27.2's iPhone Duo simulator profile (2007 x 2853 and
// 1398 x 2034 px at 3x), plus 600 wide, the narrowest big-screen width.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const List<Size> _duoSizes = <Size>[
  Size(466, 678), // closed
  Size(600, 900), // narrowest big-screen width
  Size(669, 951), // open, upright
  Size(951, 669), // open, turned
  // The tool pane beside the list (CategoryScreen, list 38% clamped 260-340,
  // 1pt divider): what a tool gets when it opens beside its list.
  Size(408, 951), // pane, open upright
  Size(610, 669), // pane, open turned
];

void main() {
  final List<ToolEntry> tools = kToolCategories
      .expand((ToolCategory c) => c.tools)
      .where((ToolEntry t) => t.isLive)
      .where((ToolEntry t) => AppRouter.routes.containsKey(t.routeName))
      .toList();

  // Guards the sweep itself: a detector that never fires would pass forever.
  testWidgets('the overflow detector catches a known overflow', (tester) async {
    final List<String> caught = await _overflowsWhilePumping(
      tester,
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(
            width: 10,
            height: 10,
            child: Row(children: <Widget>[SizedBox(width: 50, height: 5)]),
          ),
        ),
      ),
    );
    expect(caught, isNotEmpty);
  });

  test('the sweep covers every live tool', () {
    expect(tools.length, greaterThan(150));
  });

  for (final Size size in _duoSizes) {
    testWidgets('no tool overflows at ${size.width.toInt()}x'
        '${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final List<String> overflows = <String>[];
      for (final ToolEntry tool in tools) {
        final List<String> found = await _overflowsWhilePumping(
          tester,
          MaterialApp(
            key: ValueKey<String>(tool.id),
            theme: AppTheme.dark(),
            home: Builder(builder: AppRouter.routes[tool.routeName]!),
          ),
        );
        overflows.addAll(found.map((String e) => '${tool.id}: $e'));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 5));

      expect(overflows, isEmpty, reason: overflows.join('\n'));
    });
  }
}

Future<List<String>> _overflowsWhilePumping(
  WidgetTester tester,
  Widget widget,
) async {
  final List<String> overflows = <String>[];
  final FlutterExceptionHandler? previous = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    if (details.exceptionAsString().contains('overflowed')) {
      overflows.add(details.exceptionAsString());
    }
  };
  await tester.pumpWidget(widget);
  await tester.pump(const Duration(milliseconds: 100));
  FlutterError.onError = previous;
  return overflows;
}
