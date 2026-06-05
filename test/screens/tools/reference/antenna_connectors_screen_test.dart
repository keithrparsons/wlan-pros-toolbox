// AntennaConnectorsScreen widget tests — the reference groups by section,
// renders connector cards (name + full name + labeled fields), exposes a search
// field, filters live on typing, renders the three editorial sections, wires the
// per-connector diagram slot (present when bundled, omitted otherwise), and lays
// out without RenderFlex overflow at 320/375/768/1280 widths. A pre-built
// service is injected so the tests do not depend on the bundled asset load
// (AntennaConnectorsScreen.service hook). The tool id resolves to its route.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wlan_pros_toolbox/data/connector_diagrams.dart';
import 'package:wlan_pros_toolbox/router/app_router.dart';
import 'package:wlan_pros_toolbox/screens/tools/reference/antenna_connectors_screen.dart';
import 'package:wlan_pros_toolbox/services/connectors/antenna_connector_service.dart';
import 'package:wlan_pros_toolbox/theme/app_theme.dart';

const String _fixture = '''
{
  "schema_version": 1,
  "title": "Antenna Connectors",
  "source": "test fixture",
  "note": "An intro framing note.",
  "connector_count": 3,
  "connectors": [
    {
      "id": "rp-sma", "connector": "RP-SMA",
      "full_name": "Reverse-Polarity SMA",
      "group": "Enterprise (panel/external)",
      "reverse_polarity": "Yes (this is the RP variant of SMA)",
      "typical_wifi_use": "Consumer Wi-Fi routers and adapters",
      "indoor_outdoor": "Mostly indoor",
      "coupling": "Threaded",
      "impedance": "50 ohm",
      "frequency": "Up to 18 GHz",
      "mating": "Mates only with RP-SMA.",
      "notes": "Most common connector on consumer Wi-Fi gear."
    },
    {
      "id": "n-type", "connector": "N-Type",
      "full_name": "Type-N",
      "group": "Outdoor / point-to-point",
      "reverse_polarity": "No",
      "typical_wifi_use": "Outdoor APs and bridges",
      "indoor_outdoor": "Excellent outdoor",
      "coupling": "Threaded, weatherproof",
      "impedance": "50 ohm",
      "frequency": "Up to ~11 GHz",
      "mating": "Mates only with standard N.",
      "notes": "Rugged, weather resistant, low loss."
    },
    {
      "id": "dart", "connector": "DART",
      "full_name": "Cisco Smart Antenna Connector (DART)",
      "group": "Enterprise (panel/external)",
      "reverse_polarity": "N/A (proprietary multi-port interface)",
      "typical_wifi_use": "Cisco external-antenna systems",
      "indoor_outdoor": "Both",
      "coupling": "Multi-port proprietary",
      "impedance": "50 ohm (RF lines)",
      "frequency": "Covers Wi-Fi bands",
      "mating": "Cisco proprietary.",
      "notes": "Cisco does not publish the acronym."
    }
  ],
  "vendor_trends": [
    { "vendor": "Cisco Systems", "common_connector": "RP-TNC; DART" }
  ],
  "size_order_largest_to_smallest": [ "N-Type", "SMA / RP-SMA" ],
  "size_order_note": "A practical Wi-Fi-relevant ladder.",
  "troubleshooting_class_top_6": {
    "intro": "The connectors your students are most likely to encounter:",
    "connectors": [
      { "connector": "RP-SMA", "context": "consumer Wi-Fi" }
    ],
    "coverage_note": "These cover most field encounters."
  }
}
''';

AntennaConnectorService _svc() => AntennaConnectorService.fromJson(_fixture);

Widget _harness(AntennaConnectorService svc) => MaterialApp(
      theme: AppTheme.dark(),
      home: AntennaConnectorsScreen(service: svc),
    );

void main() {
  setUp(() {
    // Default: no diagrams bundled, so the diagram slot is omitted everywhere.
    ConnectorDiagrams.debugSetBundled(const <String>{});
  });
  tearDown(ConnectorDiagrams.debugReset);

  // The content scrolls in a ListView, which lazily builds. Pump a tall viewport
  // so off-screen cards + the editorial sections are built and findable by
  // text. The dedicated overflow test sets its own per-width sizes.
  Future<void> pumpTall(WidgetTester tester, AntennaConnectorService svc) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(400, 3000);
    tester.view.devicePixelRatio = 1.0;
    await tester.pumpWidget(_harness(svc));
    await tester.pump();
  }

  testWidgets('mounts, renders a known connector and the search field', (
    tester,
  ) async {
    await pumpTall(tester, _svc());

    // Connector names recur (card title + editorial sections), so assert on the
    // unique full-name / notes text that only the card renders.
    expect(find.text('Reverse-Polarity SMA'), findsOneWidget);
    expect(find.text('Type-N'), findsOneWidget);
    expect(find.text('RP-SMA'), findsWidgets);
    // Group section headers present.
    expect(find.text('Enterprise (panel/external)'), findsOneWidget);
    expect(find.text('Outdoor / point-to-point'), findsOneWidget);
    // The search field is present.
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('renders the three editorial sections (unfiltered view)', (
    tester,
  ) async {
    await pumpTall(tester, _svc());

    expect(find.text('Enterprise Wi-Fi vendor trends'), findsOneWidget);
    expect(find.text('Size order, largest to smallest'), findsOneWidget);
    expect(find.text('Top 6 connectors in the field'), findsOneWidget);
    expect(find.text('Cisco Systems'), findsOneWidget);
  });

  testWidgets('DART is named without a spelled-out acronym', (tester) async {
    await pumpTall(tester, _svc());

    expect(find.text('DART'), findsOneWidget);
    expect(
      find.text('Cisco Smart Antenna Connector (DART)'),
      findsOneWidget,
    );
    // The unverified expansion must never appear on screen.
    expect(find.textContaining('Direct Attached RF Technology'), findsNothing);
  });

  testWidgets('typing a query filters the list and hides editorial sections', (
    tester,
  ) async {
    await pumpTall(tester, _svc());

    await tester.enterText(find.byType(TextField), 'weatherproof');
    await tester.pump();

    // Only N-Type (its coupling carries "weatherproof") survives.
    expect(find.text('Rugged, weather resistant, low loss.'), findsOneWidget);
    expect(
      find.text('Most common connector on consumer Wi-Fi gear.'),
      findsNothing,
    );
    // Editorial sections are suppressed while filtering.
    expect(find.text('Enterprise Wi-Fi vendor trends'), findsNothing);
  });

  testWidgets('a no-match query shows the honest empty state', (tester) async {
    await pumpTall(tester, _svc());

    await tester.enterText(find.byType(TextField), 'zzznotapresentword');
    await tester.pump();

    expect(find.textContaining('No connectors match'), findsOneWidget);
    expect(find.text('RP-SMA'), findsNothing);
  });

  testWidgets('the diagram slot is omitted when no diagram is bundled', (
    tester,
  ) async {
    // setUp already cleared the bundle.
    await pumpTall(tester, _svc());
    expect(find.byType(SvgPicture), findsNothing);
  });

  testWidgets('the diagram slot renders when a diagram IS bundled', (
    tester,
  ) async {
    // Simulate Charta's rp-sma diagram being present in the bundle.
    ConnectorDiagrams.debugSetBundled(
      <String>{'assets/connector-diagrams/rp-sma.svg'},
    );
    await pumpTall(tester, _svc());
    // Exactly one connector (rp-sma) has a bundled diagram → one SvgPicture.
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('renders without overflow at 320/375/768/1280 widths', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final AntennaConnectorService svc = _svc();
    for (final double width in <double>[320, 375, 768, 1280]) {
      tester.view.physicalSize = Size(width, 2200);
      tester.view.devicePixelRatio = 1.0;
      await tester.pumpWidget(_harness(svc));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: 'overflow at ${width}px');
    }
  });

  test('the antenna-connectors route resolves to a registered builder', () {
    expect(
      AppRouter.routes.containsKey(AppRouter.antennaConnectors),
      isTrue,
    );
    expect(AppRouter.antennaConnectors, '/tools/antenna-connectors');
  });
}
