// Network Quality screen — widget tests.
//
// Network is never touched: the screen is driven by a MockQualityClient (the
// engine's deterministic, no-I/O client) and a ReachabilityProbe wired with a
// fake SiteProber that returns a fixed Duration for some hosts and null for
// others. These run hermetically on the test VM.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
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

  Widget harness() => MaterialApp(
        theme: AppTheme.dark(),
        home: NetQualityScreen(
          client: MockQualityClient(),
          reachabilityProbe: ReachabilityProbe(
            prober: fakeProber,
            sites: sites,
          ),
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
}
