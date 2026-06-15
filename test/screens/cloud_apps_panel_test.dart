// CloudAppsPanel — widget tests (Feature 1, Felix 2026-06-13). No real sockets:
// the panel is driven by a ReachabilityProbe wired with a fake SiteProber.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  testWidgets(
      'offers a "Re-check cloud apps" retry control on success (scoped label, '
      'Keith #7 — re-checks ONLY this panel, not the whole test)', (t) async {
    await pumpPanel(
      t,
      prober: (host, port, timeout) async => const Duration(milliseconds: 8),
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Re-check cloud apps'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Keith #3: at 320px service names render whole on one line — never '
    'character-broken ("Faceboo-k") — even in the all-unreachable state',
    (t) async {
      const List<PopularSite> narrowSites = <PopularSite>[
        PopularSite(name: 'Facebook', host: 'www.facebook.com'),
        PopularSite(name: 'Instagram', host: 'www.instagram.com'),
      ];
      await t.binding.setSurfaceSize(const Size(320, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CloudAppsPanel(
                probe: ReachabilityProbe(
                  sites: narrowSites,
                  prober: (host, port, timeout) async => null, // all unreachable
                ),
              ),
            ),
          ),
        ),
      );
      await t.pump();
      await t.pump(const Duration(milliseconds: 50));

      // Each name renders as a single, intact, one-line paragraph at 320px.
      for (final String name in <String>['Facebook', 'Instagram']) {
        final Finder f = find.text(name);
        expect(f, findsOneWidget, reason: '$name present');
        final RenderParagraph p = t.renderObject<RenderParagraph>(
          find.descendant(
            of: f,
            matching: find.byType(RichText),
            matchRoot: true,
          ),
        );
        expect(p.text.toPlainText(), name, reason: '$name not split');
        expect(p.size.height, lessThan(28),
            reason: '$name stayed on one line (no mid-word wrap) at 320px');
      }
      // No layout overflow (RenderFlex) was thrown rendering the row at 320px.
      expect(t.takeException(), isNull);
    },
  );
}
