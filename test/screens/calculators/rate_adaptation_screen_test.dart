// Widget tests for the Wi-Fi Lab Rate Adaptation screen.
//
// The model is pinned in test/services/wifi_lab/rate_adaptation_model_test.
// dart; these tests cover the screen contract: registration, the fresh
// state, Step, the settings reaching the running link, the stage and
// controls split, the MCS label contrast on its block, and the layout at
// 390 x 844 and 1280 wide in both themes without overflow or sideways
// scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_controller.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_parts.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/rate_adaptation_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/rate_adaptation_model.dart';
import 'package:wlan_pros_toolbox/theme/app_color_scheme.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<RateAdaptationController> _pump(
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
      home: const RateAdaptationScreen(),
    ),
  );
  await tester.pumpAndSettle();
  return tester
      .widget<RateAdaptationStage>(find.byType(RateAdaptationStage))
      .controller;
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

double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('catalog registers rate-adaptation in Wi-Fi Lab', () {
    final ToolCategory rf = kToolCategories.firstWhere(
      (ToolCategory c) => c.id == 'rf-calculators',
    );
    final ToolEntry e = rf.tools.firstWhere(
      (ToolEntry t) => t.id == kRateAdaptationToolId,
    );
    expect(kRateAdaptationToolId, 'rate-adaptation');
    expect(e.title, 'Rate Adaptation');
    expect(e.subgroup, 'Wi-Fi Lab');
    expect(e.isLive, isTrue);
    expect(e.routeName, '/tools/rate-adaptation');
    expect(AppRouter.rateAdaptation, e.routeName);
  });

  test('the MCS number reads on its block in both themes (4.5:1)', () {
    for (final AppColorScheme s in <AppColorScheme>[
      AppColorScheme.dark(),
      AppColorScheme.light(),
    ]) {
      for (int m = 0; m <= RaLink.maxMcs; m++) {
        expect(
          _contrast(RaPalette.of(m, s), s.surface0),
          greaterThanOrEqualTo(4.5),
          reason: 'MCS $m, light=${s.isLight}',
        );
      }
    }
  });

  testWidgets('opens paused with nothing learned yet', (
    WidgetTester tester,
  ) async {
    final RateAdaptationController c = await _pump(tester);
    expect(c.playing, isFalse);
    expect(c.engine.nowUs, 0);
    expect(find.textContaining('No frames yet'), findsOneWidget);
    expect(find.text('untried'), findsNWidgets(RaLink.mcsCount));
    expect(c.copyText(), isNull);
  });

  testWidgets('Step sends one frame and says what happened', (
    WidgetTester tester,
  ) async {
    final RateAdaptationController c = await _pump(tester);
    await tester.ensureVisible(find.text('Step'));
    await tester.tap(find.text('Step'));
    await tester.pumpAndSettle();
    expect(c.engine.totalFrames, 1);
    expect(find.textContaining('Last frame'), findsOneWidget);
    expect(c.copyText(), contains('Rate Adaptation'));
  });

  testWidgets('settings reach the running link without restarting it', (
    WidgetTester tester,
  ) async {
    final RateAdaptationController c = await _pump(tester);
    c.advanceBy(1e6);
    await tester.pumpAndSettle();
    final double t = c.engine.nowUs;
    await tester.ensureVisible(find.text('Steady'));
    await tester.tap(find.text('Steady'));
    await tester.pumpAndSettle();
    expect(c.settings.path, RaPath.steady);
    expect(c.engine.nowUs, t);
    await tester.ensureVisible(find.text('4 (long)'));
    await tester.tap(find.text('4 (long)'));
    await tester.pumpAndSettle();
    expect(c.settings.retryLimit, RaRetryLimit.long4);
    await tester.ensureVisible(find.text('Restart'));
    await tester.tap(find.text('Restart'));
    await tester.pumpAndSettle();
    expect(c.engine.nowUs, 0);
    expect(c.settings.retryLimit, RaRetryLimit.long4);
  });

  testWidgets('Play runs the clock and Pause stops it', (
    WidgetTester tester,
  ) async {
    final RateAdaptationController c = await _pump(tester);
    await tester.ensureVisible(find.text('Play'));
    await tester.tap(find.text('Play'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.playing, isTrue);
    expect(c.engine.nowUs, greaterThan(0));
    await tester.tap(find.text('Pause'));
    await tester.pump();
    final double t = c.engine.nowUs;
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.engine.nowUs, t);
  });

  // Regression, found when the Play/Pause test above missed its Pause tap:
  // the last-frame sentence (1 to 4 lines) and the readout values reflowed
  // as the link ran, so on a phone the transport slid under the finger.
  testWidgets('the transport does not move while the link runs', (
    WidgetTester tester,
  ) async {
    final RateAdaptationController c = await _pump(tester);
    await tester.ensureVisible(find.text('Step'));
    await tester.pumpAndSettle();
    final double y0 = tester.getTopLeft(find.text('Step')).dy;
    for (final double us in <double>[0, 3e5, 2e6, 4e6, 3e6]) {
      if (us == 0) {
        c.stepFrame();
      } else {
        c.advanceBy(us);
      }
      await tester.pumpAndSettle();
      expect(
        tester.getTopLeft(find.text('Step')).dy,
        y0,
        reason: 'Step moved at ${c.engine.nowUs / 1e6} s',
      );
    }
  });

  testWidgets('stage and controls are separate widgets', (
    WidgetTester tester,
  ) async {
    await _pump(tester, size: const Size(1280, 900));
    expect(find.byType(RateAdaptationStage), findsOneWidget);
    expect(find.byType(RateAdaptationControls), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(RateAdaptationStage),
        matching: find.byType(RateAdaptationControls),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(RateAdaptationControls),
        matching: find.byType(RateAdaptationStage),
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
      testWidgets('$name theme at ${size.width.toInt()} wide renders cleanly '
          'mid-run', (WidgetTester tester) async {
        final RateAdaptationController c = await _pump(
          tester,
          theme: theme(),
          size: size,
        );
        // Mid walk-away, with retries and a sample in the strip.
        c.advanceBy(6e6);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        _expectNoSidewaysScroll(tester);
        _expectTextInsideWidth(tester, size.width);
      });
    }
  }
}
