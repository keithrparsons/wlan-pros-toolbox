// Widget tests for the Wi-Fi Classroom Channel Utilization Meter
// (channel-utilization). The math has its own tests (test/services/wifi_lab/
// channel_utilization_model_test.dart); these check the screen: it is
// registered, it opens on the spec defaults, a full window shows the byte and
// the percent, the listener view moves the meter on the same history while
// the beacon keeps what the access point reports,
// the station count follows associated stations and not the neighbor,
// predict-then-reveal hides and shows the meter, labeled values carry their
// labels, Run moves the channel, and the layout holds at phone widths in
// both themes with no sideways scrolling.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_utilization_controls.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_utilization_screen.dart';
import 'package:wlan_pros_toolbox/screens/tools/calculators/channel_utilization_stage.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

Future<ChannelUtilizationController> _open(
  WidgetTester tester, {
  Size size = const Size(800, 6000),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ChannelUtilizationController c = ChannelUtilizationController();
  addTearDown(c.dispose);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark(),
      home: ChannelUtilizationScreen(controller: c),
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
  test('catalog registers channel-utilization in Wi-Fi Classroom, with its '
      'route', () {
    final ToolCategory cat = kToolCategories.firstWhere(
      (ToolCategory c) =>
          c.tools.any((ToolEntry e) => e.id == 'channel-utilization'),
    );
    expect(cat.id, 'wifi-classroom');
    final ToolEntry t = cat.tools.firstWhere(
      (ToolEntry e) => e.id == 'channel-utilization',
    );
    expect(t.title, 'Channel Utilization Meter');
    expect(t.subgroup, 'Airtime and Access');
    expect(t.routeName, '/tools/channel-utilization');
    expect(AppRouter.channelUtilization, t.routeName);
    expect(kChannelUtilizationToolId, t.id);
  });

  testWidgets('opens on the defaults: one sender, collecting the first '
      'interval', (WidgetTester tester) async {
    final ChannelUtilizationController c = await _open(tester);
    expect(find.text('Channel Utilization Meter'), findsOneWidget);
    expect(find.byType(ChannelUtilizationStage), findsOneWidget);
    expect(find.byType(ChannelUtilizationControls), findsOneWidget);
    expect(c.playing, isFalse);
    expect(find.text('collecting the first beacon interval'), findsOneWidget);
    // The worked case is in the readouts before anything runs.
    expect(find.textContaining('a cycle of 393.5 µs'), findsOneWidget);
    expect(
      find.textContaining('73.2% busy as the access point reports it'),
      findsOneWidget,
    );
    expect(find.textContaining('75.7% in the listener view'), findsOneWidget);
    expect(find.textContaining('payload 56.5%'), findsOneWidget);
  });

  testWidgets('what the access point reports is 186 of 255 = 72.9%; the '
      'listener view moves the meter on the same history, not the beacon', (
    WidgetTester tester,
  ) async {
    final ChannelUtilizationController c = await _open(tester);
    await _tap(tester, find.text('Skip one window'));
    expect(c.sim.completedIntervals, 50);
    expect(find.text('72.9%'), findsWidgets);
    expect(find.text('What the access point reports'), findsWidgets);
    expect(find.text('186 of 255'), findsOneWidget);
    expect(find.text('186 (72.9%)'), findsOneWidget);
    expect(find.text('0.0%'), findsWidgets); // truly spare
    final int before = c.sim.nowTenths;
    await _tap(tester, find.text('Listener view (counts reservations)'));
    expect(c.countReserved, isTrue);
    expect(c.sim.nowTenths, before);
    expect(c.reading!.byte, greaterThan(186));
    expect(c.reading!.exactShare, closeTo(0.757, 0.01));
    // The headline says whose view it is; the beacon still carries the
    // access point's own number.
    expect(
      find.text('${c.reading!.byte} of 255, a device outside the exchange'),
      findsOneWidget,
    );
    expect(c.apReading!.byte, 186);
    expect(find.text('186 (72.9%)'), findsOneWidget);
    expect(
      find.textContaining('A listener outside the exchange measures'),
      findsOneWidget,
    );
  });

  testWidgets('the window slider re-reads history; a filling window says so', (
    WidgetTester tester,
  ) async {
    final ChannelUtilizationController c = await _open(tester);
    await _tap(tester, find.text('Next beacon interval'));
    expect(find.textContaining('Window filling: 1 of 50'), findsOneWidget);
    c.window = 1;
    await tester.pump();
    expect(find.textContaining('Window filling'), findsNothing);
    expect(find.textContaining('the average over the bracket'), findsOneWidget);
  });

  testWidgets('the station count counts associated stations, not the '
      'neighbor', (WidgetTester tester) async {
    final ChannelUtilizationController c = await _open(tester);
    c.idleStations = 40;
    await tester.pump();
    expect(find.text('41'), findsWidgets);
    expect(find.text('associated, 1 sending'), findsOneWidget);
    await _tap(tester, find.text('A neighbor network on this channel'));
    expect(c.config.neighbor, isTrue);
    expect(find.text('41'), findsWidgets);
    c.skipWindow();
    await tester.pump();
    expect(find.text('Other network'), findsWidgets);
  });

  testWidgets('labeled values carry their labels', (WidgetTester tester) async {
    await _open(tester);
    expect(find.text(kCuWindowLabel), findsOneWidget);
    expect(kCuWindowLabel, contains('default 50: one secondary source'));
    expect(find.text('Neighbor\'s airtime (illustrative)'), findsOneWidget);
    expect(find.text('Non-Wi-Fi bursts (illustrative)'), findsOneWidget);
    expect(find.textContaining(kCuBianchiCaption), findsOneWidget);
    // Acronyms spelled out where they first appear.
    expect(
      find.textContaining('NAV, network allocation vector'),
      findsOneWidget,
    );
    expect(find.textContaining('BSS: basic service set'), findsOneWidget);
    expect(find.textContaining('TU, time units of 1024'), findsOneWidget);
  });

  testWidgets('predict, then reveal hides the meter until Reveal', (
    WidgetTester tester,
  ) async {
    final ChannelUtilizationController c = await _open(tester);
    c.senders = 5;
    await tester.pump();
    await _tap(tester, find.text('Ask the class'));
    expect(c.config.senders, 1);
    expect(c.masked, isTrue);
    c.skipWindow();
    await tester.pump();
    expect(find.text('72.9%'), findsNothing);
    expect(find.text('?'), findsWidgets);
    await _tap(tester, find.text('100%'));
    await _tap(tester, find.text('Reveal'));
    expect(find.text('72.9%'), findsWidgets);
    expect(
      find.textContaining('The meter reads 72.9% (186 of 255), not 100%.'),
      findsOneWidget,
    );
    expect(
      find.text('The class picked 100%. The answer is About 75%.'),
      findsOneWidget,
    );
    await _tap(tester, find.text('Done'));
    expect(find.text('Ask the class'), findsOneWidget);
  });

  testWidgets('Reveal fills the window first', (WidgetTester tester) async {
    final ChannelUtilizationController c = await _open(tester);
    c.ask();
    c.reveal();
    await tester.pump();
    expect(c.sim.intervals.length, 50);
    expect(c.reading!.filling, isFalse);
  });

  testWidgets('Run moves the channel; Pause and Reset stop and clear it', (
    WidgetTester tester,
  ) async {
    final ChannelUtilizationController c = await _open(tester);
    await _tap(tester, find.text('Run the channel'));
    expect(c.playing, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.sim.completedIntervals, greaterThanOrEqualTo(5));
    await _tap(tester, find.text('Pause'));
    expect(c.playing, isFalse);
    await _tap(tester, find.text('Reset'));
    expect(c.sim.nowTenths, 0);
  });

  testWidgets('the 1-second burst adds non-Wi-Fi time', (
    WidgetTester tester,
  ) async {
    final ChannelUtilizationController c = await _open(tester);
    await _tap(tester, find.text('Add a 1-second non-Wi-Fi burst'));
    c.stepInterval();
    await tester.pump();
    expect(find.textContaining('Non-Wi-Fi 100.0%'), findsOneWidget);
  });

  testWidgets('with reduced motion the channel does not run by itself', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ChannelUtilizationController c = ChannelUtilizationController();
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: ChannelUtilizationScreen(controller: c),
        ),
      ),
    );
    await tester.pump();
    expect(c.reducedMotion, isTrue);
    expect(c.playing, isFalse);
    c.stepInterval();
    expect(c.sim.completedIntervals, 1);
  });

  testWidgets('copy text carries the reading', (WidgetTester tester) async {
    final ChannelUtilizationController c = await _open(tester);
    c.skipWindow();
    final String t = c.copyText();
    expect(
      t,
      contains(
        'Channel Utilization, what the access point reports: 186 of 255 '
        '(72.9%)',
      ),
    );
    c.countReserved = true;
    expect(c.copyText(), contains('Listener view (counts reservations):'));
    expect(t, contains('cycle 393.5 µs'));
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
        final ChannelUtilizationController c = await _open(
          tester,
          size: Size(width, 7000),
          theme: theme(),
        );
        c.senders = 20;
        c.neighbor = true;
        c.nonWifi = true;
        c.skipWindow();
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
