// Widget tests for the Wi-Fi Classroom "Multicast at the Basic Rate" screen
// (multicast-basic-rate). The math has its own tests (test/services/wifi_lab/
// multicast_basic_rate_model_test.dart); these check the screen: it opens on
// the spec defaults, inputs move the readouts, predict-then-reveal hides and
// shows the answer, power save shows the DTIM delay, a stream that does not
// fit says so in words, Play sweeps the second, and the layout holds at phone
// widths in both themes with no sideways scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multicast_basic_rate_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multicast_basic_rate_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/multicast_basic_rate_stage.dart';
import 'package:wlan_pros_toolbox/services/wifi_lab/multicast_basic_rate_model.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<MulticastBasicRateController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 4000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final MulticastBasicRateController c = MulticastBasicRateController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: MulticastBasicRateScreen(controller: c),
    ),
  );
  await tester.pump();
  return c;
}

Future<void> _tap(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await tester.pump();
}

void main() {
  test('catalog registers multicast-basic-rate in Wi-Fi Classroom, with its '
      'route', () {
    final ToolCategory cat = kToolCategories.firstWhere(
      (ToolCategory c) =>
          c.tools.any((ToolEntry e) => e.id == 'multicast-basic-rate'),
    );
    expect(cat.id, 'wifi-classroom');
    final ToolEntry t = cat.tools.firstWhere(
      (ToolEntry e) => e.id == 'multicast-basic-rate',
    );
    expect(t.title, 'Multicast at the Basic Rate');
    expect(t.subgroup, 'Airtime and Access');
    expect(t.routeName, '/tools/multicast-basic-rate');
    expect(AppRouter.multicastBasicRate, t.routeName);
    expect(kMulticastBasicRateToolId, t.id);
  });

  testWidgets('opens on the defaults: 4 Mb/s video at a 6 Mb/s basic rate', (
    WidgetTester tester,
  ) async {
    await _open(tester);
    expect(find.text('Multicast at the Basic Rate'), findsOneWidget);
    expect(find.byType(MulticastBasicRateStage), findsOneWidget);
    expect(find.byType(MulticastBasicRateControls), findsOneWidget);
    // Headline and readouts carry the same computed shares.
    expect(find.text('73.8%'), findsWidgets);
    expect(find.text('45.9%'), findsWidgets);
    expect(find.text('8 listeners'), findsOneWidget);
    expect(find.text('1,941.5 µs'), findsOneWidget);
    expect(find.textContaining('no acknowledgment, no retry'), findsOneWidget);
    // Illustrative values are labeled so.
    expect(find.text('Stream bit rate (illustrative)'), findsOneWidget);
    expect(find.text('Packet size (illustrative)'), findsOneWidget);
    expect(find.text('Listener rates (illustrative)'), findsOneWidget);
    expect(find.text('Presets (illustrative)'), findsOneWidget);
  });

  testWidgets('a faster basic rate cuts the multicast share', (
    WidgetTester tester,
  ) async {
    final MulticastBasicRateController c = await _open(tester);
    c.basicRate = BasicRate.r24;
    await tester.pump();
    expect(find.text('21.9%'), findsWidgets);
    expect(find.text('73.8%'), findsNothing);
  });

  testWidgets('a stream that does not fit says so in words', (
    WidgetTester tester,
  ) async {
    final MulticastBasicRateController c = await _open(tester);
    c.band = McBand.ghz24;
    c.basicRate = BasicRate.r1;
    await tester.pump();
    expect(find.textContaining('Does not fit: needs 435.0%'), findsOneWidget);
    expect(find.text('over 30'), findsOneWidget);
  });

  testWidgets('power save shows the DTIM delay', (WidgetTester tester) async {
    await _open(tester);
    expect(find.text('none (nobody dozing)'), findsOneWidget);
    await _tap(tester, find.text('A client is in power save'));
    // DTIM 3 x 102.4 ms.
    expect(find.text('up to 307.2 ms'), findsWidgets);
    expect(find.text('Added delay from DTIM buffering'), findsOneWidget);
  });

  testWidgets('predict, then reveal hides the answer until Reveal', (
    WidgetTester tester,
  ) async {
    final MulticastBasicRateController c = await _open(tester);
    c.basicRate = BasicRate.r12;
    await tester.pump();
    await _tap(tester, find.text('Ask the class'));
    // The question's scenario is loaded and the shares are hidden.
    expect(c.config, const McConfig());
    expect(find.text('73.8%'), findsNothing);
    expect(find.text('?'), findsWidgets);
    await _tap(tester, find.text('Over 60%'));
    await _tap(tester, find.text('Reveal'));
    expect(find.text('73.8%'), findsWidgets);
    expect(
      find.text('At a 6 Mb/s basic rate it uses 73.8% of the channel.'),
      findsOneWidget,
    );
    expect(find.text('The class picked Over 60%: right.'), findsOneWidget);
    await _tap(tester, find.text('Done'));
    expect(find.text('Ask the class'), findsOneWidget);
    // Reveal started a sweep; let it finish.
    await tester.pump(kMcSweepDuration);
    await tester.pump();
  });

  testWidgets('Play sweeps the second; Next beacon and Reset move the '
      'playhead', (WidgetTester tester) async {
    final MulticastBasicRateController c = await _open(tester);
    expect(c.playhead.value, 1);
    await _tap(tester, find.text('Play the second'));
    expect(c.playing, isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(c.playhead.value, closeTo(0.5, 0.02));
    await tester.pump(const Duration(seconds: 4));
    expect(c.playing, isFalse);
    expect(c.playhead.value, 1);
    await _tap(tester, find.text('Reset'));
    expect(c.playhead.value, 0);
    await _tap(tester, find.text('Next beacon'));
    expect(c.playhead.value, closeTo(0.1024, 1e-9));
  });

  testWidgets('with reduced motion, Reveal draws the second whole', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final MulticastBasicRateController c = MulticastBasicRateController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: MulticastBasicRateScreen(controller: c),
        ),
      ),
    );
    await tester.pump();
    c.ask();
    c.reveal();
    await tester.pump();
    expect(c.playing, isFalse);
    expect(c.playhead.value, 1);
  });

  for (final (String name, ThemeData Function() theme)
      in <(String, ThemeData Function())>[
        ('dark', AppTheme.dark),
        ('light', AppTheme.light),
      ]) {
    for (final double width in <double>[320, 390, 1024]) {
      testWidgets('$name: ${width.toInt()} px lays out with no overflow', (
        WidgetTester tester,
      ) async {
        final MulticastBasicRateController c = await _open(
          tester,
          size: Size(width, 5200),
          theme: theme(),
        );
        c.powerSave = true;
        c.listeners = 30;
        await tester.pump();
        expect(tester.takeException(), isNull);
        final Iterable<Scrollable> horizontal = tester
            .widgetList<Scrollable>(find.byType(Scrollable))
            .where(
              (Scrollable s) =>
                  s.axisDirection == AxisDirection.right ||
                  s.axisDirection == AxisDirection.left,
            );
        expect(horizontal, isEmpty);
      });
    }
  }
}
