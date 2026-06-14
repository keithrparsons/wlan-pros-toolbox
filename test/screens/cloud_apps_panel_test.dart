// CloudAppsPanel — widget tests (Feature 1, Felix 2026-06-13). No real sockets:
// the panel is driven by a ReachabilityProbe wired with a fake SiteProber.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:net_quality/net_quality.dart';
import 'package:wlan_pros_toolbox/screens/tools/network/cloud_apps_panel.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

void main() {
  const List<PopularSite> sites = <PopularSite>[
    PopularSite(name: 'Google', host: 'www.google.com'),
    PopularSite(name: 'Zoom', host: 'zoom.us'),
    PopularSite(name: 'Down Co', host: 'no.such.host.invalid'),
  ];

  Future<void> pumpPanel(
    WidgetTester tester, {
    required SiteProber prober,
  }) async {
    await tester.binding.setSurfaceSize(const Size(560, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CloudAppsPanel(
              probe: ReachabilityProbe(sites: sites, prober: prober),
            ),
          ),
        ),
      ),
    );
    // Post-frame callback fires the probe; pump until results land.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('renders the panel title and honesty caption', (t) async {
    await pumpPanel(
      t,
      prober: (host, port, timeout) async => const Duration(milliseconds: 10),
    );
    expect(find.text('Cloud apps reachable?'), findsOneWidget);
    expect(
      find.textContaining('not a measure of in-app call or stream quality'),
      findsOneWidget,
    );
  });

  testWidgets('success: shows each service name + reachable word + summary',
      (t) async {
    await pumpPanel(
      t,
      prober: (host, port, timeout) async =>
          host == 'no.such.host.invalid' ? null : const Duration(milliseconds: 15),
    );
    expect(find.text('Google'), findsOneWidget);
    expect(find.text('Zoom'), findsOneWidget);
    expect(find.text('Down Co'), findsOneWidget);
    expect(find.text('reachable'), findsWidgets);
    expect(find.text('unreachable'), findsOneWidget);
    // 2 of 3 answered.
    expect(find.text('2 of 3 services are reachable.'), findsOneWidget);
  });

  testWidgets('all-unreachable: honest "couldn\'t reach any" summary',
      (t) async {
    await pumpPanel(
      t,
      prober: (host, port, timeout) async => null,
    );
    expect(
      find.textContaining("Couldn't reach any of these services"),
      findsOneWidget,
    );
    expect(find.text('unreachable'), findsNWidgets(3));
  });

  testWidgets('all-reachable: summary reads "All N services"', (t) async {
    await pumpPanel(
      t,
      prober: (host, port, timeout) async => const Duration(milliseconds: 8),
    );
    expect(find.text('All 3 services are reachable.'), findsOneWidget);
  });

  testWidgets('offers a Check again retry control on success', (t) async {
    await pumpPanel(
      t,
      prober: (host, port, timeout) async => const Duration(milliseconds: 8),
    );
    expect(find.widgetWithText(OutlinedButton, 'Check again'), findsOneWidget);
  });
}
