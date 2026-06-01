// Network Quality screen — widget tests.
//
// Network is never touched: the screen is driven by a MockQualityClient (the
// engine's deterministic, no-I/O client) and a ReachabilityProbe wired with a
// fake SiteProber that returns a fixed Duration for some hosts and null for
// others. These run hermetically on the test VM.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/live_quality_monitor.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/metric_sparkline.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/net_quality_screen.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  // A fake reachability prober: 'one.one.one.one' and 'www.google.com' answer
  // in a fixed time; everything else is unreachable (null). No real sockets.
  Future<Duration?> fakeProber(String host, int port, Duration timeout) async {
    if (host == 'one.one.one.one') return const Duration(milliseconds: 12);
    if (host == 'www.google.com') return const Duration(milliseconds: 24);
    return null;
  }

  const List<PopularSite> sites = <PopularSite>[
    PopularSite(name: 'Cloudflare', host: 'one.one.one.one'),
    PopularSite(name: 'Google', host: 'www.google.com'),
    PopularSite(name: 'Unreachable Co', host: 'no.such.host.invalid'),
  ];

  LatencyStats fakeStats() => const LatencyStats(
        avgMs: 18,
        minMs: 12,
        maxMs: 24,
        jitterMs: 3,
        lossPct: 0,
        sent: 5,
        received: 5,
      );

  // A monitor wired with a fake latency sampler so no socket is opened. The
  // screen calls start() in initState; the fake fires immediately.
  LiveQualityMonitor fakeMonitor() =>
      LiveQualityMonitor(sampler: () async => fakeStats());

  Widget harness({LiveQualityMonitor? monitor}) => MaterialApp(
        theme: AppTheme.dark(),
        home: NetQualityScreen(
          client: MockQualityClient(),
          reachabilityProbe: ReachabilityProbe(
            prober: fakeProber,
            sites: sites,
          ),
          monitor: monitor ?? fakeMonitor(),
        ),
      );

  testWidgets('renders the run affordance before a run', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.byType(NetQualityScreen), findsOneWidget);
    expect(find.text('Run test'), findsOneWidget);
  });

  testWidgets(
      'running shows the six metrics, a grade chip, and popular-site rows',
      (tester) async {
    await tester.pumpWidget(harness());

    await tester.tap(find.text('Run test'));
    await tester.pumpAndSettle();

    // The six transport metric labels render.
    for (final String label in <String>[
      'Latency',
      'Jitter',
      'Loss',
      'Download',
      'Upload',
      'Responsiveness',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label metric missing');
    }

    // At least one grade chip with a grade label appears. The default mock
    // script grades several dimensions Excellent.
    expect(find.text('Excellent'), findsWidgets);

    // At least one popular-site row renders, with a text status word.
    expect(find.text('Cloudflare'), findsOneWidget);
    expect(find.text('reachable'), findsWidgets);
    expect(find.text('unreachable'), findsWidgets);
  });

  testWidgets('renders without overflow at a 320px logical width',
      (tester) async {
    // MAJOR 3 — narrowest supported phone width. The metric card Row (Expanded
    // label + value + grade chip) must never throw a RenderFlex overflow when
    // the value is long and the chip says "Unavailable" in a ~150px cell.
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(harness());
    await tester.tap(find.text('Run test'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  group('live monitor', () {
    testWidgets('live latency samples render the metrics card before a run',
        (tester) async {
      // The screen starts the monitor in initState; the fake sampler fires one
      // immediate latency-trio sample, so the Transport card and the Live
      // indicator appear without tapping Run.
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Live · sampling latency every 30s'), findsOneWidget);
      // The latency-trio rows are present from live history alone.
      expect(find.text('Latency'), findsOneWidget);
      expect(find.text('Jitter'), findsOneWidget);
      expect(find.text('Loss'), findsOneWidget);
    });

    testWidgets('sparse expensive metric shows the tracking hint until a run',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // Before a one-shot run, download/upload/responsiveness have no points.
      expect(find.text('Run a test to start tracking'), findsWidgets);

      // After a run, the expensive trio has one point → still a hint (1 point
      // is not enough for a line), but the chip + value now render.
      await tester.tap(find.text('Run test'));
      await tester.pumpAndSettle();
      expect(find.text('Download'), findsOneWidget);
      // A single point keeps the hint (>= 2 needed for a line, spec §3).
      expect(find.text('Run a test to start tracking'), findsWidgets);
    });

    testWidgets('a dense latency trail renders a sparkline (>= 2 points)',
        (tester) async {
      // Drive the monitor to 2+ live samples via tickNow, then pump.
      final monitor = fakeMonitor();
      await tester.pumpWidget(harness(monitor: monitor));
      await tester.pumpAndSettle();
      await monitor.tickNow();
      await monitor.tickNow();
      await tester.pumpAndSettle();

      expect(find.byType(MetricSparkline), findsWidgets);
    });

    testWidgets('pause/resume toggles the live indicator and SR label',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Live · sampling latency every 30s'), findsOneWidget);
      expect(find.bySemanticsLabel('Pause live sampling'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Pause live sampling'));
      await tester.pumpAndSettle();

      expect(find.text('Paused'), findsOneWidget);
      expect(find.bySemanticsLabel('Resume live sampling'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Resume live sampling'));
      await tester.pumpAndSettle();

      expect(find.text('Live · sampling latency every 30s'), findsOneWidget);
    });

    testWidgets('leaving the screen disposes the monitor with no timer errors',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
      expect(find.byType(NetQualityScreen), findsOneWidget);

      // Replace the screen → State.dispose runs → monitor.dispose cancels the
      // timer. A leaked Timer.periodic would trip the test binding here.
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      await tester.pumpAndSettle();

      expect(find.byType(NetQualityScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('help affordance', () {
    testWidgets('app-bar help icon opens the About these metrics sheet',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      // The help affordance is the SR-labeled icon button in the app bar.
      final Finder help = find.bySemanticsLabel('About these metrics');
      expect(help, findsOneWidget);

      // Before opening, the help content is not on screen.
      expect(find.text('About Network Quality'), findsNothing);

      await tester.tap(help);
      await tester.pumpAndSettle();

      // The sheet renders its heading and the six metric headings.
      expect(find.text('About Network Quality'), findsOneWidget);
      expect(find.text('The six metrics'), findsOneWidget);
      for (final String metric in <String>[
        'Latency',
        'Jitter',
        'Loss',
        'Responsiveness',
        'Download',
        'Upload',
      ]) {
        expect(find.text(metric), findsWidgets, reason: '$metric heading');
      }

      // A representative grade band is present.
      expect(find.text('What the grades mean'), findsOneWidget);
      expect(find.text('under 20 ms'), findsOneWidget);
    });

    testWidgets('the honesty caveats are present in the help sheet',
        (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('About these metrics'));
      await tester.pumpAndSettle();

      // The not-an-Orb/Ookla-score caveat — the load-bearing honesty claim —
      // is rendered. Matched on a substring so a copy tweak elsewhere in the
      // paragraph does not break the test.
      expect(
        find.textContaining('not an Orb or Ookla score'),
        findsOneWidget,
      );
      // The RFC 9097 single-stream Responsiveness caveat is present (it appears
      // both in the metric card note and the honesty card).
      expect(find.textContaining('RFC 9097'), findsWidgets);
      // The "no single composite score" intent survives.
      expect(find.textContaining('no single overall score'), findsOneWidget);
    });

    testWidgets('Close dismisses the help sheet', (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      await tester.tap(find.bySemanticsLabel('About these metrics'));
      await tester.pumpAndSettle();
      expect(find.text('About Network Quality'), findsOneWidget);

      // The help sheet is taller than the test viewport, so the bottom Close
      // button is off-screen until scrolled to (on a real device it is reached
      // by scroll or the drag-handle swipe).
      await tester.ensureVisible(find.bySemanticsLabel('Close help'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Close help'));
      await tester.pumpAndSettle();
      expect(find.text('About Network Quality'), findsNothing);
    });
  });
}
