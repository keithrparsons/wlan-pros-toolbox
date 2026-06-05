// Optical Transceivers wiring + screen tests. Guards (a) the catalog/route
// wiring for the new `optical-transceivers` id and (b) that the screen renders
// the tier headers, the lead "Commonly ordered" flag, the IEEE vs VENDOR chips,
// the amber loss-budget caveat, the form-factor table, search, and the honest
// empty state. A pre-built service is injected so the tests do not depend on the
// bundled asset load.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/tool_catalog.dart';
import 'package:wlan_pros_toolbox/data/tool_keywords.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/optical_transceivers_screen.dart';
import 'package:wlan_pros_toolbox/services/network/optical_transceiver_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fixture = '''
{
  "tiers": [
    {
      "tier": "10G", "formFactor": "SFP+", "lead": true,
      "entries": [
        { "designation": "10GBASE-SR", "rate": "10 Gbps", "reach": "300 m (OM3); 400 m (OM4)", "fiber": "MMF (OM1-OM4)", "fiberKind": "mmf", "wavelength": "850 nm", "connector": "LC", "connectorKind": "lc", "notes": "Most common 10G multimode link.", "vendor": false, "reachCaveat": "" },
        { "designation": "10GBASE-ZR", "rate": "10 Gbps", "reach": "80 km", "fiber": "SMF (OS2)", "fiberKind": "smf", "wavelength": "1550 nm", "connector": "LC", "connectorKind": "lc", "notes": "Vendor variant, not IEEE-standardized.", "vendor": true, "reachCaveat": "vendor · loss-budget dependent" }
      ]
    },
    {
      "tier": "1G", "formFactor": "SFP", "lead": false,
      "entries": [
        { "designation": "1000BASE-SX", "rate": "1 Gbps", "reach": "550 m (OM3)", "fiber": "MMF (OM1-OM4)", "fiberKind": "mmf", "wavelength": "850 nm", "connector": "LC/SC", "connectorKind": "lc", "notes": "Short-reach multimode.", "vendor": false, "reachCaveat": "" }
      ]
    }
  ],
  "formFactors": [
    { "formFactor": "SFP", "maxRate": "1 Gbps", "lanes": "1", "power": "<1 W", "notes": "1G fiber and copper." },
    { "formFactor": "QSFP28", "maxRate": "100 Gbps", "lanes": "4", "power": "~3.5-4.5 W", "notes": "Workhorse 100G." }
  ]
}
''';

OpticalTransceiverService _svc() =>
    OpticalTransceiverService.fromJson(_fixture);

Widget _harness(OpticalTransceiverService svc) => MaterialApp(
      theme: AppTheme.dark(),
      home: OpticalTransceiversScreen(service: svc),
    );

ToolEntry _entry() => kToolCategories
    .expand((ToolCategory c) => c.tools)
    .firstWhere((ToolEntry t) => t.id == 'optical-transceivers');

void main() {
  group('catalog + route wiring', () {
    test('the tool id resolves to a live ToolEntry in Quick Reference', () {
      final ToolEntry entry = _entry();
      expect(entry.title, 'Optical Transceivers');
      expect(entry.routeName, '/tools/optical-transceivers');
      expect(entry.isLive, isTrue);
      expect(entry.subgroup, 'Cabling & Connectors');

      final ToolCategory cat = kToolCategories.firstWhere(
        (ToolCategory c) =>
            c.tools.any((ToolEntry t) => t.id == 'optical-transceivers'),
      );
      expect(cat.id, 'quick-reference');
      // sits beside the Fiber Optic reference
      expect(
        cat.tools.any((ToolEntry t) => t.id == 'fiber-optic'),
        isTrue,
        reason: 'optical transceivers sits in the Cabling & Connectors subgroup',
      );
    });

    test('the route is registered and follows the /tools/<id> convention', () {
      expect(AppRouter.routes.containsKey(AppRouter.opticalTransceivers), isTrue);
      expect(AppRouter.opticalTransceivers, '/tools/optical-transceivers');
    });

    test('the bundled asset + tool-id constants are stable', () {
      expect(kOpticalTransceiversAsset, 'assets/data/optical_transceivers.json');
      expect(kOpticalTransceiversToolId, 'optical-transceivers');
    });

    test('search keywords are registered for discovery', () {
      final List<String>? kw = kToolKeywords['optical-transceivers'];
      expect(kw, isNotNull);
      expect(kw, containsAll(<String>['sfp', 'qsfp28', 'transceiver', 'zr']));
    });
  });

  group('screen', () {
    testWidgets('renders the title, tier headers, and a known variant', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      expect(find.text('Optical Transceivers'), findsWidgets);
      // Tier badges
      expect(find.text('10G'), findsOneWidget);
      expect(find.text('1G'), findsOneWidget);
      // A known designation + its note
      expect(find.text('10GBASE-SR'), findsOneWidget);
      expect(find.text('Most common 10G multimode link.'), findsOneWidget);
      // Section headings
      expect(find.text('Optical variants · by speed tier'), findsOneWidget);
      expect(find.text('Form factors · SFP → OSFP'), findsOneWidget);
      // The search field is present.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('lead tier carries the COMMONLY ORDERED flag; non-lead does not',
        (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();
      // Exactly one lead flag in the fixture (10G is lead, 1G is not).
      expect(find.text('COMMONLY ORDERED'), findsOneWidget);
    });

    testWidgets('IEEE and VENDOR chips render; vendor caveat is shown', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      // 10GBASE-SR + 1000BASE-SX are IEEE; 10GBASE-ZR is vendor.
      expect(find.text('IEEE'), findsNWidgets(2));
      // VENDOR appears on the card AND in the legend row → at least 2.
      expect(find.text('VENDOR'), findsWidgets);
      // The verbatim loss-budget caveat is rendered next to the vendor reach.
      expect(find.text('vendor · loss-budget dependent'), findsOneWidget);
    });

    testWidgets('the form-factor table renders its rows', (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();
      expect(find.text('SFP'), findsWidgets); // form-factor name + tier sub
      expect(find.text('QSFP28'), findsOneWidget);
      expect(find.text('100 Gbps'), findsOneWidget);
    });

    testWidgets('typing a query narrows tiers in place', (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'ZR');
      await tester.pump();

      expect(find.text('10GBASE-ZR'), findsOneWidget);
      // The non-matching SR + SX variants are gone.
      expect(find.text('10GBASE-SR'), findsNothing);
      expect(find.text('1000BASE-SX'), findsNothing);
    });

    testWidgets('a no-match query shows the honest empty state', (tester) async {
      await tester.pumpWidget(_harness(_svc()));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'zzznotapresentword');
      await tester.pump();

      expect(find.text('No match'), findsOneWidget);
      expect(find.text('10GBASE-SR'), findsNothing);
    });
  });
}
