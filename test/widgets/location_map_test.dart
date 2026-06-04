// Widget tests for LocationMap — the embedded OSM map surface (GL-003 §8.18).
//
// The map's tiles are network-backed and never load in a headless test, but the
// §8.18 surface obligations that DON'T depend on tiles are fully testable, and
// they are the ones that matter most — the OSM attribution is a HARD LEGAL rule:
//   - the verbatim "© OpenStreetMap contributors" credit is PRESENT and visible
//     (not behind a toggle / popup — it renders without any interaction);
//   - the credit is TAPPABLE (wrapped in an InkWell with an onTap), exposed to
//     assistive tech as a link;
//   - the credit string is exactly the OSMF-required text (no abbreviation);
//   - a single location marker is rendered (the lime pin).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';
import 'package:wlan_pros_toolbox/widgets/location_map.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark(),
      home: const Scaffold(
        body: LocationMap(latitude: 40.7128, longitude: -74.0060),
      ),
    ),
  );
  // One frame — do NOT pumpAndSettle (the tile layer schedules network image
  // loads that never resolve in a headless test).
  await tester.pump();
}

void main() {
  group('LocationMap §8.18 attribution (HARD LEGAL RULE)', () {
    testWidgets('renders the verbatim OSM credit, with no interaction', (
      tester,
    ) async {
      await _pump(tester);
      // Persistent: present on first frame, no toggle tapped.
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
      // The constant is verbatim per the OSMF policy.
      expect(kOsmAttribution, '© OpenStreetMap contributors');
    });

    testWidgets('the credit is tappable (an InkWell-wrapped link)', (
      tester,
    ) async {
      await _pump(tester);
      final Finder credit = find.text('© OpenStreetMap contributors');
      // The credit sits inside an InkWell with an onTap (the tappable link to
      // the OSM copyright page).
      final Finder inkWell = find.ancestor(
        of: credit,
        matching: find.byType(InkWell),
      );
      expect(inkWell, findsOneWidget);
      expect(tester.widget<InkWell>(inkWell).onTap, isNotNull);
    });

    testWidgets('the credit is exposed to assistive tech as a link', (
      tester,
    ) async {
      await _pump(tester);
      final Finder credit = find.text('© OpenStreetMap contributors');
      final Finder sem = find.ancestor(
        of: credit,
        matching: find.byType(Semantics),
      );
      // At least one ancestor Semantics marks it as a link.
      final bool anyLink = tester
          .widgetList<Semantics>(sem)
          .any((s) => s.properties.link == true);
      expect(anyLink, isTrue);
    });

    testWidgets('the copyright URL is the OSM copyright page', (tester) async {
      expect(kOsmCopyrightUrl, 'https://www.openstreetmap.org/copyright');
    });
  });

  group('LocationMap marker', () {
    testWidgets('renders a single location pin', (tester) async {
      await _pump(tester);
      // The pin is two stacked location_on icons (charcoal halo + lime fill);
      // exactly one marker means exactly one pin pair.
      expect(find.byIcon(Icons.location_on), findsNWidgets(2));
    });
  });

  group('LocationMap tile policy', () {
    test('uses the OSM HTTPS tile endpoint with a unique app User-Agent', () {
      // ONLINE-ONLY HTTPS tiles (OSMF policy: no cleartext, no offline store).
      expect(kOsmTileUrl, startsWith('https://tile.openstreetmap.org/'));
      // The UA is the app bundle id — unique and attributable, NOT a library
      // default (OSMF policy requires an identifiable UA).
      expect(kOsmUserAgentPackageName, 'com.wlanpros.wlanProsToolbox');
    });
  });
}
