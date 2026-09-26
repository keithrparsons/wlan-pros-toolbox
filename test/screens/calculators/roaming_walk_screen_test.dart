// Widget tests for the Wi-Fi Classroom "Roaming Walk" screen.
//
// The model is pinned in test/services/wifi_lab/roaming_walk_engine_test.dart;
// these cover the screen contract: catalog registration beside the untouched
// 'roaming' and 'roaming-log' tools, the fresh state, Step and the readouts,
// Play and Pause, reduced motion, a preset that ping-pongs showing its
// verdict word, drawing a path, the stage and controls as separate widgets,
// the copy text, and phone and desktop widths in both themes laying out with
// no sideways scroll.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/roaming_walk_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/roaming_walk_engine.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<void> _pump(
  WidgetTester tester, {
  ThemeData? theme,
  double width = 390,
  double height = 844,
  bool reduceMotion = true,
  RoamWalkConfig? initial,
}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          disableAnimations: reduceMotion,
        ),
        child: RoamingWalkScreen(initial: initial),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String _valueOf(WidgetTester tester, String label) {
  final Finder row = find
      .ancestor(of: find.text(label), matching: find.byType(Row))
      .first;
  final List<Text> texts = tester
      .widgetList<Text>(find.descendant(of: row, matching: find.byType(Text)))
      .toList();
  return texts.last.data ?? '';
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

void main() {
  test('catalog registers roaming-walk in Wi-Fi Classroom', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'wifi-classroom',
    );
    final int i = rf.tools.indexWhere(
      (ToolEntry t) => t.id == kRoamingWalkToolId,
    );
    expect(i, greaterThan(0));
    final ToolEntry e = rf.tools[i];
    expect(e.title, 'Roaming Walk');
    expect(e.subgroup, 'Network Design and Security');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/roaming-walk');
    // The existing roaming tools are separate, untouched entries.
    for (final String id in <String>['roaming', 'roaming-log']) {
      expect(
        kToolCategories.any(
          (ToolCategory c) => c.tools.any((ToolEntry t) => t.id == id),
        ),
        isTrue,
        reason: id,
      );
    }
  });

  testWidgets('fresh: paused at 0 s, nothing roamed, Restart disabled', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    expect(find.text('Roaming Walk'), findsOneWidget);
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('Reduced motion is on'), findsOneWidget);
    expect(find.text('No roams yet. Press Play or Step.'), findsOneWidget);
    expect(_valueOf(tester, 'Roams'), '0');
    final OutlinedButton restart = tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text('Restart'),
        matching: find.byWidgetPredicate((Widget w) => w is OutlinedButton),
      ),
    );
    expect(restart.onPressed, isNull);
    // Stage and controls are separate widgets over one controller.
    expect(find.byType(RoamingWalkStage), findsOneWidget);
    expect(find.byType(RoamingWalkControls), findsOneWidget);
    expect(find.textContaining('A teaching model'), findsWidgets);
  });

  testWidgets('Step walks the client through its first roam', (
    WidgetTester tester,
  ) async {
    await _pump(tester, initial: RoamWalkConfig(shadowSigmaDb: 0));
    final Finder step = find.text('Step 1 s');
    await tester.ensureVisible(step);
    for (int i = 0; i < 18; i++) {
      await tester.tap(step);
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(_valueOf(tester, 'Roams'), '1');
    // At 18.0 s the roam that began at 17.7 s is 300 ms in.
    expect(_valueOf(tester, 'Total roam gap'), '300 ms');
    await tester.tap(step);
    await tester.pumpAndSettle();
    expect(find.textContaining('17.7 s'), findsWidgets);
    expect(find.textContaining('Gap 351 ms'), findsOneWidget);
    expect(_valueOf(tester, 'Total roam gap'), '351 ms');
  });

  testWidgets('normal motion: Play runs, Pause stops', (
    WidgetTester tester,
  ) async {
    await _pump(tester, reduceMotion: false);
    expect(find.textContaining('Reduced motion is on'), findsNothing);
    await tester.ensureVisible(find.text('Play'));
    await tester.pump();
    await tester.tap(find.text('Play'));
    // pumpAndSettle would wait for the whole walk; pump frames instead.
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Pause'), findsOneWidget);
    await tester.tap(find.text('Pause'));
    await tester.pump();
    expect(find.text('Play'), findsOneWidget);
    expect(find.textContaining('So far ('), findsOneWidget);
  });

  testWidgets('a jumpy client between two APs shows the ping-pong verdict', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      initial: RoamWalkConfig(
        path: kAcrossPath,
        seed: 2,
        shadowSigmaDb: 4,
        triggerDbm: ClientPreset.jumpy.triggerDbm,
        deltaDb: ClientPreset.jumpy.deltaDb,
      ),
    );
    final Finder slider = find.byType(Slider).first;
    await tester.ensureVisible(slider);
    // Drag the walk-time slider to the end.
    await tester.drag(slider, const Offset(1000, 0));
    await tester.pumpAndSettle();
    expect(find.text('The whole walk'), findsOneWidget);
    expect(find.textContaining('ping-pong: back within 5 s'), findsOneWidget);
    expect(find.text('Play again'), findsOneWidget);
  });

  testWidgets(
    'choosing a preset changes trigger and delta; editing is Custom',
    (WidgetTester tester) async {
      await _pump(tester);
      expect(find.text('-70 dBm'), findsWidgets);
      await _tap(tester, find.text('iPhone, transmitting'));
      await tester.tap(find.text('Mac').last);
      await tester.pumpAndSettle();
      expect(find.text('-75 dBm'), findsOneWidget);
      expect(find.textContaining('Published by Apple'), findsOneWidget);
      await _tap(tester, find.text('Mac'));
      await tester.tap(find.text('Illustrative sticky').last);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Illustrative: Android and Windows'),
        findsOne,
      );
      // Moving the trigger off every preset makes the client Custom.
      final Finder trigger = find.byType(Slider).at(1);
      await tester.ensureVisible(trigger);
      await tester.pumpAndSettle();
      await tester.drag(trigger, const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(find.text('Custom'), findsOneWidget);
      expect(find.text('Custom values.'), findsOneWidget);
    },
  );

  testWidgets('drawing a path: tap points, then Use this path', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _tap(tester, find.text('Along the corridor'));
    // The menu shows about five rows; scroll its own list to the last one.
    final Finder menuList = find
        .ancestor(
          of: find.text('Under the APs').last,
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.scrollUntilVisible(
      find.text('Draw your own'),
      40,
      scrollable: menuList,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Draw your own').last);
    await tester.pumpAndSettle();
    expect(find.textContaining('Drawing a path'), findsOneWidget);
    final Finder use = find.text('Use this path');
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(of: use, matching: find.byType(FilledButton)),
          )
          .onPressed,
      isNull,
    );
    final Finder floor = find.byType(RoamingWalkStage);
    await tester.ensureVisible(floor);
    await tester.pumpAndSettle();
    final Finder paint = find
        .descendant(of: floor, matching: find.byType(CustomPaint))
        .first;
    final Rect r = tester.getRect(paint);
    await tester.tapAt(r.centerLeft + Offset(30, -r.height * 0.3));
    await tester.pump();
    await tester.tapAt(r.centerRight + Offset(-30, r.height * 0.3));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 points'), findsOneWidget);
    await _tap(tester, use);
    expect(find.textContaining('Drawing a path'), findsNothing);
    expect(
      find.text('Drawn by you'),
      findsNothing,
    ); // select shows the menu label
    expect(find.text('Draw your own'), findsOneWidget);
  });

  test('copy text carries the verdict words', () {
    final RoamingWalkController c = RoamingWalkController(
      vsync: const TestVSync(),
      initial: RoamWalkConfig(shadowSigmaDb: 0, triggerDbm: -85, deltaDb: 12),
    );
    addTearDown(c.dispose);
    final String text = c.copyText();
    expect(text, contains('Illustrative sticky'));
    expect(text, contains('Roams: 0'));
    expect(text, contains('23.7 s (weak signal)'));
    expect(text, isNot(contains('\u2014')));
  });

  for (final String themeName in <String>['dark', 'light']) {
    for (final double w in <double>[390, 1280]) {
      testWidgets('lays out at $w px, $themeName, no sideways scroll', (
        WidgetTester tester,
      ) async {
        await _pump(
          tester,
          width: w,
          theme: themeName == 'dark' ? AppTheme.dark() : AppTheme.light(),
          initial: RoamWalkConfig(aps: defaultApLayout(6)),
        );
        final Finder step = find.text('Step 1 s');
        await tester.ensureVisible(step);
        for (int i = 0; i < 25; i++) {
          await tester.tap(step);
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final Scrollable s in tester.widgetList<Scrollable>(
          find.byType(Scrollable),
        )) {
          expect(s.axisDirection, AxisDirection.down);
        }
        expect(find.textContaining('NaN'), findsNothing);
      });
    }
  }
}
